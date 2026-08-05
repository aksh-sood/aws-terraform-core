variable "acm_certificate_arn" {
  description = "certificate arn for istio ingress application load balancer"
  type        = string
}

variable "alb_base_attributes" {
  description = "annotations for configuring alb"
  type        = string
  default     = "deletion_protection.enabled=true,routing.http.drop_invalid_header_fields.enabled=true"
}

variable "waf_arn" {
  description = "ARN of the WAF to associate with the ALB"
  type        = string
  default     = ""
}

variable "sail_operator_version" {
  description = "Version of Sail Operator Helm chart"
  type        = string
  default     = "1.0.0"
}

variable "istio_version" {}
variable "logs_storage_s3_bucket" {}
variable "enable_alb_logs" {}
variable "domain_name" {}
variable "environment" {}
variable "security_group" {}
variable "internal_alb_security_group" {}
