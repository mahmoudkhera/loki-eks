data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # When NAT is disabled we place worker nodes in the PUBLIC subnets, because
  # without a NAT Gateway a private subnet has no route to the internet at all -
  # nodes could not pull images or reach the EKS API and would never join.
  node_subnet_ids = var.enable_nat_gateway ? module.vpc.private_subnets : module.vpc.public_subnets
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 per subnet = 4091 usable IPs. The VPC CNI assigns a real VPC IP to every
  # pod, so subnets that feel oversized for the node count are correct here -
  # running out of IPs is a classic EKS failure and costs nothing to prevent.
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Nodes in public subnets need a public IP to reach the internet via the IGW.
  map_public_ip_on_launch = !var.enable_nat_gateway

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC flow logs are useful but bill per GB into CloudWatch. Off for cost.
  enable_flow_log = false

  # Subnet tags the AWS Load Balancer Controller uses to pick where to place
  # ALBs/NLBs. Harmless to leave on even if you never install the controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
