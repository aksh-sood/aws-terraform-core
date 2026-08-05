terraform {
  required_version = ">= 0.13"

  required_providers {
    kubectl = {
      source                = "gavinbunney/kubectl"
      version               = ">= 1.7.0"
      configuration_aliases = [kubectl.this]
    }
  }
}

data "aws_region" "current" {}

locals {
  merged_alerts = concat(var.custom_alerts, var.required_alerts)

  # Prometheus only scrapes ServiceMonitors carrying all of these. Rendered into
  # the chart's serviceMonitorSelector and published as an output, so an
  # application chart has one place to read the contract from rather than
  # copying the labels and finding out later that they drifted.
  service_monitor_labels = {
    prometheus = "prometheus-kube-prometheus-prometheus"
    release    = "prometheus"
  }
}

resource "random_password" "grafana" {
  length      = 16
  special     = false
  lower       = true
  min_lower   = 1
  numeric     = true
  min_numeric = 1
  upper       = true
  min_upper   = 1
}

resource "helm_release" "kube_prometheus_stack" {
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  name             = "prometheus"
  version          = var.kube_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true
  # disable_webhooks = true

  values = [
    templatefile("${path.module}/configs/config.yaml", {
      prometheus_volume_size   = var.prometheus_volume_size
      prometheus_storage_class = var.prometheus_storage_class
      prometheus_access_mode   = var.prometheus_storage_class == "efs" ? "ReadWriteMany" : "ReadWriteOnce"
      grafana_volume_size      = var.grafana_volume_size
      grafana_password         = random_password.grafana.result
      service_monitor_labels   = jsonencode(local.service_monitor_labels)
      alerts = templatefile("${path.module}/configs/alerts.yaml", {
        custom_alerts = jsonencode(local.merged_alerts)
        #  prometheus_volume_size=var.prometheus_volume_size
        #  grafana_volume_size=var.grafana_volume_size
      })
      alertmanager = templatefile("${path.module}/configs/alertmanager.yaml", {
        slack_web_hook             = var.slack_web_hook
        slack_channel_name         = var.slack_channel_name
        pagerduty_key              = var.pagerduty_key
        alertmanager_storage_class = var.prometheus_storage_class
        alertmanager_access_mode   = var.prometheus_storage_class == "efs" ? "ReadWriteMany" : "ReadWriteOnce"
        alert_manager_volume_size  = var.alert_manager_volume_size
        gchat_sns_topic_arn        = coalesce(var.sns_topic_arn, "NO_SNS_TOPIC_ARN_PROVIDED")
        gchat_webhook_url          = coalesce(var.gchat_webhook_url, "NO_GCHAT_WEBHOOK_URL_PROVIDED")
        aws_region                 = data.aws_region.current.region
      })
    })
  ]

  depends_on = [var.efs_depends_on, var.ebs_depends_on, var.dependencies]
}

resource "helm_release" "kube_state_metrics" {
  count      = 0
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  namespace  = "monitoring"
  values = [
    templatefile("${path.module}/configs/kubeStateMetrics.yaml", {
      image_version = var.kube_state_metrics_version
    })
  ]
  atomic          = true
  cleanup_on_fail = true

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "monitoring_gateway" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: monitoring-gateway
  namespace: monitoring
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - ${var.environment}-grafana.${var.domain_name}
    - ${var.environment}-prometheus.${var.domain_name}
    - ${var.environment}-alertmanager.${var.domain_name}
    port:
      name: http
      number: 80
      protocol: HTTP
YAML

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "kube_stack_virtualservices" {

  provider = kubectl.this

  for_each = {
    for pair in [
      for yaml in split(
        "\n---\n",
        "\n${replace(
          templatefile(
            "${path.module}/configs/virtualServices.yaml", {
              environment = var.environment
              domain_name = var.domain_name
          }), "/(?m)^---[[:blank:]]*(#.*)?$/", "---"
        )}\n"
      ) :
      [yamldecode(yaml), yaml]
      if trimspace(replace(yaml, "/(?m)(^[[:blank:]]*(#.*)?$)+/", "")) != ""
    ] : "${pair.0["kind"]}--${pair.0["metadata"]["name"]}" => pair.1
  }

  yaml_body = each.value

  depends_on = [helm_release.kube_prometheus_stack, kubectl_manifest.monitoring_gateway]
}

module "grafana_config" {
  source = "./modules/grafana-config"

  grafana_password = random_password.grafana.result
  vs_dependency    = kubectl_manifest.kube_stack_virtualservices

  environment       = var.environment
  domain_name       = var.domain_name
  grafana_role_arn  = var.grafana_role_arn
  configure_grafana = var.configure_grafana
}
