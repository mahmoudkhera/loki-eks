variable "region" {
  description = "AWS region. Pick the cheapest one that meets your latency needs; us-east-1 is usually lowest."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "stockwatch"
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes minor version for the control plane.

    COST WARNING: each version gets 14 months of STANDARD support at $0.10/hr.
    After that it silently rolls into EXTENDED support at $0.60/hr - a 6x jump,
    from ~$73/mo to ~$438/mo, with no notification that would stop it.
    Always create on the newest available version and upgrade before month 14.
  EOT
  type        = string
  default     = "1.36"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs. EKS requires a minimum of 2 for the control plane ENIs."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "EKS requires subnets in at least 2 availability zones."
  }
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Set false (default) to run worker nodes in PUBLIC subnets with no NAT Gateway.
    This is the single biggest cost saving in this config: a NAT Gateway is
    ~$33/month in hourly charges PLUS ~$0.045 per GB processed, and every image
    pull goes through it.

    Set true for a private-subnet layout when you need nodes to have no inbound
    reachability from the internet (production, compliance).
  EOT
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "If NAT is enabled, share ONE gateway across all AZs instead of one per AZ. Saves ~$33/mo per extra AZ; costs you AZ-failure isolation."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Node group
# ---------------------------------------------------------------------------

variable "node_architecture" {
  description = <<-EOT
    "x86_64" or "arm64".

    arm64 (Graviton, t4g family) is roughly 20% cheaper per vCPU than x86.
    BUT every container image you run must have an arm64 build - your own
    services, plus any third-party chart (ArgoCD, ingress controllers,
    Prometheus...). Most mainstream images publish multi-arch manifests now,
    but verify before switching, and be ready to add `--platform linux/arm64`
    to your CI builds.
  EOT
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.node_architecture)
    error_message = "node_architecture must be x86_64 or arm64."
  }
}

variable "instance_types" {
  description = <<-EOT
    Candidate instance types for the Spot node group. Listing SEVERAL types is
    a Spot best practice, not redundancy: it widens the capacity pool so AWS is
    far less likely to reclaim your nodes.

    Leave null to use a sensible default list for the chosen architecture.
    x86_64 default: t3.medium, t3a.medium, t2.medium  (2 vCPU / 4 GB)
    arm64  default: t4g.medium, t4g.large
  EOT
  type        = list(string)
  default     = null
}

variable "capacity_type" {
  description = <<-EOT
    "SPOT" or "ON_DEMAND".

    SPOT is ~70% cheaper and is the right default for dev/staging. Nodes can be
    reclaimed with a 2-minute warning; the managed node group drains and
    replaces them automatically. Do not put stateful singletons on Spot without
    a PDB and tolerant storage.
  EOT
  type        = string
  default     = "SPOT"
}

variable "node_min_size" {
  description = "Minimum nodes. 1 keeps the floor cheap; 2 keeps you alive during a Spot reclaim."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum nodes the group may scale to."
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Starting node count. 2 gives you room for system pods plus a small app."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root EBS volume size in GB per node. 20 is enough for the AMI, kubelet and a modest image cache."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# Optional add-ons (each one costs money - all default OFF)
# ---------------------------------------------------------------------------

variable "enable_ebs_csi_driver" {
  description = "Install the EBS CSI driver so PersistentVolumeClaims work. Turn on only if your workloads need persistent volumes - each PVC provisions a billed EBS volume."
  type        = bool
  default     = false
}

variable "enable_cluster_logging" {
  description = "Ship control plane logs to CloudWatch. Off by default: ingestion is ~$0.50/GB and a chatty API server audit log adds up fast."
  type        = bool
  default     = false
}

variable "cluster_log_types" {
  description = "Which control plane log types to enable, if enable_cluster_logging is true."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint. TIGHTEN THIS to your office/VPN IP - the default is open to the internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
