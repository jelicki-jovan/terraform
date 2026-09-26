data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  force_delete = var.force_delete

  tags = merge({
    Name = var.repository_name
  }, var.tags)
}

resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.should_create_lc_policy ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = var.lifecycle_policy == "" ? (
    templatefile("${path.module}/policies/default_ecr_lifecycle_policy.json.tpl", {
      keep_amount   = var.keep_images_amount,
      keep_amount_v = var.keep_images_amount_v,
      only_untagged = var.use_only_untagged_lifecyle_policy,
    })
    ) : templatefile(var.lifecycle_policy, {
      keep_amount   = var.keep_images_amount,
      keep_amount_v = var.keep_images_amount_v,
      only_untagged = var.use_only_untagged_lifecyle_policy,
  })
}
