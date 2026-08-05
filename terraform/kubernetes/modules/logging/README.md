# modules/logging

Ships container logs to an existing OpenSearch domain and publishes Kibana
through the mesh. Optional — the root instantiates it only when
`create_opensearch` is true.

## Creates

| Object | Notes |
| --- | --- |
| `logging` namespace | |
| `aws-es` Service | `ExternalName` pointing at `opensearch_endpoint`, so pods reach OpenSearch through a stable in-cluster name |
| `filebeat` Helm release | `filebeat-oss` 7.13.0, autodiscovering every container's logs from `/var/log/pods` |
| `Gateway`, `VirtualService` | `<environment>-kibana.<domain_name>`, redirecting `/` to `/_dashboards/` |
| `ServiceEntry`, `DestinationRule` | Registers the OpenSearch endpoint as `MESH_EXTERNAL` and originates TLS to it, so the sidecar allows the egress |

Every object references `local.namespace`, which reads back from the namespace
resource — the whole module is therefore ordered after the namespace exists
without any `depends_on`.

## Inputs

`opensearch_endpoint` (hostname, no scheme), `opensearch_username`,
`opensearch_password`, `environment`, `domain_name`, and `namespace`
(default `logging`). Requires the `kubectl.this` provider alias.

## Gotchas

- **Credentials go into Helm values** through `templatefile` on
  [filebeat.yaml](filebeat.yaml). The root marks `opensearch_password` sensitive,
  so the rendered values are redacted in plan output, but they are a Secret in the
  cluster like any other Helm value.
- **`filebeat.yaml` escapes its own templating.** `$${data.kubernetes.pod.uid}` is
  Filebeat's syntax, not Terraform's — the doubled `$` is what keeps
  `templatefile` from trying to resolve it.
- **`ssl.verification_mode: none`** on the Elasticsearch output. The
  `DestinationRule` originates TLS, so the hop leaving the node is encrypted, but
  the certificate is not verified.
- **Filebeat 7.13.0 is old** and pinned in the module rather than exposed as a
  variable.
