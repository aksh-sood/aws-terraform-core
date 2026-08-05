terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "2.3.3"
    }
  }
}

provider "grafana" {

  url  = "https://${var.environment}-grafana.${var.domain_name}"
  auth = "admin:${var.grafana_password}"
}

resource "grafana_folder" "custom" {
  count = var.configure_grafana ? 1 : 0

  title = "Custom Dashboards"

  depends_on = [var.vs_dependency]
}

resource "grafana_dashboard" "metrics" {
  for_each = var.configure_grafana ? fileset("${path.module}/dashboards", "*.json") : []

  config_json = file("${path.module}/dashboards/${each.key}")
  folder      = grafana_folder.custom[0].id

  depends_on = [var.vs_dependency]
}

resource "random_password" "password" {
  count = var.configure_grafana ? 1 : 0

  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
  min_special      = 1
  lower            = true
  min_lower        = 1
  numeric          = true
  min_numeric      = 1
  upper            = true
  min_upper        = 1
}

resource "grafana_user" "developer" {
  count = var.configure_grafana ? 1 : 0

  email    = "dev@gmail.com"
  name     = "developer"
  password = random_password.password[0].result
  is_admin = false

  depends_on = [var.vs_dependency]
}

resource "grafana_data_source" "cloudwatch" {
  count = var.configure_grafana ? 1 : 0

  name = "CloudWatch"
  type = "cloudwatch"

  json_data_encoded = <<JSON
{
  "authType": "assumeRole",
  "assumeRoleArn": "${var.grafana_role_arn}",
  "defaultRegion": "us-east-1"
}
JSON

  depends_on = [var.vs_dependency]
}
