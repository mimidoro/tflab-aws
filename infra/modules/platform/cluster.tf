# Order matters for a CNI replacement:
#   1. Cilium Helm release (no wait - there are no nodes yet)
#   2. Node group (nodes start tainted until the Cilium agent is ready on them)
#   3. CoreDNS + Pod Identity agent add-ons
#   4. Everything else

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"
  wait       = false

  values = [templatefile("${local.values_dir}/cilium.yaml.tftpl", {
    cluster_name = var.core.cluster_name
    api_host     = trimprefix(var.core.cluster_endpoint, "https://")
    pod_cidr     = var.pod_cidr
  })]
}

module "nodes" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 21.29"

  name                 = "${var.name}-ng"
  cluster_name         = var.core.cluster_name
  kubernetes_version   = var.kubernetes_version
  cluster_service_cidr = var.core.cluster_service_cidr

  subnet_ids                        = var.core.private_subnet_ids
  cluster_primary_security_group_id = var.core.cluster_primary_security_group_id
  vpc_security_group_ids            = [var.core.node_security_group_id]

  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "SPOT"
  instance_types = var.node_instance_types

  # 2 nodes across 2 AZs; room for 1 extra during Spot replacement / node-kill drills.
  min_size     = 2
  desired_size = 2
  max_size     = 3

  # No VPC CNI - Cilium owns pod networking.
  iam_role_attach_cni_policy = false

  # Keep pods off a node until Cilium is ready there (Cilium removes this taint itself).
  taints = {
    cilium = {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  }

  labels = {
    "tflab/region-role" = var.is_primary ? "primary" : "standby"
  }

  depends_on = [helm_release.cilium]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = var.core.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.nodes]
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name                = var.core.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.nodes]
}

# HPA needs metrics-server. hostNetwork because the EKS control plane cannot reach
# overlay pod IPs (same reason applies to every admission webhook / APIService).
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"

  values = [yamlencode({
    hostNetwork   = { enabled = true }
    containerPort = 4443 # 10250 is taken by the kubelet on the host network
  })]

  depends_on = [aws_eks_addon.coredns]
}

# Target groups -> node group ASG (one ASG per managed node group).
resource "aws_autoscaling_attachment" "this" {
  for_each               = toset(["web", "api"])
  autoscaling_group_name = module.nodes.node_group_autoscaling_group_names[0]
  lb_target_group_arn    = var.core.target_group_arns[each.key]
}
