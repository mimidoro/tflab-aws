# Setup (one time per AWS account)

Prereqs: open the repo in a Codespace / dev container (all tools pre-installed; run
`unset GITHUB_TOKEN && gh auth login` there), or install `aws` v2 (>= 2.32), `terraform` >= 1.10,
`kubectl`, `gh` (logged in as repo owner), `jq`, Node 22.

**Account model check first.** If the account was created through the new AWS experience
(sign-in shows `AccountFullAccessRole`, or errors mention a service control policy with
`RegionFloor` / `sso:CreateInstance`), it is a "project" account: only one workload region, no
Spot. Advanced features must be activated (M0, irreversible - confirm with the user) and the
guardrail SCP applied (M0b: `./bootstrap/org-guardrails.sh --apply` in the management account)
before bootstrap can succeed.

CLI sign-in (never root, never access keys):

```bash
aws login --remote --profile tflab-admin && export AWS_PROFILE=tflab-admin
aws sts get-caller-identity
```

Run from the repo root:

```bash
./bootstrap/bootstrap.sh
```

The script stops with a clear message at each manual step. Manual steps (also documented as
comments in the script):

| Step | What | Where |
|------|------|-------|
| M0 | Activate advanced features (irreversible) + M0b guardrail SCP | settings.aws.com > Projects; management account > Organizations |
| M1 | Temporary USD 100 budget (credits excluded) | Billing > Budgets |
| M2 | Upgrade to the Paid plan (credits carry over) | Billing > Free Tier |
| M3 | `aws login --remote` (or Identity Center from M0, us-east-1) | terminal |
| M4 | Enable Melbourne (scripted - just wait) | Account > AWS Regions |
| M5 | Register `mimidog.click`, click the ICANN email | Route 53 > Registered domains |
| M6 | Confirm SNS subscription emails | Inbox |
| M7 | Optional: required reviewer on the `lab` environment | GitHub > Settings > Environments |

Scripted steps: B1 state bucket, B2 bootstrap Terraform (OIDC role, ECR, budget + kill switch),
B3 GitHub environment `lab` + `AWS_ACCOUNT_ID` variable.

Done when: `terraform -chdir=bootstrap output` shows the role ARN and ECR URLs, and
`gh variable list` shows `AWS_ACCOUNT_ID`. Then delete the M1 manual budget.
