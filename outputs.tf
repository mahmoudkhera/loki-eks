output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Running Kubernetes version."
  value       = module.eks.cluster_version
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "node_subnets" {
  description = "Subnets the worker nodes were placed in."
  value       = local.node_subnet_ids
}

output "node_instance_types" {
  description = "Instance types in the Spot capacity pool."
  value       = local.instance_types
}

output "cost_notes" {
  description = "Rough monthly cost drivers for this configuration."
  value = {
    control_plane_usd     = "73.00 (fixed, $0.10/hr - upgrade before month 14 or it becomes 438.00)"
    nat_gateway_usd       = var.enable_nat_gateway ? "~33.00 per gateway + $0.045/GB processed" : "0.00 (disabled)"
    nodes                 = "${var.node_desired_size} x ${join("/", local.instance_types)} on ${var.capacity_type}"
    public_ipv4_usd       = var.enable_nat_gateway ? "0.00 (nodes are private)" : format("~%.2f (%d nodes x $3.65/mo)", var.node_desired_size * 3.65, var.node_desired_size)
    ebs_usd               = format("~%.2f (%d x %d GB gp3)", var.node_desired_size * var.node_disk_size * 0.08, var.node_desired_size, var.node_disk_size)
    cloudwatch_logs       = var.enable_cluster_logging ? "ENABLED - billed ~$0.50/GB ingested" : "0.00 (disabled)"
    biggest_remaining_lever = "Delete the cluster when not in use: terraform destroy"
  }
}
