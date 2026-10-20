# Cost guard (memory hook: 25-50-75-90)
#   25 / 50 / 75 % of USD 100 actual  -> email + ops topic
#   100 % forecast                    -> email + ops topic
#   USD 90 actual                     -> budget ACTION attaches tflab-deny-create to the deploy role
# Budgets are NET of credits (include_credit = false) so they track real card spend.
# Budget data refreshes ~3x a day: this is a backstop, not a substitute for the nightly destroy.

resource "aws_sns_topic" "ops" {
  name = "tflab-ops"
}

resource "aws_sns_topic_subscription" "ops_email" {
  topic_arn = aws_sns_topic.ops.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "ops_topic" {
  statement {
    sid       = "AllowBudgets"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.ops.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid       = "AllowAccountPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.ops.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_sns_topic_policy" "ops" {
  arn    = aws_sns_topic.ops.arn
  policy = data.aws_iam_policy_document.ops_topic.json
}

resource "aws_budgets_budget" "guard" {
  name         = "tflab-aws-guard"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = [25, 50, 75]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
      subscriber_sns_topic_arns  = [aws_sns_topic.ops.arn]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.ops.arn]
  }

  depends_on = [aws_sns_topic_policy.ops]
}

# --- Kill switch ----------------------------------------------------------------------
# Blocks NEW billable resources from the deploy role. Destroy still works, so the nightly
# and manual teardown workflows keep running. Undo: PLAYBOOK > "Kill switch tripped".
data "aws_iam_policy_document" "deny_create" {
  statement {
    sid    = "DenyNewBillableResources"
    effect = "Deny"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateNatGateway",
      "ec2:AllocateAddress",
      "eks:CreateCluster",
      "eks:CreateNodegroup",
      "rds:CreateDBInstance",
      "rds:CreateDBInstanceReadReplica",
      "elasticloadbalancing:CreateLoadBalancer",
      "autoscaling:CreateAutoScalingGroup",
      "fis:StartExperiment",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deny_create" {
  name        = "tflab-deny-create"
  description = "Attached by the budget action at USD ${var.kill_switch_usd} net spend"
  policy      = data.aws_iam_policy_document.deny_create.json
}

resource "aws_iam_role" "budget_action" {
  name = "tflab-budget-action"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "budget_action" {
  name = "attach-deny-create"
  role = aws_iam_role.budget_action.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
      Resource  = aws_iam_role.github.arn
      Condition = { ArnEquals = { "iam:PolicyARN" = aws_iam_policy.deny_create.arn } }
    }]
  })
}

resource "aws_budgets_budget_action" "kill_switch" {
  budget_name        = aws_budgets_budget.guard.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budget_action.arn

  action_threshold {
    action_threshold_type  = "ABSOLUTE_VALUE"
    action_threshold_value = var.kill_switch_usd
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.deny_create.arn
      roles      = [aws_iam_role.github.name]
    }
  }

  subscriber {
    address           = var.alert_email
    subscription_type = "EMAIL"
  }
}
