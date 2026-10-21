# tflab-aws

Two-region, active-passive Kubernetes lab on AWS, built to run on **USD 100 of credit**:

- **Sydney (ap-southeast-2) primary, Melbourne (ap-southeast-4) standby**: EKS 1.36 with Cilium (overlay CNI, kube-proxy replacement, Hubble), Graviton Spot nodes, max 10 app pods
- **React + .NET 10 API + RDS PostgreSQL**: IAM database auth, cross-region read replica, RTO/RPO 15 min
- **Route 53 failover** on `app.mimidog.click`, CloudWatch alarms -> email
- **Failure drills** for every layer (AWS FIS, Chaos Mesh, Cilium policies) and a **Playwright** regression suite
- **Ephemeral by design**: stand up, demo, tear down; nightly auto-destroy

Full guide: **[docs/PLAYBOOK.md](docs/PLAYBOOK.md)** · Interactive architecture: [docs/ARCH-tflabAWS-TwoRegionEKS-20261021.html](docs/ARCH-tflabAWS-TwoRegionEKS-20261021.html) (download and open in a browser - six views, zoom/pan, the reasoning per component) · Network & security: [docs/ARCH-tflabAWS-NetSec-20261021.html](docs/ARCH-tflabAWS-NetSec-20261021.html) · Agent skill: [.claude/skills/tflab-aws](.claude/skills/tflab-aws/SKILL.md)

```mermaid
flowchart LR
  u([User]) --> r53{{Route 53 failover<br/>app.mimidog.click}}
  r53 -- primary --> syd[Sydney<br/>ALB -> EKS -> RDS writer]
  r53 -. secondary .-> mel[Melbourne<br/>ALB -> EKS -> RDS replica]
  syd == replication ==> mel
```

## Quick start

```bash
# Tools: open in a GitHub Codespace (or VS Code dev container) - everything is pre-installed
./bootstrap/bootstrap.sh     # once per account (manual steps are explained inline)
make build && make up        # ~30-40 min, ~USD 0.50-0.70/hr while running
make drill                   # list failure drills
make test TARGET=app         # regression suite
make down                    # DRAIN teardown + leftovers sweep
```

Or use the GitHub Actions workflows: `up`, `drill`, `regression`, `down` (also nightly at 10:00 UTC).

## The live site (ONE-TWO-API)

While the lab is up you get a real HTTPS website. It stops answering after `down` or the nightly destroy, until the next `up`.

| URL | What you get |
|---|---|
| **https://app.mimidog.click** | **One** name for users: Route 53 sends you to Sydney, or to Melbourne during a failover |
| https://syd.mimidog.click | **Two** region-pinned names: Sydney (primary, writable) |
| https://mel.mimidog.click | Melbourne (standby, read-only until promoted) |

**The page shows** which region and pod served you, whether the database is writable, and a small form to add and list items.

**The API** (paths are the same on all three hostnames):

| Method | Path | Returns |
|---|---|---|
| GET | `/api/healthz` | `{"status":"ok"}` - process alive (ALB target health) |
| GET | `/api/ready` | `{"db":"ok","writable":true}`, or 503 when the DB is unreachable - Route 53 failover health check |
| GET | `/api/info` | region, pod, node, configured role, `dbWritable`, version |
| GET | `/api/items` | latest 50 items |
| GET | `/api/items/{id}` | one item, or 404 |
| POST | `/api/items` `{"text":"..."}` | 201 + item; 400 if empty or over 200 chars; 503 on a read-only standby |
| DELETE | `/api/items/{id}` | 204, 404, or 503 on a read-only standby |

```bash
curl -s https://app.mimidog.click/api/info  | jq     # region, pod, node, dbWritable
curl -s https://app.mimidog.click/api/items | jq     # latest 50 items
curl -s -X POST https://app.mimidog.click/api/items \
  -H 'Content-Type: application/json' -d '{"text":"hello"}'
```

**Watch it fail over:** run `drills/drill.sh failover syd --yes` (and `drills/rto-watch.sh` in a second terminal). The "Served by" region on the site flips to **Melbourne** within about 1-2 minutes, then fails back on its own.

## Glossary

ALB = Application Load Balancer · API = Application Programming Interface · DB = database · HTTPS = HTTP over TLS · CNI = Container Network Interface · EKS = Elastic Kubernetes
Service · FIS = Fault Injection Service · OIDC = OpenID Connect · RDS = Relational Database
Service · RPO / RTO = Recovery Point / Time Objective · SNS = Simple Notification Service.
Full glossary in the playbook.
