# Alarms on Cilium/Hubble metrics shipped by the CloudWatch agent (namespace tflab/Cilium).
# Counters arrive as cumulative values, so alarms use metric-math RATE().

resource "aws_cloudwatch_metric_alarm" "hubble_drops" {
  alarm_name          = "${var.name}-cilium-packet-drops"
  alarm_description   = "Hubble sees dropped flows (policy denies, unreachable endpoints). Try chaos/experiments/network-partition.yaml."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.core.sns_topic_arn]
  ok_actions          = [var.core.sns_topic_arn]

  metric_query {
    id          = "drops_per_sec"
    expression  = "RATE(m1)"
    label       = "Hubble drops/sec"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      namespace   = "tflab/Cilium"
      metric_name = "hubble_drop_total"
      dimensions  = { ClusterName = var.core.cluster_name }
      period      = 60
      stat        = "Maximum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cilium_unreachable_nodes" {
  alarm_name          = "${var.name}-cilium-unreachable-nodes"
  alarm_description   = "Cilium health reports unreachable nodes (node kill / AZ blackout drills)."
  namespace           = "tflab/Cilium"
  metric_name         = "cilium_unreachable_nodes"
  dimensions          = { ClusterName = var.core.cluster_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.core.sns_topic_arn]
  ok_actions          = [var.core.sns_topic_arn]
}
