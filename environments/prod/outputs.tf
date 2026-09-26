output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "database_subnet_group_name" {
  value = module.vpc.database_subnet_group_name
}

output "nat_public_ips" {
  description = "Egress IPs of the private subnets (NAT gateways)"
  value       = module.vpc.nat_public_ips
}
