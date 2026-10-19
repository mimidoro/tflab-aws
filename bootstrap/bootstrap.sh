#!/usr/bin/env bash
# =====================================================================================
# tflab-aws one-time account bootstrap
#
# Every MANUAL console step is written out below as comments (Mx), next to the scripted
# equivalent (Bx) where one exists. Steps already done are detected and skipped, so the
# script is safe to re-run.
#
# Memory hook - "BUILD-RIG":  Budget, Upgrade, Identity, Location (Melbourne), Domain,
#                             Remote state, IAM/ECR/guard (terraform), GitHub
#
# Usage:  ./bootstrap/bootstrap.sh            (run from the repo root, signed in as an admin)
# =====================================================================================
set -euo pipefail

PRIMARY_REGION="ap-southeast-2"
STANDBY_REGION="ap-southeast-4"
DOMAIN="mimidog.click"
REPO="mimidoro/tflab-aws"
GH_ENV="lab"

say()  { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mOK\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!!\033[0m %s\n' "$*"; }
die()  { printf '   \033[31mXX\033[0m %s\n' "$*"; exit 1; }

for bin in aws terraform gh jq; do
  command -v "$bin" >/dev/null || die "missing tool: $bin (see PLAYBOOK > Tooling)"
done

# -------------------------------------------------------------------------------------
# M1  BUDGET (manual, already done)
#     Console: Billing and Cost Management > Budgets > Create budget > Cost budget
#       - Amount USD 100, monthly; Advanced options: untick "Credits"
#       - Alerts: 25 / 50 / 75 % actual, 100 % forecast -> cwdyang888@gmail.com
#     Step B2 below creates "tflab-aws-guard" with the same alerts PLUS the USD 90 kill switch.
#     After B2 succeeds, delete the manual budget to avoid duplicate emails.
#
# M2  UPGRADE TO PAID PLAN (manual, already done)
#     Console: Billing and Cost Management > Free Tier > Upgrade plan.
#     Remaining credits carry over and are applied first. Needed for EKS and Route 53 Domains.
# -------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------
# M3  ADMIN IDENTITY (manual) - never use the root user for day-to-day work
#     Console: IAM Identity Center (region ap-southeast-2) > Enable
#       > Users > Add user (your email) > Permission sets > Create "AdministratorAccess"
#       > AWS accounts > assign the user + permission set
#     Then locally:  aws configure sso   (profile name e.g. tflab-admin)
#                    export AWS_PROFILE=tflab-admin && aws sso login
#     Also: enable MFA on the root user and lock its credentials away.
# -------------------------------------------------------------------------------------
say "M3  Checking caller identity"
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[[ "$CALLER_ARN" == *":root" ]] && die "You are signed in as ROOT. Complete M3 and use an Identity Center admin."
ok "account $ACCOUNT_ID as $CALLER_ARN"

# -------------------------------------------------------------------------------------
# M4  ENABLE MELBOURNE (opt-in region)
#     Console: account menu (top right) > Account > AWS Regions > Asia Pacific (Melbourne) > Enable
#     Scripted equivalent:
# -------------------------------------------------------------------------------------
say "M4  Melbourne ($STANDBY_REGION) opt-in"
status=$(aws account get-region-opt-status --region-name "$STANDBY_REGION" --query RegionOptStatus --output text)
if [[ "$status" != "ENABLED" && "$status" != "ENABLED_BY_DEFAULT" ]]; then
  [[ "$status" == "DISABLED" ]] && aws account enable-region --region-name "$STANDBY_REGION"
  echo "   enabling (usually a few minutes, can take longer)..."
  until [[ "$(aws account get-region-opt-status --region-name "$STANDBY_REGION" --query RegionOptStatus --output text)" == "ENABLED" ]]; do
    sleep 20
  done
fi
ok "Melbourne enabled"

# -------------------------------------------------------------------------------------
# M5  REGISTER THE DOMAIN (manual - it is a purchase, ~USD 3/yr, billed to card not credits)
#     Console: Route 53 > Registered domains > Register domains > "mimidog.click"
#       - Duration 1 year, auto-renew OFF (lab), privacy protection ON
#       - Route 53 creates the public hosted zone automatically
#     IMPORTANT: click the ICANN verification link emailed to the registrant address within
#     15 days or the domain is suspended.
#     Scripted equivalent (needs your registrant contact details in a local, git-ignored file):
#       aws route53domains register-domain --region us-east-1 --domain-name mimidog.click \
#         --duration-in-years 1 --no-auto-renew --privacy-protect-admin-contact \
#         --privacy-protect-registrant-contact --privacy-protect-tech-contact \
#         --admin-contact file://contact.json --registrant-contact file://contact.json \
#         --tech-contact file://contact.json
# -------------------------------------------------------------------------------------
say "M5  Hosted zone for $DOMAIN"
zone=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" --query "HostedZones[?Name=='${DOMAIN}.'].Id" --output text)
[[ -z "$zone" ]] && die "No hosted zone for $DOMAIN yet. Finish M5 (registration takes ~15 min), then re-run."
ok "hosted zone $zone"

# -------------------------------------------------------------------------------------
# B1  REMOTE STATE BUCKET (scripted)
#     Console equivalent: S3 > Create bucket "tflab-tfstate-ACCOUNTID" (ACCOUNTID = your 12-digit account, looked up automatically) in ap-southeast-2
#       - Block all public access ON, Versioning ON, Default encryption SSE-S3
#       - Bucket policy denying non-TLS requests; lifecycle: expire old versions after 30 days
# -------------------------------------------------------------------------------------
BUCKET="tflab-tfstate-${ACCOUNT_ID}"
say "B1  State bucket s3://$BUCKET"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$PRIMARY_REGION" \
    --create-bucket-configuration LocationConstraint="$PRIMARY_REGION" >/dev/null
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(jq -n --arg b "$BUCKET" '{
  Version:"2012-10-17",
  Statement:[{Sid:"DenyInsecureTransport",Effect:"Deny",Principal:"*",Action:"s3:*",
    Resource:["arn:aws:s3:::\($b)","arn:aws:s3:::\($b)/*"],
    Condition:{Bool:{"aws:SecureTransport":"false"}}}]}')"
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration \
  '{"Rules":[{"ID":"expire-old-versions","Status":"Enabled","Filter":{},"NoncurrentVersionExpiration":{"NoncurrentDays":30}}]}'
ok "bucket hardened"

# -------------------------------------------------------------------------------------
# B2  BOOTSTRAP TERRAFORM: GitHub OIDC + deploy role, ECR (+ Melbourne replication),
#     ops SNS topic, USD 100 budget with 25/50/75/100% alerts, USD 90 kill switch.
#     Console equivalents (for reference): IAM > Identity providers / Roles; ECR > Repositories
#     + Private registry > Replication; SNS > Topics; Budgets > Budget actions.
# -------------------------------------------------------------------------------------
say "B2  terraform apply (bootstrap)"
terraform -chdir=bootstrap init -input=false -backend-config="bucket=${BUCKET}" >/dev/null
terraform -chdir=bootstrap apply -input=false
ok "bootstrap applied"

# -------------------------------------------------------------------------------------
# M6  CONFIRM EMAIL SUBSCRIPTIONS (manual)
#     Check cwdyang888@gmail.com for "AWS Notification - Subscription Confirmation" and click
#     Confirm. One now (tflab-ops); three more after the first `make up` (Sydney, Melbourne,
#     us-east-1 failover topic). Unconfirmed = no alerts.
# -------------------------------------------------------------------------------------
warn "M6  Confirm the SNS subscription email for tflab-ops now."

# -------------------------------------------------------------------------------------
# B3  GITHUB CONFIGURATION (scripted with gh CLI; needs `gh auth login` as the repo owner)
#     UI equivalent: repo Settings > Environments > New environment "lab"
#       > Deployment branches and tags: "Selected branches" > add "main"
#     Settings > Secrets and variables > Actions > Variables: AWS_ACCOUNT_ID = your 12-digit account ID (set automatically below)
#     (No secrets are stored in GitHub - OIDC needs none.)
# -------------------------------------------------------------------------------------
say "B3  GitHub environment '$GH_ENV' and variables"
gh api -X PUT "repos/${REPO}/environments/${GH_ENV}" \
  -F "deployment_branch_policy[protected_branches]=false" \
  -F "deployment_branch_policy[custom_branch_policies]=true" >/dev/null
gh api -X POST "repos/${REPO}/environments/${GH_ENV}/deployment-branch-policies" \
  -f name=main -f type=branch >/dev/null 2>&1 || true
gh variable set AWS_ACCOUNT_ID --repo "$REPO" --body "$ACCOUNT_ID"
ok "environment + AWS_ACCOUNT_ID set"

# -------------------------------------------------------------------------------------
# M7  (optional) REQUIRE YOUR APPROVAL FOR EVERY DEPLOY
#     UI: Settings > Environments > lab > Required reviewers > add yourself.
#     Nightly destroy then also waits for approval - leave OFF if you rely on it.
# -------------------------------------------------------------------------------------

say "Done. Next: delete the manual budget from M1, then run the 'up' workflow (or: make up)."
