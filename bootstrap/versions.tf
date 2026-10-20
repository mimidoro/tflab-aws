terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
  }

  # The state bucket itself is created by bootstrap.sh (step B1) before this runs.
  #   terraform init -backend-config="bucket=tflab-tfstate-$(aws sts get-caller-identity --query Account --output text)"
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = {
      Project   = "tflab-aws-bootstrap" # different value so the leftovers sweep ignores these
      ManagedBy = "terraform"
      Repo      = "mimidoro/tflab-aws"
    }
  }
}

data "aws_caller_identity" "current" {}
