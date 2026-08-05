output "cluster_role_arn" {
  description = "role arn id for cluster nodes"
  value       = aws_iam_role.cluster_role.arn
}

output "cluster_policies_map" {
  description = "Map of all the policies for creating a cluster role"
  value       = local.cluster_policies_map
}

output "node_role_arn" {
  description = "role arn id for cluster nodes"
  value       = aws_iam_role.node_role.arn
}

output "grafana_role_arn" {
  description = "role arn id for cloudwatch datasource in grafana"
  value       = aws_iam_role.grafana.arn
}