# Providers are configured in the root (terraform.tf) and inherited; this only declares the sources
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}
