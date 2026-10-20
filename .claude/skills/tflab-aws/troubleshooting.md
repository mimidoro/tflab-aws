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

## Account and sign-in (learned during first setup, 2026-10-20/21)

| Symptom | Cause | Fix |
|---|---|---|
| `missing tool: aws` from bootstrap | not in the dev container | open a Codespace from `main`; existing codespace: **Codespaces: Full Rebuild Container** |
| `route53domains ... Free Tier accounts are not supported` | Free plan | upgrade to the Paid plan (M2); credits carry over |
| `sso:CreateInstance ... explicit deny in a service control policy` | AWS "project" account (new AWS experience) | don't create Identity Center; use `aws login --remote`; activate advanced features (M0) for the two-region lab |
| Melbourne / second region denied, `RegionFloor` in the policy | AWS region-restriction SCP | M0b: attach `tflab-guardrails` to Root, detach `AdvancedModeRegionRestrictionSecurityControlPolicy` |
| "Root user credentials are not valid or sign-in as root is currently disabled" | management root password never set, wrong email, or a project account (no root) | reach the management account via settings.aws.com; for emergency root: *Forgot password* on the management email |
| "Choose AWS sessions" page | multi-session console | **Add session** / **Sign in to another account**, or a private window |
| `aws login` asks "No AWS region has been configured" | new profile | answer `ap-southeast-2` (or `aws configure set region ap-southeast-2 --profile tflab-admin`) |
| `get-caller-identity` shows 996241422033 | logged in to the management account | `aws logout --profile tflab-admin`; open the lab project console via settings.aws.com; `aws login --remote` and pick that session |
| `gh` 403 creating the `lab` environment in a codespace | codespace token isn't repo admin | `unset GITHUB_TOKEN && gh auth login` |
| `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` | token `sub` doesn't match the trust policy (GitHub now sends `repo:owner@ID/repo@ID:environment:lab`) | check what was sent: `aws cloudtrail lookup-events --region ap-southeast-2 --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity --max-results 3 --query 'Events[].CloudTrailEvent' --output text \| jq -c '{err:.errorCode,sub:.userIdentity.userName}'`; set `github_owner_id` / `github_repo_id` in `bootstrap/variables.tf`, re-run bootstrap |
| `rds:CreateDBInstanceReadReplica ... on resource ...:db:tflab-syd-pg with an explicit deny in a service control policy` | `tflab-guardrails` v1 size cap had no `Null` guard: the replica call is also checked against the *source* DB, where `rds:DatabaseClass` is absent, so `StringNotLike` denied it | update the SCP in the management account to the current `bootstrap/org/scp-tflab-guardrails.json` (`Null` guard), re-run `up` |
| `waiting for Auto Scaling Group (tflab-syd-nat) ... Authentication Failure. Launching EC2 instance failed.` | first Auto Scaling launch in a new account (service-linked role still propagating), or an SCP denying the launch | check `aws cloudtrail lookup-events --region ap-southeast-2 --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances --max-results 5 --query 'Events[].CloudTrailEvent' --output text \| jq -c '{err:.errorCode,msg:.errorMessage,who:.userIdentity.arn}'`; no SCP deny -> just re-run `up` |
| `Creating read replicas for source instance with engine postgres where ManageMasterUserPassword is enabled is not supported` | RDS-managed master password on the source | fixed: master password is now write-only (`password_wo`) into our own secret `tflab-syd-pg-master`; recreate cleanly with `down` then `up` |
| `creating Auto Scaling Group (tflab-syd-nat) ... AlreadyExists` | a failed earlier run left the group behind, outside Terraform state | `aws autoscaling delete-auto-scaling-group --region ap-southeast-2 --auto-scaling-group-name tflab-syd-nat --force-delete`, wait until gone, re-run |
| `lookup fis.ap-southeast-4.amazonaws.com ... no such host` | AWS FIS isn't offered in Melbourne | fixed: `enable_fis = false` for Melbourne; FIS drills are Sydney-only |
