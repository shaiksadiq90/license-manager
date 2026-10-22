terraform {
  required_version = ">= 1.6"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
  # Remote state in S3 with a DynamoDB lock (created by ../../bootstrap). Settings come from backend.hcl.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags { tags = { project = "license-manager", env = "dev", managed_by = "terraform" } }
}

variable "region" {
  default = "us-east-1"
}
locals { name = "license-manager-dev" }

module "vpc" {
  source = "../../modules/vpc"
  name   = local.name
  cidr   = "10.20.0.0/16"
  azs    = ["${var.region}a", "${var.region}b"]
}
module "eks" {
  source     = "../../modules/eks"
  name       = local.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}
module "rds" {
  source       = "../../modules/rds"
  name         = local.name
  vpc_id       = module.vpc.vpc_id
  subnet_group = module.vpc.database_subnet_group
  allowed_sg   = module.eks.node_sg_id
  # dev is torn down after every session: no deletion protection, no final snapshot
  deletion_protection = false
  skip_final_snapshot = true
}
module "ecr" {
  source       = "../../modules/ecr"
  repos        = ["license-manager-api", "license-manager-web"]
  force_delete = true
}

output "cluster_name" { value = module.eks.cluster_name }
output "db_endpoint" { value = module.rds.endpoint }
output "db_secret_arn" { value = module.rds.secret_arn }
output "ecr" { value = module.ecr.urls }
