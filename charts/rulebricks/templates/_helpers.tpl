{{/*
Expand the name of the chart.
*/}}
{{- define "rulebricks-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "rulebricks-chart.imagePullSecret" -}}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.imageCredentials.registry (printf "%s:%s" .Values.imageCredentials.username .Values.imageCredentials.password | b64enc) | b64enc }}
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
*/}}
{{- define "rulebricks-chart.labels" -}}
helm.sh/chart: {{ include "rulebricks-chart.chart" . }}
{{ include "rulebricks-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
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
App Secret name
*/}}
{{- define "rulebricks-chart.app.secret" -}}
{{- printf "%s-app-secrets" .Release.Name | trunc 63 | trimSuffix "-" }}
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
