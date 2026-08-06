# modules/monitoring

Prometheus, Alertmanager and Grafana, from
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts),
plus the routing that publishes their UIs through the mesh.

## Creates

| Object | Notes |
| --- | --- |
| `prometheus` Helm release | kube-prometheus-stack in `monitoring`, values rendered from [configs/](configs) |
| `random_password` | Grafana admin |
| `monitoring-gateway` `Gateway` | Listener for the Grafana, Prometheus and Alertmanager hostnames |
| `VirtualService`s | One per UI, split out of [configs/virtualServices.yaml](configs/virtualServices.yaml) and applied individually so a change to one does not replace all three |
| [modules/grafana-config](modules/grafana-config) | Folder, dashboards, a developer user and the CloudWatch datasource, over Grafana's HTTP API |
| `kube-state-metrics` release | **`count = 0`** — kube-prometheus-stack already ships it. Kept for the case where it needs to be run separately |

## Configuration

[configs/](configs) is rendered with `templatefile` and passed to Helm as values:

| File | Contents |
| --- | --- |
| `config.yaml` | The values file itself — Prometheus retention (90d), storage, the ServiceMonitor selector, Grafana persistence, extra scrape configs |
| `alerts.yaml` | `additionalPrometheusRulesMap`, from `var.required_alerts` merged with `var.custom_alerts` |
| `alertmanager.yaml` | Receivers — Slack, PagerDuty, and an SNS topic for Google Chat |
| `kubeStateMetrics.yaml` | Only used by the disabled release above |
| `nodeExporter.yaml` | Orphaned — the release that consumed it has been removed |

`var.required_alerts` holds nine rules covering pods down, OOM kills, volume and
node disk pressure, inode exhaustion, CPU, memory and swap. Anything passed as
`custom_alerts` is appended, not merged, so the built-in set always applies.

## The ServiceMonitor label contract

Prometheus is configured with a `serviceMonitorSelector`, so it scrapes only
`ServiceMonitor` objects carrying **all** of these labels:

```
prometheus: prometheus-kube-prometheus-prometheus
release: prometheus
```

They are defined once as `local.service_monitor_labels` in [main.tf](main.tf),
rendered into the chart values *and* published as the `service_monitor_labels`
output, so the enforced selector and the documented contract cannot drift. A
chart that gets them wrong is not scraped and nothing reports an error —
`serviceMonitorNamespaceSelector` is `{}`, so namespace is not the constraint,
labels are.

## Inputs

Required: `environment`, `domain_name`, `grafana_role_arn`, `configure_grafana`,
`dependencies`, `custom_alerts`, `kube_prometheus_stack_version`,
`node_exporter_version`, `kube_state_metrics_version`, `prometheus_volume_size`,
`alert_manager_volume_size`, `slack_web_hook`, `slack_channel_name`,
`pagerduty_key`.

Defaulted: `prometheus_storage_class` (`efs`), `grafana_volume_size`,
`required_alerts`, `sns_topic_arn`, `gchat_webhook_url`, `efs_depends_on`,
`ebs_depends_on`.

Requires the `kubectl.this` provider alias.

## Outputs

`grafana_password`, `grafana_dev_password` (null unless `configure_grafana`), and
`service_monitor_labels`.

## Gotchas

- **This is a legacy module.** `modules/grafana-config` declares its own
  `provider "grafana"` block, and Terraform rejects `count`, `for_each` and
  `depends_on` on calls to any module containing a provider configuration. Callers
  order it through the `dependencies` input, which this module threads into the
  Helm release's `depends_on`. Naming *this* module in something else's
  `depends_on` is still fine.
- **Grafana configuration needs DNS.** The Grafana provider connects to
  `https://<environment>-grafana.<domain_name>`, so dashboards, the developer user
  and the CloudWatch datasource only apply when that hostname resolves. The root
  wires `configure_grafana = var.create_dns_records` for exactly that reason. On
  the default path Grafana comes up with the chart's built-in dashboards only.
- **The CloudWatch datasource hardcodes `us-east-1`** and uses
  `"authType": "assumeRole"`, which is not one of the plugin's recognised
  `authType` values — `default` with `assumeRoleArn` is the documented pairing.
- **Storage class must exist first.** `prometheus_storage_class` is `ebs` or `efs`
  depending on the root's `enable_ebs_persistent_storage`; the corresponding
  `efs_depends_on` / `ebs_depends_on` input is what orders the release after the
  StorageClass.
- **The two `additionalScrapeConfigs` in `config.yaml` are vestigial.** One keeps
  endpoints named `node-exporter-prometheus-node-exporter` — a release that no
  longer exists in this module at all; the other targets
  `kube-state-metrics.kube-system.svc.cluster.local:8080`, while
  kube-prometheus-stack installs kube-state-metrics into its own release namespace.
  Neither resolves to anything — the chart's own ServiceMonitors are what actually
  scrape both components.
- **`node_exporter_version` is a dead input.** It is declared at the root, passed
  down through `main.tf`, declared again here, and consumed by nothing since the
  node-exporter release was removed. `nodeExporter.yaml` is orphaned with it.
- **`retention: 90d` with no `retentionSize`.** The volume is sized by
  `prometheus_volume_size` (50Gi at the root) — if 90 days of series exceed it,
  Prometheus fills the disk rather than dropping old data.
