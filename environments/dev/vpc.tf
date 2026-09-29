module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "dev-vpc"

  cidr = "10.2.0.0/16"

  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets   = ["10.2.0.0/22", "10.2.4.0/22", "10.2.8.0/22"]
  private_subnets  = ["10.2.16.0/20", "10.2.32.0/20", "10.2.48.0/20"]
  database_subnets = ["10.2.64.0/24", "10.2.65.0/24", "10.2.66.0/24"]

  enable_dns_support   = true
  enable_dns_hostnames = true

  create_igw         = true
  enable_nat_gateway = true
  # Dev: one NAT for all AZs (cost); an AZ outage can cut egress for the others (prod: one per AZ)
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  create_database_nat_gateway_route  = false

  manage_default_security_group = false

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 7

  vpc_tags = {
    Name = "dev-vpc"
  }

  public_subnet_tags = {
    "Tier"                   = "Public"
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "Tier"                            = "Private"
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = "hw-eks-dev"
  }

  database_subnet_tags = {
    "Tier" = "Database"
  }
}
