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
| 4 | Cilium mutual authentication (mTLS) between web/api | zero-trust story |
| 5 | Permissions boundary on all tflab-* roles instead of policy-ARN deny list | stronger IAM guard rail |
| 6 | Infracost in CI: cost diff on every PR | cost visibility |
| 7 | Failback runbook that re-seeds Sydney from Melbourne instead of full rebuild | realistic DR |
| 8 | AWS Config / Security Hub snapshot during `up`, removed on `down` | compliance demo |
| 9 | Synthetic canary (CloudWatch Synthetics) instead of curl-based RTO watch | managed probing |

## Findings log

| Date | Drill / area | Expected | Observed | Action |
|---|---|---|---|---|
