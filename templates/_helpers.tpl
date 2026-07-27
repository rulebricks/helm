{{/*
Shared object storage helpers.
These helpers keep bucket auth and path naming consistent across Vector,
ClickHouse, and future storage-backed jobs.
*/}}
{{- define "rulebricks.storage.enabled" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{- $decisionLogs := $storage.decisionLogs | default dict -}}
{{- if or $storage.bucket $decisionLogs.bucket -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "rulebricks.storage.provider" -}}
{{- .Values.global.storage.provider | default "s3" -}}
{{- end -}}

{{- define "rulebricks.storage.bucket" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $storage := $root.Values.global.storage | default dict -}}
{{- $purpose := index $storage $key | default dict -}}
{{- $decisionLogs := $storage.decisionLogs | default dict -}}
{{- if $purpose.bucket -}}
{{- $purpose.bucket -}}
{{- else if and (ne $key "decisionLogs") $decisionLogs.bucket -}}
{{- $decisionLogs.bucket -}}
{{- else -}}
{{- $storage.bucket | default "" -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks.storage.region" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $storage := $root.Values.global.storage | default dict -}}
{{- $purpose := index $storage $key | default dict -}}
{{- $decisionLogs := $storage.decisionLogs | default dict -}}
{{- if $purpose.region -}}
{{- $purpose.region -}}
{{- else if and (ne $key "decisionLogs") $decisionLogs.region -}}
{{- $decisionLogs.region -}}
{{- else -}}
{{- $storage.region | default "" -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks.storage.azureContainer" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $storage := $root.Values.global.storage | default dict -}}
{{- $purpose := index $storage $key | default dict -}}
{{- $decisionLogs := $storage.decisionLogs | default dict -}}
{{- $azure := $storage.azure | default dict -}}
{{- if $purpose.azureContainer -}}
{{- $purpose.azureContainer -}}
{{- else if and (ne $key "decisionLogs") $decisionLogs.azureContainer -}}
{{- $decisionLogs.azureContainer -}}
{{- else -}}
{{- $azure.container | default "" -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks.storage.path" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $storage := $root.Values.global.storage | default dict -}}
{{- $purpose := index $storage $key | default dict -}}
{{- $paths := $storage.paths | default dict -}}
{{- $path := $purpose.path | default (index $paths $key) | default $key -}}
{{- $path | trimPrefix "/" | trimSuffix "/" -}}
{{- end -}}

{{- define "rulebricks.storage.serviceAccountAnnotations" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{/* AWS uses EKS Pod Identity (a namespace-scoped association created by the CLI,
     no annotation). Only GCP/Azure workload identity bind via a ServiceAccount
     annotation, so S3 intentionally emits nothing here. */}}
{{- if and (eq ($storage.provider | default "") "gcs") $storage.gcp $storage.gcp.serviceAccountEmail }}
iam.gke.io/gcp-service-account: {{ $storage.gcp.serviceAccountEmail | quote }}
{{- else if and (eq ($storage.provider | default "") "azure-blob") $storage.azure $storage.azure.clientId }}
azure.workload.identity/client-id: {{ $storage.azure.clientId | quote }}
{{- end }}
{{- end -}}

{{/*
Unified Kafka workload-identity annotations.
Given the kafkaBridge provider + identity inputs, emits the correct service-account
annotation for the cloud's managed-Kafka auth: AWS MSK IAM via IRSA, GCP Managed
Kafka via GKE Workload Identity. Azure Event Hubs uses SASL PLAIN and needs none.
Apply to the HPS service account (Kafka producer/consumer) and the Vector service
account (when the bridge sidecar is enabled) so a single identity input drives both.
*/}}
{{/*
Kafka topic prefix (parent-chart view of rulebricks.app.logging.kafkaTopicPrefix).
Used by parent-rendered resources (Vector) so they consume the same prefixed
topics HPS produces. Empty string disables; absent key falls back to default.
*/}}
{{- define "rulebricks.kafka.topicPrefix" -}}
{{- $logging := (.Values.rulebricks).app | default dict -}}
{{- $logging = $logging.logging | default dict -}}
{{- if hasKey $logging "kafkaTopicPrefix" -}}
{{- $logging.kafkaTopicPrefix -}}
{{- else -}}
com.rulebricks.
{{- end -}}
{{- end -}}

{{- define "rulebricks.kafka.identityAnnotations" -}}
{{- $bridge := .Values.kafkaBridge | default dict -}}
{{/* AWS MSK IAM uses EKS Pod Identity (association, no annotation). Only GCP
     Managed Kafka binds its workload identity via a ServiceAccount annotation. */}}
{{- if and (eq ($bridge.provider | default "") "gcp") $bridge.gcpServiceAccountEmail }}
iam.gke.io/gcp-service-account: {{ $bridge.gcpServiceAccountEmail | quote }}
{{- end }}
{{- end -}}

{{- define "rulebricks.storage.podLabels" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{- if and (eq ($storage.provider | default "") "azure-blob") $storage.azure (eq ($storage.azure.authMode | default "workload-identity") "workload-identity") }}
azure.workload.identity/use: "true"
{{- end }}
{{- end -}}

{{- define "rulebricks.storage.s3Url" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $region := include "rulebricks.storage.region" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- /* {gz,zst} alternation: Vector writes zstd (.ndjson.zst) since the zstd
     switch; pre-existing gzip archives keep matching. ClickHouse auto-detects
     compression per file from the extension. */ -}}
{{- printf "https://%s.s3.%s.amazonaws.com/%s/year=*/month=*/day=*/hour=*/*.{gz,zst}" $bucket $region $path -}}
{{- end -}}

{{- define "rulebricks.storage.azureUrl" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $container := include "rulebricks.storage.azureContainer" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://%s.blob.core.windows.net/%s/%s/year=*/month=*/day=*/hour=*/*.{gz,zst}" $bucket $container $path -}}
{{- end -}}

{{- define "rulebricks.storage.gcsUrl" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://storage.googleapis.com/%s/%s/year=*/month=*/day=*/hour=*/*.{gz,zst}" $bucket $path -}}
{{- end -}}

{{- /* Compacted decision-log tier: the compaction CronJob rewrites closed hours
     of raw NDJSON into one sorted Parquet object per hour, placed BESIDE the
     raw files it replaces (same hour= prefix, *.parquet extension), so the raw
     and parquet globs are disjoint by extension under identical IAM. */ -}}
{{- define "rulebricks.storage.s3ParquetUrl" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $region := include "rulebricks.storage.region" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://%s.s3.%s.amazonaws.com/%s/year=*/month=*/day=*/hour=*/*.parquet" $bucket $region $path -}}
{{- end -}}

{{- define "rulebricks.storage.gcsParquetUrl" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://storage.googleapis.com/%s/%s/year=*/month=*/day=*/hour=*/*.parquet" $bucket $path -}}
{{- end -}}

{{- /* Concrete (non-glob) base URLs for the compaction CronJob, which appends
     /year=Y/month=M/day=D/hour=H/... itself when reading a single hour and
     writing its compacted.parquet. */ -}}
{{- define "rulebricks.storage.s3BaseUrl" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $region := include "rulebricks.storage.region" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://%s.s3.%s.amazonaws.com/%s" $bucket $region $path -}}
{{- end -}}

{{- define "rulebricks.storage.gcsBaseUrl" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://storage.googleapis.com/%s/%s" $bucket $path -}}
{{- end -}}

{{- /* rclone env for the decision-log compaction CronJob's discover/cleanup
     containers. Mirrors db-backup-cronjob.yaml's tri-cloud auth blocks (keep
     the two in sync) but targets the decisionLogs prefix. RB_TARGET is the
     rclone remote path: container/path on azure-blob, bucket/path elsewhere. */ -}}
{{- define "rulebricks.compaction.rcloneEnv" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{- $provider := $storage.provider | default "s3" -}}
{{- $azure := $storage.azure | default dict -}}
{{- $authMode := $azure.authMode | default "workload-identity" -}}
{{- $bucket := include "rulebricks.storage.bucket" (list . "decisionLogs") -}}
{{- $region := include "rulebricks.storage.region" (list . "decisionLogs") -}}
{{- $container := include "rulebricks.storage.azureContainer" (list . "decisionLogs") -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
- name: RB_TARGET
  value: {{ ternary (printf "%s/%s" $container $path) (printf "%s/%s" $bucket $path) (eq $provider "azure-blob") | quote }}
{{- if eq $provider "azure-blob" }}
- name: RCLONE_CONFIG_DEST_TYPE
  value: "azureblob"
- name: RCLONE_CONFIG_DEST_ACCOUNT
  value: {{ $bucket | quote }}
{{- if eq $authMode "connection-string" }}
- name: RCLONE_CONFIG_DEST_CONNECTION_STRING
  valueFrom:
    secretKeyRef:
      name: {{ required "global.storage.azure.connectionStringSecretRef.name is required for connection-string auth" $azure.connectionStringSecretRef.name }}
      key: {{ required "global.storage.azure.connectionStringSecretRef.key is required for connection-string auth" $azure.connectionStringSecretRef.key }}
{{- else }}
- name: RCLONE_CONFIG_DEST_ENV_AUTH
  value: "true"
{{- end }}
{{- else if eq $provider "gcs" }}
- name: RCLONE_CONFIG_DEST_TYPE
  value: "google cloud storage"
- name: RCLONE_CONFIG_DEST_ENV_AUTH
  value: "true"
- name: RCLONE_CONFIG_DEST_BUCKET_POLICY_ONLY
  value: "true"
{{- else }}
- name: RCLONE_CONFIG_DEST_TYPE
  value: "s3"
- name: RCLONE_CONFIG_DEST_PROVIDER
  value: "AWS"
- name: RCLONE_CONFIG_DEST_ENV_AUTH
  value: "true"
- name: RCLONE_CONFIG_DEST_REGION
  value: {{ $region | quote }}
{{- $s3Secret := dig "s3" "existingSecret" "name" "" $storage }}
{{- if $s3Secret }}
# Static AWS credentials escape hatch; rclone env_auth picks
# these up. Prefer IRSA/Pod Identity (leave the secret unset).
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ $s3Secret }}
      key: AWS_ACCESS_KEY_ID
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $s3Secret }}
      key: AWS_SECRET_ACCESS_KEY
{{- end }}
{{- end }}
{{- end -}}

{{- define "rulebricks.storage.cloudDestination" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $storage := $root.Values.global.storage -}}
{{- $bucket := include "rulebricks.storage.bucket" (list $root $key) -}}
{{- $container := include "rulebricks.storage.azureContainer" (list $root $key) -}}
{{- $path := include "rulebricks.storage.path" (list $root $key) -}}
{{- $provider := $storage.provider | default "s3" -}}
{{- if eq $provider "s3" -}}
{{- printf "s3://%s/%s" $bucket $path -}}
{{- else if eq $provider "azure-blob" -}}
{{- printf "https://%s.blob.core.windows.net/%s/%s" $bucket $container $path -}}
{{- else if eq $provider "gcs" -}}
{{- printf "gs://%s/%s" $bucket $path -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks.storage.cloudProviderArgs" -}}
{{- $provider := include "rulebricks.storage.provider" . -}}
{{- if eq $provider "s3" -}}
--cloud-provider aws-s3
{{- else if eq $provider "azure-blob" -}}
--cloud-provider azure-blob-storage
{{- else if eq $provider "gcs" -}}
--cloud-provider google-cloud-storage
{{- end -}}
{{- end -}}

{{- define "rulebricks.backup.fullname" -}}
{{- printf "%s-db-backup" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rulebricks.backup.serviceAccountName" -}}
{{- printf "%s-backup" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rulebricks.productVersion" -}}
{{- $global := .Values.global | default dict -}}
{{- coalesce $global.version .Chart.AppVersion -}}
{{- end -}}

{{- define "rulebricks.supabase.fullname" -}}
{{- $values := .Values.supabase | default dict -}}
{{- if $values.fullnameOverride -}}
{{- $values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "supabase" $values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks.supabase.db.fullname" -}}
{{- $supabase := .Values.supabase | default dict -}}
{{- $db := $supabase.db | default dict -}}
{{- if $db.fullnameOverride -}}
{{- $db.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "supabase-db" $db.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rulebricks.supabase.db.secretName" -}}
{{- $supabase := .Values.supabase | default dict -}}
{{- $secret := $supabase.secret | default dict -}}
{{- $dbSecret := $secret.db | default dict -}}
{{- if $dbSecret.secretRef -}}
{{- $dbSecret.secretRef -}}
{{- else -}}
{{- printf "%s-db" (include "rulebricks.supabase.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
===========================================
Image reference helper
===========================================
rulebricks.image — render a fully-qualified, optionally digest-pinned image ref
from a structured image dict. Every container image in the chart (incl. init,
hook/Job, and test containers) renders through this helper so a single
global.imageRegistry repoints them all.

Usage: {{ include "rulebricks.image" (dict "root" . "image" $img "name" "clickhouse-server") }}
  root:  top-level context (.) — used to read .Values.global
  image: per-image dict { registry, repository, tag, digest }
  name:  logical image name; key into global.imageDigests (optional but recommended)

Semantics: global.imageRegistry (when set) replaces the registry HOST and keeps
the repository path (Bitnami-style). Version selector precedence:
explicit image.digest -> global.imageDigests[name] -> image.tag -> chart appVersion.
Subcharts define byte-identical copies under their own names (rulebricks-chart.image,
clickstack.image, supabase.image) so they stay independently packageable; all read
the same parent global (Helm auto-merges .Values.global into every subchart).
*/}}
{{- define "rulebricks.image" -}}
{{- $img := .image | default dict -}}
{{- $g := .root.Values.global | default dict -}}
{{- $registry := $img.registry | default "docker.io" -}}
{{- with $g.imageRegistry }}{{- $registry = . -}}{{- end -}}
{{- $repo := required "rulebricks.image: image.repository is required" $img.repository -}}
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
