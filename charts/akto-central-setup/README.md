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
| dashboard, db-abstractor | `ES_HOST` / `ES_API_KEY` | `global.elasticsearch.*`, once |

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

### With ready-made Java keystores (recommended)

Put a PKCS12 keystore and truststore in a Secret named `akto-db-certs` (this
one holds the certificate *files* - it stays a plain Kubernetes Secret, since
it's mounted as files, not read as an env var), then sync the passwords that
protect them into Key Vault as `tlsKeystorePassword` / `tlsTruststorePassword`,
and the x509-enabled connection string as your `aktoMongoConn` value. This is
already the chart's default (`global.tls.enabled`/`global.mongo.x509` are
`true`, `global.tls.secretName` is already `akto-db-certs`), so the install
itself needs nothing extra:

```bash
helm install akto-central-setup akto/akto-central-setup -n akto
```

If you also want certificate auth to Elasticsearch instead of an API key
(off by default):

```bash
helm install akto-central-setup akto/akto-central-setup -n akto \
  --set global.elasticsearch.mutualTls=true
```

cert-manager emits both stores directly:

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
reads both exclusively from there, never from `akto-tls-pw` directly.

### With PEM files

Set `global.tls.format=pem` and the chart runs an init container that converts
`tls.crt` / `tls.key` / `ca.crt` into PKCS12 at pod start (`global.tls.enabled`,
`global.mongo.x509` and `global.tls.secretName=akto-db-certs` are already the
defaults, so `format` is the only override needed):

```bash
--set global.tls.format=pem
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
  `authMechanism=MONGODB-X509&tls=true` directly into the `aktoMongoConn` value
  you sync into Key Vault; the chart never sees the string in plaintext to
  append anything to it.
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

## Values reference

Everything shared lives under `global`; everything else is grouped per
component. `helm show values akto/akto-central-setup` prints the annotated file.

| Key | Default | Notes |
|---|---|---|
| `global.keyVault.secretProviderClass` | `akto-keyvault` | The only source of every secret in this chart - no plaintext/existingSecret fallback exists |
| `global.keyVault.secretName` | `akto-secrets` | Kubernetes Secret your SecretProviderClass syncs into |
| `global.mongo.secretKey` | `aktoMongoConn` | Key inside the above Secret; an empty synced value disables nothing - Mongo is always required |
| `global.elasticsearch.esHostSecretKey` | `esHost` | Key inside the above Secret; sync an empty string to disable ES-backed features |
| `global.accountName` / `configName` | `Helios` / `staging` | Stamped on every component |
| `dashboard.enabled` | `true` | |
| `dashboard.service.type` | `LoadBalancer` | |
| `databaseAbstractor.enabled` | `true` | |
| `databaseAbstractor.autoscaling.enabled` | `false` | HPA on CPU |
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
