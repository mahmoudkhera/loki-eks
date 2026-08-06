terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Remote state is optional. S3 + native locking (no DynamoDB table needed,
  # which saves a few cents and one resource). Uncomment and fill in to use.
  #
  # backend "s3" {
  #   bucket       = "my-tfstate-bucket"
  #   key          = "eks-cheap/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.cluster_name
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

