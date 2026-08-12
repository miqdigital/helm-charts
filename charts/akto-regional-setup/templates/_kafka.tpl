{{/*
==============================================================================
Shared Kafka building blocks.

The old charts each carried their own copy of the broker container and the
client-side SASL env, which is how mini-runtime, threat-client and
data-ingestion drifted apart. There is one implementation here instead.
==============================================================================
*/}}

{{/*
A single-node KRaft broker sidecar.

Two listeners:
  LISTENER_DOCKER_EXTERNAL_LOCALHOST  localhost:29092  - the app in this pod
  LISTENER_DOCKER_EXTERNAL_DIFFHOST   <service>:<port> - other pods

Usage:
  {{ include "akto-regional-setup.kafka.brokerContainer" (list $ctx "mini-runtime" $ctx.Values.miniRuntime.kafka $port) }}
*/}}
{{- define "akto-regional-setup.kafka.brokerContainer" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{- $kafka := index . 2 -}}
{{- $port := index . 3 -}}
{{- $host := include "akto-regional-setup.svcHost" (list $ctx $component) -}}
- name: kafka1
  image: "{{ $kafka.image.repository }}:{{ $kafka.image.tag }}"
  imagePullPolicy: {{ $kafka.image.pullPolicy }}
  ports:
  - name: kafka
    containerPort: {{ $port }}
  - name: kafka-local
    containerPort: 29092
  - name: kafka-ctrl
    containerPort: 9093
  env:
  - name: MY_POD_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: KAFKA_ADVERTISED_LISTENERS
    value: "LISTENER_DOCKER_EXTERNAL_LOCALHOST://localhost:29092,LISTENER_DOCKER_EXTERNAL_DIFFHOST://{{ $host }}:{{ $port }}"
  - name: KAFKA_LISTENERS
    value: "CONTROLLER://0.0.0.0:9093,LISTENER_DOCKER_EXTERNAL_LOCALHOST://0.0.0.0:29092,LISTENER_DOCKER_EXTERNAL_DIFFHOST://0.0.0.0:{{ $port }}"
  - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
    value: "CONTROLLER:PLAINTEXT,LISTENER_DOCKER_EXTERNAL_LOCALHOST:PLAINTEXT,LISTENER_DOCKER_EXTERNAL_DIFFHOST:PLAINTEXT"
  - name: KAFKA_INTER_BROKER_LISTENER_NAME
    value: "LISTENER_DOCKER_EXTERNAL_LOCALHOST"
  - name: KAFKA_CONTROLLER_LISTENER_NAMES
    value: "CONTROLLER"
  - name: KAFKA_CONTROLLER_QUORUM_VOTERS
    value: "1@localhost:9093"
  - name: KAFKA_PROCESS_ROLES
    value: "broker,controller"
  - name: KAFKA_NODE_ID
    value: "1"
  - name: KAFKA_BROKER_ID
    value: "1"
  - name: CLUSTER_ID
    value: {{ quote $kafka.clusterId }}
  - name: KAFKA_CREATE_TOPICS
    value: {{ quote $kafka.createTopics }}
  - name: KAFKA_CLEANUP_POLICY
    value: "delete"
  - name: KAFKA_LOG_CLEANER_ENABLE
    value: "true"
  - name: KAFKA_LOG_RETENTION_HOURS
    value: {{ quote $kafka.logRetentionHours }}
  - name: KAFKA_LOG_RETENTION_BYTES
    value: "10737418240"
  - name: KAFKA_LOG_RETENTION_CHECK_INTERVAL_MS
    value: "60000"
  - name: KAFKA_LOG_SEGMENT_BYTES
    value: "104857600"
  - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
    value: "1"
  - name: KAFKA_TRANSACTION_STATE_LOG_MIN_ISR
    value: "1"
  - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
    value: "1"
  - name: KUBERNETES_CLUSTER_DOMAIN
    value: {{ quote $ctx.Values.global.kubernetesClusterDomain }}
  resources:
    {{- toYaml $kafka.resources | nindent 4 }}
{{- end }}

{{/*
Client-side SASL env for talking to an EXTERNAL Kafka. Emits nothing when the
component uses its bundled broker or when saslEnabled is false. Credentials
always come from Key Vault - usernameKey/passwordKey name the keys inside
global.keyVault.secretName holding them.

Usage: {{ include "akto-regional-setup.kafka.clientSaslEnv" (list $ctx $ctx.Values.miniRuntime.external) }}
*/}}
{{- define "akto-regional-setup.kafka.clientSaslEnv" -}}
{{- $ctx := index . 0 -}}
{{- $ext := index . 1 -}}
{{- if and $ext.enabled $ext.saslEnabled }}
- name: KAFKA_AUTH_ENABLED
  value: "true"
- name: AKTO_KAFKA_SASL_ENABLED
  value: "true"
- name: AKTO_KAFKA_SASL_MECHANISM
  value: {{ quote $ext.saslMechanism }}
- name: AKTO_KAFKA_SECURITY_PROTOCOL
  value: {{ quote $ext.securityProtocol }}
{{- range $envName := list "KAFKA_USERNAME" "AKTO_KAFKA_USERNAME" }}
- name: {{ $envName }}
  valueFrom:
    secretKeyRef:
      name: {{ $ctx.Values.global.keyVault.secretName }}
      key: {{ $ext.usernameKey }}
{{- end }}
{{- range $envName := list "KAFKA_PASSWORD" "AKTO_KAFKA_PASSWORD" }}
- name: {{ $envName }}
  valueFrom:
    secretKeyRef:
      name: {{ $ctx.Values.global.keyVault.secretName }}
      key: {{ $ext.passwordKey }}
{{- end }}
{{- end }}
{{- end }}
