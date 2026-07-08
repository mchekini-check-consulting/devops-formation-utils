{{- define "pgcat.labels" -}}
app: {{ .Chart.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "pgcat.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}
