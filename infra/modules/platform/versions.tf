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
}

data "aws_region" "current" {}

locals {
  region     = data.aws_region.current.region
  charts_dir = "${path.module}/../../../k8s/charts"
  values_dir = "${path.module}/../../../k8s/values"
}
