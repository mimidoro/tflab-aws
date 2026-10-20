# Stand up (~30-40 min, ~USD 0.50-0.70/hr from here)

Tell the user the hourly cost and that the nightly destroy runs at 10:00 UTC (23:00 NZDT).

## From GitHub (preferred)

```bash
gh workflow run up.yml --ref main
gh run watch --exit-status "$(gh run list --workflow up.yml -L1 --json databaseId -q '.[0].databaseId')"
```

`up` = build images (skips existing tags) -> `terraform apply` -> regression suite against app.

## Locally

```bash
make build      # images for the current commit (GitHub ARM runners)
make up         # terraform apply both regions, waits for /api/ready
make kubeconfig # contexts tflab-syd, tflab-mel
```

## Verify (all must pass)

- `curl -s https://app.mimidog.click/api/info | jq` -> region `Sydney (ap-southeast-2)`, `dbWritable: true`
- `curl -s https://mel.mimidog.click/api/info | jq` -> region Melbourne, `dbWritable: false`
- `kubectl --context tflab-syd -n app get pods` -> web and api Running (2-3 each)
- `kubectl --context tflab-syd -n kube-system exec ds/cilium -- cilium status --brief` -> OK
- CloudWatch > Alarms in both regions: all `OK` or `INSUFFICIENT_DATA` (no `ALARM`)
- First run only: confirm the three new SNS subscription emails (Sydney, Melbourne, us-east-1)

If anything fails, go to `troubleshooting.md`.
