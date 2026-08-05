output "external_loadbalancer_url" {
  description = "Hostname of the public istio ALB"
  value       = module.istio.external_loadbalancer_url
}

output "internal_loadbalancer_url" {
  description = "Hostname of the internal istio ALB"
  value       = module.istio.internal_loadbalancer_url
}

output "service_urls" {
  description = "Published URLs, whether or not their DNS records are managed here"
  value       = { for name in local.cnames : name => "https://${var.cluster_name}-${name}.${var.domain_name}" }
}

output "dns_records" {
  description = "Records created in route53_zone_id. Empty when create_dns_records is false"
  value       = [for record in aws_route53_record.services : record.fqdn]
}

# Basic auth is enforced at the istio gateway by the WasmPlugin in modules/istio.
# The user is admin for all of them.
output "prometheus_password" {
  description = "Basic auth password for the Prometheus UI"
  value       = module.istio.prometheus_password
  sensitive   = true
}

output "alertmanager_password" {
  description = "Basic auth password for the Alertmanager UI"
  value       = module.istio.alertmanager_password
  sensitive   = true
}

output "jaeger_password" {
  description = "Basic auth password for the Jaeger UI"
  value       = module.istio.jaeger_password
  sensitive   = true
}

output "app_password" {
  description = "Basic auth password for the /metrics endpoints under the domain"
  value       = module.istio.app_password
  sensitive   = true
}

output "grafana_password" {
  description = "Grafana admin password"
  value       = module.monitoring.grafana_password
  sensitive   = true
}

output "grafana_dev_password" {
  description = "Grafana developer password. Null unless create_dns_records is true"
  value       = module.monitoring.grafana_dev_password
  sensitive   = true
}

# The application chart has to stamp these onto its ServiceMonitor — all of
# them, since the selector matches on every label — or Prometheus will not
# scrape it.
output "service_monitor_labels" {
  description = "Labels a ServiceMonitor must carry to be discovered by this Prometheus"
  value       = module.monitoring.service_monitor_labels
}
