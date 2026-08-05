# ----------------------------------------------------------------------------
# Inputs produced by the aws stack.
#
# Each variable below is named after the output of the same name in
# terraform/aws/outputs.tf, so the whole set can be handed over without a
# per-value mapping:
#
#   cd ../aws && terraform output -json | jq 'map_values(.value)' \
#     > ../kubernetes/aws.auto.tfvars.json
#
# Keep both sides in step when either is renamed.
# ----------------------------------------------------------------------------

variable "region" {
  description = "AWS region the cluster runs in"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as the environment prefix for every hostname the stack publishes"
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API server endpoint, used to configure the kubernetes, helm and kubectl providers"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate for the cluster"
  type        = string
}

variable "grafana_role_arn" {
  description = "ARN of the role Grafana assumes for the CloudWatch datasource"
  type        = string
}

# ----------------------------------------------------------------------------
# Inputs from infrastructure outside this repository — networking, certificates,
# EFS and OpenSearch are not created by the aws stack.
# ----------------------------------------------------------------------------

variable "domain_name" {
  description = "Base domain the stack publishes hostnames under, e.g. <cluster_name>-grafana.<domain_name>"
  type        = string
}

variable "acm_certificate_arn" {
  description = "Certificate served by both istio ingress load balancers"
  type        = string
}

variable "elb_security_group" {
  description = "Security group attached to the public istio ALB"
  type        = string
}

variable "internal_alb_security_group" {
  description = "Security group attached to the internal istio ALB"
  type        = string
}

variable "waf_arn" {
  description = "WAFv2 ACL associated with the public ALB. Empty disables the association"
  type        = string
  default     = ""
}

variable "enable_alb_logs" {
  description = "Ship ALB access logs to logs_storage_s3_bucket. The bucket must live in the same region as the ALB"
  type        = bool
  default     = false
}

variable "logs_storage_s3_bucket" {
  description = "Bucket for ALB access logs. Required when enable_alb_logs is true"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Hosted zone the service records are created in. Required when create_dns_records is true"
  type        = string
  default     = ""
}

variable "create_dns_records" {
  description = "Create the CNAMEs for the published services. Also gates the Grafana configuration, which needs its hostname to resolve"
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------
# Storage
# ----------------------------------------------------------------------------

variable "enable_ebs_persistent_storage" {
  description = "Back the monitoring volumes with EBS. False uses EFS instead and requires efs_id"
  type        = bool
  default     = true
}

variable "efs_id" {
  description = "File system backing the efs storage class. Required when enable_ebs_persistent_storage is false"
  type        = string
  default     = ""
}

# ----------------------------------------------------------------------------
# Chart and component versions
# ----------------------------------------------------------------------------

variable "lbc_addon_version" {
  description = "aws-load-balancer-controller helm chart version"
  type        = string
  default     = "3.5.0"
}

variable "istio_version" {
  description = "Istio version, carrying the leading v — the Sail Istio resource requires that form, the gateway chart and the jaeger manifests accept it"
  type        = string
  default     = "v1.30.3"

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.istio_version))
    error_message = "istio_version must look like v1.30.3."
  }
}

variable "sail_operator_version" {
  description = "Sail operator helm chart version. Track the istio version it manages"
  type        = string
  default     = "1.30.3"
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack helm chart version"
  type        = string
  default     = "88.1.5"
}

variable "node_exporter_version" {
  description = "node-exporter image tag. Inert while the release is disabled in modules/monitoring"
  type        = string
  default     = "v1.12.1"
}

variable "kube_state_metrics_version" {
  description = "kube-state-metrics image tag. Inert while the release is disabled in modules/monitoring"
  type        = string
  default     = "v2.19.1"
}

# ----------------------------------------------------------------------------
# Monitoring and alerting
# ----------------------------------------------------------------------------

variable "prometheus_volume_size" {
  description = "Volume claim size for Prometheus"
  type        = string
  default     = "50Gi"
}

variable "alert_manager_volume_size" {
  description = "Volume claim size for Alertmanager"
  type        = string
  default     = "10Gi"
}

variable "prometheus_custom_alerts" {
  description = "Alert rules appended to the module's built-in set"
  type = list(
    object({
      alert = string
      expr  = string
      for   = optional(string)
      labels = object({
        severity = string
      })
      annotations = object({
        summary     = string
        description = string
      })
    })
  )
  default = []
}

variable "slack_web_hook" {
  description = "Slack incoming webhook Alertmanager posts to"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_channel_name" {
  description = "Slack channel Alertmanager posts to"
  type        = string
  default     = ""
}

variable "pagerduty_key" {
  description = "PagerDuty integration key for the Alertmanager receiver"
  type        = string
  default     = ""
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Logging — the filebeat/OpenSearch stack is optional
# ----------------------------------------------------------------------------

variable "create_opensearch" {
  description = "Deploy the filebeat shipper and the Kibana route to OpenSearch"
  type        = bool
  default     = false
}

variable "opensearch_endpoint" {
  description = "OpenSearch domain endpoint, without a scheme"
  type        = string
  default     = ""
}

variable "opensearch_username" {
  description = "OpenSearch master user"
  type        = string
  default     = ""
}

variable "opensearch_password" {
  description = "OpenSearch master password"
  type        = string
  default     = ""
  sensitive   = true
}
