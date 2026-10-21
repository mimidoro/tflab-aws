#!/usr/bin/env bash
# Fail back to Sydney after a promote-replica drill, by REVERSE REPLICATION (no data loss).
# Memory hook - "RE-SEED, SWITCH, RE-MIRROR":
#
#   Start:  Melbourne = promoted writer (serving users)   Sydney = fenced, stale old primary
#   R1  Record KMS keys + security groups      (so rebuilt DBs match Terraform - no replace on next up)
#   R2  Delete stale Sydney DB                 (~5-10 min)
#   R3  Create Sydney replica of Melbourne     (~15-25 min, cross-region)
#   R4  Wait until replica lag is ~0
#   S1  Marker write through Melbourne         (RPO evidence for the switch-back)
#   S2  Fence Melbourne (Cilium deny)          <- switch-back RTO clock starts
#   S3  Promote Sydney replica
#   S4  Unfence Sydney                         -> Route 53 health check passes, users return to Sydney
#   S5  Check marker arrived in Sydney         <- RPO result
#   M1  Delete Melbourne (old writer)          (~5-10 min)
#   M2  Create Melbourne replica of Sydney     (~15-25 min) - original topology restored
#   M3  Unfence Melbourne
#   T1  scripts/reconcile-db.sh - re-import the rebuilt DBs into Terraform state, plan must not replace
#   Afterwards: run `up` once - in-place changes only.
#
# Usage: drills/failback.sh            (asks for confirmation; ASSUME_YES=1 or drill.sh ... --yes to skip)
. "$(dirname "$0")/../scripts/lib.sh"

SYD="${REGION_OF[syd]}"; MEL="${REGION_OF[mel]}"
SYD_DB="tflab-syd-pg";   MEL_DB="tflab-mel-pg"
CLASS="db.t4g.micro"
t_all=$(date +%s)

db_attr() { aws rds describe-db-instances --region "$1" --db-instance-identifier "$2" --query "DBInstances[0].$3" --output text; }
sg_id()   { aws ec2 describe-security-groups --region "$1" --filters "Name=group-name,Values=$2" --query 'SecurityGroups[0].GroupId' --output text; }
wait_lag_zero() {  # region db
  say "   waiting for ReplicaLag <= 5s on $2"
  for _ in $(seq 1 60); do
    lag=$(aws cloudwatch get-metric-statistics --region "$1" --namespace AWS/RDS --metric-name ReplicaLag \
      --dimensions Name=DBInstanceIdentifier,Value="$2" --statistics Maximum --period 60 \
      --start-time "$(date -u -d '-3 min' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --query 'max(Datapoints[].Maximum)' --output text 2>/dev/null)
    [[ "$lag" != "None" && -n "$lag" ]] && awk "BEGIN{exit !($lag <= 5)}" && { ok "lag ${lag}s"; return 0; }
    sleep 30
  done
  die "replica lag never dropped to 5s - check the replica in the RDS console"
}
create_replica() {  # dest_region dest_id source_arn source_region subnet_group sg kms
  aws rds create-db-instance-read-replica --region "$1" --db-instance-identifier "$2" \
    --source-db-instance-identifier "$3" --source-region "$4" \
    --db-instance-class "$CLASS" --db-subnet-group-name "$5" --vpc-security-group-ids "$6" \
    --kms-key-id "$7" --storage-type gp3 --enable-iam-database-authentication --no-publicly-accessible \
    --tags Key=Project,Value=tflab-aws Key=ManagedBy,Value=terraform Key=Repo,Value=mimidoro/tflab-aws >/dev/null
  aws rds wait db-instance-available --region "$1" --db-instance-identifier "$2"
}

say "Preflight"
[[ -z "$(db_source mel)" ]] || die "Melbourne is still a replica - nothing to fail back (run promote-replica first)"
if db_exists syd && [[ "$(db_source syd)" == *"$MEL_DB"* ]]; then
  warn "Sydney is already a replica of Melbourne - resuming at R4"
  RESUME=1
fi
confirm "Fail back to Sydney by reverse replication? Deletes the stale Sydney DB, then later the Melbourne writer (~60 min)."
gd_log "failback:start" "mel"

# ------------------------------------------------------------------------------- RE-SEED
say "R1  Record KMS keys and security groups"
SYD_SG=$(sg_id "$SYD" tflab-syd-db); MEL_SG=$(sg_id "$MEL" tflab-mel-db)
MEL_KMS=$(db_attr "$MEL" "$MEL_DB" KmsKeyId)
SYD_KMS=$(db_exists syd && db_attr "$SYD" "$SYD_DB" KmsKeyId || echo "alias/aws/rds")
ok "Sydney sg $SYD_SG kms $SYD_KMS"
ok "Melbourne sg $MEL_SG kms $MEL_KMS"
MEL_ARN=$(db_attr "$MEL" "$MEL_DB" DBInstanceArn)

if [[ -z "${RESUME:-}" ]]; then
  if db_exists syd; then
    say "R2  Delete stale Sydney DB $SYD_DB"
    aws rds delete-db-instance --region "$SYD" --db-instance-identifier "$SYD_DB" \
      --skip-final-snapshot --delete-automated-backups >/dev/null
    aws rds wait db-instance-deleted --region "$SYD" --db-instance-identifier "$SYD_DB"
    ok "deleted"
  fi
  say "R3  Create Sydney replica of Melbourne (cross-region, ~15-25 min)"
  create_replica "$SYD" "$SYD_DB" "$MEL_ARN" "$MEL" tflab-syd "$SYD_SG" "$SYD_KMS"
  ok "Sydney replica available"
fi

say "R4  Replica catch-up"
wait_lag_zero "$SYD" "$SYD_DB"

# ------------------------------------------------------------------------------- SWITCH
say "S1  Marker write through Melbourne"
marker="failback-marker-$(date -u +%Y%m%dT%H%M%SZ)"
curl -fsS --max-time 10 -X POST "${URL_OF[mel]}/api/items" -H 'Content-Type: application/json' \
  -d "{\"text\":\"$marker\"}" >/dev/null && ok "marker '$marker' committed in Melbourne" || warn "marker write failed"
sleep 15

say "S2  Fence Melbourne"
ctx mel
k apply -f "$REPO_ROOT/chaos/policies/drill-db-block.yaml" >/dev/null
t0=$(date +%s); ok "Melbourne API->DB blocked at $(ts) - switch-back clock started"

say "S3  Promote Sydney replica"
aws rds promote-read-replica --region "$SYD" --db-instance-identifier "$SYD_DB" --backup-retention-period 1 >/dev/null
sleep 30
aws rds wait db-instance-available --region "$SYD" --db-instance-identifier "$SYD_DB"
ok "Sydney promoted after $(( $(date +%s) - t0 ))s"

say "S4  Unfence Sydney"
ctx syd
k -n app delete ciliumnetworkpolicy drill-db-block --ignore-not-found >/dev/null
for _ in $(seq 1 60); do
  w=$(curl -fsS --max-time 5 "${URL_OF[syd]}/api/ready" | jq -r '.writable // false' 2>/dev/null || echo false)
  [[ "$w" == "true" ]] && break
  sleep 10
done
rto=$(( $(date +%s) - t0 ))
[[ "$w" == "true" ]] || die "Sydney not writable after ${rto}s - check 'kubectl --context tflab-syd -n app logs deploy/api'"
ok "Sydney writable - switch-back RTO ${rto}s"

say "S5  RPO check"
if curl -fsS --max-time 5 "${URL_OF[syd]}/api/items" | jq -e --arg m "$marker" 'any(.[]; .text == $m)' >/dev/null; then
  rpo="no-loss"; ok "marker present in Sydney - no committed data lost"
else
  rpo="lost"; warn "marker NOT in Sydney"
fi
gd_log "failback:switch" "syd" "rto_s=$rto" "rpo=$rpo"
echo "   app.$DOMAIN serves: $(serving_region)   (Route 53 returns within ~1-2 min of /api/ready passing)"

# ------------------------------------------------------------------------------- RE-MIRROR
say "M1  Delete Melbourne old writer $MEL_DB"
aws rds delete-db-instance --region "$MEL" --db-instance-identifier "$MEL_DB" \
  --skip-final-snapshot --delete-automated-backups >/dev/null
aws rds wait db-instance-deleted --region "$MEL" --db-instance-identifier "$MEL_DB"
ok "deleted"

say "M2  Create Melbourne replica of Sydney (~15-25 min)"
SYD_ARN=$(db_attr "$SYD" "$SYD_DB" DBInstanceArn)
create_replica "$MEL" "$MEL_DB" "$SYD_ARN" "$SYD" tflab-mel "$MEL_SG" "$MEL_KMS"
ok "Melbourne replica available"

say "M3  Unfence Melbourne"
ctx mel
k -n app delete ciliumnetworkpolicy drill-db-block --ignore-not-found >/dev/null
ok "original topology restored: Sydney writer -> Melbourne replica"
gd_log "failback:done" "-" "total_s=$(( $(date +%s) - t_all ))"

say "Reconcile Terraform state (rebuilt DBs have new resource IDs)"
"$REPO_ROOT/scripts/reconcile-db.sh" || die "reconcile failed - do NOT run 'up' until it passes"
echo "   Next: run 'up' once (Actions > up) - in-place changes only."
