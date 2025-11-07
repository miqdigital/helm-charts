{{/*
Expand the name of the chart.
*/}}
{{- define "grafana-cloud-setup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "grafana-cloud-setup.fullname" -}}
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
{{- define "grafana-cloud-setup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "grafana-cloud-setup.labels" -}}
helm.sh/chart: {{ include "grafana-cloud-setup.chart" . }}
{{ include "grafana-cloud-setup.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "grafana-cloud-setup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana-cloud-setup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "grafana-cloud-setup.serviceAccountName" -}}
{{- if .Values.alloy.serviceAccount.create }}
{{- default (include "grafana-cloud-setup.fullname" .) .Values.alloy.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.alloy.serviceAccount.name }}
{{- end }}
{{- end }}
