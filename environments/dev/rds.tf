module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"

  identifier = "hw-rds-dev"

  engine                   = "postgres"
  engine_version           = "17.11"
  family                   = "postgres17"
  major_engine_version     = "17"
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  # Dev: smallest class (1 replica per app, test traffic only);
  # Dev: smallest class (1 replica per app, test traffic only); prod runs db.t3.small
  instance_class = "db.t4g.micro"

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

  # Dev: single-AZ (cost); prod is Multi-AZ
  multi_az               = false
  create_db_subnet_group = false
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  parameter_group_name            = "hw-rds-dev"
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

  backup_retention_period  = 1
  backup_window            = "03:00-04:00"
  maintenance_window       = "Mon:04:30-Mon:05:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = true

  # Dev: disposable, easy to destroy (prod: deletion protection + final snapshot)
  deletion_protection = false
  skip_final_snapshot = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 7

  auto_minor_version_upgrade = true
  apply_immediately          = false
}

resource "aws_security_group" "rds" {
  name        = "hw-rds-dev"
  description = "PostgreSQL, access only from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "hw-rds-dev"
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
