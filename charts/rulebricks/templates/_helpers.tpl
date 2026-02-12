{{/*
Expand the name of the chart.
*/}}
{{- define "rulebricks-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "rulebricks-chart.imagePullSecret" -}}
{{- $registry := "index.docker.io" -}}
{{- $username := "rulebricks" -}}
{{- $licenseKey := "" -}}
{{- if .Values.global.licenseKey -}}
  {{- $licenseKey = .Values.global.licenseKey -}}
{{- else -}}
  {{- $licenseKey = .Values.app.licenseKey -}}
{{- end -}}
{{- $password := printf "dckr_pat_%s" $licenseKey -}}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" $registry (printf "%s:%s" $username $password | b64enc) | b64enc }}
{{- end }}

{{/*
Registry secret name
*/}}
{{- define "rulebricks-chart.registrySecretName" -}}
{{- printf "%s-regcred" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "rulebricks-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rulebricks-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
Merges standard chart labels with global.labels if present
*/}}
{{- define "rulebricks-chart.labels" -}}
helm.sh/chart: {{ include "rulebricks-chart.chart" . }}
{{ include "rulebricks-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- /* Merge global labels */ -}}
{{- if and .Values.global .Values.global.labels }}
{{- toYaml .Values.global.labels | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Resource annotations with global merge
Returns global.annotations merged with any provided component annotations
Usage: {{ include "rulebricks-chart.annotations" . }}
*/}}
{{- define "rulebricks-chart.annotations" -}}
{{- $annotations := dict }}
{{- if and .Values.global .Values.global.annotations }}
  {{- $annotations = merge $annotations .Values.global.annotations }}
{{- end }}
{{- with $annotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Pod labels with global merge
Returns selector labels plus global.podLabels
Usage: {{ include "rulebricks-chart.podLabels" . }}
*/}}
{{- define "rulebricks-chart.podLabels" -}}
{{- include "rulebricks-chart.selectorLabels" . }}
{{- if and .Values.global .Values.global.podLabels }}
{{- toYaml .Values.global.podLabels | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Pod annotations with global merge
Returns global.podAnnotations
Usage: {{ include "rulebricks-chart.podAnnotations" . }}
*/}}
{{- define "rulebricks-chart.podAnnotations" -}}
{{- if and .Values.global .Values.global.podAnnotations }}
{{- toYaml .Values.global.podAnnotations }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rulebricks-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rulebricks-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "rulebricks-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "rulebricks-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Check if TLS is enabled
Prioritize global.tlsEnabled if present, otherwise use app.tlsEnabled
*/}}
{{- define "rulebricks-chart.tlsEnabled" -}}
{{- if .Values.global -}}
  {{- if hasKey .Values.global "tlsEnabled" -}}
    {{- .Values.global.tlsEnabled -}}
  {{- else -}}
    {{- .Values.app.tlsEnabled -}}
  {{- end -}}
{{- else -}}
  {{- .Values.app.tlsEnabled -}}
{{- end -}}
{{- end -}}

{{/*
===========================================
Service Name Helpers - CRITICAL FOR CONSISTENCY
All service references MUST use these helpers
===========================================
*/}}

{{/*
Redis service name
*/}}
{{- define "rulebricks-chart.redis.fullname" -}}
{{- printf "%s-redis" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Serverless Redis HTTP service name
*/}}
{{- define "rulebricks-chart.serverless-redis-http.fullname" -}}
{{- printf "%s-serverless-redis-http" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Redis PVC name
*/}}
{{- define "rulebricks-chart.redis.pvc" -}}
{{- printf "%s-redis-data" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
HPS service name
*/}}
{{- define "rulebricks-chart.hps.fullname" -}}
{{- printf "%s-hps" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
HPS headless service name (for StatefulSet)
*/}}
{{- define "rulebricks-chart.hps.headless" -}}
{{- printf "%s-hps-headless" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
HPS Worker service name
*/}}
{{- define "rulebricks-chart.hps-worker.fullname" -}}
{{- printf "%s-hps-worker" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
App deployment name
*/}}
{{- define "rulebricks-chart.app.fullname" -}}
{{- printf "%s-app" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
App ConfigMap name
*/}}
{{- define "rulebricks-chart.app.configmap" -}}
{{- printf "%s-app-config" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
App Secret name (internal chart secret)
*/}}
{{- define "rulebricks-chart.app.secret" -}}
{{- printf "%s-app-secrets" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
App Secret name resolver
Returns the external secretRef if provided, otherwise returns the internal secret name.
This allows enterprise users to provide their own pre-existing secret.
*/}}
{{- define "rulebricks-chart.app.secretName" -}}
{{- if and .Values.global .Values.global.secrets .Values.global.secrets.secretRef }}
  {{- .Values.global.secrets.secretRef }}
{{- else }}
  {{- include "rulebricks-chart.app.secret" . }}
{{- end }}
{{- end }}

{{/*
Get secret key name for a given field
When using external secret, uses the configured key mapping; otherwise uses default key names.
Usage: {{ include "rulebricks-chart.app.secretKey" (dict "root" . "field" "licenseKey" "default" "LICENSE_KEY") }}
*/}}
{{- define "rulebricks-chart.app.secretKey" -}}
{{- $root := .root }}
{{- $field := .field }}
{{- $default := .default }}
{{- if and $root.Values.global $root.Values.global.secrets $root.Values.global.secrets.secretRef $root.Values.global.secrets.secretRefKeys }}
  {{- $key := index $root.Values.global.secrets.secretRefKeys $field }}
  {{- if $key }}
    {{- $key }}
  {{- else }}
    {{- $default }}
  {{- end }}
{{- else }}
  {{- $default }}
{{- end }}
{{- end }}

{{/*
===========================================
External Service References
These reference services from sibling charts in the umbrella
===========================================
*/}}

{{/*
Kafka bootstrap servers - references the kafka subchart service
The Bitnami Kafka chart creates a service named: <release>-kafka
*/}}
{{- define "rulebricks-chart.kafka.bootstrapServers" -}}
{{- printf "%s-kafka.%s.svc.cluster.local:9092" .Release.Name .Release.Namespace }}
{{- end }}

{{/*
Supabase Kong URL - references the supabase subchart's Kong service
The Supabase chart creates Kong service named: <release>-supabase-kong
*/}}
{{- define "rulebricks-chart.supabase.kongUrl" -}}
{{- printf "http://%s-supabase-kong.%s.svc.cluster.local:8000" .Release.Name .Release.Namespace }}
{{- end }}

{{/*
Supabase DB service name - for migration job
*/}}
{{- define "rulebricks-chart.supabase.dbFullname" -}}
{{- printf "%s-supabase-db" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
TLS Secret name - used by cert-manager Certificate and Ingress
*/}}
{{- define "rulebricks-chart.tls.secretName" -}}
{{- printf "%s-tls-secret" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
===========================================
Scheduling Helpers
Consolidated functions for nodeSelector, tolerations, affinity
===========================================
*/}}

{{/*
Merge scheduling configuration (component-level overrides global)
Usage: {{ include "rulebricks-chart.scheduling.nodeSelector" (dict "Values" .Values "component" .Values.app) }}
Returns: nodeSelector block or empty
*/}}
{{- define "rulebricks-chart.scheduling.nodeSelector" -}}
{{- $nodeSelector := .component.nodeSelector | default dict }}
{{- if and (not $nodeSelector) .Values.global .Values.global.scheduling .Values.global.scheduling.nodeSelector }}
  {{- $nodeSelector = .Values.global.scheduling.nodeSelector }}
{{- end }}
{{- with $nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Merge tolerations (component-level overrides global)
Usage: {{ include "rulebricks-chart.scheduling.tolerations" (dict "Values" .Values "component" .Values.app) }}
*/}}
{{- define "rulebricks-chart.scheduling.tolerations" -}}
{{- $tolerations := .component.tolerations | default list }}
{{- if and (not $tolerations) .Values.global .Values.global.scheduling .Values.global.scheduling.tolerations }}
  {{- $tolerations = .Values.global.scheduling.tolerations }}
{{- end }}
{{- with $tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Merge affinity (component-level overrides global)
Usage: {{ include "rulebricks-chart.scheduling.affinity" (dict "Values" .Values "component" .Values.app) }}
*/}}
{{- define "rulebricks-chart.scheduling.affinity" -}}
{{- $affinity := .component.affinity | default dict }}
{{- if and (not $affinity) .Values.global .Values.global.scheduling .Values.global.scheduling.affinity }}
  {{- $affinity = .Values.global.scheduling.affinity }}
{{- end }}
{{- with $affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Complete scheduling block (all three: nodeSelector, tolerations, affinity)
Usage: {{ include "rulebricks-chart.scheduling" (dict "Values" .Values "component" .Values.app) | nindent 6 }}
*/}}
{{- define "rulebricks-chart.scheduling" -}}
{{- include "rulebricks-chart.scheduling.nodeSelector" . }}
{{- include "rulebricks-chart.scheduling.tolerations" . }}
{{- include "rulebricks-chart.scheduling.affinity" . }}
{{- end }}

{{/*
===========================================
Redis Connection Helpers
===========================================
*/}}

{{/*
Redis HTTP API URL
Returns the URL for the Redis HTTP API (Upstash-compatible)
Handles both internal serverless-redis-http and external Upstash
*/}}
{{- define "rulebricks-chart.redis.httpUrl" -}}
{{- if .Values.redis.enabled }}
{{- /* Internal Redis - use serverless-redis-http service */ -}}
http://{{ include "rulebricks-chart.serverless-redis-http.fullname" . }}
{{- else if .Values.redis.external.httpApi.enabled }}
{{- /* External HTTP API (e.g., Upstash) */ -}}
{{- .Values.redis.external.httpApi.url }}
{{- else }}
{{- /* External Redis but no HTTP API - use serverless-redis-http bridge */ -}}
http://{{ include "rulebricks-chart.serverless-redis-http.fullname" . }}
{{- end }}
{{- end }}

{{/*
Redis connection string
Returns a redis:// or rediss:// connection URL for internal or external Redis
Kept for future external Redis wiring.
*/}}
{{- define "rulebricks-chart.redis.connectionString" -}}
{{- if .Values.redis.enabled }}
redis://{{ include "rulebricks-chart.redis.fullname" . }}:6379
{{- else }}
{{- $scheme := ternary "rediss" "redis" (and .Values.redis.external .Values.redis.external.tls .Values.redis.external.tls.enabled) -}}
{{- $host := .Values.redis.external.host | default "" -}}
{{- $port := .Values.redis.external.port | default 6379 -}}
{{- printf "%s://%s:%v" $scheme $host $port -}}
{{- end }}
{{- end }}

{{/*
Redis HTTP API Token
Returns the token for authenticating to the Redis HTTP API
*/}}
{{- define "rulebricks-chart.redis.httpToken" -}}
{{- if .Values.redis.enabled }}
{{- /* Internal Redis - default token */ -}}
local_redis
{{- else if .Values.redis.external.httpApi.enabled }}
{{- /* External HTTP API token */ -}}
{{- .Values.redis.external.httpApi.token }}
{{- else }}
{{- /* External Redis but no HTTP API - use serverless-redis-http bridge */ -}}
local_redis
{{- end }}
{{- end }}
