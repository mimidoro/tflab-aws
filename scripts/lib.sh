#!/usr/bin/env bash
# Shared helpers for scripts/ and drills/. Source it: . "$(dirname "$0")/../scripts/lib.sh"
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN="mimidog.click"
APP_URL="https://app.${DOMAIN}"

# shellcheck disable=SC2034 # used by the scripts that source this file
declare -A REGION_OF=([syd]=ap-southeast-2 [mel]=ap-southeast-4)
declare -A CLUSTER_OF=([syd]=tflab-syd [mel]=tflab-mel)
# shellcheck disable=SC2034
declare -A URL_OF=([syd]="https://syd.${DOMAIN}" [mel]="https://mel.${DOMAIN}")

say()  { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mOK\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!!\033[0m %s\n' "$*"; }
die()  { printf '   \033[31mXX\033[0m %s\n' "$*" >&2; exit 1; }
ts()   { date -u +%H:%M:%S; }

account_id() { aws sts get-caller-identity --query Account --output text; }
state_bucket() { echo "tflab-tfstate-$(account_id)"; }

need_region_key() {
  [[ "${1:-}" == "syd" || "${1:-}" == "mel" ]] || die "region must be syd or mel (got '${1:-}')"
}

# Point kubectl at a cluster: ctx syd|mel  (sets KCTX for kubectl --context)
ctx() {
  need_region_key "$1"
  aws eks update-kubeconfig --region "${REGION_OF[$1]}" --name "${CLUSTER_OF[$1]}" \
    --alias "${CLUSTER_OF[$1]}" >/dev/null
  KCTX="${CLUSTER_OF[$1]}"
}

k() { kubectl --context "$KCTX" "$@"; }

tf_init() {
  terraform -chdir="$REPO_ROOT/infra" init -input=false -reconfigure \
    -backend-config="bucket=$(state_bucket)" >/dev/null
}

# Which region does the global hostname currently serve? Prints e.g. "Sydney (ap-southeast-2)"
serving_region() {
  curl -fsS --max-time 5 "$APP_URL/api/info" 2>/dev/null | jq -r '.region // "unreachable"' || echo unreachable
}

confirm() {
  [[ "${ASSUME_YES:-}" == "1" ]] && return 0
  [[ -t 0 ]] || die "confirmation needed: '$1' - re-run with --yes (or confirm = yes in the workflow)"
  local ans
  read -r -p "   $1 [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "aborted"
}
