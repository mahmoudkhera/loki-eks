locals {
  default_instance_types = {
    x86_64 = ["t3.medium", "t3a.medium", "t2.medium"]
    arm64  = ["t4g.medium", "t4g.large"]
  }

  instance_types = coalesce(var.instance_types, local.default_instance_types[var.node_architecture])

  ami_type = var.node_architecture == "arm64" ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Public API endpoint. Keeping this on avoids needing interface VPC endpoints
  # for EKS/ECR/STS/S3, which would otherwise cost roughly $7/month EACH plus
  # per-GB processing - easily more than the NAT Gateway we already avoided.
  # Lock it down with public_access_cidrs rather than by going private.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs
  cluster_endpoint_private_access      = true

  # Grants the IAM principal running `terraform apply` cluster-admin via an
  # EKS access entry. Without this you can create a cluster you cannot kubectl into.
  enable_cluster_creator_admin_permissions = true

  # Control plane logging is billed per GB ingested into CloudWatch.
  cluster_enabled_log_types              = var.enable_cluster_logging ? var.cluster_log_types : []
  create_cloudwatch_log_group            = var.enable_cluster_logging
  cloudwatch_log_group_retention_in_days = 7

  vpc_id     = module.vpc.vpc_id
  subnet_ids = local.node_subnet_ids

  # Control plane ENIs. Using the same subnets as the nodes keeps things simple
  # and avoids cross-AZ data transfer charges between control plane and kubelet.
  control_plane_subnet_ids = local.node_subnet_ids

  cluster_addons = merge(
    {
      coredns = {
        most_recent = true
        # CoreDNS defaults to 2 replicas. On a 1-node cluster the second replica
        # sits Pending forever due to anti-affinity. Harmless, but noisy.
        configuration_values = jsonencode({
          replicaCount = var.node_min_size >= 2 ? 2 : 1
        })
      }
      kube-proxy = { most_recent = true }
      vpc-cni = {
        most_recent    = true
        before_compute = true
        configuration_values = jsonencode({
          env = {
            # Prefix delegation: assigns /28 IP prefixes to ENIs instead of
            # individual IPs. Raises max-pods-per-node substantially, so you can
            # pack more pods onto fewer, smaller instances. Pure cost win.
            ENABLE_PREFIX_DELEGATION = "true"
            WARM_PREFIX_TARGET       = "1"
          }
        })
      }
    },
    var.enable_ebs_csi_driver ? {
      aws-ebs-csi-driver = {
        most_recent              = true
        service_account_role_arn = module.ebs_csi_irsa[0].iam_role_arn
      }
    } : {}
  )

  eks_managed_node_group_defaults = {
    ami_type = local.ami_type

    # gp3 is ~20% cheaper per GB than gp2 and gives 3000 IOPS baseline for free.
    # There is no reason to ever use gp2 on a new cluster.
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = var.node_disk_size
          volume_type           = "gp3"
          encrypted             = true
          delete_on_termination = true
        }
      }
    }
  }

  eks_managed_node_groups = {
    default = {
      name = "${var.cluster_name}-ng"

      instance_types = local.instance_types
      capacity_type  = var.capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # IMDSv2 required, hop limit 1 so pods cannot reach the instance metadata
      # service and steal the node's IAM role. Free security.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      labels = {
        "capacity-type" = lower(var.capacity_type)
      }

      # Node IAM policies required to pull from ECR and run the CNI.
      iam_role_additional_policies = var.enable_ebs_csi_driver ? {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      } : {}
    }
  }
}

# IRSA role for the EBS CSI driver, created only when the driver is enabled.
module "ebs_csi_irsa" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
