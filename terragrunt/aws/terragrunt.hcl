# The cluster stack: EKS, its IAM roles, node groups and addons.
# Run this one first; the kubernetes unit depends on its outputs.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

terraform {
  # get_parent_terragrunt_dir() is the directory of the root terragrunt.hcl
  # above, so this resolves to <repo>/terraform/aws.
  source = "${get_parent_terragrunt_dir()}/../terraform/aws"
}

inputs = {
  cluster_name = local.common.locals.cluster_name

  vpc_id             = local.common.locals.vpc_id
  private_subnet_ids = local.common.locals.private_subnet_ids
  public_subnet_ids  = local.common.locals.public_subnet_ids

  tags = local.common.locals.tags
}
