output "grafana_password" {
  description = "user password for grafana admin role"
  value       = random_password.grafana.result
  sensitive   = true
}

output "service_monitor_labels" {
  description = "Labels a ServiceMonitor must carry, all of them, to be scraped by this Prometheus"
  value       = local.service_monitor_labels
}

output "namespace" {
  description = "Namespace the monitoring stack runs in"
  value       = helm_release.kube_prometheus_stack.namespace
}
