#!/usr/bin/env bash
# =====================================================================================
# Org guardrails - run ONCE in the MANAGEMENT account, after "Activate advanced features".
#
# Why: before activation AWS manages this account's service control policies (SCPs). They
# allow only one "selected region" for workloads and deny Spot instances. After activation
# you own the SCPs. This script swaps AWS's plan SCP for tflab-guardrails
# (bootstrap/org/scp-tflab-guardrails.json):
#   + allows Sydney, Melbourne and us-east-1 (global services) - everything else denied
#   + allows Spot
#   + denies expensive EC2/RDS sizes and capacity purchases (cost guard)
# AWS's BlockOrgEscape / ProtectManagedRoles SCP is left alone (it can't be removed).
#
# Memory hook - "SWAP": Show current, Write new, Attach new, Pull old
#
# Manual equivalent (console, signed in to the MANAGEMENT account):
#   AWS Organizations > Policies > Service control policies
#     1. Create policy "tflab-guardrails" - paste bootstrap/org/scp-tflab-guardrails.json
#     2. Targets: attach it to the Root
#     3. Open AdvancedModeRegionRestrictionSecurityControlPolicy (the AWS policy whose JSON
#        contains "RegionFloor") > Targets > Detach from every target
#     4. Leave attached: FullAWSAccess, ManagedAccountSecurityControlPolicy (BlockOrgEscape /
#        ProtectManagedRoles) and the BudgetsSpendLimit* policies (AWS Budgets manages those)
#
# Usage: ./bootstrap/org-guardrails.sh          (report only)
#        ./bootstrap/org-guardrails.sh --apply  (make the changes)
# Rollback: re-attach the detached AWS policy (its ID is printed) and detach tflab-guardrails.
# =====================================================================================
set -euo pipefail

APPLY="${1:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="$DIR/org/scp-tflab-guardrails.json"
NAME="tflab-guardrails"

say()  { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mOK\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!!\033[0m %s\n' "$*"; }
die()  { printf '   \033[31mXX\033[0m %s\n' "$*"; exit 1; }

for bin in aws jq; do command -v "$bin" >/dev/null || die "missing tool: $bin"; done

say "S  Show current SCPs"
org=$(aws organizations describe-organization --query 'Organization.[Id,MasterAccountId]' --output text 2>/dev/null) \
  || die "not signed in to the organization's management account (or advanced features not activated yet)"
read -r ORG_ID MGMT_ID <<<"$org"
ME=$(aws sts get-caller-identity --query Account --output text)
[[ "$ME" == "$MGMT_ID" ]] || die "signed in to $ME - run this in the management account $MGMT_ID"
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
ok "organization $ORG_ID, management account $MGMT_ID, root $ROOT_ID"

plan_policies=()
while read -r pid pname; do
  [[ -z "$pid" ]] && continue
  content=$(aws organizations describe-policy --policy-id "$pid" --query Policy.Content --output text)
  targets=$(aws organizations list-targets-for-policy --policy-id "$pid" --query 'Targets[].Name' --output text | tr '\t' ',')
  flag=""
  if grep -q '"RegionFloor"' <<<"$content" && ! grep -q '"BlockOrgEscape"' <<<"$content"; then
    flag="  <- AWS region-restriction SCP (e.g. AdvancedModeRegionRestrictionSecurityControlPolicy) - to be detached"
    plan_policies+=("$pid")
  fi
  printf '   %-24s %-40s targets: %s%s\n' "$pid" "$pname" "${targets:-none}" "$flag"
done < <(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
           --query 'Policies[].[Id,Name]' --output text)

if [[ "$APPLY" != "--apply" ]]; then
  warn "report only - re-run with --apply to create/attach $NAME and detach the AWS plan SCP"
  exit 0
fi

say "W  Write $NAME"
existing=$(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  --query "Policies[?Name=='$NAME'].Id" --output text)
if [[ -n "$existing" ]]; then
  aws organizations update-policy --policy-id "$existing" --content "file://$POLICY_FILE" >/dev/null
  NEW_ID="$existing"; ok "updated $NEW_ID"
else
  NEW_ID=$(aws organizations create-policy --type SERVICE_CONTROL_POLICY --name "$NAME" \
    --description "tflab: lab regions only, Spot allowed, cost caps on EC2/RDS sizes" \
    --content "file://$POLICY_FILE" --query Policy.PolicySummary.Id --output text)
  ok "created $NEW_ID"
fi

say "A  Attach $NAME to the root (before detaching anything, so there is never a gap)"
aws organizations attach-policy --policy-id "$NEW_ID" --target-id "$ROOT_ID" 2>/dev/null \
  && ok "attached" || ok "already attached"

say "P  Pull the AWS plan SCP"
(( ${#plan_policies[@]} )) || warn "no AWS plan SCP found - nothing to detach"
for pid in "${plan_policies[@]}"; do
  for tid in $(aws organizations list-targets-for-policy --policy-id "$pid" --query 'Targets[].TargetId' --output text); do
    aws organizations detach-policy --policy-id "$pid" --target-id "$tid"
    ok "detached $pid from $tid   (rollback: aws organizations attach-policy --policy-id $pid --target-id $tid)"
  done
done

say "Done. Next: in the project account, ./bootstrap/bootstrap.sh (it enables Melbourne)."
