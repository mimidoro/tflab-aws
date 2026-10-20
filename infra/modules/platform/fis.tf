# AWS Fault Injection Service (FIS) experiment templates. Run with drills/drill.sh or the
# "drill" GitHub workflow. Costs USD 0.10 per action-minute; every action is time-boxed.
# Stop condition "none" is deliberate for a lab; in production use an alarm as the stop condition.
# FIS is not offered in every region (no endpoint in Melbourne, ap-southeast-4, as of 2026-10):
# enable_fis = false skips all of it there; Chaos Mesh / Cilium / RDS-API drills still work.

resource "aws_iam_role" "fis" {
  count = var.enable_fis ? 1 : 0
  name  = "${var.name}-fis"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "fis.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fis" {
  for_each = var.enable_fis ? toset([
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEKSAccess",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorRDSAccess",
    "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess",
  ]) : toset([])
  role       = aws_iam_role.fis[0].name
  policy_arn = each.value
}

# 1. Kill half the worker nodes -> pods reschedule, ALB marks targets unhealthy, ASG replaces.
resource "aws_fis_experiment_template" "node_terminate" {
  count       = var.enable_fis ? 1 : 0
  description = "${var.name}: terminate 50% of nodes in the node group"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "terminate-nodes"
    action_id = "aws:eks:terminate-nodegroup-instances"
    target {
      key   = "Nodegroups"
      value = "nodegroup"
    }
    parameter {
      key   = "instanceTerminationPercentage"
      value = "50"
    }
  }

  target {
    name           = "nodegroup"
    resource_type  = "aws:eks:nodegroup"
    resource_arns  = [module.nodes.node_group_arn]
    selection_mode = "ALL"
  }

  tags = { Name = "${var.name}-node-terminate" }
}

# 2. Reboot the database -> API /ready fails briefly, 5xx alarm, recovery.
resource "aws_fis_experiment_template" "db_reboot" {
  count       = var.enable_fis ? 1 : 0
  description = "${var.name}: reboot the RDS instance"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "reboot-db"
    action_id = "aws:rds:reboot-db-instances"
    target {
      key   = "DBInstances"
      value = "db"
    }
  }

  target {
    name           = "db"
    resource_type  = "aws:rds:db"
    resource_arns  = [var.core.db_instance_arn]
    selection_mode = "ALL"
  }

  tags = { Name = "${var.name}-db-reboot" }
}

# 3. Single-AZ network blackout (first private subnet) for 5 minutes.
resource "aws_fis_experiment_template" "az_blackout" {
  count       = var.enable_fis ? 1 : 0
  description = "${var.name}: cut all network traffic in one AZ's private subnet for 5 min"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "disrupt-az"
    action_id = "aws:network:disrupt-connectivity"
    target {
      key   = "Subnets"
      value = "az-subnet"
    }
    parameter {
      key   = "duration"
      value = "PT5M"
    }
    parameter {
      key   = "scope"
      value = "all"
    }
  }

  target {
    name           = "az-subnet"
    resource_type  = "aws:ec2:subnet"
    resource_arns  = [var.core.private_subnet_arns[0]]
    selection_mode = "ALL"
  }

  tags = { Name = "${var.name}-az-blackout" }
}

# 4. Whole-region blackout (all private subnets) for 10 minutes -> Route 53 fails over.
resource "aws_fis_experiment_template" "region_blackout" {
  count       = var.enable_fis ? 1 : 0
  description = "${var.name}: cut all private-subnet traffic for 10 min (regional outage)"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "disrupt-region"
    action_id = "aws:network:disrupt-connectivity"
    target {
      key   = "Subnets"
      value = "all-private"
    }
    parameter {
      key   = "duration"
      value = "PT10M"
    }
    parameter {
      key   = "scope"
      value = "all"
    }
  }

  target {
    name           = "all-private"
    resource_type  = "aws:ec2:subnet"
    resource_arns  = var.core.private_subnet_arns
    selection_mode = "ALL"
  }

  tags = { Name = "${var.name}-region-blackout" }
}
