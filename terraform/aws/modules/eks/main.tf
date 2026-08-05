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

  # Two security groups are managed here: the cluster one on the control plane,
  # and the node one, which every node group is attached to automatically.
  create_security_group      = true
  create_node_security_group = true

  # Fixed names (`<cluster>-cluster` and `<cluster>-node`) rather than a generated
  # suffix. The IAM role and encryption policy have no equivalent setting here,
  # since this module does not create them.
  security_group_use_name_prefix      = false
  node_security_group_use_name_prefix = false

  # Rules. On top of these the module always adds node-to-cluster ingress on 443,
  # and the recommended node-to-node rules unless they are turned off.
  security_group_additional_rules              = var.security_group_additional_rules
  node_security_group_additional_rules         = var.node_security_group_additional_rules
  node_security_group_enable_recommended_rules = var.node_security_group_enable_recommended_rules

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
