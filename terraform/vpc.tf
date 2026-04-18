module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs            = local.azs
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # ADR-001: no private subnets, no NAT Gateway. Workers run in public
  # subnets with tight security groups to keep cost under $150 / 2 weeks.
  enable_nat_gateway = false
  single_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = local.common_tags
}
