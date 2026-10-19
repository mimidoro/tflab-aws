# Teardown (memory hook: DRAIN)

```bash
make down                                   # local
gh workflow run down.yml --ref main         # GitHub
```

| Step | Does |
|---|---|
| **D**etach chaos | stops running FIS experiments, deletes Chaos Mesh experiments and drill policies |
| **R**elease Helm | if a cluster is already gone, removes its Helm releases from state so destroy can't hang |
| **A**pply destroy | `terraform destroy` both regions (replica removed before primary); retries once |
| **I**nspect | `scripts/leftovers.sh` - EKS, RDS, ALB, EC2, unattached EBS/EIP, NAT, tagged resources |
| **N**otify | emails the result via the `tflab-ops` topic |

Kept on purpose (cents/month): state bucket, OIDC role, ECR images, budget, domain, ops topic.

Done when the email says `CLEAN` (or `make leftovers` prints "nothing billable left").
The nightly `down` workflow runs this automatically at 10:00 UTC.
