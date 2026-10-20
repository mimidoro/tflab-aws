#!/usr/bin/env bash
# Measures RTO from the user's point of view: polls https://app.mimidog.click/api/info every 5s and
# reports when the serving region changes and when writes work again.
# Usage: drills/rto-watch.sh [max_seconds=600]
. "$(dirname "$0")/../scripts/lib.sh"

MAX="${1:-600}"
start=$(date +%s)
first_region=""
switched_at=""

say "Watching $APP_URL (max ${MAX}s) - target RTO 15 min (900s)"
while (( $(date +%s) - start < MAX )); do
  now=$(date +%s); el=$((now - start))
  body=$(curl -fsS --max-time 5 "$APP_URL/api/info" 2>/dev/null || echo '{}')
  region=$(jq -r '.region // "unreachable"' <<<"$body")
  writable=$(jq -r '.dbWritable // "n/a"' <<<"$body")
  printf '   %s  +%4ss  region=%-28s dbWritable=%s\n' "$(ts)" "$el" "$region" "$writable"

  [[ -z "$first_region" && "$region" != "unreachable" ]] && first_region="$region"
  if [[ -n "$first_region" && "$region" != "$first_region" && "$region" != "unreachable" && -z "$switched_at" ]]; then
    switched_at=$el
    ok "traffic moved to $region after ${switched_at}s"
  fi
  if [[ -n "$switched_at" && "$writable" == "true" ]]; then
    ok "writes available in $region after ${el}s"
    (( el <= 900 )) && ok "RTO met (<= 15 min)" || warn "RTO MISSED (> 15 min)"
    exit 0
  fi
  sleep 5
done

if [[ -n "$switched_at" ]]; then
  warn "traffic failed over after ${switched_at}s but standby is still read-only - run: drills/drill.sh promote-replica mel"
else
  warn "no failover observed within ${MAX}s"
fi
exit 1
