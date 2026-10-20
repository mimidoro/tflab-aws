terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }

  # Remote state in S3 with native lock files (no DynamoDB table needed).
  # The bucket name includes the account ID, so scripts pass it at init:
  #   terraform init -backend-config="bucket=tflab-tfstate-$(aws sts get-caller-identity --query Account --output text)"
  backend "s3" {
    key          = "infra/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
