variable "namespace" {
  description = "Namespace for logging stack"
  type        = string
  default     = "logging"
}
variable "opensearch_password" {
  description = "Password for OpenSearch"
  type        = string
}
variable "opensearch_username" {}
variable "opensearch_endpoint" {}
variable "environment" {}
variable "domain_name" {}
