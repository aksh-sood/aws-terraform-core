locals {
  cnames = toset(["prometheus", "grafana", "alertmanager", "jaeger"])
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

  providers = {
    kubectl.this = kubectl.this
  }

  efs_depends_on = kubernetes_storage_class_v1.efs[*]
  ebs_depends_on = kubernetes_storage_class_v1.ebs[*]

  # The module's Gateway and VirtualServices need the istio CRDs.
  depends_on = [module.istio]
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
