variable "environment" {
  description = "S3 bucket environment"
  type        = string
}

variable "name" {
  description = "S3 bucket name"
  type        = string
}

variable "external_bucket_policy" {
  description = "Is bucket policy managed externaly?"
  type        = bool

  default = false
}

variable "public_read" {
  description = "Allow public read access to all objects (static website hosting)"
  type        = bool

  default = false
}

variable "force_destroy" {
  description = "Delete all objects (incl. versions) when the bucket is destroyed"
  type        = bool

  default = false
}

variable "prevent_deletion" {
  description = "Deny s3:DeleteBucket for everyone via bucket policy"
  type        = bool

  default = false
}

variable "versioning" {
  description = "Is bucket versioning enabled?"
  type        = string

  default = "Enabled"
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm (AES256 or aws:kms)"
  type        = string

  default = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "The variable sse_algorithm must be AES256 or aws:kms."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN used when sse_algorithm is aws:kms (null = AWS managed key)"
  type        = string

  default = null
}

variable "tags" {
  description = "Tags to add to the resources"
  type        = map(string)
  default     = {}
}

variable "acl" {
  description = "(Optional) The canned ACL to apply. Defaults to 'private'. Ignored if ownership is BucketOwnerEnforced"
  type        = string
  default     = "private"
}

variable "object_ownership" {
  description = "Bucket ownership controls"
  type        = string

  default = "BucketOwnerEnforced"
}

variable "grants" {
  type = list(object({
    id          = string
    type        = string
    permissions = list(string)
  }))
  default     = []
  description = <<-EOT
    A list of policy grants for the bucket, taking a list of permissions.
    Conflicts with `acl`. Set `acl` to `null` to use this
    EOT
}

variable "website" {
  description = "Map containing static web-site hosting or redirect configuration."
  type        = map(string)
  default     = {}
}

variable "cors_rule" {
  description = "List of maps containing rules for Cross-Origin Resource Sharing."
  type        = any
  default     = []
}

variable "public_access_block" {
  description = "Global flags for bucket public access. Defaults to all blocked, set to null to leave unmanaged. See https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block"
  type = object({
    block_public_acls       = bool
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  })
  default = {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}
