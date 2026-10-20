# Look inside a cluster (memory hook: NCH - Nodes, Cilium, Hubble)

There is no hosted dashboard; everything is reached from the codespace with your own sign-in
(`aws login --remote --profile tflab-admin`). Your console role (`AccountFullAccessRole`) is an
EKS cluster admin via access entries, so kubectl, Hubble and the EKS console all work.

```bash
make kubeconfig              # contexts tflab-syd, tflab-mel
make observe REGION=syd      # nodes (AZ, type, Spot), pods per node, cilium status, HPA, last drops
make hubble REGION=syd       # Hubble UI on :12000 (Codespaces: Ports tab > 12000 > open in browser)
scripts/observe.sh syd flows # live flows in namespace app
scripts/observe.sh syd drops # live dropped flows only (try during drills/drill.sh db-block)
```

| Question | Where |
|---|---|
| How many nodes, which AZ, Spot or On-Demand? | `make observe` (top table); EKS console > cluster > Compute |
| Is Cilium healthy on every node? | `cilium --context tflab-syd status` |
| Who talks to whom, what got dropped and why? | Hubble UI (service map + flow table) or `hubble observe --verdict DROPPED` |
| Pod scaling | `kubectl --context tflab-syd -n app get hpa -w` |
| Alarms and metrics | CloudWatch > Alarms (Sydney, Melbourne, us-east-1); metrics namespace `tflab/Cilium` |

## Encrypted traffic

| Hop | Encrypted? | What you can see |
|---|---|---|
| Browser -> ALB | yes, TLS 1.2/1.3 (ACM cert) | ALB metrics / alarms; contents never |
| ALB -> node -> pod | no (HTTP inside the VPC) | Hubble flows: source, destination, port, verdict |
| Pod -> pod across nodes | no - VXLAN overlay, not encrypted | Hubble flows |
| API -> RDS | yes, TLS verify-full + IAM auth token | Hubble shows the TCP 5432 flow (to the VPC CIDR); contents never |

Hubble shows flow **metadata** (who, where, port, allowed/dropped), not payloads - and nothing can
read TLS payloads without the keys, which is the point. To encrypt pod-to-pod traffic too, enable
Cilium WireGuard transparent encryption (`encryption.enabled=true`, `encryption.type=wireguard` in
`k8s/values/cilium.yaml.tftpl`; check with `cilium --context tflab-syd encrypt status`). That is
backlog item 4 in `improve.md`.
