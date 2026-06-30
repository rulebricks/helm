{{/*
Self-hosted single-node ClickHouse on Docker Hardened Images. Replaces the
vendored Bitnami clickhouse subchart. The decision-log config (named collections,
query limits, user access, the decision_logs view SQL) is shared with the CLI via
the helpers in _defaults.tpl.
*/}}

{{- define "rulebricks.clickhouse.fullname" -}}
{{- printf "%s-clickhouse" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rulebricks.clickhouse.selectorLabels" -}}
app.kubernetes.io/name: clickhouse
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rulebricks.clickhouse.labels" -}}
app.kubernetes.io/name: clickhouse
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: clickhouse
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- /* The decision-log XML/SQL helpers were written for the Bitnami subchart
       context where .Values is the clickhouse values and .Values.global is the
       shared global. Rebuild that context from the parent so the helpers resolve
       .Values.auth / .Values.queryLimits / .Values.global.storage correctly.
       Returns nothing usable directly (include returns a string) - call the
       pattern inline; this define documents the shape. */ -}}

{{- define "rulebricks.clickhouse.credentialSecret" -}}
{{- if .Values.clickhouse.auth.existingSecret -}}
{{- tpl .Values.clickhouse.auth.existingSecret . -}}
{{- else -}}
{{- printf "%s-clickhouse-credentials" .Release.Name -}}
{{- end -}}
{{- end -}}
