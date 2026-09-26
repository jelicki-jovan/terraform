output "default_lifecycle_policy" {
  description = "ECR default lifecycle policy"
  value = templatefile("${path.module}/default_ecr_lifecycle_policy.json.tpl", {
    keep_amount   = 10,
    keep_amount_v = 10,
    only_untagged = false,
  })
}

output "only_untagged_lifecycle_policy" {
  description = "ECR only_untagged lifecycle policy"
  value = templatefile("${path.module}/default_ecr_lifecycle_policy.json.tpl", {
    keep_amount   = 10,
    keep_amount_v = 10,
    only_untagged = true,
  })
}
