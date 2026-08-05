# deploy-service

Helm chart that runs an HTTP microservice and exposes it through an Istio
ingress gateway.

The defaults deploy a working "Hello World" service with no extra values, but
nothing in the chart is app-specific — point `image`, `args` and `probes` at
another HTTP service and it is reusable as-is.

## What it renders

| Object | Template | Rendered when |
| --- | --- | --- |
| `Deployment` | [deployment.yaml](templates/deployment.yaml) | always |
| `Service` | [service.yaml](templates/service.yaml) | `service.enabled` |
| `Gateway` (Istio) | [gateway.yaml](templates/gateway.yaml) | `istio.gateway.enabled` |
| `VirtualService` (Istio) | [virtualservice.yaml](templates/virtualservice.yaml) | `istio.virtualService.enabled` |
| `ServiceAccount` | [serviceaccount.yaml](templates/serviceaccount.yaml) | `serviceAccount.create` |
| `ServiceMonitor` | [monitors.yaml](templates/monitors.yaml) | `metrics.serviceMonitor.enabled` (off by default) |

The first four are the set needed to run and expose the app. The
`ServiceAccount` exists so the workload does not borrow the namespace default,
and the `ServiceMonitor` carries over from the chart this replaced — both are
switchable.

## Requirements

- Kubernetes >= 1.27 (see [Version floors](#version-floors))
- Istio >= 1.22 in the cluster, with an ingress gateway `Deployment` whose
  labels match `istio.gateway.selector` (default `istio: ingressgateway`). The
  `Gateway` object configures listeners on that deployment; it does not create
  one.
- A DNS record per hostname in `istio.hosts`, pointing at the load balancer in
  front of that gateway.
- The Prometheus Operator CRDs, only if `metrics.serviceMonitor.enabled`.

Nothing above is created by this chart, and none of it is checked at install
time — a `Gateway` whose selector matches nothing is accepted by the API server
and silently programmes no listener.

## Quick start

```bash
helm install hello-world ./helm-chart \
  --namespace demo --create-namespace \
  --set istio.hosts[0]=hello.your-domain.com
```

Then:

```bash
kubectl -n demo rollout status deployment/hello-world-deploy-service
curl https://hello.your-domain.com/          # -> Hello World
```

Without a mesh or DNS, reach it directly:

```bash
kubectl -n demo port-forward svc/hello-world-deploy-service 8080:80
curl http://127.0.0.1:8080/                  # -> Hello World
```

Render locally without a cluster:

```bash
helm lint ./helm-chart --strict
helm template hello-world ./helm-chart -f ./helm-chart/ci/default-values.yaml
```

## How exposure works

```
client -> LB -> istio-ingressgateway pods -> Gateway (listener :80, host match)
                                         -> VirtualService (host -> route)
                                         -> Service :80 -> pod :8080
```

Both Istio objects live in the app's namespace, so a team owns its own routing
instead of editing a shared cluster-wide object. The `VirtualService` references
its `Gateway` namespace-qualified (`<ns>/<name>`) — an unqualified name resolves
in the *gateway's* namespace and silently drops the route.

`istio.virtualService.includeMesh` (on by default) also attaches the route to
`mesh`, so in-cluster callers use the same hostname as external ones rather than
needing a second address.

### Hostnames

Either list them:

```yaml
istio:
  hosts:
    - hello.prod.example.com
```

or derive them from a base domain, which keeps one values file usable across
environments:

```yaml
istio:
  hosts: []
  domain: prod.example.com
  hostPrefixes: [hello, hello-canary]   # -> hello.prod.example.com, ...
```

`hostPrefixes` defaults to the release's full name. Explicit `hosts` always wins.

### TLS

The default `Gateway` listens on plain HTTP:80, which assumes TLS is terminated
upstream at an ALB/NLB. To terminate at the gateway instead, put the certificate
in a secret **in the gateway's namespace** and:

```yaml
istio:
  gateway:
    servers:
      - port: { number: 80, name: http, protocol: HTTP }
        tls:
          httpsRedirect: true
      - port: { number: 443, name: https, protocol: HTTPS }
        tls:
          mode: SIMPLE
          credentialName: app-tls
```

### Routing beyond one prefix

`istio.virtualService.route` covers the single-route case. For traffic
splitting, mirroring, fault injection or several match blocks, set
`istio.virtualService.http` to a raw list of `HTTPRoute` entries — it is passed
through verbatim and `route` is then ignored. See
[ci/full-values.yaml](ci/full-values.yaml) for a canary example.

## Configuration

`values.yaml` is commented per field and is the reference. The knobs most likely
to need changing:

### Workload

| Key | Default | Notes |
| --- | --- | --- |
| `replicaCount` | `3` | Smallest count that survives losing one AZ with two left serving |
| `image.registry` / `.repository` / `.tag` / `.digest` | `""` / `hashicorp/http-echo` / `""` / `""` | `tag` falls back to `Chart.appVersion`; `digest` wins over `tag` |
| `command` / `args` | `[]` / `-listen=:8080`, `-text=Hello World` | `args` appends to the image ENTRYPOINT |
| `containerPorts` | one `http` port on `8080` | Raw port list; names are referenced by `service.ports[].targetPort` and the probes |
| `env` / `extraEnv` / `envFrom` | `{}` / `[]` / `[]` | `env` is name/value pairs; `extraEnv` is raw entries for `valueFrom` |
| `resources` | `50m` CPU request, `64Mi` memory request == limit | See [Resources](#resources) |
| `probes.{startup,readiness,liveness}` | enabled, `GET /` | Passed through minus `enabled`, so `tcpSocket`/`grpc`/`exec` work too |
| `lifecycle` | `{}` | See [Graceful shutdown](#graceful-shutdown) |
| `extraVolumes` / `extraVolumeMounts` | `emptyDir` on `/tmp` | Needed because the root filesystem is read-only |
| `initContainers` / `sidecars` | `[]` | Rendered verbatim |

### Scheduling and rollout

| Key | Default | Notes |
| --- | --- | --- |
| `topologySpreadConstraints` | zone `DoNotSchedule`, host `ScheduleAnyway` | A `labelSelector` is injected per constraint when omitted |
| `deployment.strategy` | `maxUnavailable: 0`, `maxSurge: 1` | Full capacity through a rollout; needs headroom for one extra pod |
| `deployment.minReadySeconds` | `5` | Stops a pod that passes readiness then crashes from counting as progress |
| `nodeSelector` / `tolerations` / `affinity` / `priorityClassName` | empty | Verbatim |

### Security

| Key | Default |
| --- | --- |
| `podSecurityContext` | `runAsNonRoot`, uid/gid/fsGroup `65532`, `seccompProfile: RuntimeDefault` |
| `containerSecurityContext` | the above plus `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` |
| `serviceAccount.create` | `true` — a dedicated SA, so the namespace default stays unused |
| `serviceAccount.automountServiceAccountToken` | `false` — the app makes no API calls |
| `serviceAccount.annotations` | `{}` — where an IRSA role ARN goes |

These defaults satisfy the restricted Pod Security Standard. The uid matches the
default image, which runs as `65532`; change both together for another image.

### Istio and metrics

| Key | Default | Notes |
| --- | --- | --- |
| `istio.apiVersion` | `networking.istio.io/v1` | Use `v1beta1` below Istio 1.22 |
| `istio.sidecarInject` / `istio.revision` | `""` | Empty leaves injection to the namespace label; set to force it per workload |
| `istio.gateway.selector` | `istio: ingressgateway` | Must match the ingress gateway deployment's labels |
| `istio.virtualService.route.timeout` | `15s` | Istio's own default is no timeout at all |
| `istio.virtualService.route.retries` | 3 attempts on `connect-failure,refused-stream,gateway-error` | See [Retries](#retries) |
| `metrics.serviceMonitor.enabled` | `false` | Turn on once the app serves `/metrics` |
| `metrics.serviceMonitor.labels` | `prometheus: prometheus-kube-prometheus-prometheus`, `release: prometheus` | Must match the Prometheus instance's `serviceMonitorSelector`, or the target is never scraped and nothing reports an error |

### Naming and metadata

`nameOverride`, `fullnameOverride`, `namespaceOverride`, `clusterDomain`,
`component`, `partOf`, `commonLabels`, `commonAnnotations`, and
`legacyLabels.enabled` (re-adds the pre-`app.kubernetes.io` `app` /
`application` labels for tooling that still selects on them — the chart's own
selectors never do).

## Design decisions and trade-offs

### Multi-AZ placement

The zone constraint uses `whenUnsatisfiable: DoNotSchedule`. That is what makes
the deployment genuinely multi-AZ: a pod stays `Pending` rather than letting
every replica land in one AZ, which is the failure mode a soft constraint hides
until the AZ goes away.

The cost is real: if the node groups are not spread evenly enough to satisfy the
skew, capacity in one AZ caps the whole deployment. Relax it to
`ScheduleAnyway` when that is the wrong trade.

`matchLabelKeys: [pod-template-hash]` scopes the skew calculation to the
ReplicaSet being rolled out, so a rollout is not blocked by pods of the previous
revision.

### Resources

A CPU **request** with no CPU **limit**: the request guarantees a floor and
drives scheduling, while leaving the container free to burst into idle capacity
instead of being throttled at a ceiling. Memory is set request == limit, because
memory is not compressible — a limit above the request only defers the OOM kill
and makes the pod's footprint unpredictable.

This yields a `Burstable` pod. Set `resources.limits.cpu` if you need
`Guaranteed` for static CPU pinning.

### Retries

`retryOn` lists only conditions where the request provably never reached the
app (`connect-failure`, `refused-stream`, `gateway-error`), so retrying is safe
even for non-idempotent handlers. Adding `5xx` or `retriable-status-codes` would
not be — a 500 from a handler that already committed a write gets replayed.

### Graceful shutdown

`terminationGracePeriodSeconds: 30` bounds shutdown, but `lifecycle` is empty by
default. A rolling update can still drop requests in the window between a pod
entering `Terminating` and endpoint removal propagating to the ingress gateway;
a preStop hook is what closes it:

```yaml
lifecycle:
  preStop:
    sleep:
      seconds: 5
```

It is not on by default because the `sleep` handler needs Kubernetes >= 1.30,
and the `exec` alternative needs a shell in the image — the default image has
neither a shell nor a reason to need this.

### Fail fast on bad values

`_helpers.tpl` refuses to render on combinations the API would accept and
quietly do nothing with, or reject much later:

- `replicaCount` below 1, or empty `containerPorts`
- Gateway/VirtualService enabled with no resolvable hostname
- a VirtualService with no Service to route to and no explicit `http`
- a VirtualService that would attach to no gateway at all

## Version floors

`Chart.yaml` sets `kubeVersion: ">=1.27.0-0"`, which is a soft floor:
`topologySpreadConstraints.matchLabelKeys` is honoured from 1.27 and older API
servers prune the field rather than reject it. The hard requirement is Istio
>= 1.22 for `networking.istio.io/v1`; drop `istio.apiVersion` to `v1beta1` below
that.

## Out of scope

Not included, deliberately — each belongs to a component outside this chart:

- **HorizontalPodAutoscaler** — `replicaCount` is fixed. Add an HPA and the
  chart's `replicas` field will fight it.
- **PodDisruptionBudget** — nothing currently protects the workload against
  concurrent voluntary evictions (node drains) beyond the rollout strategy.
- **NetworkPolicy**, **PeerAuthentication**, **AuthorizationPolicy** — traffic
  is scoped at the routing layer here, not restricted at L3/L4 or by workload
  identity.
- **PrometheusRule** / Grafana dashboards — the `ServiceMonitor` provides the
  scrape target only; alerts and dashboards live with the monitoring stack.
- The application image itself, and the namespace the chart renders into.

## Validating a change

```bash
helm lint ./helm-chart --strict

for f in ./helm-chart/ci/*.yaml; do
  helm template rel ./helm-chart -f "$f" > /dev/null || echo "FAILED: $f"
done
```

The [ci/](ci/) fixtures cover the paths that are easy to break: chart defaults,
derived hostnames plus the ServiceMonitor, a mesh-only release with no
`Gateway`, and [full-values.yaml](ci/full-values.yaml) exercising digest
pinning, gateway TLS, per-server host overrides, raw `http` routes, sidecars and
explicit `labelSelector` passthrough.

## Migrating from the previous chart

Value names changed to the Helm convention, and objects are now named after the
release *and* chart rather than the release alone:

| Before | Now |
| --- | --- |
| `replicas` | `replicaCount` |
| `image` (bare string) | `image.registry` + `.repository` + `.tag` / `.digest` |
| `docker_registry` | `image.registry` |
| `targetPort` | `containerPorts[].containerPort` |
| `port` | `service.ports[].port` |
| `health_endpoint` | `probes.{startup,readiness,liveness}.httpGet.path` |
| `url_prefix` | `istio.virtualService.route.match` (+ `.rewriteUri`) |
| `domain`, `subdomain_suffix` | `istio.domain`, `istio.hostPrefixes` |
| `security_context` (bool) | `podSecurityContext`, `containerSecurityContext` |
| `volumes`, `mounts` | `extraVolumes`, `extraVolumeMounts` |
| `env` | `env` (unchanged) or `extraEnv` for `valueFrom` |

The `Deployment` selector moved from `application: <release>` to
`app.kubernetes.io/{name,instance}`. Selectors are immutable, so an existing
release must be deleted and reinstalled rather than upgraded in place. Set
`legacyLabels.enabled: true` to keep emitting the old labels for other tooling.
