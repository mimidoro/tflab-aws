#!/usr/bin/env bash
# Runs once when the dev container / codespace is created.
set -euo pipefail

sudo apt-get update -qq
sudo apt-get install -y -qq jq unzip shellcheck bc >/dev/null

# Regression suite deps + Chromium so `make test` works straight away.
(cd tests/regression && npm ci --no-audit --no-fund && npx playwright install --with-deps chromium)

cat <<'EOF'

tflab-aws dev container ready. Versions:
EOF
for t in aws terraform helm gh node dotnet jq; do
  printf '  %-10s %s\n' "$t" "$($t --version 2>/dev/null | head -1)"
done
printf '  %-10s %s\n' kubectl "$(kubectl version --client 2>/dev/null | head -1)"
cat <<'EOF'

Next:
  aws login --remote --profile tflab-admin   # console sign-in, never root or access keys
  export AWS_PROFILE=tflab-admin
  ./bootstrap/bootstrap.sh

Bootstrap step B3 creates a GitHub environment + variable, which needs repo ADMIN rights.
The codespace's built-in token can't do that, so sign gh in as yourself first:
  unset GITHUB_TOKEN && gh auth login   # (locally: just gh auth login)
EOF
