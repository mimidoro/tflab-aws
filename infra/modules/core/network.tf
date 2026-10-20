data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two AZs keeps cost down while still surviving a single-AZ failure.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]       # /20 - EKS nodes
  public_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 200 + i)] # /24 - ALB, NAT
  database_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 210 + i)] # /24 - RDS

  create_database_subnet_group = true
  enable_dns_hostnames         = true
  enable_dns_support           = true
  map_public_ip_on_launch      = false

  # Managed NAT Gateways cost ~USD 0.06/hr each + data. A NAT instance (below) costs ~USD 0.005/hr.
  enable_nat_gateway = false

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

# fck-nat: community NAT instance AMI on t4g.nano, as ONE plain EC2 instance (ha_mode = false).
# Trade-off accepted for a lab: single NAT for both AZs and no self-healing - if it dies, egress
# stops until the next apply. ASG mode was dropped: its first launch in this new account failed
# ("Authentication Failure") and a half-created ASG blocks later applies (AlreadyExists).
module "nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "~> 1.6"

  name          = "${var.name}-nat"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnets[0]
  instance_type = "t4g.nano"
  ha_mode       = false

  update_route_tables = true
  route_tables_ids    = { for i, id in module.vpc.private_route_table_ids : "private-${i}" => id }
}
