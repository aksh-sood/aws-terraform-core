variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane"
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC the cluster is provisioned in"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the cluster"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the cluster"
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
  description = "EKS access entries, keyed by name"
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

variable "enable_irsa" {
  description = "Create the OIDC provider so service accounts can assume IAM roles"
  type        = bool
  default     = true
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

variable "tags" {
  description = "Tags applied to the cluster, node groups and the IAM roles"
  type        = map(string)
  default     = {}
}

# Compute — defaults mirror modules/eks/vars.tf, since every argument is passed
# through explicitly. Keep the two in step.
variable "node_groups" {
  description = "EKS managed node groups, keyed by name"
  type        = any
  default = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m6a.large"]

      min_size     = 3
      max_size     = 6
      desired_size = 3

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

variable "cluster_addons" {
  description = "EKS addons, keyed by addon name"
  type        = any
  default = {
    vpc-cni    = { before_compute = true }
    kube-proxy = { before_compute = true }

    coredns            = {}
    aws-ebs-csi-driver = {}
    aws-efs-csi-driver = {}
  }
}

variable "dataplane_wait_duration" {
  description = "How long to wait after the cluster (and before-compute addons) before creating node groups"
  type        = string
  default     = "30s"
}

# IAM — pass-through to the iam module. Defaults mirror the module's own so the
# root stays the single place these are set.
variable "cluster_policies" {
  description = "AWS managed policy names attached to the cluster role"
  type        = list(string)
  default = [
    "AmazonEKSClusterPolicy",
    "AmazonEKSServicePolicy",
    "AmazonEKS_CNI_Policy",
    "service-role/AmazonEBSCSIDriverPolicy"
  ]
}

variable "node_policies" {
  description = "AWS managed policy names attached to the node role"
  type        = list(string)
  default = [
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonEKS_CNI_Policy"
  ]
}

variable "additional_node_policies" {
  description = "Additional full policy ARNs to attach to the node role"
  type        = list(string)
  default     = []
}

variable "additional_node_inline_policy" {
  description = "Additional inline policy document (JSON) to attach to the node role"
  type        = string
  default     = null
}

variable "grafana_policies" {
  description = "Policy ARNs attached to the Grafana CloudWatch role"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"]
}

variable "mount_point_s3_bucket_name" {
  description = "S3 bucket to grant the node role access to for mountpoint-s3. Null or empty to skip."
  type        = string
  default     = null
}
