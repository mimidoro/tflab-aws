# Regional alert topic + alarms on AWS-native metrics (free to publish; alarms ~USD 0.10/month each).
# Topic is not KMS-encrypted: CloudWatch alarms cannot publish to topics using the aws/sns key,
# and alert text contains no sensitive data.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  lb_dim        = { LoadBalancer = aws_lb.this.arn_suffix }
}

# --- Edge / ALB --------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-target-5xx"
  alarm_description   = "API/web returning 5xx through the ALB."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.lb_dim
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx" {
  alarm_name          = "${var.name}-alb-no-healthy-targets"
  alarm_description   = "ALB itself returning 502/503/504 - usually no healthy targets."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = local.lb_dim
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "api_unhealthy" {
  alarm_name          = "${var.name}-api-unhealthy-targets"
  alarm_description   = "One or more nodes failing the API health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = merge(local.lb_dim, { TargetGroup = aws_lb_target_group.api.arn_suffix })
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "web_unhealthy" {
  alarm_name          = "${var.name}-web-unhealthy-targets"
  alarm_description   = "One or more nodes failing the web health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = merge(local.lb_dim, { TargetGroup = aws_lb_target_group.web.arn_suffix })
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.name}-api-latency-p95"
  alarm_description   = "API p95 response time above 1s (try the network-delay chaos experiment)."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = merge(local.lb_dim, { TargetGroup = aws_lb_target_group.api.arn_suffix })
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Database ----------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name}-db-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.name}-db-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648 # 2 GiB
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# RPO guard: replica lag above 5 minutes gives 10 minutes' warning before the 15-minute RPO is at risk.
resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  count               = var.is_primary ? 0 : 1
  alarm_name          = "${var.name}-db-replica-lag-RPO-risk"
  alarm_description   = "Melbourne replica more than 5 min behind Sydney - 15 min RPO at risk."
  namespace           = "AWS/RDS"
  metric_name         = "ReplicaLag"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
