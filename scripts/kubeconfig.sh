#!/usr/bin/env bash
# Add both lab clusters to ~/.kube/config as contexts tflab-syd and tflab-mel.
. "$(dirname "$0")/lib.sh"
for key in syd mel; do
  ctx "$key" && ok "context ${CLUSTER_OF[$key]}"
done
echo "   e.g. kubectl --context tflab-syd -n app get pods"
echo "   Hubble UI: kubectl --context tflab-syd -n kube-system port-forward svc/hubble-ui 12000:80"
