provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      env : "prod"
      project : "home-work"
      terraform : "true"
    }
  }
}

terraform {
  backend "s3" {
    bucket = "terraform-backend-home-work"
    key    = "prod/terraform.tfstate"
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
