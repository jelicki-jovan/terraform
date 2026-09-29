module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"

  identifier = "hw-rds-prod"

  engine                   = "postgres"
  engine_version           = "17.11"
  family                   = "postgres17"
  major_engine_version     = "17"
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  # Was db.t4g.micro (1 GB): the freeable-memory alarm showed it short on memory on day one.
  # db.t3.small (2 GB, x86) because db.t4g.small (Graviton) hit InsufficientDBInstanceCapacity for
  # Multi-AZ twice (2026-09-29); same memory, different capacity pool
  instance_class = "db.t3.small"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "home_work"
  username = "home_work_admin"
  port     = 5432

  # Master user (RDS-managed password in Secrets Manager) only for migrations; the app logs in as a
  # least-privilege user with IAM auth: 15-min token from its IRSA role instead of a password
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  multi_az               = true
  create_db_subnet_group = false
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  parameter_group_name            = "hw-rds-prod"
  parameter_group_use_name_prefix = false
  parameters = [
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "pending-reboot"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    },
  ]

  create_db_option_group = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:30-Mon:05:30"
  copy_tags_to_snapshot   = true
  # Keep automated backups (PITR) until they expire even if the instance is deleted
  delete_automated_backups = false

  deletion_protection              = true
  skip_final_snapshot              = false
  final_snapshot_identifier_prefix = "hw-rds-prod-final"

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 30

  auto_minor_version_upgrade = true
  apply_immediately          = false
}

resource "aws_security_group" "rds" {
  name        = "hw-rds-prod"
  description = "PostgreSQL, access only from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "hw-rds-prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes"
}

### Alarms → SNS hw-alerts-prod (monitoring.tf); also send OK on recovery

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

# db.t3.small has 2 GB (on db.t4g.micro, 1 GB, this alarm fired on day one: ~75 MB free)
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
