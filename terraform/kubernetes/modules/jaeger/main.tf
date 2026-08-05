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

# getting jaeger configuration from istio
data "http" "jaeger_crd" {
  url = "https://raw.githubusercontent.com/istio/istio/release-${regex("^v?(\\d+\\.\\d+)", var.istio_version)[0]}/samples/addons/jaeger.yaml"
  request_headers = {
    Accept = "text/plain"
  }
}


data "kubectl_file_documents" "jaeger" {
  content = data.http.jaeger_crd.response_body
}

# Due to terraform limitations , we have kept the loop on `kubectl_manifest` has been set manually as terraform does not support runtime change in resource count.
# If the version change is being made then make sure that the number of objects in source file is same as the loop on resource.

resource "kubectl_manifest" "crd" {

  provider = kubectl.this

  count = 4

  yaml_body = element(data.kubectl_file_documents.jaeger.documents, count.index)

}

resource "kubectl_manifest" "virtual_service" {

  provider = kubectl.this

  yaml_body = <<YAML
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: jaeger
  namespace: istio-system
spec:
  gateways:
    - istio-gateway
  hosts:
    - ${var.environment}-jaeger.${var.domain_name}
  http:
  - match:
    - uri:
        prefix: /
    route:
      - destination:
          host: tracing
          port:
            number: 80
YAML

}