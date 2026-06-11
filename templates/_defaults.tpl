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
      <format>JSONEachRow</format>
      <use_environment_credentials>true</use_environment_credentials>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_s3>
    {{- else if eq $provider "azure-blob" }}
    {{- /* azureBlobStorage named collections take storage_account_url + container
           + blob_path (NOT a single `url` like s3); a `url` key is rejected with
           "Unexpected key url in named collection". */}}
    {{- $account := include "rulebricks.storage.bucket" (list . "decisionLogs") }}
    {{- $container := include "rulebricks.storage.azureContainer" (list . "decisionLogs") }}
    {{- $path := include "rulebricks.storage.path" (list . "decisionLogs") }}
    <decision_logs_azure>
      <storage_account_url>{{ printf "https://%s.blob.core.windows.net" $account }}</storage_account_url>
      <container>{{ $container }}</container>
      <blob_path>{{ printf "%s/year=*/month=*/day=*/hour=*/*.gz" $path }}</blob_path>
      <format>JSONEachRow</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_azure>
    {{- else if eq $provider "gcs" }}
    <decision_logs_gcs>
      <url>{{ include "rulebricks.storage.gcsUrl" . }}</url>
      <format>JSONEachRow</format>
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
      <max_memory_usage>{{ $limits.maxMemoryUsage | default 1073741824 | int64 }}</max_memory_usage>
      <max_threads>{{ $limits.maxThreads | default 4 | int64 }}</max_threads>
      <max_execution_time>{{ $limits.maxExecutionTime | default 60 | int64 }}</max_execution_time>
      {{- /* Decision logs are read from object storage as gzipped NDJSON.
             best_effort parses Vector's RFC3339 timestamps into DateTime64;
             skip_unknown_fields tolerates extra envelope fields. */}}
      <date_time_input_format>best_effort</date_time_input_format>
      <input_format_skip_unknown_fields>1</input_format_skip_unknown_fields>
    </default>
  </profiles>
</clickhouse>
{{- end -}}

{{- /*
Named-collection access for the ClickHouse admin user. The decision_logs view
reads from a named collection (decision_logs_s3 / _azure / _gcs); without these
flags the user has access_management but no NAMED COLLECTION grant, so the initdb
view creation fails with "Not enough privileges ... NAMED COLLECTION ... ACCESS_DENIED".
This MUST be mounted under users.d (not config.d) to take effect.
*/ -}}
{{- /* Rendered in the clickhouse subchart context, so auth lives at .Values.auth
       (mirrors queryLimitsXml using .Values.queryLimits). */ -}}
{{- define "rulebricks.clickhouse.userAccessXml" -}}
{{- $user := .Values.auth.username | default "rulebricks" -}}
<clickhouse>
  <users>
    <{{ $user }}>
      <named_collection_control>1</named_collection_control>
      <show_named_collections>1</show_named_collections>
      <show_named_collections_secrets>1</show_named_collections_secrets>
    </{{ $user }}>
  </users>
</clickhouse>
{{- end -}}

{{- /*
Decision-logs view bootstrap, mounted into the ClickHouse subchart's
initdbScripts. The Bitnami ClickHouse image ONLY runs *.sh init scripts: it
skips other files with "supported formats are: .sh" and will not even start the
init flow unless a .sh file is present, so this MUST be a shell script, not raw
SQL (a prior .sql version was silently never executed -> "Database rulebricks
does not exist"). It runs clickhouse-client against the locally-started server
during init; with ClickHouse persistence disabled the data dir is ephemeral, so
this idempotent script re-creates the database + view on every fresh pod. The
admin user (CLICKHOUSE_ADMIN_USER) carries the NAMED COLLECTION grants the view
needs. Keep the rendered output on a SINGLE line: the subchart serializes initdb
values as a single-quoted YAML scalar, which folds newlines to spaces and would
otherwise corrupt a multi-line script.
*/ -}}
{{- define "rulebricks.clickhouse.decisionLogsViewScript" -}}
{{- $provider := .Values.global.storage.provider | default "s3" -}}
{{- $source := "s3(decision_logs_s3)" -}}
{{- if eq $provider "azure-blob" -}}
{{- $source = "azureBlobStorage(decision_logs_azure)" -}}
{{- else if eq $provider "gcs" -}}
{{- $source = "gcs(decision_logs_gcs)" -}}
{{- end -}}
clickhouse-client --host 127.0.0.1 --user "${CLICKHOUSE_ADMIN_USER:-default}" --password "${CLICKHOUSE_ADMIN_PASSWORD:-}" --multiquery "CREATE DATABASE IF NOT EXISTS rulebricks; CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT * FROM {{ $source }};"
{{- end -}}

{{- /*
HPS owns the decision-log schema; this coerces the Kafka envelope to the
ClickHouse column types. Statements are ';'-separated and use no '#' comments so
the script stays valid even when embedded in a single-quoted YAML scalar (which
folds newlines to spaces). The CLI inlines an equivalent block-scalar form; keep
the two in sync.
*/ -}}
{{- define "rulebricks.vector.normalizeLogs" -}}
parsed, err = parse_json(string!(.message));
if err == null { . = parsed };
.timestamp = parse_timestamp!(to_string(.timestamp) ?? to_string(now()), format: "%+");
.api_key = to_string(.api_key) ?? "";
.user_id = to_string(.user_id) ?? null;
.environment = to_string(.environment) ?? null;
.ip = to_string(.ip) ?? null;
.method = to_string(.method) ?? null;
.url = to_string(.url) ?? "";
.status = to_int(.status) ?? 0;
.rule_name = to_string(.rule_name) ?? null;
.rule_id = to_string(.rule_id) ?? null;
.rule_slug = to_string(.rule_slug) ?? null;
.rule_version = to_string(.rule_version) ?? null;
.operation = to_string(.operation) ?? null;
.level = to_string(.level) ?? "info";
.error = to_string(.error) ?? null;
.request = to_string(.request) ?? "null";
.response = to_string(.response) ?? "null";
.decision = to_string(.decision) ?? "{}";
.params = to_string(.params) ?? "{}"
{{- end -}}
