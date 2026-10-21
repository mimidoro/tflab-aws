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

- `curl -s https://syd.mimidog.click/api/ready` -> `{"db":"ok","writable":true,...}` (if 503 "unreachable", see troubleshooting: Pod Identity / Cilium rows)
- `curl -s https://app.mimidog.click/api/info | jq` -> region `Sydney (ap-southeast-2)`, `dbWritable: true`
- `curl -s https://mel.mimidog.click/api/info | jq` -> region Melbourne, `dbWritable: false`
- `make kubeconfig` (or `aws eks update-kubeconfig --region ap-southeast-2 --name tflab-syd --alias tflab-syd`, same with `ap-southeast-4` / `tflab-mel`)
- `kubectl --context tflab-syd -n app get pods` -> web and api Running (2-3 each), **no `db-init` pod left Running** (a stuck one means it can't reach the DB or credentials)
- `kubectl --context tflab-syd -n kube-system exec ds/cilium -- cilium status --brief` -> OK
- CloudWatch > Alarms in both regions: all `OK` or `INSUFFICIENT_DATA` (no `ALARM`)
- First run only: confirm the three new SNS subscription emails (Sydney, Melbourne, us-east-1)

If anything fails, go to `troubleshooting.md`.

## Show the user their site

Once verified, give them: **https://app.mimidog.click** (failover name), plus the pinned
https://syd.mimidog.click / https://mel.mimidog.click. The page shows the serving region, pod,
database writability and an add/list items form. API reference: README > "The live site".
Remind them it stops answering after `down` / the nightly destroy.
