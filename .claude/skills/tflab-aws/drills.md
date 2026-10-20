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
| **D**B | db-reboot | `drills/drill.sh db-reboot syd` | alb-target-5xx (brief) | 2-5 min |
| **A**Z | az-blackout | `drills/drill.sh az-blackout syd` | unhealthy targets in one AZ | 5 min |
| **R**egion | failover * | `drills/drill.sh failover syd --yes` | us-east-1 tflab-FAILOVER-sydney-unhealthy; app serves Melbourne (read-only) | auto fail-back |
| **R**egion | region-blackout * | `drills/drill.sh region-blackout syd --yes` | as failover + unhealthy targets | 10 min |
| **D**B | promote-replica * | `drills/drill.sh promote-replica mel --yes` | Melbourne writable; RPO marker check | **rebuild** (down + up) |

`*` destructive or user-visible: confirm with the user first.
AWS FIS drills (node-kill, db-reboot, az-blackout, region-blackout) are **Sydney only** - no FIS endpoint in Melbourne.

## Evidence to report

- **Detect time**: drill start -> alarm email timestamp.
- **RTO**: `drills/rto-watch.sh` output ("traffic moved after Ns", "writes available after Ns").
  Target 900 s.
- **RPO**: `promote-replica` marker check ("no committed data lost") + ReplicaLag before fencing.
  Target <= 15 min of data.
- Hubble view during db-block: `kubectl --context tflab-syd -n kube-system exec ds/cilium -- hubble observe --verdict DROPPED --last 20`

## Always finish with

`drills/drill.sh restore <region>` for every region you touched, then the regression suite.
