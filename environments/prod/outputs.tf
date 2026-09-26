output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "database_subnet_group_name" {
  value = module.vpc.database_subnet_group_name
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "karpenter_node_iam_role_name" {
  description = "Used in the EC2NodeClass (role)"
  value       = module.karpenter.node_iam_role_name
}

output "rds_endpoint" {
  value = module.rds.db_instance_address
}

output "rds_master_user_secret_arn" {
  description = "RDS-managed secret (username/password), read by External Secrets"
  value       = module.rds.db_instance_master_user_secret_arn
}

output "backend_secret_arn" {
  value = aws_secretsmanager_secret.backend.arn
}

output "aws_lb_controller_role_arn" {
  description = "IRSA role for the AWS Load Balancer Controller service account"
  value       = module.aws_lb_controller_irsa.arn
}

output "external_secrets_role_arn" {
  description = "IRSA role for the External Secrets service account"
  value       = module.external_secrets_irsa.arn
}

output "nat_public_ips" {
  description = "Egress IPs of the private subnets (NAT gateways)"
  value       = module.vpc.nat_public_ips
}
