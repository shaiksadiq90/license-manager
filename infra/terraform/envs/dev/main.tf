terraform {
  required_version = ">= 1.6"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.60" } }
  # backend "s3" { bucket = "CHANGE-ME-tfstate", key = "license-manager/dev.tfstate", region = "us-east-1", dynamodb_table = "tf-locks" }
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
}
module "ecr" {
  source = "../../modules/ecr"
  repos  = ["license-manager-api", "license-manager-web"]
}

output "cluster_name" { value = module.eks.cluster_name }
output "db_endpoint" { value = module.rds.endpoint }
output "ecr" { value = module.ecr.urls }
