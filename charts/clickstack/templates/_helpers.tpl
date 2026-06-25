{{- define "clickstack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickstack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "clickstack.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "clickstack.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "clickstack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "clickstack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickstack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "clickstack.collector.selectorLabels" -}}
app.kubernetes.io/name: otel-collector
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "clickstack.secretName" -}}
{{- printf "%s-secrets" (include "clickstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickstack.ferretdb.fullname" -}}
{{- printf "%s-ferretdb" (include "clickstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickstack.hyperdx.fullname" -}}
{{- printf "%s-hyperdx" (include "clickstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickstack.collector.gateway.fullname" -}}
{{- printf "%s-otel-collector" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickstack.collector.agent.fullname" -}}
{{- printf "%s-collector-agent" (include "clickstack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "clickstack.serviceAccountName" -}}
{{- include "clickstack.fullname" . -}}
{{- end -}}

{{- define "clickstack.clickhouse.httpEndpoint" -}}
{{- if .Values.clickhouse.endpoint -}}
{{- .Values.clickhouse.endpoint -}}
{{- else -}}
{{- printf "http://%s-clickhouse.%s.svc.cluster.local:8123" .Release.Name .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{- define "clickstack.clickhouse.nativeEndpoint" -}}
{{- if .Values.clickhouse.nativeEndpoint -}}
{{- .Values.clickhouse.nativeEndpoint -}}
{{- else -}}
{{- printf "tcp://%s-clickhouse.%s.svc.cluster.local:9000?dial_timeout=10s&compress=lz4" .Release.Name .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{- define "clickstack.clickhouse.passwordSecretName" -}}
{{- if .Values.clickhouse.existingSecret -}}
{{- .Values.clickhouse.existingSecret -}}
{{- else -}}
{{- printf "%s-clickhouse-credentials" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "clickstack.ferretdb.passwordSecretName" -}}
{{- if .Values.ferretdb.auth.existingSecret -}}
{{- .Values.ferretdb.auth.existingSecret -}}
{{- else -}}
{{- include "clickstack.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "clickstack.ferretdb.passwordSecretKey" -}}
{{- if .Values.ferretdb.auth.existingSecret -}}
{{- .Values.ferretdb.auth.existingSecretKey | default "password" -}}
{{- else -}}
ferretdb-password
{{- end -}}
{{- end -}}

{{- define "clickstack.ferretdb.mongoUri" -}}
{{- printf "mongodb://%s:$(FERRETDB_PASSWORD)@%s.%s.svc.cluster.local:27017/hyperdx" (.Values.ferretdb.auth.username | default "hyperdx") (include "clickstack.ferretdb.fullname" .) .Release.Namespace -}}
{{- end -}}

{{- define "clickstack.hyperdx.appUrl" -}}
{{- $hostname := .Values.hyperdx.ingress.hostname | default (printf "observability.%s" .Values.global.domain) -}}
{{- $scheme := ternary "https" "http" (eq (.Values.global.tlsEnabled | toString) "true") -}}
{{- printf "%s://%s" $scheme $hostname -}}
{{- end -}}
