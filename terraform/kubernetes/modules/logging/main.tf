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

# Referenced instead of var.namespace throughout, so everything in the stack is
# ordered after the namespace exists.
locals {
  namespace = kubernetes_namespace.logging.metadata[0].name
}

resource "kubernetes_namespace" "logging" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }
}

resource "kubernetes_service" "proxy" {
  metadata {
    name      = "aws-es"
    namespace = local.namespace
  }
  spec {
    external_name = var.opensearch_endpoint
    type          = "ExternalName"
    port {
      port        = 443
      target_port = 443
    }
  }
}

resource "helm_release" "filebeat" {
  name             = "filebeat"
  repository       = "https://helm.elastic.co/"
  chart            = "filebeat"
  version          = "7.13.0"
  namespace        = local.namespace
  create_namespace = false

  values = [
    templatefile("${path.module}/filebeat.yaml", {
      OPENSEARCH_USERNAME = var.opensearch_username
      OPENSEARCH_PASSWORD = var.opensearch_password
    })
  ]

  depends_on = [kubernetes_service.proxy]
}

resource "kubectl_manifest" "gateway" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: logging
  namespace: ${local.namespace}
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - ${var.environment}-kibana.${var.domain_name}
    port:
      name: http
      number: 80
      protocol: HTTP
YAML
}

resource "kubectl_manifest" "destination_rule" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: kibana
  namespace: ${local.namespace}
spec:
  host: ${var.opensearch_endpoint}
  trafficPolicy:
    tls:
      mode: SIMPLE
YAML
}

resource "kubectl_manifest" "service_entry" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: kibana
  namespace: ${local.namespace}
spec:
  hosts:
    - ${var.opensearch_endpoint}
  location: MESH_EXTERNAL
  ports:
    - number: 443
      name: https
      protocol: TLS
  resolution: DNS
YAML
}

resource "kubectl_manifest" "virtual_service" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: kibana
  namespace: ${local.namespace}
spec:
  gateways:
    - logging
  hosts:
    - ${var.environment}-kibana.${var.domain_name}
  http:
  - match:
    - uri:
        exact: "/"
    redirect:
      uri: "/_dashboards/"
      authority: ${var.environment}-kibana.${var.domain_name}
  - match:
    - uri:
        prefix: "/_dashboards/"
    route:
      - destination:
          host: ${var.opensearch_endpoint}
          port:
            number: 443
YAML
}
