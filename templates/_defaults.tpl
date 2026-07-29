{{/*
Internal defaults that are required by the Rulebricks stack but should not
dominate the user-facing values.yaml.
*/}}

{{- /* The object-storage structure keeps optional fields Nullable because raw
       NDJSON imports can omit them. The persistent table uses the same schema
       except for log_id: it is non-nullable (with a UUID default) because it is
       the final MergeTree sorting key and Vector always supplies it. */ -}}
{{- define "rulebricks.clickhouse.decisionLogStructure" -}}
timestamp DateTime64(3, 'UTC'), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), trace_id Nullable(String), span_id Nullable(String), flow_execution_id Nullable(String), flow_name Nullable(String), flow_slug Nullable(String), flow_node_id Nullable(String), parallel_execution_id Nullable(String), parallel_path Nullable(String), request String, response String, decision String, params Nullable(String), path_trace Nullable(String), log_id Nullable(String)
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogLocalStructure" -}}
timestamp DateTime64(3, 'UTC'), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), trace_id Nullable(String), span_id Nullable(String), flow_execution_id Nullable(String), flow_name Nullable(String), flow_slug Nullable(String), flow_node_id Nullable(String), parallel_execution_id Nullable(String), parallel_path Nullable(String), request String, response String, decision String, params Nullable(String), path_trace Nullable(String), log_id String DEFAULT toString(generateUUIDv4())
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogSelectColumns" -}}
timestamp, api_key, user_id, environment, ip, method, url, status, rule_name, rule_id, rule_slug, rule_version, operation, level, error, trace_id, span_id, flow_execution_id, flow_name, flow_slug, flow_node_id, parallel_execution_id, parallel_path, request, response, decision, params, path_trace, log_id
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogStorageXml" -}}
<clickhouse>
  <named_collections>
    {{- $provider := .Values.global.storage.provider | default "s3" }}
    {{- if eq $provider "s3" }}
    <decision_logs_s3>
      <url>{{ include "rulebricks.storage.s3Url" . }}</url>
      <format>JSONEachRow</format>
      {{- /* ClickHouse parses this named-collection key as a numeric bool: it wants
             1/0, not the XML "true"/"false" it would silently mis-read elsewhere. */}}
      <use_environment_credentials>1</use_environment_credentials>
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
      <blob_path>{{ printf "%s/year=*/month=*/day=*/hour=*/*.{gz,zst}" $path }}</blob_path>
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
             in object storage, but hive partitioning MUST stay DISABLED here: with
             it on, ClickHouse >= 25.x derives partition columns from the path and
             requires them in the named collection's pinned `structure` (which
             intentionally omits them - the views derive year/month/day/hour from
             the row timestamp so they survive an empty bucket). With the profile
             set to 1 every decision-log read fails with "All hive partitioning
             columns must be present in the schema" the moment the first blob
             lands. Nothing is lost by disabling it: the app filters on timestamp,
             not the path columns, so hive pruning was never exercised. */}}
      <use_hive_partitioning>0</use_hive_partitioning>
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
Decision-logs bootstrap shared by the post-install/upgrade Job and the
stateless ClickHouse init script. It creates:
  - decision_logs_archive: raw-NDJSON object-storage view in every mode
  - decision_logs: the persistent MergeTree table, or the stateless archive view
Keep the rendered output on a SINGLE line so it is safe in both the native
client argument and the entrypoint's generated init script.
*/ -}}
{{- /* The view exposes year/month/day/hour as stable UInt columns derived from the
       row's own timestamp, NOT from the S3 Hive path partitions. Reading them off
       the path (CAST(year AS UInt16) ...) requires ClickHouse to infer the partition
       columns by listing objects, so on a FRESH/empty bucket there are no files,
       the year/month/day/hour identifiers don't resolve, CREATE VIEW fails and the
       view step crashloops. Deriving from timestamp always resolves (timestamp is in
       the named-collection structure), survives an empty bucket, and keeps the
       decision_logs view stable. Keep on a SINGLE line. */ -}}
{{- /* Persistent mode stores decision logs in one MergeTree table:
       - Daily partitions align TTL cleanup and the disk-pressure safety valve.
       - ORDER BY (api_key, timestamp, log_id) matches the app's primary list
         query and uses the producer-minted id as a deterministic tiebreaker.
       - tokenbf_v1 indexes accelerate whole-token payload search; bloom_filter
         indexes accelerate flow/trace correlation lookups.
       - The table TTL is updated on every Helm upgrade, but is not materialized
         synchronously; normal merges apply it without turning upgrades into a
         full-table rewrite.
       - min_free_disk_ratio_to_perform_insert is the final backstop if TTL and
         the retention CronJob cannot reclaim space quickly enough. */ -}}
{{- define "rulebricks.clickhouse.decisionLogsViewSql" -}}
{{- $provider := .Values.global.storage.provider | default "s3" -}}
{{- $source := "s3(decision_logs_s3)" -}}
{{- if eq $provider "azure-blob" -}}
{{- $source = "azureBlobStorage(decision_logs_azure)" -}}
{{- else if eq $provider "gcs" -}}
{{- $source = "gcs(decision_logs_gcs)" -}}
{{- end -}}
{{- $persistent := .Values.persistence.enabled -}}
{{- $columns := include "rulebricks.clickhouse.decisionLogSelectColumns" . -}}
{{- $otelDb := .Values.otelDatabase | default "otel" -}}
{{- $decisionLogs := .Values.decisionLogs | default dict -}}
{{- $retentionDays := $decisionLogs.retentionDays | default 30 | int -}}
{{- /* Reads through these views REQUIRE use_hive_partitioning=0, set in the
       default profile (queryLimitsXml above). A view-level SETTINGS clause does
       NOT reach the underlying s3() storage read, so the profile is the only
       place that works. See queryLimitsXml for the full rationale. */ -}}
CREATE DATABASE IF NOT EXISTS rulebricks; CREATE DATABASE IF NOT EXISTS {{ $otelDb }}; CREATE OR REPLACE VIEW rulebricks.decision_logs_archive AS SELECT {{ $columns }}, toYear(timestamp) AS year, toMonth(timestamp) AS month, toDayOfMonth(timestamp) AS day, toHour(timestamp) AS hour FROM {{ $source }};{{- if $persistent }} CREATE TABLE IF NOT EXISTS rulebricks.decision_logs ({{ include "rulebricks.clickhouse.decisionLogLocalStructure" . }}, year UInt16 MATERIALIZED toYear(timestamp), month UInt8 MATERIALIZED toMonth(timestamp), day UInt8 MATERIALIZED toDayOfMonth(timestamp), hour UInt8 MATERIALIZED toHour(timestamp), INDEX idx_request_tokens request TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_response_tokens response TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_decision_tokens decision TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_flow_execution_id flow_execution_id TYPE bloom_filter(0.01) GRANULARITY 4, INDEX idx_trace_id trace_id TYPE bloom_filter(0.01) GRANULARITY 4) ENGINE = MergeTree PARTITION BY toYYYYMMDD(timestamp) ORDER BY (api_key, timestamp, log_id) TTL toDateTime(timestamp) + INTERVAL {{ $retentionDays }} DAY DELETE SETTINGS min_free_disk_ratio_to_perform_insert = 0.2; ALTER TABLE rulebricks.decision_logs MODIFY TTL toDateTime(timestamp) + INTERVAL {{ $retentionDays }} DAY DELETE;{{- else }} CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_archive;{{- end }}
{{- end -}}

{{- /* Legacy shell wrapper, retained for the Bitnami-style initdb path and the CLI's
       inline equivalent. The DHI/Strimzi path runs the SQL above directly via a
       post-install clickhouse-client Job (no shell). */ -}}
{{- define "rulebricks.clickhouse.decisionLogsViewScript" -}}
clickhouse-client --host 127.0.0.1 --user "${CLICKHOUSE_ADMIN_USER:-default}" --password "${CLICKHOUSE_ADMIN_PASSWORD:-}" --multiquery "{{ include "rulebricks.clickhouse.decisionLogsViewSql" . }}"
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
.log_id = to_string(.log_id) ?? uuid_v4();
.path_trace = to_string(.path_trace) ?? null;
.request = to_string(.request) ?? "null";
.response = to_string(.response) ?? "null";
.decision = to_string(.decision) ?? "{}";
.params = to_string(.params) ?? "{}";
_decision = parse_json(.decision) ?? {};
.flow_execution_id = to_string(.flow_execution_id) ?? to_string(_decision.flowExecutionId) ?? null;
.flow_name = to_string(.flow_name) ?? to_string(_decision.flowName) ?? null;
.flow_slug = to_string(.flow_slug) ?? to_string(_decision.flowSlug) ?? null;
.flow_node_id = to_string(.flow_node_id) ?? to_string(_decision.flowNodeId) ?? null;
.parallel_execution_id = to_string(.parallel_execution_id) ?? to_string(_decision.parallelExecutionId) ?? null;
.parallel_path = to_string(.parallel_path) ?? to_string(_decision.parallelPath) ?? null
{{- end -}}
