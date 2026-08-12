# Akto Deployment (2 Helm charts)

Two charts, two clusters:
- `akto-central-setup` → dashboard + database-abstractor + threat-backend
- `akto-regional-setup` → mini-runtime + threat-client + data-ingestion + guardrails

**Assumes:** an existing k8s cluster per side, `kubectl`/`helm` configured against it, an existing MongoDB, an existing Postgres (for threat-client), and an existing Azure Key Vault with a Managed Identity that already has `get` access to it. No infra/VM/AKS-cluster setup here — Kubernetes-side steps only.

Every secret in both charts comes from Azure Key Vault. No plaintext fallback exists — get every `az keyvault secret set` right below and there is nothing left to debug after `helm install`.

---

## Part A — Central cluster

### A1. Install the Key Vault CSI driver

```bash
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/charts
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm repo update

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system --set syncSecret.enabled=true

helm install csi-secrets-store-provider-azure csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
  -n kube-system
```
`syncSecret.enabled=true` is required — without it the driver never creates the Kubernetes Secret our charts read via `secretKeyRef`.

### A2. Push secrets to Key Vault

```bash
az keyvault secret set --vault-name <kv> --name aktoMongoConn --value "mongodb://<user>:<pass>@<host>:27017/admini"
az keyvault secret set --vault-name <kv> --name esHost --value "https://<es-host>:9200"   # skip if no ES
az keyvault secret set --vault-name <kv> --name esApiKey --value "<es-api-key>"           # skip if no ES
```

### A3. Create the SecretProviderClass

```yaml
# akto-central-spc.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: akto-keyvault
  namespace: akto
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<managed-identity-client-id>"
    keyvaultName: "<kv>"
    tenantId: "<azure-tenant-id>"
    objects: |
      array:
        - |
          objectName: aktoMongoConn
          objectType: secret
        - |
          objectName: esHost
          objectType: secret
        - |
          objectName: esApiKey
          objectType: secret
  secretObjects:
    - secretName: akto-secrets
      type: Opaque
      data:
        - objectName: aktoMongoConn
          key: aktoMongoConn
        - objectName: esHost
          key: esHost
        - objectName: esApiKey
          key: esApiKey
```
```bash
kubectl create namespace akto
kubectl apply -f akto-central-spc.yaml
```
No ES? Drop the `esHost`/`esApiKey` entries from both `objects` and `secretObjects` — the chart no-ops ES features when that key is missing.

### A4. Insert the HYBRID_SAAS keypair into Mongo

Dashboard↔threat-backend calls are JWT-signed with this keypair. Run once, from an empty scratch dir:

```bash
openssl genpkey -out privatekey.pem -algorithm RSA -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in privatekey.pem -out publicpub.pem

PRIV=$(awk '{printf "%s\\n", $0}' privatekey.pem)
PUB=$(awk '{printf "%s\\n", $0}' publicpub.pem)

mongosh "<your-mongo-conn-string>" --eval "
db.getSiblingDB('common').configs.replaceOne(
  { _id: 'HYBRID_SAAS' },
  { _id: 'HYBRID_SAAS', _t: 'com.akto.dto.Config\$HybridSaasConfig', configType: 'HYBRID_SAAS',
    privateKey: '$PRIV', publicKey: '$PUB' },
  { upsert: true }
)"

rm privatekey.pem publicpub.pem
```

### A5. Deploy akto-central-setup

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts
helm repo update akto

helm install akto-central-setup akto/akto-central-setup -n akto \
  --set global.keyVault.secretProviderClass=akto-keyvault \
  --set threatBackend.service.type=LoadBalancer
```
(`threatBackend` defaults to `ClusterIP` — it must be reachable from the regional cluster, so this override is required.)

### A6. Get the endpoints (needed for Part B)

`database-abstractor` is **ClusterIP only, on purpose** — it's a backend data layer, never given a public IP. `threat-backend` still gets one via the override above.

```bash
export TBS_IP=$(kubectl get svc -n akto akto-central-setup-threat-backend -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$TBS_IP"
```
Write it down if Part B runs in a different terminal/session (different `kubectl` context) — `$TBS_IP` won't carry over otherwise.

For `database-abstractor`, which of these applies to you:
- **Central and regional share one cluster** (common for smaller setups): use its ClusterIP DNS name directly — `http://akto-central-setup-database-abstractor.akto.svc.cluster.local:9000`. No IP to fetch.
- **Central and regional are genuinely separate clusters**: you need your own private connectivity between them first (VPN, VPC/VNet peering, a private endpoint) — that's infrastructure this doc doesn't set up. Once it exists, use whatever private address that mechanism gives you in Part B instead of a public IP.

### A7. Generate and store the regional auth token

In the dashboard UI: **Quick Start → Generate Authentication Token** (any regional scope). Then:

```bash
az keyvault secret set --vault-name <kv> --name databaseAbstractorToken --value "<token from dashboard>"
```
Add it to the SecretProviderClass from A3 (`objects` + `secretObjects`, same pattern as `aktoMongoConn`), then `kubectl apply -f akto-central-spc.yaml` again.

### A8. Verify

```bash
kubectl get pods -n akto -l app.kubernetes.io/instance=akto-central-setup
# expect dashboard 1/1, database-abstractor 1/1, threat-backend 2/2
```

---

## Part B — Regional cluster

Switch `kubectl`/`helm` context to the regional cluster before continuing.

### B1. Install the Key Vault CSI driver

Same as A1, run against this cluster.

### B2. Push secrets to Key Vault

```bash
az keyvault secret set --vault-name <kv-regional> --name databaseAbstractorToken --value "<same token from A7>"
az keyvault secret set --vault-name <kv-regional> --name threatClientPostgresUser --value "<postgres user>"
az keyvault secret set --vault-name <kv-regional> --name threatClientPostgresPassword --value "<postgres password>"
```

### B3. Create the SecretProviderClass

```yaml
# akto-regional-spc.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: akto-keyvault
  namespace: akto-regional
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<managed-identity-client-id>"
    keyvaultName: "<kv-regional>"
    tenantId: "<azure-tenant-id>"
    objects: |
      array:
        - |
          objectName: databaseAbstractorToken
          objectType: secret
        - |
          objectName: threatClientPostgresUser
          objectType: secret
        - |
          objectName: threatClientPostgresPassword
          objectType: secret
  secretObjects:
    - secretName: akto-secrets
      type: Opaque
      data:
        - objectName: databaseAbstractorToken
          key: databaseAbstractorToken
        - objectName: threatClientPostgresUser
          key: threatClientPostgresUser
        - objectName: threatClientPostgresPassword
          key: threatClientPostgresPassword
```
```bash
kubectl create namespace akto-regional
kubectl apply -f akto-regional-spc.yaml
```

### B4. Deploy akto-regional-setup

`central.databaseAbstractorUrl` below depends on which case from A6 applies to you — same-cluster ClusterIP DNS name, or your own private endpoint if central and regional are separate clusters:

```bash
helm install akto-regional-setup akto/akto-regional-setup -n akto-regional \
  --set global.keyVault.secretProviderClass=akto-keyvault \
  --set central.databaseAbstractorUrl="http://akto-central-setup-database-abstractor.akto.svc.cluster.local:9000" \
  --set central.threatBackendUrl="http://$TBS_IP:9090" \
  --set threatClient.env.postgresUrl="jdbc:postgresql://<postgres-host>:5432/<db>"
```

### B5. Verify

```bash
kubectl get pods -n akto-regional -l app.kubernetes.io/instance=akto-regional-setup
# expect mini-runtime 2/2, threat-client 2/2, data-ingestion/guardrails/agent-guard 1/1
```

---

## Optional — mTLS to Mongo/Elasticsearch (drop passwords entirely)

Only on the central cluster. Put a PKCS12 keystore/truststore in a plain (non-Key-Vault) Secret:

```bash
kubectl create secret generic akto-db-certs -n akto \
  --from-file=keystore.p12=./keystore.p12 \
  --from-file=truststore.p12=./truststore.p12
```

Push the store passwords to Key Vault, add `tlsKeystorePassword`/`tlsTruststorePassword` to the A3 SecretProviderClass the same way as `aktoMongoConn`, `kubectl apply` it again, then:

```bash
helm upgrade akto-central-setup akto/akto-central-setup -n akto --reuse-values \
  --set global.tls.enabled=true \
  --set global.mongo.x509=true \
  --set global.elasticsearch.mutualTls=true
```
Requires: your `aktoMongoConn` value in Key Vault already includes `authMechanism=MONGODB-X509&tls=true`, and `esApiKey` is set to an empty string (cert becomes the only credential).

---

## Optional — model-provider keys for agent-guard (regional)

Sync only the provider(s) you use, e.g. for OpenAI:

```bash
az keyvault secret set --vault-name <kv-regional> --name openaiApiKey --value "sk-..."
az keyvault secret set --vault-name <kv-regional> --name openaiModel --value "gpt-4o"
```
Add matching entries to the B3 SecretProviderClass, `kubectl apply` again. Every one of these keys is optional — leave unused providers out entirely. Full key list: `charts/akto-regional-setup/values.yaml` under `agentGuard.secrets`.

---

## Optional — semantic cache for guardrails (Redis + embedder, regional)

Bundles a `redis-stack-server` (needed for the cache's `FT.*` search commands — plain Redis won't work). Both this and `embedder.enabled=true` are required together; neither does anything alone.

```bash
az keyvault secret set --vault-name <kv-regional> --name guardrailsRedisPassword --value "<a real password>"
```
Add `guardrailsRedisPassword` to the B3 SecretProviderClass the same way as `databaseAbstractorToken`, `kubectl apply` again. This one is **required**, not optional — leaving it unsynced won't run Redis passwordless, it'll leave a broken mismatched literal password on each side (see the comment in `_helpers.tpl` if curious) and the pod won't start at all without it.

```bash
helm upgrade akto-regional-setup akto/akto-regional-setup -n akto-regional --reuse-values \
  --set guardrailsRedis.enabled=true \
  --set embedder.enabled=true
```
