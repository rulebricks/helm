{{/*
Expand the name of the chart.
*/}}
{{- define "rulebricks-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
rulebricks-chart.image — render a fully-qualified image ref from an RB image dict.
Byte-identical to the parent's "rulebricks.image"; defined here so this subchart
stays independently packageable. Reads the parent global (Helm auto-merges
.Values.global into the subchart), so global.imageRegistry / imageDigests apply.
Usage: {{ include "rulebricks-chart.image" (dict "root" . "image" $img "name" "valkey") }}
*/}}
{{- define "rulebricks-chart.image" -}}
{{- $img := .image | default dict -}}
{{- $g := .root.Values.global | default dict -}}
{{- $registry := $img.registry | default "docker.io" -}}
{{- with $g.imageRegistry }}{{- $registry = . -}}{{- end -}}
{{- $repo := required "image.repository is required" $img.repository -}}
{{- $ref := printf "%s/%s" $registry $repo -}}
{{- $digest := $img.digest -}}
{{- if and (not $digest) .name $g.imageDigests -}}
{{- $digest = index $g.imageDigests .name -}}
{{- end -}}
{{- if $digest -}}
{{- printf "%s@%s" $ref $digest -}}
{{- else if $img.tag -}}
{{- printf "%s:%s" $ref $img.tag -}}
{{- else -}}
{{- printf "%s:%s" $ref .root.Chart.AppVersion -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks-chart.imagePullSecret" -}}
{{- $username := "rulebricks" -}}
{{- $licenseKey := "" -}}
{{- if .Values.global.licenseKey -}}
  {{- $licenseKey = .Values.global.licenseKey -}}
{{- else -}}
  {{- $licenseKey = .Values.app.licenseKey -}}
{{- end -}}
{{- $password := printf "dckr_pat_%s" $licenseKey -}}
{{- $auth := printf "%s:%s" $username $password | b64enc -}}
{{- /* The license key is a Docker Hub read PAT for the rulebricks org; it
       authenticates docker.io/rulebricks/* (all images are private on Docker
       Hub), so this single secret covers every image the chart pulls. */ -}}
{{- printf "{\"auths\": {\"index.docker.io\": {\"auth\": \"%s\"}}}" $auth | b64enc }}
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
Single Rulebricks product version used for app, HPS, and HPS worker images.
*/}}
{{- define "rulebricks-chart.globalVersion" -}}
{{- coalesce .Values.global.version .Chart.AppVersion -}}
{{- end }}

{{- define "rulebricks-chart.app.imageTag" -}}
{{- include "rulebricks-chart.globalVersion" . -}}
{{- end }}

{{- define "rulebricks-chart.hps.imageTag" -}}
{{- include "rulebricks-chart.globalVersion" . -}}
{{- end }}

{{/*
Common labels
Merges standard chart labels with global.labels if present
*/}}
{{- define "rulebricks-chart.labels" -}}
helm.sh/chart: {{ include "rulebricks-chart.chart" . }}
{{ include "rulebricks-chart.selectorLabels" . }}
{{- $productVersion := include "rulebricks-chart.app.imageTag" . }}
{{- if $productVersion }}
app.kubernetes.io/version: {{ $productVersion | quote }}
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
Create the name of the app service account to use
*/}}
{{- define "rulebricks-chart.app.serviceAccountName" -}}
{{- if and .Values.app.serviceAccount .Values.app.serviceAccount.create }}
{{- default (include "rulebricks-chart.app.fullname" .) .Values.app.serviceAccount.name }}
{{- else }}
{{- include "rulebricks-chart.serviceAccountName" . }}
{{- end }}
{{- end }}

{{/*
Create the name of the HPS service account to use
*/}}
{{- define "rulebricks-chart.hps.serviceAccountName" -}}
{{- if and .Values.hps.serviceAccount .Values.hps.serviceAccount.create }}
{{- default (include "rulebricks-chart.hps.fullname" .) .Values.hps.serviceAccount.name }}
{{- else }}
{{- include "rulebricks-chart.serviceAccountName" . }}
{{- end }}
{{- end }}

{{/*
Create the name of the HPS worker service account to use
*/}}
{{- define "rulebricks-chart.hps-worker.serviceAccountName" -}}
{{- if and .Values.hps.workers.serviceAccount .Values.hps.workers.serviceAccount.create }}
{{- default (include "rulebricks-chart.hps-worker.fullname" .) .Values.hps.workers.serviceAccount.name }}
{{- else }}
{{- include "rulebricks-chart.serviceAccountName" . }}
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
Valkey service name (redis suffix retained for compatibility)
*/}}
{{- define "rulebricks-chart.redis.fullname" -}}
{{- printf "%s-redis" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Serverless Redis-compatible HTTP service name
*/}}
{{- define "rulebricks-chart.serverless-redis-http.fullname" -}}
{{- printf "%s-serverless-redis-http" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Valkey Admin console service name
*/}}
{{- define "rulebricks-chart.valkeyAdmin.fullname" -}}
{{- printf "%s-valkey-admin" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Redis/Valkey exporter service name
*/}}
{{- define "rulebricks-chart.redisExporter.fullname" -}}
{{- printf "%s-redis-exporter" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Kafka exporter service name
*/}}
{{- define "rulebricks-chart.kafkaExporter.fullname" -}}
{{- printf "%s-kafka-exporter" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Valkey PVC name (redis suffix retained for compatibility)
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
Kafka bootstrap servers - the Strimzi cluster's bootstrap service.
Strimzi creates a service named: <release>-kafka-kafka-bootstrap
*/}}
{{- define "rulebricks-chart.kafka.bootstrapServers" -}}
{{- printf "%s-kafka-kafka-bootstrap.%s.svc.cluster.local:9092" .Release.Name .Release.Namespace }}
{{- end }}

{{/*
Kafka topic prefix
Namespaces all Kafka topic names (e.g. "com.rulebricks.solution") so they don't
collide on a shared/managed Kafka cluster. HPS applies this prefix to its own
topics; the chart applies it to systems that must match HPS (KEDA lag triggers,
the Vector consumer). An explicit empty string disables prefixing; when the key
is absent entirely we fall back to the default.
*/}}
{{- define "rulebricks-chart.kafka.topicPrefix" -}}
{{- if and .Values.app .Values.app.logging (hasKey .Values.app.logging "kafkaTopicPrefix") -}}
{{- .Values.app.logging.kafkaTopicPrefix -}}
{{- else -}}
com.rulebricks.
{{- end -}}
{{- end }}

{{/*
Whether external Kafka uses a TOKEN-based SASL mechanism (AWS MSK IAM / GCP
OAUTHBEARER). These credentials are minted per-connection from a cloud identity,
so plain Kafka clients that only speak PLAIN/SCRAM (kafka-exporter, the KEDA Kafka
scaler) can't authenticate directly - they must go through the kafka-proxy bridge
or be gated off. Returns "true" or "" (empty = false), so guard with:
  {{- if not (include "rulebricks-chart.kafka.tokenAuth" .) }}
*/}}
{{- define "rulebricks-chart.kafka.tokenAuth" -}}
{{- $sasl := (((.Values.app).logging).kafkaSasl) | default dict -}}
{{- $m := lower ($sasl.mechanism | default "") -}}
{{- if or (eq $m "aws-iam") (eq $m "oauthbearer") (eq $m "gcp-oauthbearer") (eq $m "aws_msk_iam") -}}
true
{{- end -}}
{{- end }}

{{/*
KEDA `sasl` mode for EXTERNAL Kafka secured with a STATIC credential
(PLAIN/SCRAM - e.g. Azure Event Hubs' $ConnectionString or Confluent API keys).
Empty for in-cluster Kafka (plaintext, no auth needed) and for token-auth
mechanisms (those skip the lag trigger entirely - see kafka.tokenAuth).
Without SASL config the lag trigger renders but can never authenticate, so
lag-based scaling silently fails and only the CPU trigger drives scaling.
*/}}
{{- define "rulebricks-chart.kafka.kedaSaslMode" -}}
{{- $logging := ((.Values.app).logging) | default dict -}}
{{- if $logging.kafkaBrokers -}}
{{- $m := lower ((($logging.kafkaSasl) | default dict).mechanism | default "") -}}
{{- if eq $m "plain" -}}plaintext{{- else if eq $m "scram-sha-256" -}}scram_sha256{{- else if eq $m "scram-sha-512" -}}scram_sha512{{- end -}}
{{- end -}}
{{- end }}

{{/*
Name of the TriggerAuthentication carrying the static Kafka SASL credentials
for the KEDA lag triggers (created in kafka-trigger-auth.yaml).
*/}}
{{- define "rulebricks-chart.kafka.triggerAuthName" -}}
{{- printf "%s-kafka-lag-auth" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
KEDA `tls` mode for external static-SASL Kafka lag triggers ("enable" when
app.logging.kafkaSsl is "true", else "disable").
*/}}
{{- define "rulebricks-chart.kafka.kedaTlsMode" -}}
{{- $ssl := toString ((((.Values.app).logging) | default dict).kafkaSsl | default "") -}}
{{- ternary "enable" "disable" (eq $ssl "true") -}}
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
Tracing Helpers (OpenTelemetry)
===========================================
*/}}

{{/*
OpenTelemetry env vars for a workload, emitted only when global.tracing.enabled.
The OTLP endpoint is the in-cluster collector deployed by the parent chart; its
name is derived from the release name (see templates/otel-collector-*.yaml).
The application tracing bootstraps (HPS src/tracing.js, app instrumentation.js)
are no-ops unless OTEL_EXPORTER_OTLP_ENDPOINT is set, so this is the single
switch that turns tracing on for a pod.
Usage: {{ include "rulebricks-chart.tracing.env" (dict "root" . "serviceName" "rulebricks-hps") | nindent 12 }}
*/}}
{{- define "rulebricks-chart.tracing.env" -}}
{{- $root := .root -}}
{{- $svc := .serviceName -}}
{{- $tracing := ($root.Values.global | default dict).tracing | default dict -}}
{{- $clickstack := ($root.Values.global | default dict).clickstack | default dict -}}
{{- if or $tracing.enabled ($clickstack.enabled | default false) -}}
- name: OTEL_TRACING_ENABLED
  value: "1"
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://{{ $root.Release.Name }}-otel-collector.{{ $root.Release.Namespace }}.svc.cluster.local:4318"
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "http/json"
- name: OTEL_SERVICE_NAME
  value: {{ $svc | quote }}
- name: OTEL_TRACES_SAMPLER
  value: "parentbased_traceidratio"
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ $tracing.samplingRatio | default 1.0 | quote }}
{{- with ($root.Values.global | default dict).version }}
- name: RULEBRICKS_VERSION
  value: {{ . | quote }}
{{- end }}
{{- end -}}
{{- end -}}

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
Valkey/Redis-Compatible Connection Helpers
===========================================
*/}}

{{/*
Redis-compatible HTTP API URL
Returns the URL for the Redis-compatible HTTP API (Upstash-compatible)
Handles both internal serverless-redis-http and external Upstash
*/}}
{{- define "rulebricks-chart.redis.httpUrl" -}}
{{- if .Values.redis.enabled }}
{{- /* Internal Valkey - use serverless-redis-http service */ -}}
http://{{ include "rulebricks-chart.serverless-redis-http.fullname" . }}
{{- else if .Values.redis.external.httpApi.enabled }}
{{- /* External HTTP API (e.g., Upstash) */ -}}
{{- .Values.redis.external.httpApi.url }}
{{- else }}
{{- /* External Valkey/Redis-compatible endpoint but no HTTP API - use serverless-redis-http bridge */ -}}
http://{{ include "rulebricks-chart.serverless-redis-http.fullname" . }}
{{- end }}
{{- end }}

{{/*
Redis-compatible connection string
Returns a redis:// or rediss:// connection URL for internal Valkey or an external compatible endpoint.
This form omits credentials; use rulebricks-chart.redis.connectionStringAuth when
the external endpoint requires a password so the secret is injected at runtime instead.
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
Valkey/Redis-compatible external auth detection
Returns "true" when using an external endpoint (redis.enabled: false) that is protected by
a password, supplied either inline (external.password) or via an existing secret
(external.existingSecret). Empty string otherwise.
*/}}
{{- define "rulebricks-chart.redis.hasAuth" -}}
{{- if and (not .Values.redis.enabled) .Values.redis.external -}}
{{- if or .Values.redis.external.password .Values.redis.external.existingSecret -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Redis-compatible connection string with runtime password substitution
Emits a literal $(REDIS_PASSWORD) reference that Kubernetes expands from the
REDIS_PASSWORD env var at container start, so the password never lands in a ConfigMap.
The consuming container must define REDIS_PASSWORD (from a Secret) earlier in its env list.
Note: passwords are not URL-encoded; use URL-safe credentials or an existing secret.
*/}}
{{- define "rulebricks-chart.redis.connectionStringAuth" -}}
{{- $scheme := ternary "rediss" "redis" (and .Values.redis.external .Values.redis.external.tls .Values.redis.external.tls.enabled) -}}
{{- $host := .Values.redis.external.host | default "" -}}
{{- $port := .Values.redis.external.port | default 6379 -}}
{{- printf "%s://:$(REDIS_PASSWORD)@%s:%v" $scheme $host $port -}}
{{- end }}

{{/*
Valkey/Redis-compatible password Secret reference
Returns a secretKeyRef (name + key) block body for the REDIS_PASSWORD env var.
Uses the user-provided existing secret when set, otherwise the chart-managed app secret.
*/}}
{{- define "rulebricks-chart.redis.passwordSecretRef" -}}
{{- if .Values.redis.external.existingSecret }}
name: {{ .Values.redis.external.existingSecret }}
key: {{ .Values.redis.external.existingSecretKey | default "redis-password" }}
{{- else }}
name: {{ include "rulebricks-chart.app.secretName" . | trim }}
key: REDIS_PASSWORD
{{- end }}
{{- end }}

{{/*
Redis-compatible HTTP API Token
Returns the token for authenticating to the Redis-compatible HTTP API
*/}}
{{- define "rulebricks-chart.redis.httpToken" -}}
{{- if .Values.redis.enabled }}
{{- /* Internal Valkey - default token */ -}}
local_redis
{{- else if .Values.redis.external.httpApi.enabled }}
{{- /* External HTTP API token */ -}}
{{- .Values.redis.external.httpApi.token }}
{{- else }}
{{- /* External Valkey/Redis-compatible endpoint but no HTTP API - use serverless-redis-http bridge */ -}}
local_redis
{{- end }}
{{- end }}
