### Loki: log storage in S3 (chunks + index), accessed by the Loki pod via IRSA
module "loki_bucket" {
  source = "../../modules/s3"

  environment = "prod"
  name        = "hw-loki-prod"

  versioning    = "Enabled"
  force_destroy = true
}

# Loki's compactor deletes chunks after the 30-day retention; with versioning they'd stay as
# noncurrent versions forever, so expire those (keeps 7 days to recover from mistakes)
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = module.loki_bucket.bucket_id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "loki" {
  statement {
    sid       = "LokiBucketList"
    actions   = ["s3:ListBucket"]
    resources = [module.loki_bucket.bucket_arn]
  }

  statement {
    sid = "LokiObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${module.loki_bucket.bucket_arn}/*"]
  }
}

module "loki_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "hw-eks-loki-prod"
  use_name_prefix = false
  policy_name     = "hw-eks-loki-prod"

  source_policy_documents = [data.aws_iam_policy_document.loki.json]

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:loki"]
    }
  }
}

### Grafana: read-only CloudWatch access (RDS/ALB metrics, AWS-side logs) for its CloudWatch data source
data "aws_iam_policy_document" "grafana_cloudwatch" {
  statement {
    sid = "CloudWatchMetricsRead"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport",
    ]
    resources = ["*"]
  }

  statement {
    sid = "CloudWatchLogsRead"
    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ResourceDiscovery"
    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

module "grafana_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "hw-eks-grafana-prod"
  use_name_prefix = false
  policy_name     = "hw-eks-grafana-prod"

  source_policy_documents = [data.aws_iam_policy_document.grafana_cloudwatch.json]

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:grafana"]
    }
  }
}

### Alerting: everything ends in one SNS topic → email.
###   CloudWatch alarms (next to their component: rds.tf, frontend.tf): work even when the cluster is down
###   Alertmanager (in-cluster rules): publishes to SNS via IRSA
###   Dead man's switch: Alertmanager sends the always-firing Watchdog to hw-watchdog-prod; a CloudWatch
###   alarm fires when nothing arrives there (monitoring itself is down)
###
### Email subscription is NOT managed here (it would put the address in the public repo, and Terraform
### can't confirm email subscriptions). Subscribe once by hand, then click the link in the email:
###   aws sns subscribe --region us-east-1 --protocol email --notification-endpoint <email> \
###     --topic-arn $(terraform output -raw alerts_topic_arn)
resource "aws_sns_topic" "alerts" {
  name = "hw-alerts-prod"
}

# Heartbeat only, no subscribers
resource "aws_sns_topic" "watchdog" {
  name = "hw-watchdog-prod"
}

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
