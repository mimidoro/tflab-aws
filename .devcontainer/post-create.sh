#!/usr/bin/env bash
# Runs once when the dev container / codespace is created.
set -euo pipefail

sudo apt-get update -qq
sudo apt-get install -y -qq jq unzip shellcheck bc >/dev/null

# Cilium + Hubble CLIs (cluster status, flow observation through hubble-relay)
arch=$(dpkg --print-architecture)   # amd64 | arm64
cver=$(curl -fsSL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -fsSL "https://github.com/cilium/cilium-cli/releases/download/${cver}/cilium-linux-${arch}.tar.gz" \
  | sudo tar -xz -C /usr/local/bin cilium
hver=$(curl -fsSL https://raw.githubusercontent.com/cilium/hubble/main/stable.txt)
curl -fsSL "https://github.com/cilium/hubble/releases/download/${hver}/hubble-linux-${arch}.tar.gz" \
  | sudo tar -xz -C /usr/local/bin hubble

# Regression suite deps + Chromium so `make test` works straight away.
(cd tests/regression && npm ci --no-audit --no-fund && npx playwright install --with-deps chromium)

cat <<'EOF'

tflab-aws dev container ready. Versions:
EOF
for t in aws terraform helm gh node dotnet jq; do
  printf '  %-10s %s\n' "$t" "$($t --version 2>/dev/null | head -1)"
done
printf '  %-10s %s\n' kubectl "$(kubectl version --client 2>/dev/null | head -1)"
printf '  %-10s %s\n' cilium "$(cilium version --client 2>/dev/null | head -1)"
printf '  %-10s %s\n' hubble "$(hubble version 2>/dev/null | head -1)"
cat <<'EOF'

Next:
  aws login --remote --profile tflab-admin   # console sign-in, never root or access keys
                                             # region prompt: ap-southeast-2; pick the LAB account session (073019354521)
  export AWS_PROFILE=tflab-admin
  ./bootstrap/bootstrap.sh

Bootstrap step B3 creates a GitHub environment + variable, which needs repo ADMIN rights.
The codespace's built-in token can't do that, so sign gh in as yourself first:
  unset GITHUB_TOKEN && gh auth login   # (locally: just gh auth login)
EOF
