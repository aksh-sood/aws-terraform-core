# kubernetes

The second of the two stacks: everything that runs *inside* the cluster the
[aws](../aws/README.md) stack built, plus the application release.

```
main.tf          module wiring, storage classes, DNS records, the app release
providers.tf     the three Kubernetes providers and how they authenticate
vars.tf          inputs — the aws handover first, then external infrastructure
outputs.tf       load balancer hostnames, generated credentials, the scrape contract
modules/addons      AWS Load Balancer Controller     → modules/addons/README.md
modules/istio       mesh, ingress, ALBs, basic auth  → modules/istio/README.md
modules/monitoring  Prometheus, Alertmanager, Grafana → modules/monitoring/README.md
modules/jaeger      tracing                          → modules/jaeger/README.md
modules/logging     Filebeat to OpenSearch, optional → modules/logging/README.md
```

## Prerequisites

- The `aws` stack applied, and its outputs handed over — see
  [../README.md](../README.md#the-handover).
- An ACM certificate (`acm_certificate_arn`) and two security groups
  (`elb_security_group`, `internal_alb_security_group`) for the ALBs.
- A domain (`domain_name`). Every hostname is
  `<cluster_name>-<service>.<domain_name>`.
- The `aws` CLI on `PATH` — all three providers mint API tokens with
  `aws eks get-token`.

## Applying

```bash
cp dev.tfvars.example dev.tfvars
terraform init
terraform apply -var-file=dev.tfvars
```

## Reaching a private cluster

`endpoint_public_access` defaults to `false` in the `aws` stack, so the API
server is reachable only from inside the VPC. **This stack talks to that endpoint
directly**, so it has to run from inside the VPC too:

- a bastion in a private subnet, reached with `aws ssm start-session`, or
- an SSM port-forward to the endpoint from your workstation, or
- a CI runner or CodeBuild project attached to the VPC.

For a demo, set `endpoint_public_access = true` with your own address in
`public_access_cidrs` on the first stack. That is a deliberate exception, not the
default.

## How the providers authenticate

[providers.tf](providers.tf) configures `kubernetes`, `helm` and `kubectl` the
same way: host and CA from the `aws` stack's outputs, and a token minted at apply
time by `aws eks get-token` rather than read from kubeconfig. Tokens therefore
cannot go stale part-way through a long apply.

Every module takes the kubectl provider through a `kubectl.this` configuration
alias, passed explicitly in the `providers` block of each module call. Adding a
module that uses `kubectl_manifest` means passing it too.

## Ordering

Terraform's graph gets most of this from references. The rest is explicit:

```
addons (load balancer controller)
  └─ storage classes ── istio (needs the controller for its ALB ingresses)
                          ├─ route53 records (CNAME → the public ALB)
                          ├─ monitoring   (istio CRDs for Gateway/VirtualService)
                          ├─ jaeger       (routes through the istio gateway)
                          ├─ logging      (same, optional)
                          └─ app release  (chart renders Gateway + VirtualService)
```

**`module.monitoring` cannot take `depends_on`.** Its `grafana-config` submodule
declares its own `provider "grafana"` block, which makes it a *legacy module* —
Terraform rejects `count`, `for_each` and `depends_on` on calls to those. It takes
its ordering through the `dependencies` input instead, which the module threads
into the Helm release's own `depends_on`. Anything that needs to run *after*
monitoring can still name it in its own `depends_on`, which is how the app release
waits for the Prometheus Operator CRDs.

## Inputs worth knowing

Full descriptions are in [vars.tf](vars.tf).

| Variable | Default | Effect |
| --- | --- | --- |
| `create_dns_records` | `false` | Creates the CNAMEs, and gates Grafana configuration — the Grafana provider needs the hostname to resolve. Requires `route53_zone_id` |
| `enable_ebs_persistent_storage` | `true` | `ebs` StorageClass. `false` switches to `efs` and needs `efs_id` |
| `deploy_app` | `true` | Installs the chart from `../../helm-chart` and publishes its hostname |
| `app_replica_count` | `1` | Three is the smallest count that survives losing a zone with two left serving |
| `app_values` | `{}` | Merged over the wiring in `main.tf`, so anything in the chart's `values.yaml` is reachable |
| `create_opensearch` | `false` | Adds the Filebeat shipper and the Kibana route |
| `istio_version` | `v1.30.3` | Must carry the leading `v` — the Sail `Istio` resource requires that form |
| `lbc_addon_version` | `3.5.0` | Load balancer controller chart |
| `enable_alb_logs` | `false` | Needs `logs_storage_s3_bucket` in the ALB's own region |

## Outputs

| Output | Notes |
| --- | --- |
| `external_loadbalancer_url`, `internal_loadbalancer_url` | ALB hostnames |
| `service_urls` | Published URLs, whether or not their DNS records are managed here |
| `dns_records` | FQDNs created. Empty when `create_dns_records` is false |
| `service_monitor_labels` | **All** of these must be on a `ServiceMonitor` for Prometheus to scrape it |
| `grafana_password`, `grafana_dev_password` | Grafana admin and developer. The developer is null unless `create_dns_records` is true |
| `prometheus_password`, `alertmanager_password`, `jaeger_password`, `app_password` | Basic auth at the istio gateway, user `admin` for all four |

## Reaching the UIs

With DNS records, `terraform output service_urls`. Without them:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
terraform output grafana_password
```

Prometheus, Alertmanager and Jaeger sit behind the basic auth WasmPlugin in
`modules/istio` when reached through the gateway; a port-forward bypasses it.

## Monitoring an application

Prometheus only scrapes `ServiceMonitor` objects carrying every label in
`service_monitor_labels` — the selector is an AND. The output and the chart's
`serviceMonitorSelector` are rendered from the same local in
[modules/monitoring/main.tf](modules/monitoring/main.tf), so the two cannot drift.
The in-repo chart already stamps both onto its ServiceMonitor; anything else
deployed here should read them from the output rather than copy them.
