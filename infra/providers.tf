locals {
  tags = {
    Project   = "tflab-aws"
    ManagedBy = "terraform"
    Repo      = "mimidoro/tflab-aws"
  }
}

# Sydney - primary region
provider "aws" {
  alias  = "syd"
  region = "ap-southeast-2"
  default_tags { tags = local.tags }
}

# Melbourne - standby region (opt-in region: enable it first, playbook step M3)
provider "aws" {
  alias  = "mel"
  region = "ap-southeast-4"
  default_tags { tags = local.tags }
}

# us-east-1 - Route 53 health-check metrics only live here
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
  default_tags { tags = local.tags }
}

provider "helm" {
  alias = "syd"
  kubernetes = {
    host                   = module.syd_core.cluster_endpoint
    cluster_ca_certificate = base64decode(module.syd_core.cluster_ca)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.syd_core.cluster_name, "--region", "ap-southeast-2"]
    }
  }
}

provider "helm" {
  alias = "mel"
  kubernetes = {
    host                   = module.mel_core.cluster_endpoint
    cluster_ca_certificate = base64decode(module.mel_core.cluster_ca)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.mel_core.cluster_name, "--region", "ap-southeast-4"]
    }
  }
}
