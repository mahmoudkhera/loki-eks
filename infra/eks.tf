locals {
  default_instance_types = {
    x86_64 = ["t3.medium", "t3a.medium", "t2.medium"]
    arm64  = ["t4g.medium", "t4g.large"]
  }

  # coalesce returns the first non-null, non-empty argument
  instance_types = coalesce(var.instance_types, local.default_instance_types[var.node_architecture])

  ami_type = var.node_architecture == "arm64" ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"
  # Feeds var.cluster_name straight through. Two things follow from this that aren't visible
  # It's an immutable attribute. Changing it doesn't rename anything; it destroys and recreates the cluster,
  # along with node groups, the OIDC provider, and the IRSA role trust relationships that reference that provider ARN.
  # It's also the anchor for a lot of derived naming across your config
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version


  # These three flags control how the Kubernetes API server is reachable. They're independent booleans, and at least one must be true

  # Public API endpoint. Keeping this on avoids needing interface VPC endpoints
  # for EKS/ECR/STS/S3, which would otherwise cost roughly $7/month EACH plus
  # per-GB processing - easily more than the NAT Gateway we already avoided.
  # Lock it down with public_access_cidrs rather than by going private.



  # keeps the internet-facing endpoint alive, so kubectl from your laptop or CI works without a VPN or bastion.
  cluster_endpoint_public_access       = true
  # is the allowlist on that public endpoint — an AWS-managed network filter, evaluated before authentication. Module default is ["0.0.0.0/0"].
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs

  # creates ENIs for the API server inside your VPC subnets and a private hosted zone
  # so that <id>.gr7.<region>.eks.amazonaws.com resolves to those private IPs from inside the VPC
  cluster_endpoint_private_access      = true

  # Grants the IAM principal running `terraform apply` cluster-admin via an
  # EKS access entry. Without this you can create a cluster you cannot kubectl into.
  enable_cluster_creator_admin_permissions = true

  # Control plane logging is billed per GB ingested into CloudWatch.
  cluster_enabled_log_types              = var.enable_cluster_logging ? var.cluster_log_types : []
  
  # If you enable log types without a log group existing, EKS creates one itsel
  # with Never expire retention. Logs then accumulate forever, on a resource Terraform doesn't manage and won't clean up on destroy.
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
        # the version is resolved at plan time, so it can change between applies without you touching the config
        # CoreDNS addon update is a rolling restart of cluster DNS
        most_recent = true
        # CoreDNS defaults to 2 replicas. On a 1-node cluster the second replica
        # sits Pending forever due to anti-affinity
        # If you kubectl scale deployment/coredns --replicas=2 by hand
        # the addon will revert it on its next reconcile or on the next Terraform apply. Configuration has to go through configuration_values
        configuration_values = jsonencode({
          replicaCount = var.node_min_size >= 2 ? 2 : 1
        })
      }

      kube-proxy = { most_recent = true }
      # The most consequential addon block
      # The plugin that gives pods their network. Unlike overlay CNIs (Calico, Flannel) that create a
      # virtual network on top of the VPC, the AWS VPC CNI hands every pod a real VPC IP address from your subnet.
      # pods are first-class VPC citizens. Security groups apply to them, ALBs can target pod IPs directly, no encapsulation overhead
      
      vpc-cni = {
        most_recent    = true
        
        # This forces the addon to be installed before the node groups are created. It matters specifically because of prefix delegation.
        before_compute = true
        configuration_values = jsonencode({
          env = {
            # Prefix delegation: assigns /28 IP prefixes to ENIs instead of
            # individual IPs. Raises max-pods-per-node substantially, so you can
            # pack more pods onto fewer, smaller instances. Pure cost win.

            # EKS caps max-pods at 110 for instances under 32 vCPUs
            ENABLE_PREFIX_DELEGATION = "true"
            # Keep one full spare prefix (16 IPs) allocated ahead of demand, so pod scheduling doesn't block on an EC2 API call to allocate more.
            # 1 is the recommended minimum. The tradeoff is that every node holds 16 addresses it may not use

            WARM_PREFIX_TARGET       = "1"
          }
        })
      }
    },
    # Since Kubernetes 1.23, in-tree cloud storage drivers were removed. Without this addon, a PersistentVolumeClaim requesting an EBS volume just sits Pending forever

    # The driver runs as two pieces:
    #     controller (Deployment) — talks to the AWS API to create, delete, attach, detach, and snapshot volumes
    #     node (DaemonSet) — formats and mounts the attached device inside the pod

    var.enable_ebs_csi_driver ? {
      aws-ebs-csi-driver = {
        most_recent              = true
        service_account_role_arn = module.ebs_csi_irsa[0].iam_role_arn
      }
    } : {}
  )






  # A baseline map merged into every entry in eks_managed_node_groups

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
      # desired_size drifts. If Cluster Autoscaler or Karpenter scales the group to 5 nodes, your
      # Terraform config still says 2, and the next apply scales it back down — evicting pods for no reason


      desired_size = var.node_desired_size

      

      metadata_options = {
        http_endpoint               = "enabled"
        # http_tokens = "required" enforces IMDSv2. The difference:
        http_tokens                 = "required"
      # http_put_response_hop_limit = 1 It's the IP TTL on the metadata response.
      # Pods sit behind an extra network hop (the veth pair into the pod's namespace
      # so a TTL of 1 means the response dies before reaching a pod, while processes on the host itself can still read it

        http_put_response_hop_limit = 1
      }

      labels = {
        "capacity-type" = lower(var.capacity_type)
      }


    }
  }
}

# IRSA role for the EBS CSI driver, created only when the driver is enabled.

# This creates the IAM role that the EBS CSI controller assumes. It's the concrete
# implementation of IRSA — worth walking through the mechanism, because the trust policy is
# where the actual security lives.
module "ebs_csi_irsa" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${var.cluster_name}-ebs-csi"
  # Attaches the AWS-managed AmazonEBSCSIDriverPolicy, which grants CreateVolume,
  # DeleteVolume, AttachVolume, DetachVolume, CreateSnapshot, and friends.

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
/*
How IRSA works underneath

This is the part worth understanding properly, since the module hides it.

The trust policy the module generates looks roughly like:

{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/ABC123"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  # Restricts how the role can be assumed. Plain sts:AssumeRole isn't permitted here — an IAM
  # user or EC2 instance can't take this role, even in the same account. Only the web-identity flow works.
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/id/ABC123:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
      "oidc.eks.us-east-1.amazonaws.com/id/ABC123:aud": "sts.amazonaws.com"
    }
  }
}


That sub condition is the security boundary. It says: only a pod running as ebs-csi-controller-sa in kube-system
can assume this role. A pod in another namespace, or with a different service account, gets denied by STS.
the aud : The audience claim — who the token was intended for. EKS sets this on projected service account tokens.





*/

# IRSA role for the AWS Load Balancer Controller, created only when enabled.
module "lb_controller_irsa" {
  count = var.enable_lb_controller ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}