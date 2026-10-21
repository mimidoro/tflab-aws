# Setup - the golden path (one time per AWS account)

Validated end to end on 2026-10-20/21. Do the steps **in this order**; every detour we hit is
already fixed in the code, and the remaining manual traps are called out inline.
Memory hook: **TOOLS-ACCOUNT-ORG-LOGIN-BOOT-UP-PROVE**.

## 1. TOOLS - codespace (5 min)

1. Create the codespace from **`main`** (the dev container only exists on branches that have
   `.devcontainer/`). After pulling dev-container changes into an existing codespace: Command
   Palette > **Codespaces: Full Rebuild Container**.
2. Check: `for t in aws terraform kubectl helm gh jq cilium hubble; do command -v $t >/dev/null && echo "ok $t" || echo "MISSING $t"; done`
3. Sign `gh` in as yourself (the codespace token can't create environments):
   `unset GITHUB_TOKEN && gh auth login` - repeat `unset GITHUB_TOKEN` in every new terminal.

## 2. ACCOUNT - AWS console (15-60 min, mostly waiting)

1. **Paid plan:** Billing > Free Tier > Upgrade plan. Credits carry over. (Free plan blocks EKS
   and Route 53 Domains: "Free Tier accounts are not supported".)
2. **Domain:** Route 53 > Registered domains > register `mimidog.click` (~USD 3/yr, card not
   credits, auto-renew off, privacy on). Click the **ICANN email** within 15 days. Status:
   `aws route53domains list-operations --region us-east-1 --query 'Operations[?Type==`REGISTER_DOMAIN`].[DomainName,Status]' --output table`
3. **Temporary budget** (until bootstrap creates the real one): Billing > Budgets, USD 100,
   credits excluded, 25/50/75/100%-forecast alerts.

## 3. ORG - only if the account is an AWS "project" account

Signs: console role `AccountFullAccessRole`; errors mentioning a service control policy with
`RegionFloor` or `sso:CreateInstance`. Such accounts allow one workload region and no Spot.

1. **Activate advanced features** (IRREVERSIBLE - confirm with the user first; removes AWS's hard
   spend limit): https://settings.aws.com > Projects > Actions > Explore advanced features. Team
   name (e.g. `mimido-team`), a management email not used by any AWS account
   (`cwdyang888+aws-mgmt@gmail.com` works), verify, confirm.
2. **Reach the management account via settings.aws.com** (Builder ID), not root. Root of the
   management account is emergency-only: Forgot password on the management email, then add MFA.
   Project accounts have no usable root at all.
3. **Swap the guardrail policy** - management account > Organizations > Policies > Service
   control policies:
   - **Create** `tflab-guardrails` from `bootstrap/org/scp-tflab-guardrails.json` (current
     version - it has the `Null` guards) and **attach it to Root first**.
   - **Detach** `AdvancedModeRegionRestrictionSecurityControlPolicy` from every target.
   - **Keep** `ManagedAccountSecurityControlPolicy`, `FullAWSAccess`, `BudgetsSpendLimit*`.
   - Scripted alternative: `./bootstrap/org-guardrails.sh` (report) / `--apply`, run as the
     management account.
   - Root attachment applies to every member account (other projects too).

## 4. LOGIN - CLI as the lab account (2 min)

1. Open the **lab** account console session: settings.aws.com > Projects > lab project.
2. `aws login --remote --profile tflab-admin` - region prompt `ap-southeast-2`; pick the
   session for the **lab account (073019354521)**, not the management account (996241422033).
3. `export AWS_PROFILE=tflab-admin && aws sts get-caller-identity --query Account --output text`
   must print the lab account. Wrong one: `aws logout --profile tflab-admin` and repeat.
4. Check guardrails: `aws account get-region-opt-status --region-name ap-southeast-4` returns a
   status (not AccessDenied).

## 5. BOOT - bootstrap (5-15 min)

```bash
./bootstrap/bootstrap.sh
```

- M4 enables Melbourne and waits; M5 stops if the hosted zone doesn't exist yet (re-run later).
- B2 plan: **17 to add, 0 to change, 0 to destroy** on a fresh account -> `yes`.
- B3 sets GitHub environment `lab` + `AWS_ACCOUNT_ID` (needs step 1.3).
- Then: confirm the **tflab-ops** SNS email, delete the temporary budget from 2.3, deactivate
  any IAM user access keys bootstrap warns about (e.g. `svc-github-deploy`).

## 6. UP - first stand-up (30-40 min, billing starts)

Actions > `up` > Run workflow on `main` (or `make build && make up`). Confirm the three new SNS
emails (Sydney, Melbourne, us-east-1). Then follow `standup.md` > Verify.

## 7. PROVE

`standup.md` Verify list, then `observe.md` (`make observe REGION=syd`, Hubble UI) and one
`regression.md` run. End the session with `teardown.md`.

## Reference: manual vs scripted

| Step | What | Where |
|---|---|---|
| M0/M0b | Activate advanced features (irreversible) + guardrail SCP swap | settings.aws.com > Projects; management account > Organizations |
| M1 | Temporary budget | Billing > Budgets |
| M2 | Paid plan | Billing > Free Tier |
| M3 | `aws login --remote` (lab account) | terminal |
| M4 | Enable Melbourne (scripted, just wait) | bootstrap |
| M5 | Register domain, click ICANN email | Route 53 |
| M6 | Confirm SNS emails | inbox |
| M7 | Optional: required reviewer on `lab` | GitHub > Settings > Environments |
| B1 | State bucket | bootstrap |
| B2 | OIDC role, ECR, alerts, budget + kill switch | bootstrap (Terraform) |
| B3 | GitHub environment + variable | bootstrap (`gh`) |

Anything unexpected: `troubleshooting.md` has a row for every error seen on the first build.
