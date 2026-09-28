locals {
  acl_grants = var.grants == null ? [] : flatten(
    [
      for grant in var.grants : [
        for permission in grant.permissions : {
          id         = grant.id
          type       = grant.type
          permission = permission
        }
      ]
  ])
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = merge({
    Name = var.name
  }, var.tags)
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.sse_algorithm == "aws:kms"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.public_access_block != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.public_access_block.block_public_acls
  block_public_policy     = var.public_access_block.block_public_policy
  ignore_public_acls      = var.public_access_block.ignore_public_acls
  restrict_public_buckets = var.public_access_block.restrict_public_buckets
}

resource "aws_s3_bucket_policy" "this" {
  # Do not manage bucket policy here if it's managed elsewhere e.g. CloudFront
  # See https://github.com/hashicorp/terraform-provider-aws/issues/6334
  count = var.external_bucket_policy ? 0 : 1

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.enforce_ssl_requests.json

  depends_on = [aws_s3_bucket_public_access_block.this]

  lifecycle {
    precondition {
      condition     = !var.public_read || try(!var.public_access_block.block_public_policy && !var.public_access_block.restrict_public_buckets, true)
      error_message = "public_read = true requires block_public_policy and restrict_public_buckets to be false in public_access_block."
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning
  }
}

resource "aws_s3_bucket_acl" "this" {
  count = var.object_ownership != "BucketOwnerEnforced" ? 1 : 0

  bucket = aws_s3_bucket.this.id

  depends_on = [aws_s3_bucket_ownership_controls.this]

  acl = length(local.acl_grants) == 0 ? var.acl : null

  dynamic "access_control_policy" {
    for_each = length(local.acl_grants) == 0 ? [] : [1]

    content {
      dynamic "grant" {
        for_each = local.acl_grants

        content {
          grantee {
            id   = grant.value.id
            type = grant.value.type
          }
          permission = grant.value.permission
        }
      }

      owner {
        id = data.aws_canonical_user_id.current[0].id
      }
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_website_configuration" "this" {
  count  = length(keys(var.website)) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "index_document" {
    for_each = try([var.website["index_document"]], [])

    content {
      suffix = index_document.value
    }
  }

  dynamic "error_document" {
    for_each = try([var.website["error_document"]], [])

    content {
      key = error_document.value
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = try(length(var.cors_rule), 0) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rule

    content {
      id              = try(cors_rule.value.id, null)
      allowed_headers = try(cors_rule.value.allowed_headers, null)
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = try(cors_rule.value.expose_headers, null)
      max_age_seconds = try(cors_rule.value.max_age_seconds, null)
    }
  }
}
