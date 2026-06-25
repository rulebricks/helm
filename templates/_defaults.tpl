{{/*
Internal defaults that are required by the Rulebricks stack but should not
dominate the user-facing values.yaml.
*/}}

{{- define "rulebricks.clickhouse.decisionLogStructure" -}}
timestamp DateTime64(3, 'UTC'), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), trace_id Nullable(String), span_id Nullable(String), request String, response String, decision String, params Nullable(String)
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogLocalStructure" -}}
timestamp DateTime64(3), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), trace_id Nullable(String), span_id Nullable(String), request String, response String, decision String, params Nullable(String)
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogSelectColumns" -}}
timestamp, api_key, user_id, environment, ip, method, url, status, rule_name, rule_id, rule_slug, rule_version, operation, level, error, trace_id, span_id, request, response, decision, params
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
{{- $otelLimits := .Values.otelQueryLimits | default dict -}}
<clickhouse>
  <profiles>
    <default>
      <max_memory_usage>{{ $limits.maxMemoryUsage | default 4294967296 | int64 }}</max_memory_usage>
      <max_threads>{{ $limits.maxThreads | default 4 | int64 }}</max_threads>
      <max_execution_time>{{ $limits.maxExecutionTime | default 120 | int64 }}</max_execution_time>
      {{- /* Hard cap on rows scanned per query so an unbounded decision-log read
             can't OOM the server. read_overflow_mode=break returns the rows
             gathered so far instead of throwing once the cap is hit. */}}
      <max_rows_to_read>{{ $limits.maxRowsToRead | default 50000000 | int64 }}</max_rows_to_read>
      <read_overflow_mode>{{ $limits.readOverflowMode | default "break" }}</read_overflow_mode>
      {{- /* Decision logs are read from object storage as gzipped NDJSON.
             best_effort parses Vector's RFC3339 timestamps into DateTime64;
             skip_unknown_fields tolerates extra envelope fields. */}}
      <date_time_input_format>best_effort</date_time_input_format>
      <input_format_skip_unknown_fields>1</input_format_skip_unknown_fields>
      {{- /* Decision logs are laid out as year=/month=/day=/hour= Hive partitions
             in object storage. Enabling this exposes those path segments as the
             decision_logs view's year/month/day/hour columns AND lets a query that
             filters on them prune whole files at listing time instead of scanning
             all of history. MUST be a profile (session) setting: when set inline in
             the view's own SETTINGS the predicate does not push down and pruning is
             silently lost. */}}
      <use_hive_partitioning>1</use_hive_partitioning>
    </default>
    <otel>
      <max_memory_usage>{{ $otelLimits.maxMemoryUsage | default 4294967296 | int64 }}</max_memory_usage>
      <max_threads>{{ $otelLimits.maxThreads | default 8 | int64 }}</max_threads>
      <max_execution_time>{{ $otelLimits.maxExecutionTime | default 120 | int64 }}</max_execution_time>
      <date_time_input_format>best_effort</date_time_input_format>
      <input_format_skip_unknown_fields>1</input_format_skip_unknown_fields>
    </otel>
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
      <access_management>1</access_management>
      <named_collection_control>1</named_collection_control>
      <show_named_collections>1</show_named_collections>
      <show_named_collections_secrets>1</show_named_collections_secrets>
    </{{ $user }}>
  </users>
</clickhouse>
{{- end -}}

{{- /*
Decision-logs bootstrap, mounted into the ClickHouse subchart's
initdbScripts. The Bitnami ClickHouse image ONLY runs *.sh init scripts: it
skips other files with "supported formats are: .sh" and will not even start the
init flow unless a .sh file is present, so this MUST be a shell script, not raw
SQL (a prior .sql version was silently never executed -> "Database rulebricks
does not exist"). It creates:
  - decision_logs_archive: object-storage external view (durable archive)
  - decision_logs_recent: local MergeTree cache (query acceleration)
  - decision_logs: compatibility view used by app/HyperDX
Keep the rendered output on a SINGLE line: the subchart serializes initdb values
as a single-quoted YAML scalar, which folds newlines to spaces and would
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
{{- $clickstack := dig "clickstack" dict (.Values.global | default dict) -}}
{{- $accelerated := $clickstack.enabled | default false -}}
{{- $decisionLogs := dig "clickstack" "clickhouse" "decisionLogs" dict (.Values.global | default dict) -}}
{{- $retentionDays := $decisionLogs.retentionDays | default 30 | int -}}
{{- $fallback := dig "objectStorageFallback" "enabled" true $decisionLogs -}}
{{- $columns := include "rulebricks.clickhouse.decisionLogSelectColumns" . -}}
{{- $user := .Values.auth.username | default "rulebricks" -}}
{{- $otelDb := .Values.otelDatabase | default "otel" -}}
{{- /* The view exposes the Hive path partitions (year/month/day/hour) as stable
       UInt columns so callers can prune by partition. The CAST is deliberate: the
       raw Hive virtual columns come back as LowCardinality with an inference-
       dependent base type (String for zero-padded values like '06', Int otherwise),
       so a plain `SELECT *, year, ...` would yield a fragile, shifting schema. CAST
       normalizes them to fixed UInt; pruning still pushes down because the Hive
       setting is enabled at the profile level (see queryLimitsXml), not inline.
       use_hive_partitioning + allow_suspicious_low_cardinality_types are passed on
       the create so the columns resolve at bootstrap regardless of profile load
       order. Keep on a SINGLE line (the initdb scalar folds newlines to spaces). */ -}}
clickhouse-client --host 127.0.0.1 --user "${CLICKHOUSE_ADMIN_USER:-default}" --password "${CLICKHOUSE_ADMIN_PASSWORD:-}" --use_hive_partitioning=1 --allow_suspicious_low_cardinality_types=1 --multiquery "CREATE DATABASE IF NOT EXISTS rulebricks; CREATE DATABASE IF NOT EXISTS {{ $otelDb }}; GRANT ALL ON {{ $otelDb }}.* TO {{ $user }}; CREATE OR REPLACE VIEW rulebricks.decision_logs_archive AS SELECT {{ $columns }}, CAST(year AS UInt16) AS year, CAST(month AS UInt8) AS month, CAST(day AS UInt8) AS day, CAST(hour AS UInt8) AS hour FROM {{ $source }}; {{- if $accelerated }} CREATE TABLE IF NOT EXISTS rulebricks.decision_logs_recent ({{ include "rulebricks.clickhouse.decisionLogLocalStructure" . }}, year UInt16 MATERIALIZED toYear(timestamp), month UInt8 MATERIALIZED toMonth(timestamp), day UInt8 MATERIALIZED toDayOfMonth(timestamp), hour UInt8 MATERIALIZED toHour(timestamp)) ENGINE = MergeTree PARTITION BY toYYYYMM(timestamp) ORDER BY (api_key, timestamp, status) TTL toDateTime(timestamp) + INTERVAL {{ $retentionDays }} DAY DELETE; ALTER TABLE rulebricks.decision_logs_recent MODIFY TTL toDateTime(timestamp) + INTERVAL {{ $retentionDays }} DAY DELETE; {{- if $fallback }} CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_recent WHERE timestamp >= now() - INTERVAL {{ $retentionDays }} DAY UNION ALL SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_archive WHERE timestamp < now() - INTERVAL {{ $retentionDays }} DAY;{{- else }} CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_recent;{{- end }}{{- else }} CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_archive;{{- end }}"
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
.trace_id = to_string(.trace_id) ?? null;
.span_id = to_string(.span_id) ?? null;
.request = to_string(.request) ?? "null";
.response = to_string(.response) ?? "null";
.decision = to_string(.decision) ?? "{}";
.params = to_string(.params) ?? "{}"
{{- end -}}
