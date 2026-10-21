#!/usr/bin/env bash
# Failure drills for every layer. Memory hook - "PANDA-R":
#   P  Pods      pod-kill, web-down, cpu-stress           (Chaos Mesh)
#   A  App->DB   db-block, latency                        (Cilium deny policy, Chaos Mesh)
#   N  Nodes     node-kill                                (AWS FIS)
#   D  Database  db-reboot, promote-replica               (AWS FIS, RDS API)
#   A  AZ        az-blackout                              (AWS FIS)
#   R  Region    failover, region-blackout                (Cilium / AWS FIS + Route 53)
#
# Usage:  drills/drill.sh list
#         drills/drill.sh <drill> <syd|mel> [--yes]
#         drills/drill.sh restore <syd|mel>
# Watch alarms: CloudWatch console > Alarms (Sydney, Melbourne, and us-east-1 for failover),
# and your email. Run drills/rto-watch.sh in a second terminal for any region-level drill.
. "$(dirname "$0")/../scripts/lib.sh"

DRILL="${1:-list}"
KEY="${2:-}"
[[ "${3:-}" == "--yes" ]] && export ASSUME_YES=1
EXP_DIR="$REPO_ROOT/chaos/experiments"

usage() {
  cat <<'EOF'
Drill            Layer     Tool        Expected signal
---------------  --------  ----------  -------------------------------------------------------------
pod-kill         Pod       Chaos Mesh  pod replaced in seconds, no alarm (PDB + replicas)
web-down         Pod       Chaos Mesh  web-unhealthy-targets + alb-no-healthy-targets alarms (3 min)
cpu-stress       Pod       Chaos Mesh  HPA scales api to max (watch: kubectl get hpa -w)
latency          App       Chaos Mesh  api-latency-p95 alarm (5 min)
db-block         App->DB   Cilium      cilium-packet-drops + alb-target-5xx; in syd: Route 53 failover
node-kill        Node      AWS FIS*    api/web-unhealthy-targets, cilium-unreachable-nodes; ASG heals
db-reboot        Database  AWS FIS*    alb-target-5xx briefly; recovers in ~2-5 min
az-blackout      AZ        AWS FIS*    unhealthy targets in one AZ; traffic shifts to the other AZ (5 min)
failover         Region    Cilium      syd only: db-block + RTO timer -> app.mimidog.click serves Melbourne
region-blackout  Region    AWS FIS     syd only: private subnets cut 10 min -> Route 53 failover
promote-replica  Database  RDS API     mel only, DESTRUCTIVE: fence syd, promote replica, report RPO/RTO
failback         Database  RDS API     mel only, after promote: Sydney re-seeded from Melbourne, switched back (~60 min)
restore          -         -           remove drill policies/experiments in a region
* AWS FIS drills: syd only (no FIS endpoint in Melbourne)
EOF
}

apply_exp()  { k apply -f "$EXP_DIR/$1.yaml" >/dev/null && ok "applied $1 at $(ts)"; }
fis_start() {
  local tpl_key="$1" region="${REGION_OF[$KEY]}" region_name
  region_name=$([[ "$KEY" == "syd" ]] && echo sydney || echo melbourne)
  tf_init
  local tpl
  tpl=$(terraform -chdir="$REPO_ROOT/infra" output -json fis_templates | jq -r ".${region_name}.${tpl_key}")
  [[ -n "$tpl" && "$tpl" != "null" ]] || die "no FIS template '$tpl_key' in $KEY - FIS has no endpoint in Melbourne; FIS drills (node-kill, db-reboot, az-blackout, region-blackout) run in syd only"
  local id
  id=$(aws fis start-experiment --region "$region" --experiment-template-id "$tpl" \
        --tags Drill="$tpl_key" --query experiment.id --output text)
  ok "FIS experiment $id started at $(ts) ($tpl_key)"
  echo "   follow: aws fis get-experiment --region $region --id $id --query experiment.state"
}

db_block()   { k apply -f "$REPO_ROOT/chaos/policies/drill-db-block.yaml" >/dev/null && ok "API->DB blocked at $(ts)"; }
db_unblock() { k -n app delete ciliumnetworkpolicy drill-db-block --ignore-not-found >/dev/null && ok "API->DB restored at $(ts)"; }

[[ "$DRILL" == "list" ]] && { usage; exit 0; }
need_region_key "$KEY"
gd_log "drill:$DRILL" "$KEY"

case "$DRILL" in
  pod-kill)   ctx "$KEY"; apply_exp pod-kill-api ;;
  web-down)   ctx "$KEY"; apply_exp pod-failure-web ;;
  cpu-stress) ctx "$KEY"; apply_exp stress-cpu-api ;;
  latency)    ctx "$KEY"; apply_exp network-delay-api ;;

  db-block)
    ctx "$KEY"; db_block
    echo "   auto-restoring in 5 min (Ctrl-C keeps it blocked; undo with: drills/drill.sh restore $KEY)"
    sleep 300; db_unblock ;;

  node-kill)   fis_start node_terminate ;;
  db-reboot)   fis_start db_reboot ;;
  az-blackout) fis_start az_blackout ;;

  region-blackout)
    [[ "$KEY" == "syd" ]] || die "region-blackout targets the primary (syd)"
    confirm "Cut ALL Sydney private-subnet traffic for 10 minutes?"
    fis_start region_blackout
    "$REPO_ROOT/drills/rto-watch.sh" 900 ;;

  failover)
    [[ "$KEY" == "syd" ]] || die "failover drill fences the primary (syd)"
    confirm "Fence Sydney's API from its database so Route 53 fails over to Melbourne?"
    ctx syd; db_block
    "$REPO_ROOT/drills/rto-watch.sh" 600 || true
    # Traffic failover only (the DB stays in Sydney) - fail back automatically.
    db_unblock
    ok "failed back: Route 53 returns traffic to Sydney once its health check passes (~30-60s)" ;;

  promote-replica)
    [[ "$KEY" == "mel" ]] || die "promote-replica runs against the standby (mel)"
    "$REPO_ROOT/drills/promote-replica.sh" ;;

  failback)
    [[ "$KEY" == "mel" ]] || die "failback starts from the promoted writer (mel)"
    "$REPO_ROOT/drills/failback.sh" ;;

  restore)
    ctx "$KEY"
    # G1 split-brain guard: once Melbourne has been promoted, Sydney's database is stale.
    # Unfencing Sydney would let Route 53 send users back to it. Fail back instead.
    if [[ "$KEY" == "syd" ]] && db_exists mel && [[ -z "$(db_source mel)" ]] && [[ "$(db_source syd)" != *tflab-mel-pg* ]]; then
      die "Melbourne is the promoted writer - unfencing Sydney would serve stale data (split brain). Fail back with: drills/drill.sh failback mel --yes"
    fi
    db_unblock
    k delete podchaos,networkchaos,stresschaos --all -A --wait=false >/dev/null 2>&1 || true
    ok "chaos experiments removed in $KEY" ;;

  *) usage; die "unknown drill '$DRILL'" ;;
esac
