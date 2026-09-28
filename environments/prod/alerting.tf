# Alerting: everything ends in one SNS topic → email.
#   CloudWatch alarms (RDS, ALB): work even when the whole cluster is down
#   Alertmanager (in-cluster rules): publishes to SNS via IRSA
#   Dead man's switch: Alertmanager sends the always-firing Watchdog to hw-watchdog-prod; a CloudWatch
#   alarm fires when nothing arrives there (monitoring itself is down)
#
# Email subscription is NOT managed here (it would put the address in the public repo, and Terraform
# can't confirm email subscriptions). Subscribe once by hand, then click the link in the email:
#   aws sns subscribe --region us-east-1 --protocol email --notification-endpoint <email> \
#     --topic-arn $(terraform output -raw alerts_topic_arn)
#
# Topics are not KMS-encrypted: CloudWatch can't publish to a topic encrypted with the AWS-managed key
# (would need a customer-managed key); alert contents are not sensitive.

resource "aws_sns_topic" "alerts" {
  name = "hw-alerts-prod"
}

# Heartbeat only, no subscribers
resource "aws_sns_topic" "watchdog" {
  name = "hw-watchdog-prod"
}

# --- Alertmanager → SNS (IRSA) ---

data "aws_iam_policy_document" "alertmanager" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn, aws_sns_topic.watchdog.arn]
  }
}

module "alertmanager_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "hw-eks-alertmanager-prod"
  use_name_prefix = false
  policy_name     = "hw-eks-alertmanager-prod"

  source_policy_documents = [data.aws_iam_policy_document.alertmanager.json]

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:alertmanager"]
    }
  }
}

# --- Dead man's switch ---

# Alertmanager re-sends Watchdog every 5 min; no message for 15 min → Prometheus, Alertmanager or the
# cluster is down (missing data counts as breaching)
resource "aws_cloudwatch_metric_alarm" "watchdog" {
  alarm_name          = "hw-monitoring-heartbeat-prod"
  alarm_description   = "No Watchdog heartbeat from Alertmanager for 15 min: in-cluster monitoring/alerting is down"
  namespace           = "AWS/SNS"
  metric_name         = "NumberOfMessagesPublished"
  dimensions          = { TopicName = aws_sns_topic.watchdog.name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- RDS ---

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "hw-rds-cpu-prod"
  alarm_description   = "RDS CPU > 80% for 10 min"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = module.rds.db_instance_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Storage autoscaling goes up to 100 GB, this catches it before/when that runs out
resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "hw-rds-free-storage-prod"
  alarm_description   = "RDS free storage < 2 GB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = module.rds.db_instance_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 2 * 1024 * 1024 * 1024
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# db.t4g.micro has 1 GB; ~170 MB freeable at idle (2026-09-28)
resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory" {
  alarm_name          = "hw-rds-freeable-memory-prod"
  alarm_description   = "RDS freeable memory < 100 MB for 10 min"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = module.rds.db_instance_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 100 * 1024 * 1024
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- ALB ---
# The ALB and its target group are created by the AWS Load Balancer Controller (Ingress), not by
# Terraform. Looked up by the controller's tags: on a fresh environment the list is empty (no error),
# so these alarms appear on the first apply after ArgoCD has created the ALB.

data "aws_lbs" "frontend" {
  tags = {
    "elbv2.k8s.aws/cluster" = module.eks.cluster_name
    "ingress.k8s.aws/stack" = "prod/hw-frontend-prod"
  }
}

data "aws_lb_target_group" "frontend" {
  for_each = data.aws_lbs.frontend.arns

  tags = {
    "elbv2.k8s.aws/cluster" = module.eks.cluster_name
    "ingress.k8s.aws/stack" = "prod/hw-frontend-prod"
  }
}

# 5xx returned by our pods (nginx/backend), not by the ALB itself
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  for_each = data.aws_lbs.frontend.arns

  alarm_name          = "hw-alb-target-5xx-prod"
  alarm_description   = "More than 10 HTTP 5xx from the app in 5 min"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = split("loadbalancer/", each.value)[1] }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  for_each = data.aws_lbs.frontend.arns

  alarm_name        = "hw-alb-unhealthy-targets-prod"
  alarm_description = "Unhealthy frontend targets behind the ALB for 5 min"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "UnHealthyHostCount"
  dimensions = {
    LoadBalancer = split("loadbalancer/", each.value)[1]
    TargetGroup  = data.aws_lb_target_group.frontend[each.key].arn_suffix
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  for_each = data.aws_lbs.frontend.arns

  alarm_name          = "hw-alb-latency-p95-prod"
  alarm_description   = "p95 response time from the app > 1 s for 10 min"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = split("loadbalancer/", each.value)[1] }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
