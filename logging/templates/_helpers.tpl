{{/* Namespace every resource in this chart lands in. */}}
{{- define "logging.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name -}}
{{- end -}}

{{/* Labels shared by every object in the chart. */}}
{{- define "logging.labels" -}}
app.kubernetes.io/part-of: logging
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "loki.selectorLabels" -}}
app: {{ .Values.loki.name }}
app.kubernetes.io/name: {{ .Values.loki.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "fluentBit.selectorLabels" -}}
app: {{ .Values.fluentBit.name }}
app.kubernetes.io/name: {{ .Values.fluentBit.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "grafana.selectorLabels" -}}
app: {{ .Values.grafana.name }}
app.kubernetes.io/name: {{ .Values.grafana.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* In-cluster address Fluent Bit and Grafana use to reach Loki. */}}
{{- define "loki.url" -}}
http://{{ .Values.loki.name }}.{{ include "logging.namespace" . }}.svc.cluster.local:{{ .Values.loki.service.httpPort }}
{{- end -}}

{{/* Object store backing the schema and compactor. */}}
{{- define "loki.objectStore" -}}
{{- if eq .Values.loki.storage.type "s3" -}}s3{{- else -}}filesystem{{- end -}}
{{- end -}}

{{/* Name of the secret holding the Grafana admin credentials. */}}
{{- define "grafana.secretName" -}}
{{- if .Values.grafana.existingSecret -}}
{{- .Values.grafana.existingSecret -}}
{{- else -}}
{{- .Values.grafana.name }}-admin
{{- end -}}
{{- end -}}
