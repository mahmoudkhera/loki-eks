data "aws_caller_identity" "current" {}

locals {
  loki_bucket_name = var.loki_bucket_name != null && trimspace(var.loki_bucket_name) != "" ? var.loki_bucket_name : substr(
    regexreplace(lower("loki-${var.cluster_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"), "[^a-z0-9-]+", "-"),
    0,
    63,
  )
}

resource "aws_s3_bucket" "loki_logs" {
  count = var.enable_loki_bucket ? 1 : 0

  bucket = local.loki_bucket_name

  tags = {
    Name        = local.loki_bucket_name
    Purpose     = "loki-logs"
    Service     = "loki"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "loki_logs" {
  count = var.enable_loki_bucket ? 1 : 0

  bucket = aws_s3_bucket.loki_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  count = var.enable_loki_bucket ? 1 : 0

  bucket = aws_s3_bucket.loki_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  count = var.enable_loki_bucket ? 1 : 0

  bucket = aws_s3_bucket.loki_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "loki_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = ["system:serviceaccount:${var.loki_namespace}:${var.loki_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}


data "aws_iam_policy_document" "loki_s3_access" {
  count = var.enable_loki_bucket ? 1 : 0

  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.loki_logs[0].arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.loki_logs[0].arn}/*"]
  }
}

resource "aws_iam_role" "loki_s3" {
  count = var.enable_loki_bucket ? 1 : 0

  name = "${var.cluster_name}-loki-s3"

  assume_role_policy = data.aws_iam_policy_document.loki_assume_role.json

  tags = {
    Purpose = "loki-irsa"
  }
}

resource "aws_iam_policy" "loki_s3" {
  count = var.enable_loki_bucket ? 1 : 0

  name   = "${var.cluster_name}-loki-s3"
  policy = data.aws_iam_policy_document.loki_s3_access[0].json
}

resource "aws_iam_role_policy_attachment" "loki_s3" {
  count = var.enable_loki_bucket ? 1 : 0

  role       = aws_iam_role.loki_s3[0].name
  policy_arn = aws_iam_policy.loki_s3[0].arn
}
