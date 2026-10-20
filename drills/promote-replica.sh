#!/usr/bin/env bash
# Database regional failover with RPO/RTO evidence. DESTRUCTIVE: after promotion Melbourne is a
# standalone writer and Sydney has diverged. Fail back = scripts/down.sh then scripts/up.sh.
#
#   1. Write a marker row through Sydney          (proves what "last committed" was)
#   2. Fence Sydney: Cilium blocks API->DB         (no split-brain writes; Route 53 fails over)
#   3. Promote the Melbourne replica               (RTO clock running)
#   4. Verify Melbourne is writable + marker exists (RPO evidence)
. "$(dirname "$0")/../scripts/lib.sh"

DB_ID="tflab-mel-pg"
MEL_REGION="${REGION_OF[mel]}"

confirm "Promote $DB_ID to a standalone writer? (irreversible for this lab run)"

say "1  Marker write through Sydney"
marker="rpo-marker-$(date -u +%Y%m%dT%H%M%SZ)"
created=$(curl -fsS --max-time 10 -X POST "${URL_OF[syd]}/api/items" \
  -H 'Content-Type: application/json' -d "{\"text\":\"$marker\"}" || true)
if [[ -n "$created" ]]; then
  ok "marker '$marker' committed in Sydney"
else
  warn "Sydney already not accepting writes - RPO is measured from replica lag instead"
fi
lag=$(aws cloudwatch get-metric-statistics --region "$MEL_REGION" --namespace AWS/RDS \
  --metric-name ReplicaLag --dimensions Name=DBInstanceIdentifier,Value="$DB_ID" \
  --start-time "$(date -u -d '-5 min' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Maximum --query 'max(Datapoints[].Maximum)' --output text 2>/dev/null || echo "n/a")
echo "   replica lag (last 5 min max): ${lag}s"
sleep 10 # let the marker replicate

say "2  Fence Sydney"
ctx syd
k apply -f "$REPO_ROOT/chaos/policies/drill-db-block.yaml" >/dev/null
t0=$(date +%s)
ok "Sydney API->DB blocked at $(ts) - RTO clock started"

say "3  Promote $DB_ID"
aws rds promote-read-replica --region "$MEL_REGION" --db-instance-identifier "$DB_ID" \
  --backup-retention-period 1 >/dev/null
aws rds wait db-instance-available --region "$MEL_REGION" --db-instance-identifier "$DB_ID"
ok "promoted after $(( $(date +%s) - t0 ))s"

say "4  Verify"
for _ in $(seq 1 60); do
  w=$(curl -fsS --max-time 5 "${URL_OF[mel]}/api/ready" | jq -r '.writable // false' 2>/dev/null || echo false)
  [[ "$w" == "true" ]] && break
  sleep 10
done
rto=$(( $(date +%s) - t0 ))
[[ "$w" == "true" ]] || die "Melbourne still not writable after ${rto}s"
ok "Melbourne writable - RTO ${rto}s $( (( rto <= 900 )) && echo '(met)' || echo '(MISSED)')"

if [[ -n "$created" ]]; then
  if curl -fsS --max-time 5 "${URL_OF[mel]}/api/items" | jq -e --arg m "$marker" 'any(.[]; .text == $m)' >/dev/null; then
    ok "marker present in Melbourne - RPO: no committed data lost"
  else
    warn "marker NOT in Melbourne - data written in the last ~${lag}s before fencing was lost"
  fi
fi
echo "   app.$DOMAIN now serves: $(serving_region)"
echo "   Fail back: scripts/down.sh && scripts/up.sh (rebuilds the replica topology)."
