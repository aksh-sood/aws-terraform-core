# modules/grafana-config

Grafana configuration applied over its HTTP API: the dashboards in
[dashboards/](dashboards), a folder to hold them, a non-admin user, and the
CloudWatch datasource.

Split out of [../..](../../README.md) because it is the only part of monitoring
that talks to Grafana rather than to Kubernetes.

## Creates

Every resource is gated on `configure_grafana`:

| Object | Notes |
| --- | --- |
| `grafana_folder` "Custom Dashboards" | |
| `grafana_dashboard` per file in `dashboards/` | `Nodes.json` and `Pods.json` today |
| `random_password` + `grafana_user` `developer` | Non-admin, for read access without sharing the admin credentials |
| `grafana_data_source` CloudWatch | `assumeRoleArn` set to `grafana_role_arn` from the aws stack |

All of them wait on `var.vs_dependency` — the VirtualServices from the parent
module — because the provider cannot reach Grafana until the route to it exists.

## Inputs

`grafana_password`, `configure_grafana`, `vs_dependency`, `grafana_role_arn`,
`domain_name`, `environment`.

## Outputs

`grafana_dev_password`, null when `configure_grafana` is false.

## Gotchas

- **The provider block here is what makes the parent a legacy module.** Terraform
  rejects `count`, `for_each` and `depends_on` on any module call whose tree
  contains a provider configuration, which is why the parent takes ordering
  through a `dependencies` variable. Moving this provider to the root is not a
  straight swap: its `url` and `auth` derive from a `random_password` generated
  inside the parent, and provider configuration cannot depend on a value that is
  unknown at plan time.
- **It needs the hostname to resolve, from wherever Terraform runs.** That is why
  the root sets `configure_grafana = var.create_dns_records`. The alternative —
  dashboards as ConfigMaps labelled `grafana_dashboard=1`, picked up by the
  chart's sidecar — removes the dependency on DNS and on the API being reachable,
  at the cost of the user resource, which has no file-based provisioning in
  Grafana.
- **`defaultRegion` is hardcoded `us-east-1`** in the datasource JSON, and
  `authType` is `assumeRole`, which the CloudWatch plugin does not list among its
  accepted values (`default` alongside `assumeRoleArn` is the documented pairing).
- **The datasource assumes a role reachable from the pod's own credentials.** The
  Grafana role trusts the node role, so this works today because Grafana picks up
  node-role credentials through IMDS — and would need an IRSA annotation on the
  Grafana service account if the node role were tightened.
