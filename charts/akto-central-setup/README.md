# Akto Central Cloud

One chart for everything that runs in the central cloud:

| Component | What it does | Port |
|---|---|---|
| `dashboard` | The Akto UI and API | 8080 |
| `database-abstractor` | Data access layer regional clusters write through | 9000 |
| `threat-backend` | Threat detection API + its own Kafka broker | 9090 (API), 9092 (Kafka) |

This replaces installing `akto-dashboard`, `akto-dbabs` and `akto-threat-backend`
separately and then hand-wiring them together.

## Install

Every secret this chart needs - the Mongo connection string, and optionally
Elasticsearch's host/API key and the mTLS keystore/truststore passwords -
comes from Azure Key Vault. There is no plaintext-connection-string install
path and no bring-your-own-Kubernetes-Secret option: create a
SecretProviderClass named `akto-keyvault` first (see your Key Vault setup
docs) that syncs at least an `aktoMongoConn` key into a Secret, then:

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts
helm repo update akto

helm install akto-central-setup akto/akto-central-setup -n akto --create-namespace
```

That is the whole install - no flags. mTLS to Mongo (`global.tls.enabled`,
`global.mongo.x509`) and the SecretProviderClass name (`akto-keyvault`) are
already this chart's defaults; see
[Certificate auth to Mongo and Elasticsearch](#certificate-auth-to-mongo-and-elasticsearch)
if you need to turn mTLS off instead. There is no second command to point the
dashboard at the threat backend either — see [Auto-wiring](#auto-wiring).

If your SecretProviderClass is named something other than `akto-keyvault`, or
syncs into a Secret with a name other than the default `akto-secrets`, or your
`aktoMongoConn` key is named something other than `aktoMongoConn`:

```bash
helm install akto-central-setup akto/akto-central-setup -n akto --create-namespace \
  --set global.keyVault.secretProviderClass=my-spc \
  --set global.keyVault.secretName=my-synced-secret \
  --set global.mongo.secretKey=myMongoConnKey
```

Verify:

```bash
kubectl get pods -n akto -l app.kubernetes.io/instance=akto-central-setup
```

Expect `dashboard` 1/1, `database-abstractor` 1/1, `threat-backend` 2/2 (the
second container is its Kafka broker).

## Required one-time setup: HYBRID_SAAS keypair

Dashboard ↔ threat backend calls are authenticated with a JWT signed by an RSA
keypair that lives in Mongo. Without it every call returns `401`. Insert it into
the shared Mongo's `common.configs` collection once:

```js
db.configs.insertOne({
  "_id": "HYBRID_SAAS",
  "_t": "com.akto.dto.Config$HybridSaasConfig",
  "configType": "HYBRID_SAAS",
  "privateKey": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "publicKey": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n"
})
```

The threat backend verifies inbound JWTs with the public key; the dashboard
signs outbound ones with the private key.

## Auto-wiring

Every cross-service URL is computed by the chart, so there are no follow-up
`--set` commands and no FQDNs to paste:

| Consumer | Variable | Resolved to |
|---|---|---|
| dashboard | `THREAT_DETECTION_BACKEND_URL` | the in-chart threat backend on 9090 |
| all three | `AKTO_MONGO_CONN` | `global.mongo.*`, once |
| dashboard, db-abstractor | `ES_HOST` / `ES_API_KEY` | `global.elasticsearch.*`, once - `ES_HOST` is computed by the chart when `elasticsearch.enabled` |

Override any of them if you need to point somewhere else, e.g. at Akto SaaS:

```bash
--set dashboard.env.threatDetectionBackendUrl=https://tbs.akto.io
```

## Certificate auth to Mongo and Elasticsearch (x509 / mTLS)

Replaces password and API-key access with client certificates. **No application
change is involved** — all three components are JVM services whose Mongo driver
(`applyConnectionString`) and HTTP client (OkHttp, default `SSLContext`) take TLS
material from the JVM's own keystore. The chart mounts the certificates and sets
the standard `javax.net.ssl.*` system properties.

### With PEM files (recommended - default)

Put a plain cert-manager-issued `tls.crt` / `tls.key` pair in a Secret named
`akto-db-certs` (this one holds the certificate *files* - it stays a plain
Kubernetes Secret, since it's mounted as files, not read as an env var), then
sync the passwords that will protect the *generated* Java stores into Key
Vault as `tlsKeystorePassword` / `tlsTruststorePassword`, and the
x509-enabled connection string as your `aktoMongoConn` value. This is already
the chart's default (`global.tls.enabled`/`global.mongo.x509`/
`global.tls.format` are all already set correctly, `global.tls.secretName` is
already `akto-db-certs`), so the install itself needs nothing extra:

```bash
helm install akto-central-setup akto/akto-central-setup -n akto
```

If you also want certificate auth to Elasticsearch instead of an API key
(off by default):

```bash
helm install akto-central-setup akto/akto-central-setup -n akto \
  --set global.elasticsearch.mutualTls=true
```

A plain cert-manager `Certificate` (no `keystores` block) emits exactly this
shape:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: akto-db-client, namespace: akto }
spec:
  secretName: akto-db-certs
  commonName: akto-client
  subject: { organizations: ["AktoClient"] }
  usages: ["client auth"]
  issuerRef: { name: your-ca-issuer, kind: ClusterIssuer }
```

An init container converts `tls.crt` / `tls.key` into a PKCS12
keystore/truststore at pod start, encrypted with the
`tlsKeystorePassword` / `tlsTruststorePassword` you sync into Key Vault -
cert-manager never sees or handles those passwords itself.

`global.tls.pem.caKey` is empty by default - only set it if you actually have
a custom CA to import into the truststore. Most managed Mongo/ES endpoints
(Atlas included) use publicly-trusted server TLS, so the truststore just
needs the JDK's own CA bundle, which the init container already builds
regardless. `certKey` and `keyKey` can also point at the *same* file if your
cert-provider hands you a combined cert+key PEM (the `openssl pkcs12 -export`
step accepts one file for both `-in` and `-inkey`).

### With ready-made Java keystores

Only relevant if your cert-manager `Certificate` sets
`keystores.pkcs12.create: true` to emit PKCS12 files itself instead of plain
PEM:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: akto-db-client, namespace: akto }
spec:
  secretName: akto-db-certs
  commonName: akto-client
  subject: { organizations: ["AktoClient"] }
  usages: ["client auth"]
  issuerRef: { name: your-ca-issuer, kind: ClusterIssuer }
  keystores:
    pkcs12:
      create: true
      passwordSecretRef: { name: akto-tls-pw, key: keystorePassword }
```

That Secret carries `keystore.p12` and `truststore.p12`, matching the chart's
`keystoreKey` / `truststoreKey` defaults. Whatever password you generate for
`akto-tls-pw` above also needs to be synced into Key Vault under
`tlsKeystorePassword` (and `tlsTruststorePassword`, if different) - the chart
reads both exclusively from there, never from `akto-tls-pw` directly. Switch
the chart to this format explicitly, since PEM is the default:

```bash
--set global.tls.format=pkcs12
```

### Turning mTLS off

If you want plain password auth to Mongo and an API key to Elasticsearch
instead (both are on by default):

```bash
helm install akto-central-setup akto/akto-central-setup -n akto \
  --set global.tls.enabled=false \
  --set global.mongo.x509=false
```
(`global.elasticsearch.mutualTls` is already `false` by default - nothing to
change there.) With `global.tls.enabled=false`, no `akto-db-certs` Secret is
required at all - just put a plain username/password connection string in
`aktoMongoConn`.

### What the chart does

- `global.mongo.x509=true` only fails the install fast if `global.tls.enabled`
  isn't also set — it does **not** rewrite your connection string. Put
  `authMechanism=MONGODB-X509&authSource=$external&tls=true` directly into the
  `aktoMongoConn` value you sync into Key Vault; the chart never sees the
  string in plaintext to append anything to it. `authSource` has to be
  exactly `$external` — the Mongo Java driver throws
  `IllegalArgumentException: Invalid authSource for MONGODB-X509` at startup
  otherwise (confirmed against a real Atlas cluster), it won't just fall back
  to a default.
- Injects the keystore/truststore passwords (from Key Vault, keys
  `tlsKeystorePassword`/`tlsTruststorePassword`) as their own env vars and
  references them from the JVM options with `$(VAR)`, so they are not literals
  in the rendered manifest.
- For Elasticsearch, sync an empty string for `esApiKey`: the client only sends
  an `Authorization` header when the key is non-empty, so the certificate
  becomes the sole credential.

### The truststore caveat

A JVM has **one** truststore and it is used for *every* outbound TLS connection,
not just the database. Handing it a truststore that contains only your private CA
will break calls to any publicly-signed endpoint.

`global.tls.includeSystemCAs` (default `true`, `pem` format) handles this: the
init container starts from the JDK's bundled CA list and adds your CA to it. If
you supply your own PKCS12 truststore instead, build it the same way — import
your CA into a copy of `$JAVA_HOME/lib/security/cacerts` rather than creating a
CA-only store.

### Verifying

```bash
kubectl logs -n akto <pod> -c tls-cert-converter          # conversion output
kubectl exec -n akto <pod> -- keytool -list \
  -keystore /etc/akto/tls/truststore.p12 -storepass <pw>  # should list your CA + system CAs
```

On the MongoDB side, a successful connection logs:

```
"msg":"Successfully authenticated","attr":{"user":"O=AktoClient,CN=akto-client",
"db":"$external","mechanism":"MONGODB-X509","client":"<akto-pod-ip>"}
```

> The Akto images run as an unprivileged user, so the generated stores are
> chmod'ed to `global.tls.storeFileMode` (`0644`, matching how Kubernetes mounts
> Secret volumes). A `0600` root-owned keystore surfaces as the JVM's unhelpful
> `Unable to create default SSLContext` rather than a permission error.

## Renaming the shared Mongo databases

Akto keeps two shared, non-account databases — `common` and `billing`. Both
names are configurable:

```bash
--set global.mongo.dbNames.common=akto_common \
--set global.mongo.dbNames.billing=akto_billing
```

Leave them empty (the default) and the applications use `common`/`billing`.
Account databases are named after the account id and are **not** configurable.

The chart stamps these onto **every** component from a single place, and that
is deliberate — see the warning below.

### Two things to get right

**Every component sharing a Mongo must get identical values.** That's why this
lives in `global` and is emitted from `commonEnv`, rather than being set
per-component. Setting it in one place is what makes the values consistent by
construction.

**An invalid name does not fail the install — it silently splits your data.**
Mongo rejects names over 63 characters or containing `/ \ . " $ * < > : | ?` or
spaces. Given one, the application logs an error and falls back to the built-in
default, then keeps running:

```
ERROR com.akto.util.DbNames - Ignoring env var AKTO_DB_NAME_COMMON:
database name contains illegal character '.'. Falling back to 'common'
```

Verified behaviour: a pod given `bad.name` carried on writing to `common` while
the previously-configured database still held the original collections — the
data ends up in two places, and only a log line says so. On a valid value you
get the matching confirmation instead:

```
INFO com.akto.util.DbNames - Using database name 'akto_common' from
AKTO_DB_NAME_COMMON (default 'common')
```

Check for that line on **every** component after enabling this.

### Minimum image versions

This is only honoured by builds from 2026-09-22 onward. Older images ignore the
variables entirely and keep using `common`/`billing` — which, if only some of
your components are new enough, produces exactly the split described above.
Bump all three together, and confirm each one logs the `Using database name`
line.

## Self-hosted Elasticsearch and Kibana

By default this chart expects an Elasticsearch you run elsewhere (Elastic Cloud,
Azure), reached via the `esHost`/`esApiKey` values you sync into Key Vault. Set
`elasticsearch.enabled=true` and the chart runs Elasticsearch itself instead:

```bash
--set elasticsearch.enabled=true
```

The chart then computes `ES_HOST` for you (the in-cluster Service address) and
**ignores `esHost` in Key Vault**. Only the API key still has to be synced,
because only a running Elasticsearch can issue one.

**Akto authenticates with an API key and nothing else.** It sends
`Authorization: ApiKey <esApiKey>` — basic auth (`elastic` / password) is not
supported by the Akto code at all, no matter how Elasticsearch is hosted. The
header is only sent when `esApiKey` is non-empty.

### One-time bootstrap

Elasticsearch can only mint an API key once it is running, so this is a
first-start step, not something the chart can do for you. Sync
`esElasticPassword` into Key Vault first (that is the built-in `elastic`
superuser's password — Akto never uses it), install with
`elasticsearch.enabled=true`, wait for the pod to be ready, then:

```bash
ES_POD=$(kubectl get pods -n akto -l app.kubernetes.io/component=elasticsearch -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n akto "$ES_POD" -- sh -c 'curl -s -u "elastic:$ELASTIC_PASSWORD" \
  -X POST "localhost:9200/_security/api_key" -H "Content-Type: application/json" \
  -d "{\"name\":\"akto\",\"role_descriptors\":{\"akto\":{\"cluster\":[\"monitor\"],\"indices\":[{\"names\":[\"agent_query_logs*\"],\"privileges\":[\"all\"]}]}}}"'
```

Take the **`encoded`** field from the response — that exact string is the
`esApiKey` value (it is already the base64 form the `ApiKey` header expects;
don't re-encode it). Sync it to Key Vault, then restart the components that read
it so they pick the new value up.

### Why there is no TLS on this endpoint

The Service is ClusterIP and speaks plain HTTP on purpose. A JVM has **one**
truststore, and this chart already replaces it to do mTLS to Mongo — putting
Elasticsearch's self-signed CA in that same path is a needless way to break
either the database connection or the search one. Authentication is still
enforced (the API key above); it is transport encryption that is deliberately
left off, on an endpoint that never leaves the cluster. Keep it ClusterIP.

### Sizing and storage

Single node, `discovery.type=single-node`. That also makes Elasticsearch skip
its bootstrap checks, which is what lets it run on a stock AKS node pool — a
multi-node setup would additionally need `vm.max_map_count=262144` on every
node, which is infrastructure work outside this chart. Keep `heapSize` at about
half of `resources.limits.memory`; the rest is Lucene's off-heap file cache.
`persistence` is on by default (50Gi, default StorageClass).

### Kibana

Off by default, and entirely optional — **Akto never talks to Kibana** (nothing
in the Akto codebase references it). It is only there if you want to look at the
index yourself:

```bash
--set elasticsearch.enabled=true --set kibana.enabled=true
```

It logs in as the built-in `kibana_system` user, not with Akto's API key, so set
that account's password once and sync it as `kibanaSystemPassword`:

```bash
kubectl exec -n akto "$ES_POD" -- sh -c 'curl -s -u "elastic:$ELASTIC_PASSWORD" \
  -X POST "localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" -d "{\"password\":\"<the value you synced>\"}"'
```

Kibana's Service is ClusterIP — reach it with
`kubectl port-forward svc/<release>-kibana 5601:5601`. If you expose it instead,
put TLS termination in front of it.

## Self-hosted model serving (vLLM)

Off by default. Set `vllm.enabled=true` and the chart runs
[vLLM](https://docs.vllm.ai) as an OpenAI-compatible endpoint, so the regional
chart's `agent-guard` can call a model you host instead of Azure AI Foundry.

```bash
--set vllm.enabled=true --set vllm.model=google/gemma-3-4b-it
```

`vllm.model` is **required** — the image's entrypoint is `vllm serve` with no
model baked in, so the chart fails fast rather than starting a server with
nothing to serve.

### Two things that will bite you

**It needs a GPU node pool, and it deliberately ignores the chart-wide
`nodeSelector`.** Every other component defaults to `nodeSelector: {workload:
cpu}`; inheriting that here would pin a GPU workload to a CPU pool where it can
never be scheduled. Set `vllm.nodeSelector`/`vllm.tolerations` to match your GPU
pool. Your cluster also needs an NVIDIA device plugin already installed, or the
`nvidia.com/gpu` request is never satisfied and the pod sits `Pending` — that is
cluster setup, not something this chart does.

**Gated models need a HuggingFace token.** Gemma is gated. Sync one into Key
Vault under `hfToken` (`vllm.hfTokenKey`) or the weight download just fails.

### Wiring agent-guard to it

agent-guard lives in the **regional** chart, so this is a two-chart change. Its
generic `openai_compatible` provider is the one to use — agent-guard's own
provider class is literally "OpenAI-compatible (OpenAI, Ollama, vLLM, LM
Studio, …)", and it calls `<baseUrl>/chat/completions` with
`Authorization: Bearer <OPENAI_API_KEY>`, which is exactly what vLLM's
`--api-key` expects.

On the regional release:

```yaml
agentGuard:
  env:
    openaiCompatibleBaseUrl: "http://<this service's address>:8000/v1"   # note the /v1
    openaiModel: "<vllm.servedModelName, or vllm.model>"
```

and sync the same token you set as `vllm.apiKeyKey` here into the **regional**
Key Vault as `openaiApiKey`. Then swap the provider in
`defaultModelConfigJson` — e.g. `"provider":"gemma_foundry"` becomes
`"provider":"openai_compatible"`.

Because the two charts are in different clusters, that base URL has to reach
across them over your own private connectivity — the same requirement as
`central.databaseAbstractorUrl`. The Service is an internal LoadBalancer by
default and must never get a public IP.

### Storage and startup

First start downloads the weights, which for a several-GB model takes minutes;
the startup probe allows ~30 minutes by default (`vllm.startupFailureThreshold`).
`persistence` is on (100Gi) so restarts don't re-download. `/dev/shm` is raised
to 8Gi — vLLM's default 64MB is not enough and the failures it causes don't look
like memory problems.

## Restricting outbound traffic (NetworkPolicy)

**Enabled by default.** Each component gets a NetworkPolicy with
`policyTypes: [Egress]`, which makes Kubernetes default-deny that pod's
outbound traffic — only the rules the chart writes are allowed. The dashboard
cannot reach the public internet.

Allowed by default:

- DNS to `kube-system`
- other pods in the same release (dashboard → threat backend, etc.)
- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` — i.e. internal network only

### If Mongo or Elasticsearch is on a public endpoint

Mongo Atlas / Elastic Cloud are **outside** those private ranges, so add them or
those components will not connect. `egressAllowlist` is empty by default and
purely additive to the private ranges above (which are hardcoded, not part of
this list), so index from `[0]`:

```bash
--set 'networkPolicy.egressAllowlist[0].cidr=203.0.113.10/32'
```

Restrict to specific ports as well:

```yaml
networkPolicy:
  egressAllowlist:
    - cidr: 10.0.0.0/8
      ports:
        - port: 27017
          protocol: TCP
```

Give one component a hole the others don't get:

```yaml
networkPolicy:
  components:
    databaseAbstractor:
      egressAllowlist:
        - cidr: 203.0.113.0/24
```

Also restrict who can connect **in**:

```yaml
networkPolicy:
  restrictIngress: true
  ingressNamespaces:
    - kubernetes.io/metadata.name: ingress-nginx
```

Turn the whole thing off:

```bash
--set networkPolicy.enabled=false
```

> **Enforcement requires a NetworkPolicy-capable CNI** — Calico, Cilium, Azure
> NPM, and similar. On a CNI that ignores NetworkPolicy (including minikube's
> default bridge CNI) the objects are still created but nothing is restricted.
> Confirm with `kubectl get networkpolicy -n <ns>` and by testing egress from a
> pod.

## Connecting regional clusters

After install, the notes print the endpoints the `akto-regional-setup` chart needs:

```
central.threatBackendUrl:      http://akto-central-setup-threat-backend.akto.svc.cluster.local:9090
central.databaseAbstractorUrl: http://akto-central-setup-database-abstractor.akto.svc.cluster.local:9000
```

Those are in-cluster names. `threat-backend` gets a public IP if you set
`threatBackend.service.type=LoadBalancer` (its default is `ClusterIP`).
`database-abstractor` does **not** get that option — it's `ClusterIP` only,
always, on purpose, since it's a backend data layer that should never have a
public IP. If regional runs in the same cluster, the ClusterIP name above
works as-is. If it's a genuinely separate cluster, you need your own private
connectivity to it first (VPN, VPC/VNet peering, a private endpoint) — that's
infrastructure this chart doesn't set up. See
[charts/akto-regional-setup](../akto-regional-setup/README.md).

## Node scheduling

**`nodeSelector` defaults to `{workload: cpu}` on every component** — meant to
keep pods off a GPU nodepool if your cluster has one. This is a real
label match, not a placeholder: if no node in your cluster is labeled
`workload=cpu`, every pod stays `Pending` after a fresh install. Check your
actual node labels first (`kubectl get nodes --show-labels`) and override to
match, or clear it, before installing:

```bash
--set nodeSelector.workload=<your-actual-value>
# or, to disable entirely:
--set-json nodeSelector='{}'
```

## Values reference

Everything shared lives under `global`; everything else is grouped per
component. `helm show values akto/akto-central-setup` prints the annotated file.

| Key | Default | Notes |
|---|---|---|
| `nodeSelector` | `{workload: cpu}` | See "Node scheduling" above - verify this label exists on your cluster before installing |
| `global.keyVault.secretProviderClass` | `akto-keyvault` | The only source of every secret in this chart - no plaintext/existingSecret fallback exists |
| `global.keyVault.secretName` | `akto-secrets` | Kubernetes Secret your SecretProviderClass syncs into |
| `global.mongo.secretKey` | `aktoMongoConn` | Key inside the above Secret; an empty synced value disables nothing - Mongo is always required |
| `global.elasticsearch.esHostSecretKey` | `esHost` | Key inside the above Secret; sync an empty string to disable ES-backed features. **Ignored when `elasticsearch.enabled=true`** - the chart computes the address itself |
| `global.elasticsearch.esApiKeySecretKey` | `esApiKey` | Akto's only supported Elasticsearch credential - sent as `Authorization: ApiKey`; basic auth is not supported |
| `elasticsearch.enabled` | `false` | Run Elasticsearch in-cluster instead of pointing at a managed one |
| `elasticsearch.heapSize` | `2g` | Keep at ~half of `resources.limits.memory` |
| `elasticsearch.persistence.size` | `50Gi` | Default StorageClass unless `storageClass` is set |
| `elasticsearch.elasticPasswordKey` | `esElasticPassword` | Key Vault key for the `elastic` superuser - used only to mint the API key, never by Akto |
| `kibana.enabled` | `false` | Optional console; Akto itself never talks to Kibana. Requires `elasticsearch.enabled` |
| `kibana.systemPasswordKey` | `kibanaSystemPassword` | Key Vault key for the built-in `kibana_system` account |
| `vllm.enabled` | `false` | OpenAI-compatible model server for regional's agent-guard |
| `vllm.model` | `""` | **Required** when enabled - no model is baked into the image |
| `vllm.nodeSelector` | `{}` | Must point at a GPU pool; deliberately does NOT inherit the chart-wide `workload: cpu` |
| `vllm.hfTokenKey` | `hfToken` | Key Vault key for a HuggingFace token - gated models (Gemma) need it |
| `vllm.apiKeyKey` | `vllmApiKey` | Bearer token vLLM requires; must match `openaiApiKey` in the *regional* Key Vault |
| `global.mongo.dbNames.common` | `""` (app default `common`) | Renames the shared `common` database; an invalid value silently falls back - see above |
| `global.mongo.dbNames.billing` | `""` (app default `billing`) | Renames the shared `billing` database |
| `global.accountName` / `configName` | `Helios` / `staging` | Stamped on every component |
| `dashboard.enabled` | `true` | |
| `dashboard.service.type` | `LoadBalancer` | |
| `databaseAbstractor.enabled` | `true` | |
| `databaseAbstractor.autoscaling.enabled` | `true` | HPA on CPU |
| `threatBackend.enabled` | `true` | |
| `threatBackend.service.httpPort` | `9090` | The API port |
| `threatBackend.service.kafkaPort` | `9092` | Bundled broker |
| `networkPolicy.enabled` | `true` | Default-deny egress |
| `imageAutoUpdate.enabled` | `false` | Adds keel.sh annotations; does not deploy Keel |

## Migrating from the old charts

The old charts are unchanged and still installable. To move over:

1. Install `akto-central-setup` into a new namespace, pointed at the **same** Mongo.
2. Confirm the dashboard comes up and threat data still renders.
3. Repoint traffic (DNS / LoadBalancer) to the new dashboard Service.
4. Uninstall `akto-dashboard`, `akto-dbabs`, `akto-threat-backend`.

Value paths changed — shared settings moved under `global`, and per-component
blocks were flattened (`dashboard.aktoApiSecurityDashboard.env.X` →
`dashboard.env.X`). `--reuse-values` from an old release will **not** carry over.

Two behaviour changes worth knowing:

- **Keel is no longer deployed.** `imageAutoUpdate.enabled=true` adds the
  keel.sh annotations for an existing cluster-wide Keel; install Keel itself
  separately if you want it.
- **The optional `testing` component was dropped.** Use the `akto-mini-testing`
  chart.
