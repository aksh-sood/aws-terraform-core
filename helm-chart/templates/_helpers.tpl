{{/*
Chart name, overridable with nameOverride.
*/}}
{{- define "deploy-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Object name. "<release>-<chart>", collapsed to just the release name when the
release already contains the chart name, so a release called "hello-world" does
not produce "hello-world-deploy-service". Truncated to 63 chars for the DNS
label limit that Service names are bound by.
*/}}
{{- define "deploy-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Namespace every object is rendered into.
*/}}
{{- define "deploy-service.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end }}

{{- define "deploy-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Selector labels. These land in Deployment.spec.selector, which is immutable
after creation, so this set must stay stable across chart versions — never add
anything version- or config-derived here.
*/}}
{{- define "deploy-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "deploy-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full label set for object metadata.
*/}}
{{- define "deploy-service.labels" -}}
helm.sh/chart: {{ include "deploy-service.chart" . }}
{{ include "deploy-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: {{ .Values.component | default "server" }}
app.kubernetes.io/part-of: {{ .Values.partOf | default (include "deploy-service.name" .) }}
{{- if .Values.legacyLabels.enabled }}
app: {{ include "deploy-service.fullname" . }}
application: {{ include "deploy-service.fullname" . }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Pod labels the mesh reads. Empty values leave sidecar injection to the
namespace label, which is the usual arrangement.
*/}}
{{- define "deploy-service.istioPodLabels" -}}
{{- with .Values.istio.sidecarInject }}
sidecar.istio.io/inject: {{ . | quote }}
{{- end }}
{{- with .Values.istio.revision }}
istio.io/rev: {{ . | quote }}
{{- end }}
{{- end }}

{{/*
Fully qualified image reference. A digest, when given, wins over the tag.
*/}}
{{- define "deploy-service.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- with .Values.image.registry -}}
{{- $repo = printf "%s/%s" . $repo -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repo (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end }}

{{- define "deploy-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "deploy-service.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{/*
In-cluster FQDN of this chart's Service, used as the VirtualService
destination. The short name would also resolve, but only from the same
namespace — the FQDN keeps the route correct when the VirtualService is
exported elsewhere.
*/}}
{{- define "deploy-service.serviceHost" -}}
{{- printf "%s.%s.svc.%s" (include "deploy-service.fullname" .) (include "deploy-service.namespace" .) .Values.clusterDomain -}}
{{- end }}

{{- define "deploy-service.gatewayName" -}}
{{- default (printf "%s-gateway" (include "deploy-service.fullname" .)) .Values.istio.gateway.name -}}
{{- end }}

{{- define "deploy-service.virtualServiceName" -}}
{{- default (include "deploy-service.fullname" .) .Values.istio.virtualService.name -}}
{{- end }}

{{/*
Hostnames served, as a YAML list. Explicit istio.hosts wins; otherwise they are
derived from istio.domain and istio.hostPrefixes, defaulting the prefix to the
release's full name.
*/}}
{{- define "deploy-service.hosts" -}}
{{- $hosts := .Values.istio.hosts | default list -}}
{{- if and (not $hosts) .Values.istio.domain -}}
{{- $prefixes := .Values.istio.hostPrefixes | default (list (include "deploy-service.fullname" .)) -}}
{{- range $prefix := $prefixes -}}
{{- $hosts = append $hosts (printf "%s.%s" $prefix $.Values.istio.domain) -}}
{{- end -}}
{{- end -}}
{{- toYaml $hosts -}}
{{- end }}

{{/*
VirtualService hosts, falling back to the shared set.
*/}}
{{- define "deploy-service.virtualServiceHosts" -}}
{{- if .Values.istio.virtualService.hosts -}}
{{- toYaml .Values.istio.virtualService.hosts -}}
{{- else -}}
{{- include "deploy-service.hosts" . -}}
{{- end -}}
{{- end }}

{{/*
Destination port for the generated route: an explicit route.port, else the
Service port named route.portName, else the first Service port.
*/}}
{{- define "deploy-service.routePort" -}}
{{- $route := .Values.istio.virtualService.route -}}
{{- if $route.port -}}
{{- $route.port -}}
{{- else -}}
{{- $ports := .Values.service.ports -}}
{{- if not $ports -}}
{{- fail "istio.virtualService needs a destination: set service.ports, or istio.virtualService.route.port" -}}
{{- end -}}
{{- $want := $route.portName | default "http" -}}
{{- $found := "" -}}
{{- range $port := $ports -}}
{{- if eq $port.name $want -}}
{{- $found = $port.port -}}
{{- end -}}
{{- end -}}
{{- if $found -}}
{{- $found -}}
{{- else -}}
{{- (first $ports).port -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Fail fast on value combinations the API would only reject later, or would
accept and quietly do nothing useful with. Included from deployment.yaml, which
always renders.
*/}}
{{- define "deploy-service.validate" -}}
{{- if lt (int .Values.replicaCount) 1 -}}
{{- fail "replicaCount must be at least 1" -}}
{{- end -}}
{{- if not .Values.containerPorts -}}
{{- fail "containerPorts must define at least one port" -}}
{{- end -}}
{{- if or .Values.istio.gateway.enabled .Values.istio.virtualService.enabled -}}
{{- if not (include "deploy-service.hosts" . | fromYamlArray) -}}
{{- fail "set istio.hosts, or istio.domain, when the Gateway or VirtualService is enabled" -}}
{{- end -}}
{{- end -}}
{{- if and .Values.istio.virtualService.enabled (not .Values.service.enabled) (not .Values.istio.virtualService.http) -}}
{{- fail "istio.virtualService.enabled needs service.enabled for its destination, or an explicit istio.virtualService.http" -}}
{{- end -}}
{{- if and .Values.istio.virtualService.enabled (not .Values.istio.gateway.enabled) (not .Values.istio.virtualService.gateways) (not .Values.istio.virtualService.includeMesh) -}}
{{- fail "the VirtualService would attach to no gateway: enable istio.gateway, or set istio.virtualService.gateways, or leave includeMesh on" -}}
{{- end -}}
{{- end }}
