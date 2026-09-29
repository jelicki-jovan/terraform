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
  value       = module.platform.karpenter_node_iam_role_name
}

output "rds_endpoint" {
  value = module.rds.db_instance_address
}

output "rds_master_user_secret_arn" {
  description = "RDS-managed secret (username/password), read by External Secrets"
  value       = module.rds.db_instance_master_user_secret_arn
}

output "backend_role_arn" {
  description = "IRSA role for the backend service account (dev/hw-backend-dev): rds-db:connect as app_user"
  value       = module.backend_irsa.arn
}

output "backend_secret_arn" {
  value = aws_secretsmanager_secret.backend.arn
}

output "aws_lb_controller_role_arn" {
  description = "IRSA role for the AWS Load Balancer Controller service account"
  value       = module.aws_lb_controller_irsa.arn
}

output "eso_namespace_role_arns" {
  description = "Per-namespace IRSA roles for External Secrets (annotation on <namespace>/external-secrets)"
  value       = { for ns, role in module.eso_namespace_irsa : ns => role.arn }
}

output "nat_public_ips" {
  description = "Egress IPs of the private subnets (NAT gateways)"
  value       = module.vpc.nat_public_ips
}
