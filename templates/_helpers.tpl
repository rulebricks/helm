{{/*
Shared object storage helpers.
These helpers keep bucket auth and path naming consistent across Vector,
ClickHouse, and future storage-backed jobs.
*/}}
{{- define "rulebricks.storage.enabled" -}}
{{- if and .Values.global .Values.global.storage .Values.global.storage.enabled -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "rulebricks.storage.provider" -}}
{{- .Values.global.storage.provider | default "s3" -}}
{{- end -}}

{{- define "rulebricks.storage.path" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $paths := $root.Values.global.storage.paths | default dict -}}
{{- index $paths $key | default $key | trimPrefix "/" | trimSuffix "/" -}}
{{- end -}}

{{- define "rulebricks.storage.serviceAccountAnnotations" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{- if and (eq ($storage.provider | default "") "s3") $storage.s3 $storage.s3.iamRoleArn }}
eks.amazonaws.com/role-arn: {{ $storage.s3.iamRoleArn | quote }}
{{- else if and (eq ($storage.provider | default "") "gcs") $storage.gcp $storage.gcp.serviceAccountEmail }}
iam.gke.io/gcp-service-account: {{ $storage.gcp.serviceAccountEmail | quote }}
{{- else if and (eq ($storage.provider | default "") "azure-blob") $storage.azure $storage.azure.clientId }}
azure.workload.identity/client-id: {{ $storage.azure.clientId | quote }}
{{- end }}
{{- end -}}

{{- define "rulebricks.storage.podLabels" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{- if and (eq ($storage.provider | default "") "azure-blob") $storage.azure (eq ($storage.azure.authMode | default "workload-identity") "workload-identity") }}
azure.workload.identity/use: "true"
{{- end }}
{{- end -}}

{{- define "rulebricks.storage.s3Url" -}}
{{- $storage := .Values.global.storage -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://%s.s3.%s.amazonaws.com/%s/year=*/month=*/day=*/hour=*/*.parquet" $storage.bucket $storage.region $path -}}
{{- end -}}

{{- define "rulebricks.storage.azureUrl" -}}
{{- $storage := .Values.global.storage -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://%s.blob.core.windows.net/%s/%s/year=*/month=*/day=*/hour=*/*.parquet" $storage.bucket $storage.azure.container $path -}}
{{- end -}}

{{- define "rulebricks.storage.gcsUrl" -}}
{{- $storage := .Values.global.storage -}}
{{- $path := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- printf "https://storage.googleapis.com/%s/%s/year=*/month=*/day=*/hour=*/*.parquet" $storage.bucket $path -}}
{{- end -}}

{{- define "rulebricks.storage.cloudDestination" -}}
{{- $root := index . 0 -}}
{{- $key := index . 1 -}}
{{- $storage := $root.Values.global.storage -}}
{{- $path := include "rulebricks.storage.path" (list $root $key) -}}
{{- $provider := $storage.provider | default "s3" -}}
{{- if eq $provider "s3" -}}
{{- printf "s3://%s/%s" $storage.bucket $path -}}
{{- else if eq $provider "azure-blob" -}}
{{- printf "https://%s.blob.core.windows.net/%s/%s" $storage.bucket $storage.azure.container $path -}}
{{- else if eq $provider "gcs" -}}
{{- printf "gs://%s/%s" $storage.bucket $path -}}
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
