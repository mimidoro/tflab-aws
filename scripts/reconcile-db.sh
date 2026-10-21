#!/usr/bin/env bash
# Re-attach Terraform state to databases rebuilt outside Terraform (promote / failback drills).
# AWS provider v6 tracks aws_db_instance by its DBI resource ID, which changes on rebuild, so the
# next plan would otherwise try to CREATE the instance again and fail with AlreadyExists.
#   1. state rm + import each tflab-*-pg instance by identifier
#   2. plan, and fail loudly if anything database-related would be REPLACED
# Usage: scripts/reconcile-db.sh [image_tag]   (image_tag only satisfies the required variable)
. "$(dirname "$0")/lib.sh"

TAG="${1:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"
TF=(terraform -chdir="$REPO_ROOT/infra")
tf_init

for key in syd mel; do
  addr="module.${key}_core.aws_db_instance.this"
  id="tflab-${key}-pg"
  db_exists "$key" || { warn "$id does not exist - skipping"; continue; }
  live=$(aws rds describe-db-instances --region "${REGION_OF[$key]}" --db-instance-identifier "$id" \
           --query 'DBInstances[0].DbiResourceId' --output text)
  state=$("${TF[@]}" state show -no-color "$addr" 2>/dev/null | awk -F'"' '/^ *resource_id *=/{print $2}')
  if [[ "$live" == "$state" ]]; then
    ok "$addr already tracks $id ($live)"
    continue
  fi
  say "Re-import $addr ($id: state=${state:-none} live=$live)"
  "${TF[@]}" state rm "$addr" >/dev/null 2>&1 || true
  "${TF[@]}" import -input=false -var "image_tag=$TAG" "$addr" "$id"
done

say "Plan check (no database may be replaced)"
"${TF[@]}" plan -input=false -no-color -var "image_tag=$TAG" -out=/tmp/reconcile.tfplan > /tmp/reconcile.plan.txt || die "plan failed - see /tmp/reconcile.plan.txt"
if grep -E "aws_db_instance.*(must be replaced|will be destroyed)" /tmp/reconcile.plan.txt; then
  die "plan would REPLACE/DESTROY a database - do not apply; check /tmp/reconcile.plan.txt"
fi
grep -E "^Plan:|No changes" /tmp/reconcile.plan.txt || true
ok "state reconciled - run 'up' (or terraform apply) next"
