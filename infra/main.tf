# tflab-aws - two-region active-passive lab
#   Sydney (ap-southeast-2)    = primary: 6 app pods (3 web + 3 api), RDS PostgreSQL writer
#   Melbourne (ap-southeast-4) = standby: 4 app pods (2 web + 2 api), RDS cross-region read replica
#   Route 53 failover record app.mimidog.click -> Sydney ALB, falls back to Melbourne ALB
#
# Layering per region:
#   core     (AWS only)  : VPC, NAT instance, EKS control plane, RDS, ALB, ACM, alarms
#   platform (AWS + Helm): Cilium -> nodes -> CoreDNS/Pod Identity -> metrics-server, Chaos Mesh,
#                          CloudWatch agent, app chart, FIS experiments
# Splitting core/platform lets the Helm provider be configured from core outputs without a cycle.

data "aws_caller_identity" "current" {
  provider = aws.syd
}

data "aws_iam_session_context" "current" {
  provider = aws.syd
  arn      = data.aws_caller_identity.current.arn
}

# The role people use day to day (console + `aws login`). In an AWS project account that is
# AccountFullAccessRole. Looked up by name so its IAM path is right; an empty match is fine.
data "aws_iam_roles" "console_admins" {
  provider   = aws.syd
  for_each   = toset(var.console_admin_role_names)
  name_regex = "^${each.value}$"
}

data "aws_route53_zone" "this" {
  provider = aws.syd
  name     = var.domain_name
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  github_role_arn = "arn:aws:iam::${local.account_id}:role/tflab-github-actions"

  # Cluster admins: GitHub Actions role + whoever is running apply + your console role
  # (so kubectl / Hubble / the EKS console work after a GitHub-run apply) + optional extras.
  admin_arns = distinct(compact(concat(
    [local.github_role_arn, data.aws_iam_session_context.current.issuer_arn],
    flatten([for d in data.aws_iam_roles.console_admins : tolist(d.arns)]),
    var.extra_admin_arns,
  )))

  app_hostname = "app.${var.domain_name}"
}

# ---------------------------------------------------------------- Sydney (primary)
module "syd_core" {
  source    = "./modules/core"
  providers = { aws = aws.syd }

  name               = "tflab-syd"
  is_primary         = true
  vpc_cidr           = "10.20.0.0/16"
  kubernetes_version = var.kubernetes_version
  admin_arns         = local.admin_arns
  api_allowed_cidrs  = var.api_allowed_cidrs
  zone_id            = data.aws_route53_zone.this.zone_id
  app_hostname       = local.app_hostname
  regional_hostname  = "syd.${var.domain_name}"
  alert_email        = var.alert_email
}

module "syd_platform" {
  source    = "./modules/platform"
  providers = { aws = aws.syd, helm = helm.syd }

  name                   = "tflab-syd"
  is_primary             = true
  region_label           = "Sydney (ap-southeast-2)"
  core                   = module.syd_core
  kubernetes_version     = var.kubernetes_version
  pod_cidr               = "10.200.0.0/16"
  account_id             = local.account_id
  image_registry         = "${local.account_id}.dkr.ecr.ap-southeast-2.amazonaws.com"
  image_tag              = var.image_tag
  web_replicas           = { min = 2, max = 3 }
  api_replicas           = { min = 2, max = 3 }
  cilium_version         = var.cilium_version
  chaos_mesh_version     = var.chaos_mesh_version
  metrics_server_version = var.metrics_server_version
}

# ---------------------------------------------------------------- Melbourne (standby)
module "mel_core" {
  source    = "./modules/core"
  providers = { aws = aws.mel }

  name               = "tflab-mel"
  is_primary         = false
  db_source_arn      = module.syd_core.db_instance_arn
  vpc_cidr           = "10.40.0.0/16"
  kubernetes_version = var.kubernetes_version
  admin_arns         = local.admin_arns
  api_allowed_cidrs  = var.api_allowed_cidrs
  zone_id            = data.aws_route53_zone.this.zone_id
  app_hostname       = local.app_hostname
  regional_hostname  = "mel.${var.domain_name}"
  alert_email        = var.alert_email
}

module "mel_platform" {
  source    = "./modules/platform"
  providers = { aws = aws.mel, helm = helm.mel }

  name                   = "tflab-mel"
  is_primary             = false
  region_label           = "Melbourne (ap-southeast-4)"
  enable_fis             = false # no FIS endpoint in ap-southeast-4
  core                   = module.mel_core
  kubernetes_version     = var.kubernetes_version
  pod_cidr               = "10.201.0.0/16"
  account_id             = local.account_id
  image_registry         = "${local.account_id}.dkr.ecr.ap-southeast-4.amazonaws.com"
  image_tag              = var.image_tag
  web_replicas           = { min = 2, max = 2 }
  api_replicas           = { min = 2, max = 2 }
  cilium_version         = var.cilium_version
  chaos_mesh_version     = var.chaos_mesh_version
  metrics_server_version = var.metrics_server_version
}
