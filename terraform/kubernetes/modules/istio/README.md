# modules/istio

The service mesh and the cluster's edge: two ALBs terminating TLS, the Istio
ingress gateway behind them, and basic auth on the platform UIs.

## Creates

| Object | Notes |
| --- | --- |
| `sail-operator` Helm release | In its own namespace. Manages the Istio control plane as a CRD instead of the `istioctl`/`istiod` chart |
| `istio-system` namespace | Annotations ignored after creation, since the operator writes to them |
| `Istio` resource | `RevisionBased` update strategy — a new revision is installed alongside the old one, and old revisions are reaped 30s after becoming inactive |
| `IstioRevisionTag` `default` | The stable name workloads inject from, so a revision upgrade does not require relabelling namespaces |
| `istio-ingressgateway` Helm release | The `gateway` chart, `service.type = NodePort`. The ALBs are the internet-facing part; the gateway itself is not a LoadBalancer Service |
| Public `Ingress` | `internet-facing` ALB, target-type `ip`, HTTP→HTTPS redirect, the ACM certificate, `ELBSecurityPolicy-FS-1-2-Res-2020-10`, optional WAF |
| Internal `Ingress` | Same, `scheme: internal`, with its own security group |
| `Gateway` `istio-gateway` | Listener for `<environment>-jaeger.<domain_name>` |
| 4 × `random_password` | Basic auth credentials |
| `basic-auth` `WasmPlugin` | Enforces those credentials at the gateway, per hostname |

## Inputs

Required: `acm_certificate_arn`, `istio_version`, `logs_storage_s3_bucket`,
`enable_alb_logs`, `domain_name`, `environment`, `security_group`,
`internal_alb_security_group`.

Defaulted: `waf_arn` (empty disables the association), `sail_operator_version`,
`alb_base_attributes` — `deletion_protection.enabled=true` and
`routing.http.drop_invalid_header_fields.enabled=true`.

Requires the `kubectl.this` provider alias.

## Outputs

`external_loadbalancer_url`, `internal_loadbalancer_url` — read from the
Ingress status, so they force Terraform to wait for the ALB to be provisioned —
and `prometheus_password`, `alertmanager_password`, `jaeger_password`,
`app_password`.

## Basic auth

The WasmPlugin maps one credential per hostname, user `admin` throughout:

| Hostname | Password output |
| --- | --- |
| `<env>-prometheus.<domain>` | `prometheus_password` |
| `<env>-alertmanager.<domain>` | `alertmanager_password` |
| `<env>-jaeger.<domain>` | `jaeger_password` |
| `*.<domain>` suffix `/metrics` | `app_password` |

It runs in the `AUTHN` phase on the ingress gateway, so it applies to traffic
arriving through the ALBs. A `kubectl port-forward` bypasses it entirely.

## Gotchas

- **`istio_version` must carry the leading `v`.** The Sail `Istio` resource
  requires that form; the gateway Helm chart and the jaeger manifests both accept
  it. The root validates the shape.
- **`sail_operator_version` should track the Istio version it manages.** The
  module's own default is stale; the root passes `1.30.3`.
- **Depends on the load balancer controller** being installed — the root orders
  this after `module.addons`. Without it the Ingresses stay pending forever, and
  `wait_for_load_balancer = true` means the apply hangs rather than fails.
- **`enable_alb_logs` needs a bucket in the ALB's own region.** A precondition
  fails the plan if the bucket is empty, but the region match is on you.
- **`deletion_protection.enabled=true`** is in the base attributes, so a
  `terraform destroy` will not remove the ALBs until it is turned off.
