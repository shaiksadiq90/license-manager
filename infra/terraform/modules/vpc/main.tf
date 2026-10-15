variable "name" { type = string }
variable "cidr" { type = string }
variable "azs" { type = list(string) }

module "vpc" {
  source              = "terraform-aws-modules/vpc/aws"
  version             = "~> 5.8"
  name                = var.name
  cidr                = var.cidr
  azs                 = var.azs
  private_subnets     = [for i, _ in var.azs : cidrsubnet(var.cidr, 4, i)]
  public_subnets      = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, 100 + i)]
  database_subnets    = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, 200 + i)]
  enable_nat_gateway  = true
  single_nat_gateway  = true # cost trade-off for dev; one per AZ in prod
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
}

output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnets }
output "database_subnet_group" { value = module.vpc.database_subnet_group_name }
output "vpc_cidr" { value = var.cidr }
