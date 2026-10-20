#!/usr/bin/env bash
# Look inside a cluster - memory hook "NCH": Nodes, Cilium, Hubble.
# Usage: scripts/observe.sh [syd|mel]       (default syd)
#        scripts/observe.sh syd ui          (opens Hubble UI on :12000 - Codespaces forwards it)
#        scripts/observe.sh syd flows       (live flows; Ctrl-C to stop)
#        scripts/observe.sh syd drops       (only dropped flows)
. "$(dirname "$0")/lib.sh"

KEY="${1:-syd}"; MODE="${2:-summary}"
need_region_key "$KEY"
ctx "$KEY"

case "$MODE" in
  summary)
    say "N  Nodes (${CLUSTER_OF[$KEY]})"
    k get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,eks.amazonaws.com/capacityType
    say "   Pods per node"
    k get pods -A --no-headers -o custom-columns=NODE:.spec.nodeName | sort | uniq -c
    say "C  Cilium"
    cilium --context "$KCTX" status --wait=false || true
    say "   App pods + autoscalers"
    k -n app get pods -o wide
    k -n app get hpa
    say "H  Hubble - last 20 dropped flows"
    cilium --context "$KCTX" hubble port-forward >/dev/null 2>&1 &
    pf=$!; sleep 3
    hubble observe --verdict DROPPED --last 20 || warn "hubble relay not reachable yet"
    kill "$pf" 2>/dev/null || true
    ;;
  ui)
    say "Hubble UI -> http://localhost:12000  (Codespaces: Ports tab > 12000 > open in browser)"
    k -n kube-system port-forward svc/hubble-ui 12000:80
    ;;
  flows|drops)
    cilium --context "$KCTX" hubble port-forward >/dev/null 2>&1 &
    pf=$!; trap 'kill $pf 2>/dev/null' EXIT; sleep 3
    if [[ "$MODE" == drops ]]; then hubble observe --verdict DROPPED --follow
    else hubble observe --namespace app --follow; fi
    ;;
  *) die "mode must be summary, ui, flows or drops" ;;
esac
