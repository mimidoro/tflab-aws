# ---------------------------------------------------------------- Route 53 failover
# Health check probes Sydney's /api/ready (API up AND database writable).
# 3 failures x 10s interval => failover in ~30-60s; DNS TTL is 60s for alias records.
resource "aws_route53_health_check" "syd" {
  provider          = aws.syd
  fqdn              = "syd.${var.domain_name}"
  type              = "HTTPS"
  port              = 443
  resource_path     = "/api/ready"
  request_interval  = 10
  failure_threshold = 3
  measure_latency   = false
  regions           = ["ap-southeast-1", "ap-northeast-1", "us-west-2"]

  tags = { Name = "tflab-syd-ready" }
}

resource "aws_route53_record" "app_primary" {
  provider        = aws.syd
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = local.app_hostname
  type            = "A"
  set_identifier  = "sydney-primary"
  health_check_id = aws_route53_health_check.syd.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = module.syd_core.alb_dns_name
    zone_id                = module.syd_core.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app_secondary" {
  provider       = aws.syd
  zone_id        = data.aws_route53_zone.this.zone_id
  name           = local.app_hostname
  type           = "A"
  set_identifier = "melbourne-secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = module.mel_core.alb_dns_name
    zone_id                = module.mel_core.alb_zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------- Failover alarm (us-east-1)
# Route 53 publishes HealthCheckStatus to us-east-1 only, so the alarm + topic live there.
resource "aws_sns_topic" "global_alerts" {
  provider = aws.use1
  name     = "tflab-global-alerts"
}

resource "aws_sns_topic_subscription" "global_email" {
  provider  = aws.use1
  topic_arn = aws_sns_topic.global_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "syd_health" {
  provider            = aws.use1
  alarm_name          = "tflab-FAILOVER-sydney-unhealthy"
  alarm_description   = "Sydney /api/ready failing - Route 53 is sending traffic to Melbourne. Run drills/promote-replica.sh if Sydney DB is lost (RTO target 15 min)."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.syd.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.global_alerts.arn]
  ok_actions          = [aws_sns_topic.global_alerts.arn]
}
