# Setup (one time per AWS account)

Prereqs on the machine: `aws` v2, `terraform` >= 1.10, `kubectl`, `gh` (logged in as repo owner),
`jq`, Node 22.

Run from the repo root, signed in as an IAM Identity Center admin (never root):

```bash
./bootstrap/bootstrap.sh
```

The script stops with a clear message at each manual step. Manual steps (also documented as
comments in the script):

| Step | What | Where |
|------|------|-------|
| M1 | Temporary USD 100 budget (credits excluded) | Billing > Budgets |
| M2 | Upgrade to the Paid plan (credits carry over) | Billing > Free Tier |
| M3 | Identity Center admin user + `aws configure sso` | IAM Identity Center |
| M4 | Enable Melbourne (scripted - just wait) | Account > AWS Regions |
| M5 | Register `mimidog.click`, click the ICANN email | Route 53 > Registered domains |
| M6 | Confirm SNS subscription emails | Inbox |
| M7 | Optional: required reviewer on the `lab` environment | GitHub > Settings > Environments |

Scripted steps: B1 state bucket, B2 bootstrap Terraform (OIDC role, ECR, budget + kill switch),
B3 GitHub environment `lab` + `AWS_ACCOUNT_ID` variable.

Done when: `terraform -chdir=bootstrap output` shows the role ARN and ECR URLs, and
`gh variable list` shows `AWS_ACCOUNT_ID`. Then delete the M1 manual budget.
