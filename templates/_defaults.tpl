{{/*
Internal defaults that are required by the Rulebricks stack but should not
dominate the user-facing values.yaml.
*/}}

{{- /* flow_* columns promote the flow correlation that already lives inside the
       `decision` JSON to first-class columns so HyperDX can filter/group rule
       executions by their parent flow. Nullable so direct (non-flow) solves and
       pre-existing archived rows (which lack the keys) read back as NULL. Keep
       all three definitions below column-for-column identical. */ -}}
{{- define "rulebricks.clickhouse.decisionLogStructure" -}}
timestamp DateTime64(3, 'UTC'), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), trace_id Nullable(String), span_id Nullable(String), flow_execution_id Nullable(String), flow_name Nullable(String), flow_slug Nullable(String), flow_node_id Nullable(String), parallel_execution_id Nullable(String), parallel_path Nullable(String), request String, response String, decision String, params Nullable(String)
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogLocalStructure" -}}
timestamp DateTime64(3), api_key String, user_id Nullable(String), environment Nullable(String), ip Nullable(String), method Nullable(String), url String, status Int32, rule_name Nullable(String), rule_id Nullable(String), rule_slug Nullable(String), rule_version Nullable(String), operation Nullable(String), level String, error Nullable(String), trace_id Nullable(String), span_id Nullable(String), flow_execution_id Nullable(String), flow_name Nullable(String), flow_slug Nullable(String), flow_node_id Nullable(String), parallel_execution_id Nullable(String), parallel_path Nullable(String), request String, response String, decision String, params Nullable(String)
{{- end -}}

{{- define "rulebricks.clickhouse.decisionLogSelectColumns" -}}
timestamp, api_key, user_id, environment, ip, method, url, status, rule_name, rule_id, rule_slug, rule_version, operation, level, error, trace_id, span_id, flow_execution_id, flow_name, flow_slug, flow_node_id, parallel_execution_id, parallel_path, request, response, decision, params
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
    {{- /* Compacted tier: the compaction CronJob rewrites closed hours of raw
           NDJSON into sorted per-hour Parquet objects in the same prefix (see
           clickhouse-retention/compaction CronJobs). Parquet gives the archive
           branch column pruning and row-group min/max timestamp stats, so
           time-bounded queries stop paying full decompress-and-parse. Reads
           tolerate an empty/no-match glob (s3_throw_on_zero_files_match
           defaults to 0), so this collection is safe before the first
           compaction run. */}}
    <decision_logs_parquet_s3>
      <url>{{ include "rulebricks.storage.s3ParquetUrl" . }}</url>
      <format>Parquet</format>
      <use_environment_credentials>1</use_environment_credentials>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_parquet_s3>
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
    {{- /* See decision_logs_parquet_s3 above for the compacted-tier rationale. */}}
    <decision_logs_parquet_azure>
      <storage_account_url>{{ printf "https://%s.blob.core.windows.net" $account }}</storage_account_url>
      <container>{{ $container }}</container>
      <blob_path>{{ printf "%s/year=*/month=*/day=*/hour=*/*.parquet" $path }}</blob_path>
      <format>Parquet</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_parquet_azure>
    {{- else if eq $provider "gcs" }}
    <decision_logs_gcs>
      <url>{{ include "rulebricks.storage.gcsUrl" . }}</url>
      <format>JSONEachRow</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_gcs>
    {{- /* See decision_logs_parquet_s3 above for the compacted-tier rationale. */}}
    <decision_logs_parquet_gcs>
      <url>{{ include "rulebricks.storage.gcsParquetUrl" . }}</url>
      <format>Parquet</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_parquet_gcs>
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
Decision-logs bootstrap, mounted into the ClickHouse subchart's
initdbScripts. The Bitnami ClickHouse image ONLY runs *.sh init scripts: it
skips other files with "supported formats are: .sh" and will not even start the
init flow unless a .sh file is present, so this MUST be a shell script, not raw
SQL (a prior .sql version was silently never executed -> "Database rulebricks
does not exist"). It creates:
  - decision_logs_archive: object-storage external view (durable archive)
  - decision_logs_recent: local MergeTree hot tier (ClickStack mode only)
  - decision_logs: compatibility view used by the app
Keep the rendered output on a SINGLE line: the subchart serializes initdb values
as a single-quoted YAML scalar, which folds newlines to spaces and would
otherwise corrupt a multi-line script.
*/ -}}
{{- /* The view exposes year/month/day/hour as stable UInt columns derived from the
       row's own timestamp, NOT from the S3 Hive path partitions. Reading them off
       the path (CAST(year AS UInt16) ...) requires ClickHouse to infer the partition
       columns by listing objects, so on a FRESH/empty bucket there are no files,
       the year/month/day/hour identifiers don't resolve, CREATE VIEW fails and the
       view step crashloops. Deriving from timestamp always resolves (timestamp is in
       the named-collection structure), survives an empty bucket, and keeps the
       decision_logs view stable. Keep on a SINGLE line. */ -}}
{{- /* Hot tier (ClickStack mode only): decision_logs_recent is a size-bounded
       CACHE, never the system of record - Vector always writes the durable
       archive to object storage and best-effort dual-writes here.
       - Daily partitions (toYYYYMMDD) so the retention CronJob has fine-grained
         eviction units; it drops the oldest partition while disk free space is
         low (see clickhouse-retention-cronjob.yaml). There is deliberately NO
         time TTL: eviction is disk-pressure-driven, so the hot window sizes
         itself to actual traffic instead of a guessed retention number.
       - min_free_disk_ratio_to_perform_insert (MergeTree setting, ClickHouse
         >= 24.10) is the backstop if the CronJob dies: inserts into this table
         fail before the volume fills, protecting the otel database and the
         query path on the same PVC.
       - tokenbf_v1 skip indexes accelerate the app's bare-term DDQL search
         (request/response/decision LIKE '%needle%') for whole-token needles
         (IDs, emails, slugs); ngrambf_v1 would cover arbitrary substrings but
         costs far more storage.
       - bloom_filter skip indexes on flow_execution_id and trace_id cover the
         app's correlation-ID lookup (flow_execution_id = X OR trace_id = X OR
         decision LIKE '%X%'): these are the only correlation columns probed by
         equality. Root/parent flow ids deliberately have no columns - they live
         inside the decision JSON and are pruned by idx_decision_tokens (UUIDs
         tokenize to whole hex segments). With every OR branch index-checkable,
         granule pruning engages for the whole condition. NOTE: CREATE TABLE IF
         NOT EXISTS means existing deployments keep their old index set; new
         indexes apply to fresh installs only (no migration by design).
       - The decision_logs view splits hot/cold on a DYNAMIC boundary read from
         system.parts metadata: the archive branch serves everything OLDER than
         the oldest hot partition. Dropping a partition therefore never punches
         a hole - the archive transparently covers the evicted range - and a
         fresh/empty hot table routes everything to the archive (minOrNull is
         required: plain min() over an empty set returns 0, not NULL, which
         would silently exclude the whole archive). Whole-day granularity is
         correct because whole daily partitions are the eviction unit. */ -}}
{{- define "rulebricks.clickhouse.decisionLogsViewSql" -}}
{{- $provider := .Values.global.storage.provider | default "s3" -}}
{{- $source := "s3(decision_logs_s3)" -}}
{{- $parquetSource := "s3(decision_logs_parquet_s3)" -}}
{{- if eq $provider "azure-blob" -}}
{{- $source = "azureBlobStorage(decision_logs_azure)" -}}
{{- $parquetSource = "azureBlobStorage(decision_logs_parquet_azure)" -}}
{{- else if eq $provider "gcs" -}}
{{- $source = "gcs(decision_logs_gcs)" -}}
{{- $parquetSource = "gcs(decision_logs_parquet_gcs)" -}}
{{- end -}}
{{- $clickstack := dig "clickstack" dict (.Values.global | default dict) -}}
{{- $accelerated := $clickstack.enabled | default false -}}
{{- $columns := include "rulebricks.clickhouse.decisionLogSelectColumns" . -}}
{{- $otelDb := .Values.otelDatabase | default "otel" -}}
{{- /* Reads through these views REQUIRE use_hive_partitioning=0, set in the
       default profile (queryLimitsXml above). A view-level SETTINGS clause does
       NOT reach the underlying s3() storage read, so the profile is the only
       place that works. See queryLimitsXml for the full rationale. */ -}}
{{- /* The archive is TWO object-storage tiers behind one view: raw NDJSON
       (the tail Vector is still writing) UNION ALL compacted per-hour Parquet
       (rewritten by the compaction CronJob). An hour lives in exactly one tier
       - the CronJob deletes an hour's raw files only after its Parquet object
       verifies - except for a transient window if a compaction run dies
       between write and delete, in which case that one hour double-counts
       until the next (idempotent, truncate-on-insert) run converges. */ -}}
CREATE DATABASE IF NOT EXISTS rulebricks; CREATE DATABASE IF NOT EXISTS {{ $otelDb }}; CREATE OR REPLACE VIEW rulebricks.decision_logs_archive AS SELECT {{ $columns }}, toYear(timestamp) AS year, toMonth(timestamp) AS month, toDayOfMonth(timestamp) AS day, toHour(timestamp) AS hour FROM {{ $source }} UNION ALL SELECT {{ $columns }}, toYear(timestamp) AS year, toMonth(timestamp) AS month, toDayOfMonth(timestamp) AS day, toHour(timestamp) AS hour FROM {{ $parquetSource }};{{- if $accelerated }} CREATE TABLE IF NOT EXISTS rulebricks.decision_logs_recent ({{ include "rulebricks.clickhouse.decisionLogLocalStructure" . }}, year UInt16 MATERIALIZED toYear(timestamp), month UInt8 MATERIALIZED toMonth(timestamp), day UInt8 MATERIALIZED toDayOfMonth(timestamp), hour UInt8 MATERIALIZED toHour(timestamp), INDEX idx_request_tokens request TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_response_tokens response TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_decision_tokens decision TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_flow_execution_id flow_execution_id TYPE bloom_filter(0.01) GRANULARITY 4, INDEX idx_trace_id trace_id TYPE bloom_filter(0.01) GRANULARITY 4) ENGINE = MergeTree PARTITION BY toYYYYMMDD(timestamp) ORDER BY (api_key, timestamp, status) SETTINGS min_free_disk_ratio_to_perform_insert = 0.2; CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_recent UNION ALL SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_archive WHERE toYYYYMMDD(timestamp) < (SELECT ifNull(minOrNull(toUInt32(partition)), toUInt32(29990101)) FROM system.parts WHERE database = 'rulebricks' AND table = 'decision_logs_recent' AND active);{{- else }} CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_archive;{{- end }}
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
