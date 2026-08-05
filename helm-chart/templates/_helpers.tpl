{{- define "deploy-service.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Object name: "<release>-<chart>", collapsed to just the release name when the
release already contains the chart name. Truncated to 63 chars for the DNS
label limit Service names are bound by.
*/}}
{{- define "deploy-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Selector labels. These land in Deployment.spec.selector, which is immutable
after creation, so this set must stay stable — never add anything version- or
config-derived here.
*/}}
{{- define "deploy-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "deploy-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "deploy-service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "deploy-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "deploy-service.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- printf "%s:%s" $repo (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end }}

{{- define "deploy-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- include "deploy-service.fullname" . -}}
{{- else -}}
default
{{- end -}}
{{- end }}

{{/*
In-cluster FQDN of this chart's Service, used as the VirtualService
destination. The short name resolves only from this namespace; the FQDN stays
correct wherever the route is evaluated.
*/}}
{{- define "deploy-service.serviceHost" -}}
{{- printf "%s.%s.svc.cluster.local" (include "deploy-service.fullname" .) .Release.Namespace -}}
{{- end }}

{{- define "deploy-service.gatewayName" -}}
{{- printf "%s-gateway" (include "deploy-service.fullname" .) -}}
{{- end }}

{{/*
Fail on value combinations the API would accept and quietly do nothing useful
with. Included from deployment.yaml, which always renders.
*/}}
{{- define "deploy-service.validate" -}}
{{- if lt (int .Values.replicaCount) 1 -}}
{{- fail "replicaCount must be at least 1" -}}
{{- end -}}
{{- if and (or .Values.istio.gateway.enabled .Values.istio.virtualService.enabled) (not .Values.istio.hosts) -}}
{{- fail "istio.hosts must be set when the Gateway or VirtualService is enabled" -}}
{{- end -}}
{{- end }}
