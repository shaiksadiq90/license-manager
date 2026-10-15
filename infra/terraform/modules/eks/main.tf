variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }

module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "~> 20.20"
  cluster_name                             = var.name
  cluster_version                          = "1.30"
  vpc_id                                   = var.vpc_id
  subnet_ids                               = var.subnet_ids
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true
  cluster_addons                           = { coredns = {}, kube-proxy = {}, vpc-cni = { configuration_values = jsonencode({ enableNetworkPolicy = "true" }) } }
  eks_managed_node_groups = {
    default = { instance_types = ["t3.small"], min_size = 2, max_size = 4, desired_size = 2 }
  }
}

output "cluster_name" { value = module.eks.cluster_name }
output "node_sg_id" { value = module.eks.node_security_group_id }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
