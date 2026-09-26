### ECR repositories for prod
module "ecr_prod" {
  source = "../modules/ecr"

  for_each = toset(["backend", "frontend"])

  repository_name    = "hw-${each.key}-prod"
  keep_images_amount = 30
  force_delete       = true
}
