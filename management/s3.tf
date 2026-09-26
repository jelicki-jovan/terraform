### S3 Bucket for Terraform state (all stacks)
module "terraform_backend_bucket" {
  source = "../modules/s3"

  environment = "management"
  name        = "terraform-backend-home-work"

  versioning       = "Enabled"
  prevent_deletion = true
}
