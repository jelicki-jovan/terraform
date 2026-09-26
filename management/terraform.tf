provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      env : "management"
      project : "home-work"
      terraform : "true"
    }
  }
}

terraform {
  # Enabled after the first apply (bucket is created by this stack), then: terraform init -migrate-state
  backend "s3" {
    bucket = "terraform-backend-home-work"
    key    = "management/terraform.tfstate"
    region = "us-east-1"

    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }

  required_version = ">= 1.10"
}
