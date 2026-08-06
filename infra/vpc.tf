

# Queries AZs in whatever region your provider is configured for. Two filters matter:
# state = "available" — excludes AZs that are impaired or not usable.
# opt-in-status = "opt-in-not-required" — this is the important one. It excludes Local
# Zones, Wavelength Zones, and AZs in opt-in regions. Those zones often don't support EKS

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# local.azs takes the first var.az_count names off that list.
# Note AWS shuffles AZ names per account (your us-east-1a is not my us-east-1a), but that doesn't matter here since you just need N distinct zones.


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


  # cidrsubnet(prefix, 4, n) adds 4 bits to the mask, giving 16 possible subnets numbered 0–
  # 15. Public takes slots 0,1,2…; private starts at slot 8. That offset leaves a clean gap and makes the CIDRs readable at a glance.
  # Two constraints fall out of this that are worth knowing:
  #       az_count must be ≤ 8.
  # The "/20 = 4091 usable" comment is only true if vpc_cidr is a /16. 16 + 4 = /20, which is 4096 addresses minus the 5 AWS reserves in every subnet




  # /20 per subnet = 4091 usable IPs. The VPC CNI assigns a real VPC IP to every
  # pod, so subnets that feel oversized for the node count are correct here -
  # running out of IPs is a classic EKS failure and costs nothing to prevent.
  
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Nodes in public subnets need a public IP to reach the internet via the IGW.

  # This applies to public subnets only in this module. When NAT is off and nodes land in public
  # subnets, they need a public IP to actually use the IGW — a private-IP-only instance in a public subnet still can't reach the internet.

  map_public_ip_on_launch = !var.enable_nat_gateway


  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = false


  # When you create VPC interface endpoints AWS creates a private hosted zone
  # so that api.ecr.us-east-1.amazonaws.com resolves to the endpoint's private IP instead of the public one



  # Controls whether instances that get a public IP also get an AWS-assigned public DNS
  # hostname — the ec2-203-0-113-25.compute-1.amazonaws.com style name. It also enables
  # resolution of the internal ip-10-0-1-45.ec2.internal names.
  enable_dns_hostnames = true
  # Controls whether the Amazon-provided DNS resolver is reachable from inside the VPC.
  # When it's on, DHCP hands instances that resolver address, and anything in the VPC can
  # resolve public DNS names plus any private hosted zones associated with the VPC
  # When it's off, DNS queries to that address get no response, and you'd have to run or point at your own resolver
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
