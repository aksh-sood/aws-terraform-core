# Every output here is consumed by terraform/kubernetes under the same name, so
# the whole set can be injected without a per-value mapping. Renaming an output
# means renaming the matching variable in terraform/kubernetes/vars.tf.

output "region" {
  description = "AWS region the cluster is provisioned in"
  value       = var.region
}

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
  value       = module.eks.cluster_cidr
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

output "node_groups" {
  description = "Managed node groups, keyed by the input map key"
  value       = module.eks.node_groups
}

output "cluster_addons" {
  description = "Installed addons and their resolved versions"
  value       = module.eks.cluster_addons
}

output "cluster_role_arn" {
  description = "ARN of the control plane IAM role"
  value       = module.iam.cluster_role_arn
}

output "node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = module.iam.node_role_arn
}

output "grafana_role_arn" {
  description = "ARN of the Grafana CloudWatch datasource role"
  value       = module.iam.grafana_role_arn
}