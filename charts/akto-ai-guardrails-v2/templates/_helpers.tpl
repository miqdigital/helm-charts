{{/*
Expand the name of the chart.
*/}}
{{- define "akto-ai-guardrails-v2.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "akto-ai-guardrails-v2.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "akto-ai-guardrails-v2.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akto-ai-guardrails-v2.labels" -}}
helm.sh/chart: {{ include "akto-ai-guardrails-v2.chart" . }}
{{ include "akto-ai-guardrails-v2.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akto-ai-guardrails-v2.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto-ai-guardrails-v2.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "akto-ai-guardrails-v2.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akto-ai-guardrails-v2.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Per-component label/selector helpers. Each component gets an
app.kubernetes.io/component label so `kubectl get pods -l component=X` works.
*/}}
{{- define "akto-ai-guardrails-v2.componentLabels" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "akto-ai-guardrails-v2.labels" $ctx }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{- define "akto-ai-guardrails-v2.componentSelectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "akto-ai-guardrails-v2.selectorLabels" $ctx }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{/*
Cross-service DNS helpers, so components can find each other without the user
having to hand-compute release-prefixed Service names.
*/}}
{{- define "akto-ai-guardrails-v2.anonymizer.url" -}}
http://{{ include "akto-ai-guardrails-v2.fullname" . }}-anonymizer:{{ .Values.anonymizer.service.port }}
{{- end }}

{{- define "akto-ai-guardrails-v2.embedder.url" -}}
http://{{ include "akto-ai-guardrails-v2.fullname" . }}-embedder:{{ .Values.embedder.service.port }}
{{- end }}

{{- define "akto-ai-guardrails-v2.agentGuard.url" -}}
http://{{ include "akto-ai-guardrails-v2.fullname" . }}-agent-guard:{{ .Values.agentGuard.service.port }}
{{- end }}

{{- define "akto-ai-guardrails-v2.redis.host" -}}
{{ include "akto-ai-guardrails-v2.fullname" . }}-redis
{{- end }}

{{- define "akto-ai-guardrails-v2.redis.secretName" -}}
{{- if .Values.redis.auth.existingSecret -}}
{{ .Values.redis.auth.existingSecret }}
{{- else -}}
{{ include "akto-ai-guardrails-v2.fullname" . }}-redis-auth
{{- end }}
{{- end }}

{{- define "akto-ai-guardrails-v2.guardrailsKafka.brokerUrl" -}}
{{ include "akto-ai-guardrails-v2.fullname" . }}-guardrails-kafka:9092
{{- end }}
