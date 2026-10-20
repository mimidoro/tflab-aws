# --- Chaos Mesh (in-cluster fault injection) -------------------------------------------
resource "helm_release" "chaos_mesh" {
  name             = "chaos-mesh"
  repository       = "https://charts.chaos-mesh.org"
  chart            = "chaos-mesh"
  version          = var.chaos_mesh_version
  namespace        = "chaos-mesh"
  create_namespace = true

  values = [file("${local.values_dir}/chaos-mesh.yaml")]

  depends_on = [aws_eks_addon.coredns]
}

# --- CloudWatch agent (Prometheus scrape of Cilium + Hubble) ---------------------------
resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/tflab/${var.name}/prometheus"
  retention_in_days = 1
}

resource "helm_release" "cwagent" {
  name             = "cwagent"
  chart            = "${local.charts_dir}/cwagent"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  values = [yamlencode({
    clusterName  = var.core.cluster_name
    region       = local.region
    logGroupName = aws_cloudwatch_log_group.prometheus.name
  })]

  depends_on = [aws_eks_addon.coredns, aws_eks_pod_identity_association.cwagent]
}

# --- Application: React web + .NET API (+ db-init Job on the primary) -------------------
resource "helm_release" "app" {
  name             = "tflab"
  chart            = "${local.charts_dir}/app"
  namespace        = "app"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    regionLabel = var.region_label
    isPrimary   = var.is_primary
    awsRegion   = local.region
    image = {
      web = "${var.image_registry}/tflab/web:${var.image_tag}"
      api = "${var.image_registry}/tflab/api:${var.image_tag}"
    }
    web = { minReplicas = var.web_replicas.min, maxReplicas = var.web_replicas.max }
    api = { minReplicas = var.api_replicas.min, maxReplicas = var.api_replicas.max }
    db = {
      host            = var.core.db_address
      name            = "tflab"
      user            = "tflab_api"
      masterSecretArn = var.is_primary ? var.core.db_master_secret_arn : ""
    }
    networkPolicy = { vpcCidr = var.core.vpc_cidr }
  })]

  depends_on = [
    aws_eks_addon.coredns,
    helm_release.metrics_server,
    aws_eks_pod_identity_association.api,
    aws_eks_pod_identity_association.db_init,
    aws_eks_addon.pod_identity,
  ]
}
