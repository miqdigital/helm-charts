{{/*
Chart name, optionally overridden by nameOverride.
*/}}
{{- define "akto-central-setup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name. Every resource in this chart is named
"<fullname>-<component>" so the release name alone is enough to find anything.
*/}}
{{- define "akto-central-setup.fullname" -}}
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

{{- define "akto-central-setup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of a single component's resources, e.g. "akto-central-setup-dashboard".
Usage: {{ include "akto-central-setup.componentName" (list . "dashboard") }}
*/}}
{{- define "akto-central-setup.componentName" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{- printf "%s-%s" (include "akto-central-setup.fullname" $ctx) $component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels shared by every object in the chart.
*/}}
{{- define "akto-central-setup.labels" -}}
helm.sh/chart: {{ include "akto-central-setup.chart" . }}
{{ include "akto-central-setup.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: akto
{{- end }}

{{- define "akto-central-setup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akto-central-setup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Per-component label sets.
Usage: {{ include "akto-central-setup.componentLabels" (list . "dashboard") }}
*/}}
{{- define "akto-central-setup.componentLabels" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "akto-central-setup.labels" $ctx }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{- define "akto-central-setup.componentSelectorLabels" -}}
{{- $ctx := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "akto-central-setup.selectorLabels" $ctx }}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{- define "akto-central-setup.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akto-central-setup.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Shared env blocks. These exist so Mongo/Elasticsearch wiring is written once
and consumed identically by every component - the old charts each had their
own copy, which is how they drifted apart.
------------------------------------------------------------------------------
*/}}

{{/*
AKTO_MONGO_CONN, always sourced from Key Vault. global.mongo.x509 only gates
a fail-fast check here - the actual x509 connection-string parameters
("authMechanism=MONGODB-X509&tls=true") have to be part of the value you sync
into Key Vault, since the chart never sees the plaintext string to rewrite it.
*/}}
{{- define "akto-central-setup.mongoEnv" -}}
{{- if and .Values.global.mongo.x509 (not .Values.global.tls.enabled) }}
{{- fail "global.mongo.x509=true requires global.tls.enabled=true - the client certificate has to be mounted for MONGODB-X509 to work" }}
{{- end }}
- name: AKTO_MONGO_CONN
  {{- include "akto-central-setup.mongoSecretKeyRef" . | nindent 2 }}
{{- end }}

{{/*
Just the valueFrom block, reused by threat-backend.yaml for
AKTO_THREAT_PROTECTION_MONGO_CONN (same underlying secret, different env var
name).
*/}}
{{- define "akto-central-setup.mongoSecretKeyRef" -}}
valueFrom:
  secretKeyRef:
    name: {{ .Values.global.keyVault.secretName }}
    key: {{ .Values.global.mongo.secretKey | default "aktoMongoConn" }}
{{- end }}

{{/*
Elasticsearch env. Emitted by dashboard and database-abstractor, which are the
only two processes that talk to ES. ES_HOST/ES_API_KEY always come from Key
Vault - sync an empty string for esHost to disable ES-backed features.
*/}}
{{- define "akto-central-setup.elasticsearchEnv" -}}
- name: SEARCH_BACKEND
  value: {{ quote .Values.global.elasticsearch.searchBackend }}
- name: ES_INDEX_AGENT_QUERY
  value: {{ .Values.global.elasticsearch.indexAgentQuery | default "agent_query_logs" | quote }}
- name: ES_HOST
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ .Values.global.elasticsearch.esHostSecretKey | default "esHost" }}
      optional: true
- name: ES_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ .Values.global.elasticsearch.esApiKeySecretKey | default "esApiKey" }}
      optional: true
{{- end }}

{{/*
Env shared by every Akto JVM component.
*/}}
{{- define "akto-central-setup.commonEnv" -}}
- name: IS_KUBERNETES
  value: "true"
- name: AKTO_ACCOUNT_NAME
  value: {{ quote .Values.global.accountName }}
- name: AKTO_CONFIG_NAME
  value: {{ quote .Values.global.configName }}
- name: KUBERNETES_CLUSTER_DOMAIN
  value: {{ quote .Values.global.kubernetesClusterDomain }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Certificate-based auth (x509 / mutual TLS) to Mongo and Elasticsearch.

The Mongo Java driver and the OkHttp client the Elasticsearch code uses both
read TLS material from the JVM's default SSLContext, so pointing the standard
javax.net.ssl.* system properties at a mounted keystore is enough to get client
certificates presented on both connections. Nothing in the application changes.
------------------------------------------------------------------------------
*/}}

{{- define "akto-central-setup.tls.enabled" -}}
{{- if .Values.global.tls.enabled -}}
true
{{- end -}}
{{- end }}

{{/*
Absolute paths of the stores the JVM will load. For the pem format the init
container writes them into an emptyDir at the same mount path.
*/}}
{{- define "akto-central-setup.tls.keystorePath" -}}
{{- $t := .Values.global.tls -}}
{{- if eq $t.format "pem" -}}
{{- printf "%s/keystore.p12" $t.mountPath -}}
{{- else -}}
{{- printf "%s/%s" $t.mountPath $t.keystoreKey -}}
{{- end -}}
{{- end }}

{{- define "akto-central-setup.tls.truststorePath" -}}
{{- $t := .Values.global.tls -}}
{{- if eq $t.format "pem" -}}
{{- printf "%s/truststore.p12" $t.mountPath -}}
{{- else -}}
{{- printf "%s/%s" $t.mountPath $t.truststoreKey -}}
{{- end -}}
{{- end }}

{{- define "akto-central-setup.tls.storeType" -}}
{{- if eq .Values.global.tls.format "jks" -}}
JKS
{{- else -}}
PKCS12
{{- end -}}
{{- end }}

{{/*
Password env vars, always sourced from Key Vault - kept as their own
variables so the JVM options string can interpolate them with $(VAR) instead
of embedding the secret in the manifest.
*/}}
{{- define "akto-central-setup.tls.passwordEnv" -}}
{{- $t := .Values.global.tls -}}
- name: AKTO_TLS_KEYSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ $t.keystorePasswordKey | default "tlsKeystorePassword" }}
- name: AKTO_TLS_TRUSTSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.global.keyVault.secretName }}
      key: {{ $t.truststorePasswordKey | default "tlsTruststorePassword" }}
{{- end }}

{{/*
Full TLS env block: passwords plus the JVM options that activate them.
*/}}
{{- define "akto-central-setup.tls.env" -}}
{{- if include "akto-central-setup.tls.enabled" . }}
{{- $t := .Values.global.tls }}
{{- include "akto-central-setup.tls.passwordEnv" . }}
- name: {{ $t.javaOptsEnvVar }}
  value: >-
    -Djavax.net.ssl.keyStore={{ include "akto-central-setup.tls.keystorePath" . }}
    -Djavax.net.ssl.keyStoreType={{ include "akto-central-setup.tls.storeType" . }}
    -Djavax.net.ssl.keyStorePassword=$(AKTO_TLS_KEYSTORE_PASSWORD)
    -Djavax.net.ssl.trustStore={{ include "akto-central-setup.tls.truststorePath" . }}
    -Djavax.net.ssl.trustStoreType={{ include "akto-central-setup.tls.storeType" . }}
    -Djavax.net.ssl.trustStorePassword=$(AKTO_TLS_TRUSTSTORE_PASSWORD)
    {{- with $t.extraJavaOpts }} {{ . }}{{ end }}
{{- end }}
{{- end }}

{{/*
Init container that turns PEM material into a PKCS12 keystore and truststore.
Only rendered for format: pem.
*/}}
{{- define "akto-central-setup.tls.initContainers" -}}
{{- if and (include "akto-central-setup.tls.enabled" .) (eq .Values.global.tls.format "pem") }}
{{- $t := .Values.global.tls }}
- name: tls-cert-converter
  image: "{{ $t.pem.image.repository }}:{{ $t.pem.image.tag }}"
  imagePullPolicy: {{ $t.pem.image.pullPolicy }}
  command: ["/bin/sh", "-c"]
  args:
    - |
      set -e
      echo "Building PKCS12 stores from PEM material..."

      # Client keystore: certificate + private key.
      openssl pkcs12 -export \
        -in /tls-pem/{{ $t.pem.certKey }} \
        -inkey /tls-pem/{{ $t.pem.keyKey }} \
        -name akto-client \
        -out {{ $t.mountPath }}/keystore.p12 \
        -passout pass:"$AKTO_TLS_KEYSTORE_PASSWORD"

      {{- if $t.includeSystemCAs }}
      # Start from the JDK's CA bundle so publicly-signed endpoints keep
      # working, then add the private CA to it.
      SYS_CACERTS="$JAVA_HOME/lib/security/cacerts"
      cp "$SYS_CACERTS" {{ $t.mountPath }}/truststore.p12
      keytool -storepasswd -noprompt \
        -keystore {{ $t.mountPath }}/truststore.p12 \
        -storepass changeit \
        -new "$AKTO_TLS_TRUSTSTORE_PASSWORD" 2>/dev/null || true
      {{- end }}

      keytool -importcert -noprompt \
        -alias akto-db-ca \
        -file /tls-pem/{{ $t.pem.caKey }} \
        -keystore {{ $t.mountPath }}/truststore.p12 \
        -storetype PKCS12 \
        -storepass "$AKTO_TLS_TRUSTSTORE_PASSWORD"

      # This container runs as root but the application containers do not
      # (the Akto images run as an unprivileged user). openssl creates the
      # keystore 0600/root, which the app then cannot read - and the JVM
      # reports that as "Unable to create default SSLContext" rather than a
      # permission error. Widen it to match how Kubernetes mounts Secret
      # volumes; the file never leaves this pod's emptyDir.
      chmod {{ $t.storeFileMode }} {{ $t.mountPath }}/keystore.p12 {{ $t.mountPath }}/truststore.p12

      echo "Wrote keystore.p12 and truststore.p12 to {{ $t.mountPath }}"
      ls -l {{ $t.mountPath }}
  env:
    {{- include "akto-central-setup.tls.passwordEnv" . | nindent 4 }}
  volumeMounts:
  - name: tls-pem
    mountPath: /tls-pem
    readOnly: true
  - name: tls-stores
    mountPath: {{ $t.mountPath }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Volumes. One place emits both the Key Vault CSI volume and the TLS material, so
component templates never have to reason about which combination is active.
------------------------------------------------------------------------------
*/}}
{{- define "akto-central-setup.volumeMounts" -}}
- name: secrets-store
  mountPath: /mnt/secrets-store
  readOnly: true
{{- if include "akto-central-setup.tls.enabled" . }}
- name: tls-stores
  mountPath: {{ .Values.global.tls.mountPath }}
  readOnly: {{ ne .Values.global.tls.format "pem" }}
{{- end }}
{{- end }}

{{- define "akto-central-setup.volumes" -}}
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ .Values.global.keyVault.secretProviderClass }}
{{- if include "akto-central-setup.tls.enabled" . }}
{{- $t := .Values.global.tls }}
{{- if eq $t.format "pem" }}
# Raw PEM from the Secret, plus a scratch dir the init container writes the
# converted Java stores into.
- name: tls-pem
  secret:
    secretName: {{ $t.secretName }}
- name: tls-stores
  emptyDir: {}
{{- else }}
- name: tls-stores
  secret:
    secretName: {{ $t.secretName }}
{{- end }}
{{- end }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Database-abstractor write-scaling pipeline (Kafka producer/consumer split).
------------------------------------------------------------------------------
*/}}

{{/*
Kafka broker Service address for the write pipeline.
*/}}
{{- define "akto-central-setup.writePipeline.kafkaBrokerUrl" -}}
{{- printf "%s:9092" (include "akto-central-setup.componentName" (list . "database-abstractor-kafka")) -}}
{{- end }}

{{/*
Env shared by every write-pipeline pod - deliberately everything commonEnv
sets EXCEPT IS_KUBERNETES. See the comment on databaseAbstractor.writePipeline
in values.yaml for why: the app's Kafka client hardcodes the broker address to
a same-pod sidecar whenever IS_KUBERNETES=true, which breaks a standalone
broker shared across producer + consumer pods.
*/}}
{{- define "akto-central-setup.writePipeline.commonEnv" -}}
- name: AKTO_ACCOUNT_NAME
  value: {{ quote .Values.global.accountName }}
- name: AKTO_CONFIG_NAME
  value: {{ quote .Values.global.configName }}
- name: KUBERNETES_CLUSTER_DOMAIN
  value: {{ quote .Values.global.kubernetesClusterDomain }}
{{- end }}

{{/*
------------------------------------------------------------------------------
Service URLs. These are what remove the manual --set commands: any component
that needs to reach another one resolves it from here instead of the operator
pasting an FQDN.
------------------------------------------------------------------------------
*/}}

{{- define "akto-central-setup.threatBackend.url" -}}
{{- printf "http://%s.%s.svc.%s:%v" (include "akto-central-setup.componentName" (list . "threat-backend")) .Release.Namespace .Values.global.kubernetesClusterDomain .Values.threatBackend.service.httpPort -}}
{{- end }}

{{- define "akto-central-setup.databaseAbstractor.url" -}}
{{- printf "http://%s.%s.svc.%s:%v" (include "akto-central-setup.componentName" (list . "database-abstractor")) .Release.Namespace .Values.global.kubernetesClusterDomain .Values.databaseAbstractor.service.port -}}
{{- end }}

{{/*
Threat backend URL the dashboard should call. An explicit override wins;
otherwise it points at the in-chart threat backend when that is enabled, and
finally falls back to Akto SaaS.
*/}}
{{- define "akto-central-setup.dashboard.threatBackendUrl" -}}
{{- if .Values.dashboard.env.threatDetectionBackendUrl -}}
{{- .Values.dashboard.env.threatDetectionBackendUrl -}}
{{- else if .Values.threatBackend.enabled -}}
{{- include "akto-central-setup.threatBackend.url" . -}}
{{- else -}}
https://tbs.akto.io
{{- end -}}
{{- end }}
