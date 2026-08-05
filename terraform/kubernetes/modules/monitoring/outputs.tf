output "grafana_dev_password" {
  description = "user password for grafana developer role"
  value       = module.grafana_config.grafana_dev_password
  sensitive   = true
}

output "grafana_password" {
  description = "user password for grafana admin role"
  value       = random_password.grafana.result
  sensitive   = true
}

output "service_monitor_labels" {
  description = "Labels a ServiceMonitor must carry, all of them, to be scraped by this Prometheus"
  value       = local.service_monitor_labels
}
