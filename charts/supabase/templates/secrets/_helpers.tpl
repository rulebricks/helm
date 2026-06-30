{{/*
Expand the name of the JWT secret.
*/}}
{{- define "supabase.secret.jwt" -}}
{{- printf "%s-jwt" (include "supabase.fullname" .) }}
{{- end -}}

{{/*
Expand the name of the SMTP secret.
*/}}
{{- define "supabase.secret.smtp" -}}
{{- printf "%s-smtp" (include "supabase.fullname" .) }}
{{- end -}}

{{/*
Expand the name of the dashboard secret.
*/}}
{{- define "supabase.secret.dashboard" -}}
{{- printf "%s-dashboard" (include "supabase.fullname" .) }}
{{- end -}}

{{/*
Expand the name of the database secret.
*/}}
{{- define "supabase.secret.db" -}}
{{- printf "%s-db" (include "supabase.fullname" .) }}
{{- end -}}

{{/*
Expand the name of the realtime secret (SECRET_KEY_BASE / DB_ENC_KEY).
*/}}
{{- define "supabase.secret.realtime" -}}
{{- printf "%s-realtime" (include "supabase.fullname" .) }}
{{- end -}}
