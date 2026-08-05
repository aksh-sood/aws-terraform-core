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

# Install Sail Operator
resource "helm_release" "sail_operator" {
  name             = "sail-operator"
  repository       = "https://istio-ecosystem.github.io/sail-operator"
  chart            = "sail-operator"
  version          = var.sail_operator_version
  namespace        = "sail-operator"
  create_namespace = true
}



# Create istio-system Namespace
resource "kubernetes_namespace" "istio" {
  metadata {
    name = "istio-system"
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  depends_on = [helm_release.sail_operator]
}

# Deploy Istio Control Plane CR (via Sail Operator)
resource "kubectl_manifest" "istio_cr" {
  provider  = kubectl.this
  yaml_body = <<-YAML
    apiVersion: sailoperator.io/v1
    kind: Istio
    metadata:
      name: default
    spec:
      namespace: istio-system
      updateStrategy:
        type: RevisionBased
        inactiveRevisionDeletionGracePeriodSeconds: 30
      version: ${var.istio_version}
  YAML

  depends_on = [kubernetes_namespace.istio]
}

# Deploy IstioRevisionTag CR
resource "kubectl_manifest" "istio_revision_tag" {
  provider = kubectl.this

  yaml_body = <<-YAML
    apiVersion: sailoperator.io/v1
    kind: IstioRevisionTag
    metadata:
      name: default
    spec:
      targetRef:
        kind: Istio
        name: default
  YAML

  depends_on = [kubectl_manifest.istio_cr]
}

resource "helm_release" "istio_ingress" {
  repository      = "https://istio-release.storage.googleapis.com/charts"
  chart           = "gateway"
  name            = "istio-ingressgateway"
  version         = var.istio_version
  cleanup_on_fail = true
  namespace       = "istio-system"

  set {
    name  = "revision"
    value = "default"
  }

  set {
    name  = "service.type"
    value = "NodePort"
  }

  set {
    name  = "service.ports[0].name"
    value = "status-port"
  }
  set {
    name  = "service.ports[0].port"
    value = "15021"
  }
  set {
    name  = "service.ports[0].protocol"
    value = "TCP"
  }
  set {
    name  = "service.ports[0].targetPort"
    value = "15021"
  }

  set {
    name  = "service.ports[1].name"
    value = "http2"
  }
  set {
    name  = "service.ports[1].port"
    value = "80"
  }
  set {
    name  = "service.ports[1].protocol"
    value = "TCP"
  }
  set {
    name  = "service.ports[1].targetPort"
    value = "80"
  }

  set {
    name  = "service.ports[2].name"
    value = "https"
  }
  set {
    name  = "service.ports[2].port"
    value = "443"
  }
  set {
    name  = "service.ports[2].protocol"
    value = "TCP"
  }
  set {
    name  = "service.ports[2].targetPort"
    value = "80"
  }

  depends_on = [kubectl_manifest.istio_revision_tag]
}

#PUBLIC ALB
resource "kubernetes_ingress_v1" "alb_ingress" {
  wait_for_load_balancer = true
  metadata {
    name      = "istio-alb"
    namespace = "istio-system"
    annotations = {
      "kubernetes.io/ingress.class"                    = "alb"
      "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz/ready"
      "alb.ingress.kubernetes.io/healthcheck-port"     = "traffic-port"
      "alb.ingress.kubernetes.io/certificate-arn"      = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/security-groups"      = var.security_group
      "alb.ingress.kubernetes.io/ssl-policy"           = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
      "alb.ingress.kubernetes.io/success-codes"        = "404"
      "alb.ingress.kubernetes.io/ssl-redirect"         = "443"
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/listen-ports"         = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/wafv2-acl-arn"        = var.waf_arn != null && var.waf_arn != "" ? var.waf_arn : ""
      # The flow logging for the ELB cannot work if the native region of the bucket does not match that is the ELB
      "alb.ingress.kubernetes.io/load-balancer-attributes" = var.enable_alb_logs ? join("", [var.alb_base_attributes, ",access_logs.s3.enabled=true,access_logs.s3.bucket=${var.logs_storage_s3_bucket}"]) : var.alb_base_attributes
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "ssl-redirect"
              port {
                name = "use-annotation"
              }
            }
          }

        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "istio-ingressgateway"
              port {
                number = 443
              }
            }
          }

        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.enable_alb_logs ? (var.logs_storage_s3_bucket != "" && var.logs_storage_s3_bucket != null) : true
      error_message = "Provided logs_storage_s3_bucket or disable enable_alb_logs"
    }
  }

  depends_on = [helm_release.istio_ingress]
}

#PRIVATE ALB
resource "kubernetes_ingress_v1" "internal_alb_ingress" {
  wait_for_load_balancer = true
  metadata {
    name      = "internal-istio-alb"
    namespace = "istio-system"
    annotations = {
      "kubernetes.io/ingress.class"                    = "alb"
      "alb.ingress.kubernetes.io/scheme"               = "internal"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz/ready"
      "alb.ingress.kubernetes.io/healthcheck-port"     = "traffic-port"
      "alb.ingress.kubernetes.io/certificate-arn"      = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/security-groups"      = var.internal_alb_security_group
      "alb.ingress.kubernetes.io/ssl-policy"           = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
      "alb.ingress.kubernetes.io/success-codes"        = "404,200"
      "alb.ingress.kubernetes.io/ssl-redirect"         = "443"
      "alb.ingress.kubernetes.io/actions.ssl-redirect" = "{\"Type\": \"redirect\", \"RedirectConfig\": { \"Protocol\": \"HTTPS\", \"Port\": \"443\", \"StatusCode\": \"HTTP_301\"}}"
      "alb.ingress.kubernetes.io/listen-ports"         = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      # The flow logging for the ELB cannot work if the native region of the bucket does not match that is the ELB
      "alb.ingress.kubernetes.io/load-balancer-attributes" = var.enable_alb_logs ? join("", [var.alb_base_attributes, ",access_logs.s3.enabled=true,access_logs.s3.bucket=${var.logs_storage_s3_bucket}"]) : var.alb_base_attributes
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "ssl-redirect"
              port {
                name = "use-annotation"
              }
            }
          }

        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "istio-ingressgateway"
              port {
                number = 443
              }
            }
          }

        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.enable_alb_logs ? (var.logs_storage_s3_bucket != "" && var.logs_storage_s3_bucket != null) : true
      error_message = "Provided logs_storage_s3_bucket or disable enable_alb_logs"
    }
  }

  depends_on = [helm_release.istio_ingress]
}

resource "kubectl_manifest" "istio_gateway" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: istio-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - ${var.environment}-jaeger.${var.domain_name}
    port:
      name: http
      number: 80
      protocol: HTTP
YAML

  depends_on = [helm_release.istio_ingress]
}

resource "random_password" "password" {
  count = 4

  length           = 16
  special          = true
  override_special = "!*=+?"
  min_special      = 1
  lower            = true
  min_lower        = 1
  numeric          = true
  min_numeric      = 1
  upper            = true
  min_upper        = 1
}

resource "kubectl_manifest" "basic_auth" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: extensions.istio.io/v1alpha1
kind: WasmPlugin
metadata:
  name: basic-auth
  namespace: istio-system
spec:
  phase: AUTHN
  pluginConfig:
    basic_auth_rules:
    - credentials:
      - ${base64encode("admin:${random_password.password[0].result}")}
      hosts:
      - ${var.environment}-prometheus.${var.domain_name}
      prefix: /
      request_methods:
      - GET
      - POST
    - credentials:
      - ${base64encode("admin:${random_password.password[1].result}")}
      hosts:
      - ${var.environment}-alertmanager.${var.domain_name}
      prefix: /
      request_methods:
      - GET
      - POST
    - credentials:
      - ${base64encode("admin:${random_password.password[2].result}")}
      hosts:
      - ${var.environment}-jaeger.${var.domain_name}
      prefix: /
      request_methods:
      - GET
      - POST
    - credentials:
      - ${base64encode("admin:${random_password.password[3].result}")}
      hosts:
      - '*.${var.domain_name}'
      suffix: /metrics
      request_methods:
      - GET
      - POST
  selector:
    matchLabels:
      istio: ingressgateway
  url: oci://ghcr.io/istio-ecosystem/wasm-extensions/basic_auth:1.12.0
YAML

  depends_on = [helm_release.istio_ingress]
}
