# Failure drills (memory hook: PANDA-R)

`drills/drill.sh list` prints the catalogue. One drill at a time; wait for recovery (alarms back
to OK) before the next. Workflow equivalent: `gh workflow run drill.yml -f drill=<name> -f region=<syd|mel> [-f confirm=yes]`.

| Layer | Drill | Command | Expect (alarm names prefixed tflab-syd- / tflab-mel-) | Recovers |
|---|---|---|---|---|
| **P**od | pod-kill | `drills/drill.sh pod-kill syd` | no alarm; new pod in < 30 s | auto |
| **P**od | web-down | `drills/drill.sh web-down syd` | web-unhealthy-targets, alb-no-healthy-targets | 3 min |
| **P**od | cpu-stress | `drills/drill.sh cpu-stress syd` | HPA scales api 2 -> 3 (`kubectl get hpa -w`) | 5 min |
| **A**pp | latency | `drills/drill.sh latency syd` | api-latency-p95 | 5 min |
| **A**pp->DB | db-block | `drills/drill.sh db-block mel` | cilium-packet-drops, alb-target-5xx | 5 min |
| **N**ode | node-kill | `drills/drill.sh node-kill syd` | api/web-unhealthy-targets, cilium-unreachable-nodes | ASG ~5 min |
| **D**B | db-reboot | `drills/drill.sh db-reboot syd` | alb-target-5xx; **also expect Route 53 failover** (single-AZ DB is down 2-5 min, longer than the 30 s health threshold) - app serves Melbourne read-only, then returns | 2-5 min |
| **A**Z | az-blackout | `drills/drill.sh az-blackout syd` | unhealthy targets in one AZ | 5 min |
| **R**egion | failover * | `drills/drill.sh failover syd --yes` | us-east-1 tflab-FAILOVER-sydney-unhealthy; app serves Melbourne (read-only) | auto fail-back |
| **R**egion | region-blackout * | `drills/drill.sh region-blackout syd --yes` | as failover + unhealthy targets | 10 min |
| **D**B | promote-replica * | `drills/drill.sh promote-replica mel --yes` | Melbourne writable; RPO marker check; **Sydney stays fenced** | `failback` |
| **D**B | failback * | `drills/drill.sh failback mel --yes` | Sydney re-seeded from Melbourne, switched back with an RPO marker check, Melbourne re-mirrored, Terraform state reconciled | ~60-90 min |

`*` destructive or user-visible: confirm with the user first.
AWS FIS drills (node-kill, db-reboot, az-blackout, region-blackout) are **Sydney only** - no FIS endpoint in Melbourne.

## Split-brain guard

After `promote-replica`, Sydney's old database is stale. `drills/drill.sh restore syd` **refuses** to
unfence Sydney while Melbourne is the promoted writer; the only way back is `failback`, which
re-seeds Sydney from Melbourne first. `down` is always allowed.

## Game day (memory hook: BASE-POD-INFRA-DNS-DATA)

Run from the **codespace** (the event log lives in `.gameday/`, which a workflow runner won't keep).
Each phase starts only when the previous one is green (alarms OK, regression passes).

| Phase | Drills | Proves | Risk |
|---|---|---|---|
| 0 BASE | `make test TARGET=app`, `make observe REGION=syd`, Hubble UI | baseline green | none |
| 1 POD | pod-kill, web-down, latency, cpu-stress (syd); db-block (mel) | reading Hubble + logs; alarms fire and clear | none |
| 2 INFRA | node-kill, db-reboot, az-blackout (syd, FIS) | self-healing; db-reboot also triggers DNS failover | minutes of 5xx |
| 3 DNS | `failover syd --yes` with `drills/rto-watch.sh 900` in a 2nd terminal | traffic RTO (expect 1-2 min) | read-only for minutes |
| 4 DATA | `promote-replica mel --yes`, regression vs `mel`, then `failback mel --yes` | real RTO + RPO both ways | one-way until failback completes |

Finish with `make report` -> `docs/gameday/<date>.md` (drill start, alarms fired, detect/recover
times, RTO/RPO results) and commit it. Log any expected-vs-observed difference in `improve.md`.

## Fail-back steps (drills/failback.sh - RE-SEED, SWITCH, RE-MIRROR)

| Step | Does | Typical time |
|---|---|---|
| R1-R2 | record KMS keys/SGs, delete stale Sydney DB | 5-10 min |
| R3-R4 | create Sydney replica of Melbourne, wait lag <= 5 s | 15-25 min |
| S1-S5 | marker write in Melbourne, fence Melbourne, promote Sydney, unfence Sydney, marker check | 5-10 min (switch-back RTO) |
| M1-M3 | delete Melbourne writer, create Melbourne replica of Sydney, unfence | 20-35 min |
| T1 | `scripts/reconcile-db.sh`: re-import both DBs into Terraform state; plan must not replace them | 2 min |

Then run `up` once. Resumable: if interrupted after R3, re-running starts at R4.

## Evidence to report

- **Detect time**: drill start -> alarm email timestamp.
- **RTO**: `drills/rto-watch.sh` output ("traffic moved after Ns", "writes available after Ns").
  Target 900 s.
- **RPO**: `promote-replica` marker check ("no committed data lost") + ReplicaLag before fencing.
  Target <= 15 min of data.
- Hubble view during db-block: `kubectl --context tflab-syd -n kube-system exec ds/cilium -- hubble observe --verdict DROPPED --last 20`

- **Report**: `make report` writes `docs/gameday/<date>.md` from `.gameday/events.log` + CloudWatch alarm history.

## Always finish with

`drills/drill.sh restore <region>` for every region you touched, then the regression suite.
