data "aws_canonical_user_id" "current" {
  count = length(local.acl_grants) > 0 ? 1 : 0
}

data "aws_iam_policy_document" "enforce_ssl_requests" {
  # Allow public read access for static website hosting
  dynamic "statement" {
    for_each = var.public_read ? [1] : []

    content {
      sid = "PublicReadGetObject"

      effect = "Allow"
      actions = [
        "s3:GetObject",
      ]
      resources = [
        "${aws_s3_bucket.this.arn}/*",
      ]

      principals {
        type        = "*"
        identifiers = ["*"]
      }
    }
  }

  # Deny bucket deletion for everyone (remove this statement first to delete the bucket)
  dynamic "statement" {
    for_each = var.prevent_deletion ? [1] : []

    content {
      sid = "DenyBucketDeletion"

      effect = "Deny"
      actions = [
        "s3:DeleteBucket",
      ]
      resources = [
        aws_s3_bucket.this.arn,
      ]

      principals {
        type        = "*"
        identifiers = ["*"]
      }
    }
  }

  # Enforce SSL/TLS for all requests
  statement {
    sid = "EnforceSSLRequests"

    effect = "Deny"
    actions = [
      "s3:*",
    ]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false"
      ]
    }
  }
}
