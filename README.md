# Cost-minimized EKS cluster

Terraform for an EKS cluster with EC2 managed nodes, tuned for the lowest
defensible monthly bill rather than for production hardening.

## Quick start

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars - at minimum set public_access_cidrs to your own IP

terraform init
terraform plan
terraform apply

aws eks update-kubeconfig --region us-east-1 --name stockwatch
kubectl get nodes
```

The Terraform configuration now lives in the infra directory. It also creates an S3 bucket and an IAM role for the Loki service account via IRSA when enable_loki_bucket is true.

Apply takes roughly 12-15 minutes; the control plane alone is about 9 of those.

## Estimated monthly cost (us-east-1, 730 hours)

| Item | Default config | With NAT + on-demand |
|---|---|---|
| EKS control plane | $73.00 | $73.00 |
| Worker nodes | ~$18 (2x t3.medium Spot) | ~$60 (2x t3.medium on-demand) |
| NAT Gateway | $0.00 | ~$33 + $0.045/GB |
| Public IPv4 addresses | ~$7.30 (2 nodes) | $0.00 |
| EBS root volumes | ~$3.20 (2x 20 GB gp3) | ~$3.20 |
| CloudWatch logs | $0.00 | varies |
| **Total** | **~$102/mo** | **~$170/mo** |

Spot prices fluctuate; treat node cost as an estimate. Everything else is fixed.

## Where the savings come from

**No NAT Gateway (~$33/mo + data processing).** The single largest avoidable
cost in almost every EKS setup. A NAT Gateway bills hourly whether or not
traffic flows, and then charges per GB on top - and on Kubernetes every image
pull, every ECR call, and every outbound API request goes through it. This
config puts worker nodes in public subnets behind security groups instead.

**Spot instances (~70% off).** Managed node groups handle Spot interruption
automatically: AWS gives a 2-minute warning, the node is cordoned and drained,
and a replacement is launched. Listing several instance types widens the
capacity pool and makes reclaims much rarer.

**gp3 over gp2 (~20% off storage).** No downside. gp3 is cheaper per GB and
includes 3000 baseline IOPS.

**Prefix delegation on the VPC CNI.** Raises the pods-per-node ceiling
substantially, so you can run the same workload on fewer or smaller instances.

**Public API endpoint.** Going fully private would require interface VPC
endpoints for EKS, ECR (two of them), STS, and S3 - roughly $7/month each plus
per-GB processing, which would cost more than the NAT Gateway this config
already avoids. The endpoint is locked down with a CIDR allowlist instead.

**Nothing optional enabled.** Control plane logging, flow logs, and the EBS CSI
driver are all off by default. Each is a real line item.

## The tradeoff you are accepting

Worker nodes sit in public subnets with public IPs. They are not open - the
security groups still control all inbound traffic, and nothing is reachable
unless a rule permits it - but this is a weaker posture than private subnets
and is not what you would ship for a regulated production workload.

For production, set `enable_nat_gateway = true`. That moves nodes to private
subnets and costs roughly $33/month more.

## The version trap - read this one

EKS charges $0.10/hr per cluster during **standard support**, which lasts 14
months from a version's release. After that the cluster rolls automatically
into **extended support** at $0.60/hr. That is $73/mo becoming $438/mo, with
no action on your part and no interruption to warn you.

As of July 2026, 1.36 and 1.35 are comfortably inside standard support.
**1.33 leaves standard support on 29 July 2026** - do not create a cluster on
it. Verify the current window before you apply:

```bash
aws eks describe-cluster-versions --query \
  'clusterVersions[].{v:clusterVersion,status:status,ends:endOfStandardSupportDate}' \
  --output table
```

Put a calendar reminder for month 12 when you create the cluster.

## Turning it off

The control plane bills hourly whether or not you are using it. For a cluster
you touch a few hours a week, the honest saving is destroying it:

```bash
terraform destroy
```

If you want to keep the cluster but stop node cost overnight:

```bash
# scale to zero nodes - control plane still bills
aws eks update-nodegroup-config \
  --cluster-name stockwatch \
  --nodegroup-name <name> \
  --scaling-config minSize=0,maxSize=3,desiredSize=0
```

## What is deliberately not here

- **Cluster Autoscaler / Karpenter** - Karpenter is the better long-term
  answer for cost (it bin-packs and consolidates aggressively), but it adds
  setup complexity. Worth adding once the cluster is stable.
- **AWS Load Balancer Controller** - each ALB it creates is ~$16-22/mo. Install
  it when you need ingress, and share one ALB across services via a single
  Ingress with host rules rather than one per service.
- **EKS Auto Mode** - AWS manages nodes for you but adds a 10-12% surcharge on
  top of EC2 cost. The opposite of what you asked for.
- **Fargate** - no EC2 nodes, per-pod billing. Often more expensive for
  steady workloads and you asked specifically for EC2.
