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

{{- /*
Persistent ClickHouse stores native MergeTree objects in the same object-store
account as the raw decision archive, but under a separate prefix. The original
StatefulSet PVC remains authoritative for ClickHouse catalog/object metadata.
A standalone PVC backs the bounded read cache and a size-limited emptyDir backs
temporary spill, so neither can exhaust the catalog filesystem.
*/ -}}
{{- define "rulebricks.clickhouse.objectStorageXml" -}}
{{- $storage := .Values.global.storage | default dict -}}
{{- $provider := $storage.provider | default "s3" -}}
{{- $bucket := required "global.storage.bucket is required for persistent ClickHouse object storage" (include "rulebricks.storage.bucket" (list . "clickhouse")) -}}
{{- $path := required "global.storage.paths.clickhouse is required for persistent ClickHouse object storage" (include "rulebricks.storage.path" (list . "clickhouse")) -}}
{{- $archivePath := include "rulebricks.storage.path" (list . "decisionLogs") -}}
{{- if eq $path $archivePath -}}
{{- fail "global.storage.paths.clickhouse must be separate from global.storage.paths.decisionLogs" -}}
{{- end -}}
<clickhouse>
  <storage_configuration>
    <disks>
      <default>
        <!-- This is the catalog/metadata PVC. Preserve enough free space for
             metadata commits even when an administrator creates local data. -->
        <keep_free_space_bytes>{{ .Values.persistence.keepFreeSpaceBytes | default 21474836480 | int64 }}</keep_free_space_bytes>
      </default>
      <object_storage>
        <type>object_storage</type>
        <metadata_type>local</metadata_type>
        <metadata_path>/var/lib/clickhouse/disks/object_storage/</metadata_path>
        <skip_access_check>true</skip_access_check>
        {{- if eq $provider "s3" }}
        {{- $region := required "global.storage.region is required for S3-backed persistent ClickHouse" (include "rulebricks.storage.region" (list . "clickhouse")) }}
        <object_storage_type>s3</object_storage_type>
        <endpoint>{{ printf "https://%s.s3.%s.amazonaws.com/%s/" $bucket $region $path }}</endpoint>
        <region>{{ $region }}</region>
        <use_environment_credentials>1</use_environment_credentials>
        {{- else if eq $provider "azure-blob" }}
        {{- $azure := $storage.azure | default dict }}
        {{- $container := required "global.storage.azure.container is required for Azure-backed persistent ClickHouse" (include "rulebricks.storage.azureContainer" (list . "clickhouse")) }}
        <object_storage_type>azure</object_storage_type>
        <endpoint>{{ printf "https://%s.blob.core.windows.net/%s/%s/" $bucket $container $path }}</endpoint>
        <endpoint_contains_account_name>false</endpoint_contains_account_name>
        <container_already_exists>true</container_already_exists>
        {{- if eq ($azure.authMode | default "workload-identity") "connection-string" }}
        <connection_string from_env="AZURE_STORAGE_CONNECTION_STRING"/>
        {{- else }}
        <use_workload_identity>true</use_workload_identity>
        {{- end }}
        {{- else if eq $provider "gcs" }}
        <object_storage_type>s3</object_storage_type>
        <endpoint>{{ printf "https://storage.googleapis.com/%s/%s/" $bucket $path }}</endpoint>
        <http_client>gcp_oauth</http_client>
        <use_environment_credentials>1</use_environment_credentials>
        <support_batch_delete>false</support_batch_delete>
        {{- else }}
        {{- fail (printf "unsupported global.storage.provider %q for persistent ClickHouse" $provider) }}
        {{- end }}
      </object_storage>
      <object_storage_cache>
        <type>cache</type>
        <disk>object_storage</disk>
        <path>/var/lib/clickhouse/disks/object_storage_cache/</path>
        <skip_access_check>true</skip_access_check>
        <max_size_ratio_to_total_space>0.70</max_size_ratio_to_total_space>
        <max_elements>1000000</max_elements>
        <cache_policy>SLRU</cache_policy>
        <slru_size_ratio>0.20</slru_size_ratio>
        <keep_free_space_size_ratio>0.10</keep_free_space_size_ratio>
        <cache_on_write_operations>false</cache_on_write_operations>
        <skip_cache_on_disk_failure>true</skip_cache_on_disk_failure>
      </object_storage_cache>
    </disks>
    <policies>
      <object_storage>
        <volumes>
          <main>
            <disk>object_storage_cache</disk>
          </main>
        </volumes>
      </object_storage>
    </policies>
  </storage_configuration>
  <merge_tree>
    <storage_policy>object_storage</storage_policy>
  </merge_tree>
</clickhouse>
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
    {{- $azure := .Values.global.storage.azure | default dict }}
    <decision_logs_azure>
      {{- if eq ($azure.authMode | default "workload-identity") "connection-string" }}
      <connection_string from_env="AZURE_STORAGE_CONNECTION_STRING"/>
      {{- else }}
      <storage_account_url>{{ printf "https://%s.blob.core.windows.net" $account }}</storage_account_url>
      <client_id>{{ required "global.storage.azure.clientId is required for Azure workload identity" $azure.clientId }}</client_id>
      <tenant_id>{{ required "global.storage.azure.tenantId is required for Azure workload identity" $azure.tenantId }}</tenant_id>
      {{- end }}
      <container>{{ $container }}</container>
      <blob_path>{{ printf "%s/year=*/month=*/day=*/hour=*/*.{gz,zst}" $path }}</blob_path>
      <format>JSONEachRow</format>
      <structure>{{ include "rulebricks.clickhouse.decisionLogStructure" . }}</structure>
    </decision_logs_azure>
    {{- else if eq $provider "gcs" }}
    <decision_logs_gcs>
      <url>{{ include "rulebricks.storage.gcsUrl" . }}</url>
      <format>JSONEachRow</format>
      <http_client>gcp_oauth</http_client>
      <use_environment_credentials>1</use_environment_credentials>
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
      <max_memory_usage>{{ $limits.maxMemoryUsage | default 4294967296 | int64 }}</max_memory_usage>
      <max_threads>{{ $limits.maxThreads | default 4 | int64 }}</max_threads>
      <max_execution_time>{{ $limits.maxExecutionTime | default 120 | int64 }}</max_execution_time>
      {{- /* Hard cap on rows scanned per query so an unbounded decision-log read
             cannot OOM the server. Throw instead of returning a silently partial
             result when the cap is reached. */}}
      <max_rows_to_read>{{ $limits.maxRowsToRead | default 50000000 | int64 }}</max_rows_to_read>
      <read_overflow_mode>throw</read_overflow_mode>
      {{- if .Values.persistence.enabled }}
      <enable_filesystem_cache>1</enable_filesystem_cache>
      <enable_filesystem_cache_on_write_operations>0</enable_filesystem_cache_on_write_operations>
      {{- end }}
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
  </profiles>
</clickhouse>
{{- end -}}

{{- /*
Named-collection administration for the ClickHouse migrator user. Runtime
named-collection access is an explicit GRANT in 00-users.xml; it cannot create,
alter, or reveal collection secrets. This MUST be mounted under users.d.
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
{{- /* Persistent mode stores decision logs in one remote-backed MergeTree table:
       - Daily partitions keep bounded time-range queries and merges efficient.
       - ORDER BY (api_key, timestamp, log_id) matches the app's primary list
         query and uses the producer-minted id as a deterministic tiebreaker.
       - tokenbf_v1 indexes accelerate whole-token payload search; bloom_filter
         indexes accelerate flow/trace correlation lookups.
       - Native MergeTree parts are authoritative in object storage; the separate
         raw NDJSON archive remains the durable recovery/interchange copy.
       - The bounded filesystem cache evicts cached bytes without deleting data. */ -}}
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
{{- /* Reads through these views REQUIRE use_hive_partitioning=0, set in the
       default profile (queryLimitsXml above). A view-level SETTINGS clause does
       NOT reach the underlying s3() storage read, so the profile is the only
       place that works. See queryLimitsXml for the full rationale. */ -}}
CREATE DATABASE IF NOT EXISTS rulebricks; CREATE OR REPLACE VIEW rulebricks.decision_logs_archive AS SELECT {{ $columns }}, toYear(timestamp) AS year, toMonth(timestamp) AS month, toDayOfMonth(timestamp) AS day, toHour(timestamp) AS hour FROM {{ $source }};{{- if $persistent }} CREATE TABLE IF NOT EXISTS rulebricks.decision_logs ({{ include "rulebricks.clickhouse.decisionLogLocalStructure" . }}, year UInt16 MATERIALIZED toYear(timestamp), month UInt8 MATERIALIZED toMonth(timestamp), day UInt8 MATERIALIZED toDayOfMonth(timestamp), hour UInt8 MATERIALIZED toHour(timestamp), INDEX idx_request_tokens request TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_response_tokens response TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_decision_tokens decision TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4, INDEX idx_flow_execution_id flow_execution_id TYPE bloom_filter(0.01) GRANULARITY 4, INDEX idx_trace_id trace_id TYPE bloom_filter(0.01) GRANULARITY 4) ENGINE = MergeTree PARTITION BY toYYYYMMDD(timestamp) ORDER BY (api_key, timestamp, log_id) SETTINGS storage_policy = 'object_storage';{{- else }} CREATE OR REPLACE VIEW rulebricks.decision_logs AS SELECT {{ $columns }}, year, month, day, hour FROM rulebricks.decision_logs_archive;{{- end }}
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
