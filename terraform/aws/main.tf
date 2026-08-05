module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
  region       = var.region

  cluster_policies = var.cluster_policies

  node_policies                 = var.node_policies
  additional_node_policies      = var.additional_node_policies
  additional_node_inline_policy = var.additional_node_inline_policy

  grafana_policies = var.grafana_policies

  tags = var.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  cluster_role_arn   = module.iam.cluster_role_arn
  kubernetes_version = var.kubernetes_version
  vpc_id             = var.vpc_id
  subnet_ids         = var.endpoint_public_access ? concat(var.private_subnet_ids, var.public_subnet_ids) : var.private_subnet_ids

  cluster_additional_security_group_ids = var.cluster_additional_security_group_ids

  security_group_additional_rules              = var.security_group_additional_rules
  node_security_group_additional_rules         = var.node_security_group_additional_rules
  node_security_group_enable_recommended_rules = var.node_security_group_enable_recommended_rules

  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access  = var.endpoint_public_access
  public_access_cidrs     = var.public_access_cidrs

  authentication_mode                      = var.authentication_mode
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = var.access_entries

  service_ipv4_cidr = var.service_ipv4_cidr
  kms_key_arn       = var.kms_key_arn

  enabled_cluster_log_types              = var.enabled_cluster_log_types
  create_cloudwatch_log_group            = var.create_cloudwatch_log_group
  cloudwatch_log_group_retention_in_days = var.cloudwatch_log_group_retention_in_days
  cloudwatch_log_group_kms_key_id        = var.cloudwatch_log_group_kms_key_id

  # Compute
  node_role_arn  = module.iam.node_role_arn
  node_groups    = var.node_groups
  cluster_addons = var.cluster_addons

  tags = var.tags

  # Policy attachments must exist before the cluster and nodes are created, and
  # are removed only after they are destroyed. The role ARN references alone do
  # not guarantee this, since the attachments are separate resources.
  depends_on = [module.iam]
}
