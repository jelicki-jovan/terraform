output "karpenter_node_iam_role_name" {
  description = "Used in the EC2NodeClass (role)"
  value       = module.karpenter.node_iam_role_name
}
