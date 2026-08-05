output "grafana_dev_password" {
  description = "user password for grafana developer role"
  value       = var.configure_grafana ? random_password.password[0].result : null
  sensitive   = true
}
