output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane"
  value       = module.eks.cluster_version
}

output "cluster_cidr" {
  description = "Service IPv4 CIDR of the cluster"
  value       = module.eks.cluster_service_cidr
}

output "cluster_primary_security_group_id" {
  description = "Security group EKS created for control plane / node communication"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider, for IRSA trust policies"
  value       = module.eks.oidc_provider_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the control plane log group"
  value       = module.eks.cloudwatch_log_group_name
}

output "node_groups" {
  description = "Managed node groups, keyed by the input map key"
  value       = module.eks.eks_managed_node_groups
}

output "node_groups_autoscaling_group_names" {
  description = "Autoscaling group names of the managed node groups"
  value       = module.eks.eks_managed_node_groups_autoscaling_group_names
}

output "cluster_addons" {
  description = "Installed addons"
  value       = module.eks.cluster_addons
}
