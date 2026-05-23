{{/*
Expand the name of the chart.
*/}}
{{- define "supabase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "supabase.fullname" -}}
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
{{- define "supabase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "supabase.labels" -}}
helm.sh/chart: {{ include "supabase.chart" . }}
{{ include "supabase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "supabase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "supabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "supabase.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "supabase.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve the database host used by Supabase services.
*/}}
{{- define "supabase.db.host" -}}
{{- if .Values.db.enabled -}}
{{- include "supabase.db.fullname" . -}}
{{- else if and .Values.externalDatabase .Values.externalDatabase.enabled .Values.externalDatabase.host -}}
{{- .Values.externalDatabase.host -}}
{{- else -}}
{{- .Values.auth.environment.DB_HOST -}}
{{- end -}}
{{- end }}

{{/*
Resolve the database port used by Supabase services.
*/}}
{{- define "supabase.db.port" -}}
{{- if and .Values.externalDatabase .Values.externalDatabase.enabled .Values.externalDatabase.port -}}
{{- .Values.externalDatabase.port -}}
{{- else -}}
{{- .Values.auth.environment.DB_PORT | default 5432 -}}
{{- end -}}
{{- end }}

{{/*
Resolve the database credentials secret name.
*/}}
{{- define "supabase.db.secretName" -}}
{{- if and .Values.externalDatabase .Values.externalDatabase.enabled .Values.externalDatabase.secretRef -}}
{{- .Values.externalDatabase.secretRef -}}
{{- else if .Values.secret.db.secretRef -}}
{{- .Values.secret.db.secretRef -}}
{{- else -}}
{{- include "supabase.secret.db" . -}}
{{- end -}}
{{- end }}

{{/*
Resolve a database secret key.
Usage: {{ include "supabase.db.secretKey" (dict "root" . "field" "password" "default" "password") }}
*/}}
{{- define "supabase.db.secretKey" -}}
{{- $root := .root -}}
{{- $field := .field -}}
{{- $default := .default -}}
{{- if and $root.Values.externalDatabase $root.Values.externalDatabase.enabled $root.Values.externalDatabase.secretRef -}}
  {{- index $root.Values.externalDatabase.secretRefKey $field | default $default -}}
{{- else if $root.Values.secret.db.secretRef -}}
  {{- index $root.Values.secret.db.secretRefKey $field | default $default -}}
{{- else -}}
  {{- $default -}}
{{- end -}}
{{- end }}

{{/*
Resolve the secret key used for URL-encoded database passwords.
Existing external secrets keep using the normal password key for backward compatibility.
*/}}
{{- define "supabase.db.encodedPasswordKey" -}}
{{- $root := . -}}
{{- if and $root.Values.externalDatabase $root.Values.externalDatabase.enabled $root.Values.externalDatabase.secretRef -}}
  {{- $root.Values.externalDatabase.secretRefKey.password | default "password" -}}
{{- else if $root.Values.secret.db.secretRef -}}
  {{- $root.Values.secret.db.secretRefKey.password | default "password" -}}
{{- else -}}
password_encoded
{{- end -}}
{{- end }}
