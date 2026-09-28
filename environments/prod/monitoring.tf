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
