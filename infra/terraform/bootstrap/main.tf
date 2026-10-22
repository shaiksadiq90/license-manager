# One-time setup per AWS account, applied with local state:
#   1. S3 bucket + DynamoDB table for the remote Terraform state of every environment
#   2. GitHub OIDC trust + a deploy role, so CI pushes images without any stored AWS keys
terraform {
  required_version = ">= 1.6"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
}

variable "region" {
  default = "us-east-1"
}
variable "github_repo" {
  description = "owner/name allowed to assume the deploy role"
  default     = "shaiksadiq90/license-manager"
}

provider "aws" {
  region = var.region
  default_tags { tags = { project = "license-manager", managed_by = "terraform", stack = "bootstrap" } }
}

data "aws_caller_identity" "me" {}
locals { account = data.aws_caller_identity.me.account_id }

# ---------- remote state ----------
resource "aws_s3_bucket" "state" {
  bucket = "license-manager-tfstate-${local.account}"
  lifecycle { prevent_destroy = true } # losing state means losing track of real resources
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" } # roll back a corrupted state file
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_dynamodb_table" "locks" {
  name         = "license-manager-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID" # two people can't apply at the same time
  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------- GitHub Actions -> AWS without keys ----------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition { # only the main branch of this repo
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "license-manager-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# With GitOps, CI only pushes images; Argo CD inside the cluster does the deploying.
data "aws_iam_policy_document" "push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage"]
    resources = ["arn:aws:ecr:${var.region}:${local.account}:repository/license-manager-*"]
  }
}
resource "aws_iam_role_policy" "push" {
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.push.json
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "lock_table" { value = aws_dynamodb_table.locks.name }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
