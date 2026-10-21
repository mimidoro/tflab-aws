# EKS Pod Identity: pods get short-lived AWS credentials for their service account only.
# No static keys, no secrets in manifests.

data "aws_iam_policy_document" "pod_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# --- API: IAM database auth as tflab_api on databases in THIS region ----------------------
# Scoped by region + DB user, not by the instance's resource ID: DR rebuilds the database
# (promote, fail-back), which changes its resource ID and would lock the API out until the
# next apply. Only lab databases exist in this account/region, and only they have tflab_api.
resource "aws_iam_role" "api" {
  name               = "${var.name}-api"
  assume_role_policy = data.aws_iam_policy_document.pod_trust.json
}

resource "aws_iam_role_policy" "api_db_connect" {
  name = "rds-iam-connect"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:aws:rds-db:${local.region}:${var.account_id}:dbuser:*/tflab_api"
    }]
  })
}

resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = var.core.cluster_name
  namespace       = "app"
  service_account = "api"
  role_arn        = aws_iam_role.api.arn
}

# --- db-init Job (primary only): reads the tflab master secret once to create tflab_api --------
resource "aws_iam_role" "db_init" {
  count              = var.is_primary ? 1 : 0
  name               = "${var.name}-db-init"
  assume_role_policy = data.aws_iam_policy_document.pod_trust.json
}

resource "aws_iam_role_policy" "db_init" {
  count = var.is_primary ? 1 : 0
  name  = "read-master-secret"
  role  = aws_iam_role.db_init[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.core.db_master_secret_arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "db_init" {
  count           = var.is_primary ? 1 : 0
  cluster_name    = var.core.cluster_name
  namespace       = "app"
  service_account = "db-init"
  role_arn        = aws_iam_role.db_init[0].arn
}

# --- CloudWatch agent: ships Cilium/Hubble Prometheus metrics as CloudWatch metrics --------
resource "aws_iam_role" "cwagent" {
  name               = "${var.name}-cwagent"
  assume_role_policy = data.aws_iam_policy_document.pod_trust.json
}

resource "aws_iam_role_policy_attachment" "cwagent" {
  role       = aws_iam_role.cwagent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_pod_identity_association" "cwagent" {
  cluster_name    = var.core.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cwagent"
  role_arn        = aws_iam_role.cwagent.arn
}
