data "aws_caller_identity" "current" {}

# 1. Networking (VPC & Subnets) using Community Module (Tier 1)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "aws-landing-zone-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Disable NAT Gateways to respect Free Tier boundaries
  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Environment = "Production"
    Project     = "AWS-Landing-Zone"
  }
}

# 2. Security Logging (CloudTrail) - Fallback to Native Resources (Tier 2)
# Since no verified community module exists in the terraform-aws-modules namespace for cloudtrail.
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket        = "aws-landing-zone-trail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Environment = "Production"
    Project     = "AWS-Landing-Zone"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_bucket_pab" {
  bucket                  = aws_s3_bucket.cloudtrail_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_bucket_sse" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy_doc.json
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy_doc" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_bucket.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_cloudtrail" "trail" {
  name                          = "aws-landing-zone-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_bucket_policy
  ]
}

# 3. Budget Monitoring Guardrail using Native Resource (Tier 2)
resource "aws_budgets_budget" "monthly_budget" {
  name         = "monthly-budget-limit"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = kedesai@gmail.com
  }
}
