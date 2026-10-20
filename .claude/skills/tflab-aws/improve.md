# Improving this skill and the lab

## How to change the skill

1. Edit files in `.claude/skills/tflab-aws/` on a branch; keep `SKILL.md` short and route detail
   into the runbook files.
2. When a drill's observed signal differs from `drills.md`, fix the lab or the table - never both
   silently. Record the finding below with the date.
3. Open a PR; CI checks Terraform, Helm, .NET, web, tests and shell scripts.

## Backlog (pick from the top)

| # | Improvement | Why |
|---|---|---|
| 1 | Pin GitHub Actions to commit SHAs and the CloudWatch agent image to a digest | supply-chain risk |
| 2 | Automate DB failover: Route 53 alarm -> EventBridge -> Lambda promote (with fencing) | RTO without a human |
| 3 | Add k6 load test job to prove "high throughput" numbers (RPS at p95 < 300 ms) | performance evidence |
| 4 | Cilium WireGuard transparent encryption (pod-to-pod), then mutual authentication between web/api | encrypted east-west traffic, zero-trust story |
| 5 | Permissions boundary on all tflab-* roles instead of policy-ARN deny list | stronger IAM guard rail |
| 6 | Infracost in CI: cost diff on every PR | cost visibility |
| 7 | Failback runbook that re-seeds Sydney from Melbourne instead of full rebuild | realistic DR |
| 8 | AWS Config / Security Hub snapshot during `up`, removed on `down` | compliance demo |
| 9 | Synthetic canary (CloudWatch Synthetics) instead of curl-based RTO watch | managed probing |

## Findings log

| Date | Drill / area | Expected | Observed | Action |
|---|---|---|---|---|
| 2026-10-20 | Setup: domain | `route53domains` works after creating the account | Free plan blocks it ("Free Tier accounts are not supported") | M2 upgrade documented in bootstrap |
| 2026-10-21 | Setup: account model | standalone account, Identity Center available | AWS "project" account: one region, Identity Center denied | activated advanced features; `tflab-guardrails` SCP replaces `AdvancedModeRegionRestrictionSecurityControlPolicy`; CLI via `aws login --remote` |
| 2026-10-21 | Setup: Spot | Spot might stay denied after activation | no SCP denies Spot after activation | design kept (Graviton Spot) |
| 2026-10-21 | Setup: CLI | `aws login` picks the right account | picked the management account first | bootstrap now refuses the management account |
| 2026-10-21 | First `up`: OIDC | sub = `repo:mimidoro/tflab-aws:environment:lab` | sub = `repo:mimidoro@7311162/tflab-aws@1426218913:environment:lab` (immutable IDs) | trust policy accepts the ID form (plus the plain form) |
| 2026-10-21 | Observability | your console role can use kubectl/Hubble after a GitHub-run apply | only the GitHub role + apply caller were cluster admins | `console_admin_role_names` (AccountFullAccessRole) added to EKS access entries; `scripts/observe.sh`, cilium + hubble CLIs in the dev container |
| 2026-10-21 | First `up`: guardrails | replica create allowed (db.t4g.micro) | SCP denied CreateDBInstanceReadReplica on the source DB (condition key absent) | `Null` guard on the EC2/RDS size-cap statements |
| 2026-10-21 | First `up`: NAT ASG | instance launches | `Authentication Failure` on first launch | troubleshooting row + CloudTrail check; re-run |
| 2026-10-21 | First `up`: RDS replica | replica of a primary with RDS-managed password | AWS rejects postgres replicas when ManageMasterUserPassword is on | write-only password into own Secrets Manager secret (never in state) |
| 2026-10-21 | First `up`: FIS | FIS templates in both regions | no FIS endpoint in ap-southeast-4 | `enable_fis` per region (off in Melbourne) |
| 2026-10-21 | First `up`: NAT | fck-nat ASG self-heals | ASG launch failed, then orphan blocked re-runs | NAT is a single instance (`ha_mode = false`); leftovers sweep checks ASGs |
