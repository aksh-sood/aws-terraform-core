locals {
  # Hostnames published under domain_name. The application's own hostname joins
  # the platform's so it gets a DNS record on the same terms.
  cnames = toset(concat(
    ["prometheus", "grafana", "alertmanager", "jaeger"],
    var.deploy_hello_world ? [var.app_host_prefix] : [],
  ))
}

module "addons" {
  source = "./modules/addons"

  cluster_name      = var.cluster_name
  lbc_addon_version = var.lbc_addon_version
}

resource "kubernetes_storage_class_v1" "efs" {
  count = var.enable_ebs_persistent_storage ? 0 : 1
  metadata {
    name = "efs"
  }
  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Retain"
  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = "${var.efs_id}"
    directoryPerms   = "777"
    uid              = 0
    gid              = 0
  }

  depends_on = [module.addons]
}

# EBS 
resource "kubernetes_storage_class_v1" "ebs" {
  count = var.enable_ebs_persistent_storage ? 1 : 0

  metadata {
    name = "ebs"
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [module.addons]
}

module "istio" {
  source = "./modules/istio"

  enable_alb_logs             = var.enable_alb_logs
  environment                 = var.cluster_name
  domain_name                 = var.domain_name
  acm_certificate_arn         = var.acm_certificate_arn
  istio_version               = var.istio_version
  sail_operator_version       = var.sail_operator_version
  logs_storage_s3_bucket      = var.logs_storage_s3_bucket
  security_group              = var.elb_security_group
  internal_alb_security_group = var.internal_alb_security_group
  waf_arn                     = var.waf_arn

  providers = {
    kubectl.this = kubectl.this
  }

  depends_on = [module.addons]
}

# The published hostnames all resolve to the public istio ALB. They have to
# exist before the monitoring module runs: its grafana submodule configures
# Grafana over its own hostname.
resource "aws_route53_record" "services" {
  for_each = var.create_dns_records ? local.cnames : toset([])

  zone_id = var.route53_zone_id
  name    = "${var.cluster_name}-${each.key}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [module.istio.external_loadbalancer_url]

  lifecycle {
    precondition {
      condition     = var.route53_zone_id != ""
      error_message = "Provide route53_zone_id or disable create_dns_records"
    }
  }
}

module "monitoring" {
  source = "./modules/monitoring"

  configure_grafana             = var.create_dns_records
  environment                   = var.cluster_name
  domain_name                   = var.domain_name
  slack_channel_name            = var.slack_channel_name
  kube_prometheus_stack_version = var.kube_prometheus_stack_version
  node_exporter_version         = var.node_exporter_version
  kube_state_metrics_version    = var.kube_state_metrics_version
  slack_web_hook                = var.slack_web_hook
  pagerduty_key                 = var.pagerduty_key
  custom_alerts                 = var.prometheus_custom_alerts
  alert_manager_volume_size     = var.alert_manager_volume_size
  prometheus_volume_size        = var.prometheus_volume_size
  prometheus_storage_class      = var.enable_ebs_persistent_storage ? "ebs" : "efs"
  grafana_role_arn              = var.grafana_role_arn

  # modules/monitoring cannot be ordered with depends_on: its grafana submodule
  # carries its own provider configuration, which makes it a legacy module. It
  # takes its ordering through this input instead. It needs the istio CRDs for
  # its Gateway and VirtualServices, and the hostname has to resolve before the
  # grafana submodule can configure Grafana over it.
  dependencies = [
    kubernetes_storage_class_v1.efs,
    kubernetes_storage_class_v1.ebs,
    module.istio.external_loadbalancer_url,
    aws_route53_record.services
  ]

  providers = {
    kubectl.this = kubectl.this
  }

  efs_depends_on = kubernetes_storage_class_v1.efs[*]
  ebs_depends_on = kubernetes_storage_class_v1.ebs[*]
}

module "logging" {
  source = "./modules/logging"
  count  = var.create_opensearch ? 1 : 0

  environment         = var.cluster_name
  domain_name         = var.domain_name
  opensearch_endpoint = var.opensearch_endpoint
  opensearch_password = var.opensearch_password
  opensearch_username = var.opensearch_username

  providers = {
    kubectl.this = kubectl.this
  }

  depends_on = [module.istio]
}

module "jaeger" {
  source = "./modules/jaeger"

  environment   = var.cluster_name
  istio_version = var.istio_version
  domain_name   = var.domain_name

  providers = {
    kubectl.this = kubectl.this
  }

  depends_on = [module.istio]
}

# The application, from the chart in this repository rather than a registry, so
# the chart is versioned with the stack that deploys it. The path is relative to
# this module: terraform/kubernetes up to the repository root.
resource "helm_release" "app_release" {
  count = var.deploy_app ? 1 : 0

  name             = var.app_release_name
  chart            = "${path.module}/../../helm-chart"
  namespace        = var.app_namespace
  create_namespace = true

  # Two documents, merged by Helm in order: the wiring this stack owns, then the
  # caller's overrides. app_values therefore wins key by key and can
  # reach nested chart values the block below never mentions.
  values = [
    yamlencode({
      replicaCount = var.app_replica_count

      image = {
        repository = var.app_image.repository
        tag        = var.app_image.tag
      }

      istio = {
        hosts = ["${var.cluster_name}-${var.app_host_prefix}.${var.domain_name}"]

      }
    }),
    yamlencode(var.app_values),
  ]

  # The chart's Gateway and VirtualService need the istio CRDs, and the gateway
  # deployment their selector matches. Both come from modules/istio.
  #
  # Enabling the chart's ServiceMonitor through app_values additionally
  # needs the Prometheus Operator CRDs from modules/monitoring, which cannot be
  # ordered with depends_on — see the note on that module above.
  depends_on = [module.istio,module.monitoring]
}
