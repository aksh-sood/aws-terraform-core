# deploy-service

Helm chart that runs an HTTP microservice and exposes it through an Istio
ingress gateway.

The defaults deploy a working "Hello World" with no extra values, but nothing in
the chart is app-specific — point `image`, `args` and `healthPath` at another
HTTP service and it is reusable as-is.

The chart is deliberately opinionated. `values.yaml` exposes only what varies
between deployments; the production-hardening decisions are fixed in the
templates, with the reasoning written next to each one. [What is fixed, and
why](#what-is-fixed-and-why) lists all of it.

## What it renders

| Object | Template | Rendered when |
| --- | --- | --- |
| `Deployment` | [deployment.yaml](templates/deployment.yaml) | always |
| `Service` | [service.yaml](templates/service.yaml) | always |
| `Gateway` (Istio) | [gateway.yaml](templates/gateway.yaml) | `istio.gateway.enabled` |
| `VirtualService` (Istio) | [virtualservice.yaml](templates/virtualservice.yaml) | `istio.virtualService.enabled` |
| `ServiceAccount` | [serviceaccount.yaml](templates/serviceaccount.yaml) | `serviceAccount.create` |
| `ServiceMonitor` | [monitors.yaml](templates/monitors.yaml) | `metrics.enabled` (off by default) |

## Requirements

- Kubernetes >= 1.27. `topologySpreadConstraints.matchLabelKeys` is honoured
  from 1.27; older API servers prune the field rather than reject it, so the
  floor is soft.
- Istio >= 1.22 for `networking.istio.io/v1`. Verified against 1.24.
- An ingress gateway `Deployment` whose labels match `istio.gateway.selector`
  (default `istio: ingressgateway`). The `Gateway` object configures listeners
  on that deployment; **it does not create one**.
- A DNS record per hostname in `istio.hosts`, resolving to the load balancer in
  front of that gateway.
- Prometheus Operator CRDs, only if `metrics.enabled`.

None of that is created by this chart, and none of it is checked at install
time. A `Gateway` whose selector matches nothing is accepted by the API server
and silently programmes no listener.

## Quick start

```bash
helm install hello-world ./helm-chart \
  --namespace demo --create-namespace \
  --set istio.hosts[0]=hello.your-domain.com
```

```bash
kubectl -n demo rollout status deployment/hello-world-deploy-service
curl https://hello.your-domain.com/          # -> Hello World
```

Without DNS or a mesh, go straight at the Service:

```bash
kubectl -n demo port-forward svc/hello-world-deploy-service 8080:80
curl http://127.0.0.1:8080/                  # -> Hello World
```

Render locally, no cluster needed:

```bash
helm lint ./helm-chart --strict
helm template hello-world ./helm-chart -f ./helm-chart/ci/default-values.yaml
```

## How exposure works

```
client -> LB (TLS terminates here) -> istio-ingressgateway pods
       -> Gateway        (listener :80, matches Host)
       -> VirtualService (Host -> route)
       -> Service :80    -> pod :8080
```

Both Istio objects live in the app's namespace, so a team owns its own routing
rather than editing a shared cluster-wide object. The `VirtualService` names its
`Gateway` namespace-qualified (`<ns>/<name>`) — an unqualified name resolves in
the *gateway's* namespace and silently drops the route.

`mesh` is always in the `gateways` list, so in-cluster callers reach the app on
the same hostname as external ones.

### Sidecar injection

The chart does not force injection. Label the namespace, which is the normal
arrangement:

```bash
kubectl label namespace demo istio.io/rev=default
```

If the namespace is not yours to label, opt in per pod instead — both labels are
required:

```yaml
podLabels:
  sidecar.istio.io/inject: "true"
  istio.io/rev: default
```

Without a sidecar the app is still reachable through the Gateway; what you lose
is mesh mTLS, the `mesh` route for in-cluster callers, and Istio's RED metrics.

## Configuration

That is the whole list. `values.yaml` carries a comment per field.

| Key | Default | Notes |
| --- | --- | --- |
| `fullnameOverride` | `""` | Replaces the generated `<release>-<chart>` name on every object |
| `image.repository` | `hashicorp/http-echo` | |
| `image.tag` | `latest` | Empty falls back to `Chart.appVersion` |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | |
| `replicaCount` | `1` | 3+ to actually spread across AZs |
| `args` | http-echo flags | Appended to the image ENTRYPOINT. Clear when changing `image` |
| `containerPort` | `8080` | Named `http` everywhere downstream |
| `env` | `{}` | Name/value pairs |
| `envFrom` | `[]` | For Secret/ConfigMap references |
| `healthPath` | `/` | Serves all three probes |
| `resources` | 50m CPU req, 64Mi mem req == limit | See [Resources](#resources) |
| `podAnnotations` | `{}` | |
| `podLabels` | `{}` | Where per-pod injection labels go |
| `nodeSelector` / `tolerations` | `{}` / `[]` | |
| `serviceAccount.create` | `true` | Named after the release |
| `serviceAccount.annotations` | `{}` | Where an IRSA role ARN goes |
| `service.port` | `80` | |
| `istio.hosts` | `[hello-world.example.com]` | **Shared by the Gateway and the VirtualService.** Change this |
| `istio.gateway.enabled` | `true` | |
| `istio.gateway.selector` | `istio: ingressgateway` | Must match the ingress gateway deployment |
| `istio.virtualService.enabled` | `true` | |
| `istio.virtualService.prefix` | `/` | URI prefix match |
| `istio.virtualService.timeout` | `15s` | Istio's own default is no timeout |
| `metrics.enabled` | `false` | Turn on once the app serves metrics |
| `metrics.path` | `/metrics` | Scraped on the `http` port |

## What is fixed, and why

These are hardcoded in the templates. Each is a decision that should not vary
per deployment; changing one means editing the template, which is the point —
it makes the change visible in review.

**Security** ([deployment.yaml](templates/deployment.yaml),
[serviceaccount.yaml](templates/serviceaccount.yaml))

- Pod context: `runAsNonRoot`, uid/gid/fsGroup `65532`, `seccompProfile:
  RuntimeDefault`. The uid matches what the default image already runs as.
- Container context: `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`.
- `automountServiceAccountToken: false` on both the pod and the ServiceAccount —
  the app makes no API calls. An injected sidecar is unaffected; it mounts its
  own `istio-token`.
- Together these satisfy the restricted Pod Security Standard.
- `readOnlyRootFilesystem` is why an `emptyDir` is mounted at `/tmp`.

**Availability** ([deployment.yaml](templates/deployment.yaml))

- Topology spread: `maxSkew: 1` on `topology.kubernetes.io/zone` with
  `whenUnsatisfiable: DoNotSchedule`, plus a soft constraint on
  `kubernetes.io/hostname`. See [Multi-AZ placement](#multi-az-placement).
- Rollout: `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 5`,
  `revisionHistoryLimit: 3`, `progressDeadlineSeconds: 600`.
- `terminationGracePeriodSeconds: 30`.
- Probes: startup (2s × 30), readiness (5s, 3 failures), liveness (10s, 3
  failures), all on `healthPath`. Startup absorbs a slow boot so liveness can
  stay tight; liveness is more forgiving than readiness on purpose.

**Networking** ([service.yaml](templates/service.yaml),
[gateway.yaml](templates/gateway.yaml),
[virtualservice.yaml](templates/virtualservice.yaml))

- Service is `ClusterIP` with one `http` port and `appProtocol: http` — the
  gateway is the only client, and `appProtocol` is what tells Istio the port
  speaks HTTP.
- Gateway serves one plain-HTTP listener on `:80`, because TLS terminates at
  the load balancer upstream. To terminate at the gateway instead, add an HTTPS
  server with `tls.mode: SIMPLE` and a `credentialName` naming a secret in the
  *gateway's* namespace, and set `tls.httpsRedirect` on the `:80` server.
- `mesh` is always in the VirtualService's `gateways`.
- Retries: 3 attempts, 3s per try, on
  `connect-failure,refused-stream,gateway-error`. See [Retries](#retries).
- `networking.istio.io/v1`, no version switch. Drop to `v1beta1` in the two
  templates for Istio < 1.22.

**Monitoring** ([monitors.yaml](templates/monitors.yaml))

- ServiceMonitor labels `prometheus: prometheus-kube-prometheus-prometheus` and
  `release: prometheus`. These are what the platform's Prometheus selects
  ServiceMonitors on — wrong labels mean the target is never scraped and
  *nothing reports an error*.
- Scrape interval 30s, timeout 10s, on the `http` port.

## Design decisions and trade-offs

### Multi-AZ placement

`whenUnsatisfiable: DoNotSchedule` on the zone key is what makes this genuinely
multi-AZ: a pod stays `Pending` rather than letting every replica land in one
AZ, which is the failure mode a soft constraint hides until the AZ goes away.

The cost is real. If node capacity is not spread evenly enough to satisfy the
skew, capacity in one AZ caps the whole deployment, and a `helm install --wait`
will time out rather than schedule. Relax that one constraint to
`ScheduleAnyway` when that is the wrong trade.

`matchLabelKeys: [pod-template-hash]` scopes the skew calculation to the
ReplicaSet being rolled out, so a rollout is not blocked by pods of the previous
revision.

### Resources

A CPU **request** with no CPU **limit**: the request guarantees a floor and
drives scheduling, while leaving the container free to burst into idle capacity
instead of being throttled at a ceiling. Memory is request == limit, because
memory is not compressible — a limit above the request only defers the OOM kill
and makes the footprint unpredictable.

This yields a `Burstable` pod. Add a CPU limit if you need `Guaranteed`.

### Retries

`retryOn` lists only conditions where the request provably never reached the app,
so a retry is safe even for a non-idempotent handler. Adding `5xx` or
`retriable-status-codes` would not be: a 500 from a handler that already
committed a write would be replayed.

### Fail fast on bad values

[_helpers.tpl](templates/_helpers.tpl) refuses to render when `replicaCount` is
below 1, when `image.repository` is empty, or when the Gateway/VirtualService is
enabled with no `istio.hosts`. The last one otherwise produces a Gateway with an
empty host list, which is valid YAML that matches no traffic.

## Not included

Deliberately out of scope — each belongs to a component outside this chart:

- **HorizontalPodAutoscaler** — `replicaCount` is fixed, and an HPA would fight
  the `replicas` field.
- **PodDisruptionBudget** — nothing protects the workload against concurrent
  voluntary evictions (node drains) beyond the rollout strategy. This is the
  most significant gap.
- **NetworkPolicy**, **PeerAuthentication**, **AuthorizationPolicy** — traffic
  is scoped at the routing layer only, not at L3/L4 or by workload identity.
- **PrometheusRule** and Grafana dashboards — the ServiceMonitor gives a scrape
  target; alerts and dashboards live with the monitoring stack.
- **preStop hook** — without one, a rolling update can drop requests in the
  window between a pod entering `Terminating` and endpoint removal reaching the
  ingress gateway. Adding `lifecycle.preStop.sleep` to the container needs
  Kubernetes >= 1.30; the `exec` form needs a shell, which the default image
  does not have.
- The application image, and the namespace the chart renders into.

Consequences of the reduced value surface: **no** gateway TLS termination, raw
`http` route lists (canary/mirroring/traffic splitting), CORS, URI rewrite,
per-probe tuning, `initContainers`, sidecars, extra volumes, `affinity`,
`priorityClassName`, or digest-pinned images. All are a small template edit
away; none is reachable from values.

## Validating a change

```bash
helm lint ./helm-chart --strict

for f in ./helm-chart/ci/*.yaml; do
  helm template rel ./helm-chart -f "$f" > /dev/null || echo "FAILED: $f"
done
```

The [ci/](ci/) fixtures are picked up automatically by
[chart-testing](https://github.com/helm/chart-testing) (`ct lint`), which runs a
separate render per file:

| Fixture | Pins |
| --- | --- |
| [default-values.yaml](ci/default-values.yaml) | Chart defaults with a real hostname |
| [mesh-only-values.yaml](ci/mesh-only-values.yaml) | `Gateway` disabled — the `gateways` list must not render empty |
| [overrides-values.yaml](ci/overrides-values.yaml) | Every remaining knob moved off its default, plus the ServiceMonitor and per-pod injection labels |

These are render checks, not assertions: they prove the templates produce
parseable YAML, not that a specific field has a specific value. Use
[helm-unittest](https://github.com/helm-unittest/helm-unittest) if you need the
latter.

## Deployed by Terraform

`helm_release.app_release` in
[terraform/kubernetes/main.tf](../terraform/kubernetes/main.tf) installs this
chart from the local path, so the chart is versioned with the stack that deploys
it. That release sets `replicaCount`, `image` and `istio.hosts` — the last built
as `<cluster_name>-<app_host_prefix>.<domain_name>` to match the platform's
other hostnames — and passes `var.app_values` as a second values document, so
anything in this file can be overridden from Terraform without editing HCL.
