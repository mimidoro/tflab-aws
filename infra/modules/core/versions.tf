terraform {
  required_version = ">= 1.11" # write-only arguments
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7" # ephemeral random_password
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
