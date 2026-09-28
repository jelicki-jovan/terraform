# Daily EBS snapshots with Data Lifecycle Manager (AWS Backup is denied by the SCP).
# Targets every volume tagged backup=daily: the EBS CSI driver adds that tag to all volumes it creates
# (Prometheus, Loki). RDS has its own automated backups (rds.tf).

resource "aws_iam_role" "dlm" {
  name = "hw-dlm-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dlm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "ebs_daily" {
  # Only letters, digits, spaces, _ and - allowed
  description        = "hw-ebs-daily-prod - daily snapshots of volumes tagged backup daily - keep 7"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      backup = "daily"
    }

    schedule {
      name = "daily"

      # After the RDS backup window (03:00-04:00 UTC)
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["04:00"]
      }

      retain_rule {
        count = 7
      }

      # Volume tags (kubernetes.io/created-for/pvc/name, ...) show which PVC a snapshot belongs to
      copy_tags = true

      tags_to_add = {
        SnapshotCreator = "dlm"
      }
    }
  }

  tags = {
    Name = "hw-ebs-daily-prod"
  }
}
