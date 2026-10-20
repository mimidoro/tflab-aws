# EKS control plane only - node groups are created in the platform module AFTER Cilium is
# installed. Module v21 never installs the self-managed VPC CNI / kube-proxy / CoreDNS
# (bootstrap_self_managed_addons = false), which is exactly what a Cilium CNI replacement needs.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint so GitHub-hosted runners can reach it; access still requires IAM + access entry.
  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    for i, arn in var.admin_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Pod Identity is used instead of IRSA; secrets encryption uses the EKS default AWS-owned key
  # (no per-cluster KMS key to pay for or wait 7+ days to delete).
  enable_irsa       = false
  create_kms_key    = false
  encryption_config = null

  # Control-plane logs for auditability, kept 1 day to stay cheap.
  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 1

  node_security_group_additional_rules = {
    cilium_vxlan = {
      description = "Cilium VXLAN overlay between nodes"
      protocol    = "udp"
      from_port   = 8472
      to_port     = 8472
      type        = "ingress"
      self        = true
    }
    alb_nodeports = {
      description              = "ALB to web/api NodePorts"
      protocol                 = "tcp"
      from_port                = 30080
      to_port                  = 30081
      type                     = "ingress"
      source_security_group_id = aws_security_group.alb.id
    }
  }
}
