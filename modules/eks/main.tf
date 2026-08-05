module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Control plane role is managed by the iam module
  create_iam_role = false
  iam_role_arn    = var.cluster_role_arn

  # Networking
  vpc_id                        = var.vpc_id
  subnet_ids                    = var.subnet_ids
  additional_security_group_ids = var.cluster_additional_security_group_ids
  service_ipv4_cidr             = var.service_ipv4_cidr

  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access ? var.public_access_cidrs : []

  # Node groups ride on the security group EKS creates for the cluster, so no
  # separate node security group is managed here.
  # create_security_group      = false
  create_node_security_group = false

  #prefix configuration
  # if set to true random suffixes will be added to the names of the security groups and IAM roles created by this module. This is useful when you want to create multiple clusters in the same AWS account and region, and you want to avoid name collisions.
  security_group_use_name_prefix      = false
  node_security_group_use_name_prefix = false
  iam_role_use_name_prefix            = false
  encryption_policy_use_name_prefix   = false

  create_primary_security_group_tags = var.create_cluster_primary_security_group_tags

  # Authentication
  authentication_mode                      = var.authentication_mode
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = var.access_entries

  # Secrets encryption with an existing key. `null` leaves envelope encryption off.
  create_kms_key    = false
  encryption_config = var.kms_key_arn != null ? { provider_key_arn = var.kms_key_arn, resources = ["secrets"] } : null

  # Logging
  enabled_log_types                      = var.enabled_cluster_log_types
  create_cloudwatch_log_group            = var.create_cloudwatch_log_group
  cloudwatch_log_group_retention_in_days = var.cloudwatch_log_group_retention_in_days
  cloudwatch_log_group_kms_key_id        = var.cloudwatch_log_group_kms_key_id

  # IRSA
  enable_irsa                     = true
  include_oidc_root_ca_thumbprint = true

  # Compute
  eks_managed_node_groups = local.node_groups
  addons                  = var.cluster_addons


  tags = var.tags
}
