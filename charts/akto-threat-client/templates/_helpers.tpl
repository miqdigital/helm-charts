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
Broker carrying the malicious-event buffer. Falls back to the bundled kafka1
sidecar via the threat-client Service; the port mirrors the
KAFKA_ADVERTISED_LISTENERS branches in deployment.yaml.
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

{{/*
Threat backend token for the guardrail forwarder: Key Vault, then an existing
Secret, then a plain value - the same order deployment.yaml uses.
*/}}
{{- define "akto.guardrailForwarder.backendTokenEnv" -}}
{{- $env := .Values.threat_client.aktoApiSecurityThreatClient.env -}}
- name: AKTO_THREAT_PROTECTION_BACKEND_TOKEN
{{- if .Values.keyVault.enabled }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.keyVault.secretName }}
      key: {{ .Values.keyVault.secretKeys.databaseAbstractorToken }}
{{- else if $env.useSecretsForDatabaseAbstractorToken }}
  valueFrom:
    secretKeyRef:
      key: token
      name: {{ (tpl $env.databaseAbstractorTokenSecrets.existingSecret .) | default (printf "%s-threat-client" (include "akto.fullname" .)) }}
{{- else }}
  value: {{ quote $env.databaseAbstractorToken }}
{{- end }}
{{- end }}

{{/*
Kafka SASL env for the guardrail forwarder. AKTO_KAFKA_* are the names
KafkaConfig.addAuthenticationFromEnv actually reads - the forwarder is Java, so
GUARDRAILS_THREAT_CLIENT_* names would be ignored. Credential source mirrors
deployment.yaml: Key Vault, then an existing Secret, then a plain value.
*/}}
{{- define "akto.guardrailForwarder.kafkaAuthEnv" -}}
{{- $tc := .Values.threat_client -}}
{{- if or $tc.kafka1.useSasl (and $tc.useExternalKafka $tc.externalKafka.username) }}
- name: AKTO_KAFKA_SASL_ENABLED
  value: "true"
- name: AKTO_KAFKA_SASL_MECHANISM
  value: {{ if $tc.useExternalKafka }}{{ quote $tc.externalKafka.saslMechanism }}{{ else }}{{ quote $tc.kafka1.env.saslMechanism }}{{ end }}
{{- if $tc.useExternalKafka }}
- name: AKTO_KAFKA_SECURITY_PROTOCOL
  value: {{ quote $tc.externalKafka.securityProtocol }}
{{- end }}
{{- if .Values.keyVault.enabled }}
- name: AKTO_KAFKA_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.keyVault.secretName }}
      key: {{ .Values.keyVault.secretKeys.kafkaSaslUsername }}
- name: AKTO_KAFKA_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.keyVault.secretName }}
      key: {{ .Values.keyVault.secretKeys.kafkaSaslPassword }}
{{- else if and $tc.kafka1.useSasl $tc.kafka1.env.useSecretsForSaslCredentials }}
{{- $secret := $tc.kafka1.env.saslCredentialsSecrets.existingSecret | default (printf "%s-threat-client-sasl" (include "akto.fullname" .)) }}
- name: AKTO_KAFKA_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: username
- name: AKTO_KAFKA_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: password
{{- else }}
- name: AKTO_KAFKA_USERNAME
  value: {{ if $tc.useExternalKafka }}{{ quote $tc.externalKafka.username }}{{ else }}{{ quote $tc.kafka1.env.saslUsername }}{{ end }}
- name: AKTO_KAFKA_PASSWORD
  value: {{ if $tc.useExternalKafka }}{{ quote $tc.externalKafka.password }}{{ else }}{{ quote $tc.kafka1.env.saslPassword }}{{ end }}
{{- end }}
{{- end }}
{{- end }}

{{/* Pod scheduling, shared shape across deployments. */}}
{{- define "akto.scheduling" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* Key Vault CSI mount; empty when Key Vault is off. */}}
{{- define "akto.keyVault.volumeMounts" -}}
{{- if .Values.keyVault.enabled }}
volumeMounts:
- name: secrets-store
  mountPath: /mnt/secrets-store
  readOnly: true
{{- end }}
{{- end }}

{{- define "akto.keyVault.volumes" -}}
{{- if .Values.keyVault.enabled }}
volumes:
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ .Values.keyVault.secretProviderClass | default "akto-keyvault" }}
{{- end }}
{{- end }}
