# HyperDX (ClickStack) examples

Starter content for the built-in observability UI at
`observability.<your-domain>`, parallel to [examples/dashboards](../dashboards)
for Grafana.

## What the chart already sets up

- **Connection + sources** are seeded automatically on first boot via
  `DEFAULT_CONNECTIONS` / `DEFAULT_SOURCES`
  ([charts/clickstack/templates/hyperdx.yaml](../../charts/clickstack/templates/hyperdx.yaml)):
  Operational Logs, Distributed Traces, Metrics, and Sessions, wired to the
  ClickStack ClickHouse tables. Seeding runs only when the team has **zero
  sources** - it never overwrites edits, and installs created before a chart
  fix keep their old (possibly broken) sources. To repair an existing install,
  edit the source under **Team Settings → Sources** instead (the current
  schema uses the `Timestamp` column; log and trace sources also require a
  Default Select expression).
- **Noise filtering** happens in the collector gateway before anything is
  stored. By default only HTTP spans for the `/api/v1` decision API are kept
  (internal spans - Kafka, workers, DB - always pass so traces stay complete),
  and health-probe/metrics-scrape spans and log lines are dropped. Tune or
  disable this with the `clickstack.collector.filters` values (see
  [charts/clickstack/values.yaml](../../charts/clickstack/values.yaml)).

## Saved searches

HyperDX has no seeding mechanism for saved searches; create them once in the
UI (run the query, then **Save**). Useful starters:

| Name | Source | Query |
| --- | --- | --- |
| Decision API errors | Distributed Traces | `StatusCode:Error` |
| Slow decisions (>1s) | Distributed Traces | `Duration:>1000000000` |
| HPS errors and timeouts | Operational Logs | `ServiceName:rulebricks-hps AND (SeverityText:ERROR OR Body:timeout OR Body:kafka_unavailable)` |
| Worker errors | Operational Logs | `ServiceName:rulebricks-hps-worker AND (SeverityText:ERROR OR Body:error)` |
| All service errors | Operational Logs | `SeverityText:ERROR OR SeverityText:error OR level:error` |
| Find request by trace ID | Distributed Traces | `TraceId:<paste-trace-id>` |

## Dashboards

[dashboards/rulebricks-api-overview.json](dashboards/rulebricks-api-overview.json)
is a starter dashboard: decision API throughput, p95 latency, error spans, and
per-service log errors.

Dashboard tiles reference sources by their per-install database ID, so the
JSON ships with placeholders. To use it:

1. Get your source IDs (personal API key is under **Team Settings → API Keys**):

   ```bash
   curl -s -H "Authorization: Bearer <personal-api-key>" \
     https://observability.<your-domain>/api/v2/sources | jq '.[] | {name, id}'
   ```

2. Substitute the placeholders:

   ```bash
   sed -e 's/__TRACES_SOURCE_ID__/<distributed-traces-id>/' \
       -e 's/__LOGS_SOURCE_ID__/<operational-logs-id>/' \
       dashboards/rulebricks-api-overview.json > rulebricks-api-overview.json
   ```

3. Load it, either by hand (recreate the tiles in **Dashboards → New**) or with
   HyperDX's file provisioner, which syncs every `*.json` in a directory as a
   managed dashboard. Mount the substituted file into the HyperDX pod and set
   (via the `clickstack.hyperdx.env` value):

   ```yaml
   hyperdx:
     env:
       - name: DASHBOARD_PROVISIONER_DIR
         value: /etc/hyperdx/dashboards
       - name: DASHBOARD_PROVISIONER_ALL_TEAMS
         value: "true"
   ```

   Provisioned dashboards are upserted by name and marked as provisioned;
   user-created dashboards are never touched.
