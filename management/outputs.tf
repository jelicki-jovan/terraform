output "ecr_prod_urls" {
  value = { for name, repo in module.ecr_prod : name => repo.repository_url }
}

output "github_actions_ecr_role_arn" {
  description = "Set as AWS_ROLE_ARN in the app repo's GitHub Actions"
  value       = aws_iam_role.github_actions_ecr.arn
}
