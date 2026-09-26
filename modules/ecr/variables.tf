variable "repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "scan_on_push" {
  description = "Enable vulnerability scan on image push"
  type        = bool

  default = true
}

variable "image_tag_mutability" {
  description = "Tag mutability setting for the repository (MUTABLE or IMMUTABLE)"
  type        = string

  default = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "The variable image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "lifecycle_policy" {
  description = "ECR repository lifecycle policy"
  type        = string
  default     = ""
}

variable "use_only_untagged_lifecyle_policy" {
  description = "Use only_untagged lifecycle policy"
  type        = bool
  default     = false
}

variable "keep_images_amount" {
  description = "Define the number of git SHA tagged images that should be kept"
  type        = number
  default     = 5

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.keep_images_amount))
    error_message = "The variable keep_images_amount must be an integer superior or equal to 1."
  }
}

variable "keep_images_amount_v" {
  description = "Define the number of release images that should be kept ('v' - prefix)"
  type        = number
  default     = 5

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.keep_images_amount_v))
    error_message = "The variable keep_images_amount_v must be an integer superior or equal to 1."
  }
}

variable "should_create_lc_policy" {
  description = "If ECR repository lifecycle policy should be created"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to add to the resources"
  type        = map(string)
  default     = {}
}

variable "force_delete" {
  description = "Force empty and delete ECR"
  type        = bool

  default = false
}
