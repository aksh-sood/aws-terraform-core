################################################################################
# Cluster
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_role_arn" {
  description = "ARN of the control plane IAM role, created by the iam module"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane"
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC the cluster is provisioned in. Required, since the module creates a cluster security group in it."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the control plane ENIs, and the default subnets for node groups"
  type        = list(string)
}

variable "cluster_additional_security_group_ids" {
  description = "Existing security groups to attach to the control plane, on top of the one EKS creates"
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Enable the private Kubernetes API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint"
  type        = list(string)
  default     = []
}

variable "authentication_mode" {
  description = "Cluster authentication mode: API, API_AND_CONFIG_MAP or CONFIG_MAP"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Give the identity running Terraform cluster-admin through an access entry"
  type        = bool
  default     = true
}

variable "access_entries" {
  description = "EKS access entries, keyed by name. See the upstream module for the object shape."
  type        = any
  default     = {}
}

variable "service_ipv4_cidr" {
  description = "CIDR the cluster assigns service IPs from. Null lets EKS choose."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt Kubernetes secrets. Null disables envelope encryption."
  type        = string
  default     = null
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types shipped to CloudWatch"
  type        = list(string)
  default     = ["audit", "api", "authenticator", "controllerManager", "scheduler"]
}

variable "create_cloudwatch_log_group" {
  description = "Manage the control plane log group in Terraform instead of letting EKS create it"
  type        = bool
  default     = true
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Retention for the control plane log group"
  type        = number
  default     = 90
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "KMS key ARN used to encrypt the control plane log group"
  type        = string
  default     = null
}

variable "create_cluster_primary_security_group_tags" {
  description = "Copy `tags` onto the security group EKS creates for the cluster"
  type        = bool
  default     = true
}

################################################################################
# Security group rules
################################################################################

variable "security_group_additional_rules" {
  description = <<-EOT
    Extra rules for the cluster security group, keyed by rule name. Set
    `source_node_security_group = true` to source traffic from the node security
    group. Node-to-cluster ingress on 443 is always added by the module.
  EOT
  type = map(object({
    from_port                  = number
    to_port                    = number
    protocol                   = optional(string, "tcp")
    type                       = optional(string, "ingress")
    description                = optional(string)
    cidr_blocks                = optional(list(string))
    ipv6_cidr_blocks           = optional(list(string))
    prefix_list_ids            = optional(list(string))
    self                       = optional(bool)
    source_node_security_group = optional(bool, false)
    source_security_group_id   = optional(string)
  }))
  default = {}
}

variable "node_security_group_additional_rules" {
  description = <<-EOT
    Extra rules for the node security group, keyed by rule name. Set
    `source_cluster_security_group = true` to source traffic from the cluster
    security group. This is where load balancer ingress to the nodes belongs.
  EOT
  type = map(object({
    from_port                     = number
    to_port                       = number
    protocol                      = optional(string, "tcp")
    type                          = optional(string, "ingress")
    description                   = optional(string)
    cidr_blocks                   = optional(list(string))
    ipv6_cidr_blocks              = optional(list(string))
    prefix_list_ids               = optional(list(string))
    self                          = optional(bool)
    source_cluster_security_group = optional(bool, false)
    source_security_group_id      = optional(string)
  }))
  default = {}
}

variable "node_security_group_enable_recommended_rules" {
  description = "Add the module's recommended node security group rules: node-to-node ingress on ephemeral ports, and all egress"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource this module creates"
  type        = map(string)
  default     = {}
}

################################################################################
# Node groups
################################################################################

variable "node_role_arn" {
  description = "ARN of the node IAM role, created by the iam module. Required when node_groups is non-empty."
  type        = string
  default     = null
}

variable "node_groups" {
  description = <<-EOT
    EKS managed node groups, keyed by name. Accepts any attribute of the upstream
    module's `eks_managed_node_groups` object. `create_iam_role`, `iam_role_arn`
    and `attach_cluster_primary_security_group` are set for you.
  EOT
  type        = any
  default = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m6a.large"]

      min_size     = 3
      max_size     = 6
      desired_size = 3

      # Track the AMI release version AWS recommends for this Kubernetes version
      use_latest_ami_release_version = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }
}

################################################################################
# Addons
################################################################################

variable "cluster_addons" {
  description = <<-EOT
    EKS addons, keyed by addon name. Accepts any attribute of the upstream
    module's `addons` object. Addons marked `before_compute` are installed
    before node groups are created.
  EOT
  type        = any
  default = {
    vpc-cni    = { before_compute = true }
    kube-proxy = { before_compute = true }

    coredns            = {}
    aws-ebs-csi-driver = {}
    aws-efs-csi-driver = {}
  }
}
