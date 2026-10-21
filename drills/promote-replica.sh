#!/usr/bin/env bash
# One-step regional failover with writes: Sydney -> Melbourne, RPO/RTO evidence. DESTRUCTIVE: after
# promotion Melbourne is a standalone writer and Sydney's database is stale (stays fenced).
# Fail back = drills/drill.sh failback mel --yes. Memory hook - MARK-FENCE-PROMOTE-PROVE:
#
#   1. MARK     write a marker through Sydney, wait until Melbourne's replica has it (RPO proof)
#   2. FENCE    Cilium blocks Sydney API->DB: no split-brain writes; Route 53 fails over (~1-2 min)
#   3. PROMOTE  start promoting the Melbourne replica straight away (runs alongside the DNS move)
#   4. PROVE    poll Melbourne every 5 s; report write RTO and traffic RTO separately
#
# Fast path: no fixed sleeps and no 'aws rds wait' - the API checks pg_is_in_recovery() on every
# request, so Melbourne accepts writes the moment PostgreSQL leaves recovery (typically 2-5 min on
# db.t4g.micro), before RDS reports 'available'. No pod restarts needed.
. "$(dirname "$0")/../scripts/lib.sh"

DB_ID="tflab-mel-pg"
MEL_REGION="${REGION_OF[mel]}"

confirm "Promote $DB_ID to a standalone writer? (irreversible for this lab run)"

say "1  MARK - marker write through Sydney"
marker="rpo-marker-$(date -u +%Y%m%dT%H%M%SZ)"
created=$(curl -fsS --max-time 10 -X POST "${URL_OF[syd]}/api/items" \
  -H 'Content-Type: application/json' -d "{\"text\":\"$marker\"}" || true)
lag=$(aws cloudwatch get-metric-statistics --region "$MEL_REGION" --namespace AWS/RDS \
  --metric-name ReplicaLag --dimensions Name=DBInstanceIdentifier,Value="$DB_ID" \
  --start-time "$(date -u -d '-5 min' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Maximum --query 'max(Datapoints[].Maximum)' --output text 2>/dev/null || echo "n/a")
echo "   replica lag (last 5 min max): ${lag}s"
replicated=false
if [[ -n "$created" ]]; then
  ok "marker '$marker' committed in Sydney"
  for _ in $(seq 1 15); do  # up to 30 s; normally visible in Melbourne within 1-2 s
    if curl -fsS --max-time 3 "${URL_OF[mel]}/api/items" | jq -e --arg m "$marker" 'any(.[]; .text == $m)' >/dev/null 2>&1; then
      replicated=true; break
    fi
    sleep 2
  done
  $replicated && ok "marker already in Melbourne's replica - nothing committed is left behind" \
              || warn "marker not in Melbourne after 30 s - promoting anyway; RPO checked again at the end"
else
  warn "Sydney already not accepting writes - RPO is measured from replica lag instead"
fi

say "2  FENCE - Sydney"
ctx syd
k apply -f "$REPO_ROOT/chaos/policies/drill-db-block.yaml" >/dev/null
t0=$(date +%s)
ok "Sydney API->DB blocked at $(ts) - RTO clock started; Route 53 fails over in ~1-2 min"

say "3  PROMOTE - $DB_ID (no wait: runs alongside the DNS failover)"
aws rds promote-read-replica --region "$MEL_REGION" --db-instance-identifier "$DB_ID" \
  --backup-retention-period 1 >/dev/null
ok "promotion started at $(ts)"

say "4  PROVE - polling every 5 s (max 15 min)"
w=false; t_write=""; t_dns=""
while (( $(date +%s) - t0 < 900 )); do
  el=$(( $(date +%s) - t0 ))
  if [[ -z "$t_write" ]]; then
    [[ "$(curl -fsS --max-time 4 "${URL_OF[mel]}/api/ready" | jq -r '.writable // false' 2>/dev/null)" == "true" ]] \
      && { w=true; t_write=$el; ok "Melbourne WRITABLE after ${el}s"; }
  fi
  if [[ -z "$t_dns" && "$(serving_region)" == Melbourne* ]]; then
    t_dns=$el; ok "app.$DOMAIN serving Melbourne after ${el}s"
  fi
  [[ -n "$t_write" && -n "$t_dns" ]] && break
  printf '   %4ss  rds=%s\n' "$el" "$(aws rds describe-db-instances --region "$MEL_REGION" \
    --db-instance-identifier "$DB_ID" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)"
  sleep 5
done
rto=${t_write:-$(( $(date +%s) - t0 ))}
[[ "$w" == "true" ]] || die "Melbourne still not writable after ${rto}s"
ok "write RTO ${rto}s $( (( rto <= 900 )) && echo '(met)' || echo '(MISSED)') - traffic RTO ${t_dns:-not yet}s"
curl -fsS --max-time 10 -X POST "$APP_URL/api/items" -H 'Content-Type: application/json' \
  -d "{\"text\":\"post-failover-write-$(date -u +%H%M%S)\"}" >/dev/null \
  && ok "test write through app.$DOMAIN succeeded" \
  || warn "write through app.$DOMAIN failed - DNS may still point at Sydney; use ${URL_OF[mel]}"

if [[ -n "$created" ]]; then
  if curl -fsS --max-time 5 "${URL_OF[mel]}/api/items" | jq -e --arg m "$marker" 'any(.[]; .text == $m)' >/dev/null; then
    ok "marker present in Melbourne - RPO: no committed data lost"
  else
    warn "marker NOT in Melbourne - data written in the last ~${lag}s before fencing was lost"
  fi
fi
echo "   app.$DOMAIN now serves: $(serving_region)"
rpo_result=$([[ -z "$created" ]] && echo "n/a" || (curl -fsS --max-time 5 "${URL_OF[mel]}/api/items" | jq -e --arg m "$marker" 'any(.[]; .text == $m)' >/dev/null && echo "no-loss" || echo "lost"))
gd_log "promote" "mel" "rto_s=$rto" "rpo=$rpo_result" "lag_s=$lag"
echo "   Sydney STAYS FENCED (its database is now stale). Do not run 'restore syd'."
echo "   Fail back: drills/drill.sh failback mel --yes   (re-seeds Sydney from Melbourne, ~60 min)"
