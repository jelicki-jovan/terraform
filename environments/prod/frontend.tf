### Frontend app: the public entry point (ALB). Its Kubernetes side lives in k8s-envs.

### The ALB and its target group are created by the AWS Load Balancer Controller from the frontend's
### Ingress, not by Terraform. Looked up by the controller's tags: on a fresh environment the list is
### empty (no error), so the alarms appear on the first apply after ArgoCD has created the ALB.
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

### Alarms → SNS hw-alerts-prod (monitoring.tf); also send OK on recovery

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
