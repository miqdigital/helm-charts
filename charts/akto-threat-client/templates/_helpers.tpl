{{/*
Expand the name of the chart.
*/}}
{{- define "akto.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "akto.fullname" -}}
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
{{- define "akto.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akto.labels" -}}
helm.sh/chart: {{ include "akto.chart" . }}
{{ include "akto.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akto.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "akto.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akto.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Broker carrying the malicious-event buffer that the guardrail forwarder drains.

Explicit override wins; then the external cluster when useExternalKafka is set;
otherwise the bundled kafka1 sidecar, reached through the threat-client Service.
The port mirrors the KAFKA_ADVERTISED_LISTENERS branches in deployment.yaml -
the sidecar advertises a cluster-DNS listener alongside localhost, which is what
makes it reachable from the forwarder's own pod at all.
*/}}
{{- define "akto.guardrailForwarder.broker" -}}
{{- $tc := .Values.threat_client -}}
{{- if $tc.guardrailForwarder.kafkaBrokerUrl -}}
{{- $tc.guardrailForwarder.kafkaBrokerUrl -}}
{{- else if $tc.useExternalKafka -}}
{{- if $tc.externalKafka.brokerUrl -}}
{{- $tc.externalKafka.brokerUrl -}}
{{- else -}}
{{- fail "threat_client.guardrailForwarder.enabled=true with useExternalKafka=true but no externalKafka.brokerUrl - set it, or set guardrailForwarder.kafkaBrokerUrl" -}}
{{- end -}}
{{- else -}}
{{- $host := printf "%s-threat-client.%s.svc.%s" (include "akto.fullname" .) .Release.Namespace .Values.kubernetesClusterDomain -}}
{{- if and $tc.kafka1.useSasl $tc.kafka1.useTls -}}
{{- printf "%s:%v" $host (index .Values.ports.sasl 1).port -}}
{{- else if $tc.kafka1.useSasl -}}
{{- printf "%s:%v" $host (index .Values.ports.sasl 0).port -}}
{{- else if $tc.kafka1.useTls -}}
{{- printf "%s:%v" $host (index .Values.ports.tls 0).port -}}
{{- else -}}
{{- printf "%s:%v" $host (index .Values.ports.default 0).port -}}
{{- end -}}
{{- end -}}
{{- end }}
