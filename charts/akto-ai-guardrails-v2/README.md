# Akto Guardrails Stack Helm Chart

Deploys everything needed to run the Akto AI Guardrails pipeline end-to-end in one chart:

1. **Data Ingestion Service** - reused from `../data-ingestion-service` as a local
   chart dependency (alias `ingestion`)
2. **Guardrails Service (HTTP)** - the guardrails API, serving synchronous requests
3. **Guardrails Service (Kafka)** - the same image run as a Kafka consumer, for
   async/high-volume guardrail processing
4. **Guardrails Kafka** - a dedicated single-broker Kafka + Zookeeper for the
   guardrails pipeline
5. **Redis** - a `redis-stack-server` instance backing Agent Guard's semantic
   cache (needs the RediSearch module, so plain `redis`/`redis:alpine` will not work)
6. **Embedder** - model sidecar used by the semantic cache
7. **Anonymizer** - PII masking sidecar
8. **Agent Guard** - the executor that orchestrates anonymizer + embedder + redis
   to run the guardrail scanners

## Architecture

```
                 ┌────────────────────┐
 HTTP traffic -> │ Data Ingestion Svc │ -> topic: akto.guardrails
                 └────────────────────┘         │
                                                 v
┌──────────────────────┐   consumes    ┌──────────────────┐
│   Guardrails Kafka    │<─────────────│ Guardrails Service │
│  (broker + zookeeper) │               │  (kafka consumer)  │
└──────────────────────┘               └─────────┬──────────┘
                                                   │
        ┌──────────────────────────────────────────┘
        v
┌───────────────────┐        ┌─────────────┐       ┌───────────┐
│ Guardrails Service │──────▶│ Agent Guard │──────▶│ Anonymizer│
│      (HTTP)        │       │  (executor) │       └───────────┘
└───────────────────┘        │             │       ┌───────────┐
                              │             │──────▶│ Embedder  │
                              │             │       └───────────┘
                              │             │       ┌───────────┐
                              │             │──────▶│   Redis   │
                              └─────────────┘       │ (stack)   │
                                                     └───────────┘
```

## Installation

```bash
cd helm-charts/charts/akto-ai-guardrails-v2
helm dependency update
helm install akto-guardrails . -n akto-guardrails --create-namespace \
  -f custom-values.yaml
```

Add `custom-values.yaml` to `.gitignore` - it will hold your model provider
credentials and Redis password overrides.

### Required configuration before first install

| Value | Why |
|---|---|
| `agentGuard.secrets.*` | At least one LLM provider (Qwen3Guard, Gemma, Anthropic, or OpenAI-compatible) must be set for Agent Guard's model-backed scanners to work |
| `guardrailsService.http.env.databaseAbstractorServiceToken` / `guardrailsService.kafka.env.databaseAbstractorServiceToken` | Auth token guardrails-service uses to call the database abstractor |
| `ingestion.dataIngestionService.env.aktoKafkaBrokerUrl` | Subchart values aren't templated, so this can't default to the bundled broker automatically - set it to the hostname printed in `NOTES.txt` after install, e.g. `<release>-akto-ai-guardrails-v2-guardrails-kafka:9092` |
| `ingestion.dataIngestionService.env.guardrailsServiceUrl` | Same reason - set it to the guardrails-service-http hostname printed in `NOTES.txt` (guardrails forwarding is enabled by default via `enableGuardrails: "true"`) |

Env var names for `guardrailsService` are verified directly against the Go
source (`apps/guardrails-service/container/src/config.go`), not assumed from
the older `akto-ai-guardrails` chart - notably `SCANNER_API_URL` (not
`AKTO_AGENT_GUARD_URL`) is what points guardrails-service at Agent Guard's
`/scan` endpoint, and the semantic cache vars (`CACHE_MODE`/`REDIS_URL`/
`EMBEDDER_URL`) live on `guardrailsService`, not `agentGuard`.

### Bringing your own Kafka / Redis

Set `guardrailsKafka.enabled: false` / `redis.enabled: false` and point the
relevant `*BrokerUrl` / `redis.auth.existingSecret` fields at your existing
infrastructure instead of the bundled ones.

### Azure Key Vault (optional)

Mirrors the pattern `charts/akto-setup-dashboard` uses for its Mongo
connection string, via the Secrets Store CSI Driver. This chart never talks
to Key Vault directly - you create a `SecretProviderClass` separately
(pointing at your Key Vault + identity) with a `secretObjects` block that
syncs the fetched values into a native Kubernetes Secret; this chart just
mounts that `SecretProviderClass` (which triggers the sync) and reads the
resulting Secret via `secretKeyRef`.

```yaml
csiDriver:
  install: true   # or false if the CSI driver is already installed cluster-wide

keyVault:
  secretProviderClass: akto-guardrails-keyvault   # must already exist in the cluster

agentGuard:
  secrets:
    useKeyVault: true
    existingSecretName: akto-guardrails-agent-guard-secrets   # synced by the SecretProviderClass above

guardrailsService:
  http:
    env:
      useKeyVaultForDbToken: true
      dbTokenSecretName: akto-guardrails-db-abstractor-token
      dbTokenSecretKey: DATABASE_ABSTRACTOR_SERVICE_TOKEN
  kafka:
    env:
      useKeyVaultForDbToken: true
      dbTokenSecretName: akto-guardrails-db-abstractor-token
      dbTokenSecretKey: DATABASE_ABSTRACTOR_SERVICE_TOKEN

# The bundled data-ingestion-service subchart supports the same pattern
# independently (it doesn't read keyVault.secretProviderClass above, since it
# needs to stay usable outside this stack too):
ingestion:
  dataIngestionService:
    secrets:
      useKeyVault: true
      existingSecretName: akto-data-ingestion-secrets   # must contain DATABASE_ABSTRACTOR_SERVICE_TOKEN + AKTO_DI_REVOKED_TOKENS
      secretProviderClass: akto-guardrails-keyvault
```

When `agentGuard.secrets.useKeyVault: true`, the chart-managed
`agent-guard-secrets` Secret is skipped entirely, so `existingSecretName` must
already contain the same keys the chart would otherwise generate
(`QWEN3GUARD_*`, `GEMMA_VERTEX_*`, `ANTHROPIC_*`, `OPENAI_*`,
`DEFAULT_MODEL_CONFIG_JSON`). Same idea for `guardrailsService.*.env.dbTokenSecretName`
(just `DATABASE_ABSTRACTOR_SERVICE_TOKEN`) and `ingestion...secrets.existingSecretName`
(`DATABASE_ABSTRACTOR_SERVICE_TOKEN` + `AKTO_DI_REVOKED_TOKENS`).

## Notes on architecture drift

This chart targets the executor/anonymizer/embedder split described in
`infra/docker-compose-agent-guard.yml`. The older `charts/akto-ai-guardrails`
chart models a previous engine/executor split and is left untouched - don't
mix the two for the same deployment.
