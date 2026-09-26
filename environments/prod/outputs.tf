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

output "nat_public_ips" {
  description = "Egress IPs of the private subnets (NAT gateways)"
  value       = module.vpc.nat_public_ips
}
