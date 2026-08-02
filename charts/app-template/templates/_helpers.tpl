{{- define "app.name" -}}
{{ required "app.name is required" .Values.app.name }}
{{- end -}}

{{- define "app.labels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/managed-by: argocd
app.kubernetes.io/part-of: vendor-platform
team: {{ required "app.team is required" .Values.app.team }}
{{- end -}}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
{{- end -}}
