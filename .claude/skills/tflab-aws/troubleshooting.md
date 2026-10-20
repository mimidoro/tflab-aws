# Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Nodes stuck `NotReady` | Cilium not running (quay.io pull, NAT instance down) | `kubectl -n kube-system get pods -l k8s-app=cilium`; check fck-nat ASG has 1 healthy instance |
| Pods `Pending` with taint `node.cilium.io/agent-not-ready` | Cilium agent crashlooping | `kubectl -n kube-system logs ds/cilium`; check `k8sServiceHost` matches the cluster endpoint |
| Helm install of chaos-mesh / metrics-server times out on webhook | control plane can't reach webhook | confirm `hostNetwork: true` in values and node SG allows 9443 / 4443 from the cluster SG |
| `db-init` Job fails | secret read denied or DB not up | `kubectl -n app logs job/db-init`; check Pod Identity association `app/db-init` |
| API 500 on `/api/items`, `/api/ready` 503 | IAM auth: role or `rds_iam` grant missing | `kubectl -n app logs deploy/api`; re-run `helm upgrade` (re-runs db-init) |
| ALB targets all unhealthy | NodePort not reachable | node SG rule `alb_nodeports`; `kubectl -n app get svc` shows 30080/30081 |
| Spot capacity error in Melbourne | no Spot pool available | add instance types in `node_instance_types`, or temporarily set `capacity_type = "ON_DEMAND"` |
| `terraform destroy` hangs on helm_release | cluster already gone | `scripts/down.sh` handles it; manually: `terraform state rm <helm_release addr>` |
| Deploy role suddenly `AccessDenied` on create | **kill switch tripped** (USD 90) | see PLAYBOOK > "Kill switch tripped" |
| Plan wants to recreate Melbourne DB after a promote drill | replica was promoted | expected: run `down` then `up` to rebuild |
