{{/*
Internal defaults that are required by the Rulebricks stack but should not
dominate the user-facing values.yaml.
*/}}

{{- define "rulebricks.clickhouse.decisionLogStructure" -}}
timestamp DateTime64(3, 'UTC'), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), request String, response String, decision String, params Nullable(String)
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogStorageXml" -}}
<clickhouse>
  <named_collections>
    {{- $provider := .Values.global.storage.provider | default "s3" }}
    {{- if eq $provider "s3" }}
    <decision_logs_s3>
      <url>{{ include "rulebricks.storage.s3Url" . }}</url>
      <format>Parquet</format>
      <use_environment_credentials>true</use_environment_credentials>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_s3>
    {{- else if eq $provider "azure-blob" }}
    <decision_logs_azure>
      <url>{{ include "rulebricks.storage.azureUrl" . }}</url>
      <format>Parquet</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_azure>
    {{- else if eq $provider "gcs" }}
    <decision_logs_gcs>
      <url>{{ include "rulebricks.storage.gcsUrl" . }}</url>
      <format>Parquet</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_gcs>
    {{- end }}
  </named_collections>
</clickhouse>
{{- end -}}

{{- define "rulebricks.clickhouse.queryLimitsXml" -}}
{{- $limits := .Values.queryLimits | default dict -}}
<clickhouse>
  <profiles>
    <default>
      <max_memory_usage>{{ $limits.maxMemoryUsage | default 1073741824 }}</max_memory_usage>
      <max_threads>{{ $limits.maxThreads | default 4 }}</max_threads>
      <max_execution_time>{{ $limits.maxExecutionTime | default 60 }}</max_execution_time>
    </default>
  </profiles>
</clickhouse>
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogsViewSql" -}}
{{- $provider := .Values.global.storage.provider | default "s3" }}
CREATE DATABASE IF NOT EXISTS rulebricks;
{{- if eq $provider "s3" }}
CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT * FROM s3(decision_logs_s3);
{{- else if eq $provider "azure-blob" }}
CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT * FROM azureBlobStorage(decision_logs_azure);
{{- else if eq $provider "gcs" }}
CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT * FROM gcs(decision_logs_gcs);
{{- end }}
{{- end -}}

{{- define "rulebricks.vector.normalizeLogs" -}}
# HPS owns the decision-log schema. Vector only parses the Kafka envelope and
# coerces fields to the Parquet/ClickHouse types below.
parsed, err = parse_json(string!(.message))
if err == null {
  . = parsed
}

.timestamp = parse_timestamp!(to_string(.timestamp) ?? to_string(now()), format: "%+")
.api_key = to_string(.api_key) ?? ""
.user_id = to_string(.user_id) ?? null
.environment = to_string(.environment) ?? null
.ip = to_string(.ip) ?? null
.method = to_string(.method) ?? null
.url = to_string(.url) ?? ""
.status = to_int(.status) ?? 0
.rule_name = to_string(.rule_name) ?? null
.rule_id = to_string(.rule_id) ?? null
.rule_slug = to_string(.rule_slug) ?? null
.rule_version = to_string(.rule_version) ?? null
.operation = to_string(.operation) ?? null
.level = to_string(.level) ?? "info"
.error = to_string(.error) ?? null
.request = to_string(.request) ?? "null"
.response = to_string(.response) ?? "null"
.decision = to_string(.decision) ?? "{}"
.params = to_string(.params) ?? "{}"
{{- end -}}
