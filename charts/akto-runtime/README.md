# Akto Runtime

Helm chart for installing Akto's hybrid runtime, with a bundled Kafka broker co-located in the same pod. No Keel, no threat detection client, no Redis — for threat detection, see [`akto-threat-client`](../akto-threat-client/README.md).

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find Akto mini-runtime on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-runtime).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)
3. A database abstractor token, generated from the dashboard's **Quick Start → Hybrid SaaS** page (scoped to `MINI_RUNTIME`)

## Install via Helm

1. Add Akto repo
   ```bash
   helm repo add akto https://akto-api-security.github.io/helm-charts
   helm repo update
   ```
2. Install the chart
   ```bash
   helm install akto-mini-runtime akto/akto-runtime -n dev --create-namespace \
     --set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorToken="<your-database-abstractor-token>"
   ```
3. Run `kubectl get pods -n <NAMESPACE>` and verify the mini-runtime pod is `Running` (2 containers: the runtime app + its bundled Kafka broker).

## Using an existing Kafka cluster instead of the bundled one

```bash
--set mini_runtime.useExternalKafka=true \
--set mini_runtime.externalKafka.brokerUrl="<host>:<port>"
```

## Storing the database abstractor token in a secret

```bash
--set mini_runtime.aktoApiSecurityRuntime.env.useSecretsForDatabaseAbstractorToken=true \
--set mini_runtime.aktoApiSecurityRuntime.env.databaseAbstractorTokenSecrets.token="<your-database-abstractor-token>"
```

## Pulling secrets from Azure Key Vault

If you want the database abstractor token and Kafka SASL credentials pulled from Azure Key Vault (via the CSI driver) instead of passed as plain text or a pre-existing K8s Secret:

```bash
--set keyVault.enabled=true --set keyVault.secretProviderClass=<your-SecretProviderClass-name>
```

By default this expects a Key Vault-synced K8s Secret named `akto-secrets` with keys `databaseAbstractorToken`, `kafkaSaslUsername`, and `kafkaSaslPassword` — override `keyVault.secretName` / `keyVault.secretKeys.*` if your SecretProviderClass uses different names.

## Configuring Annotations

You can add custom Kubernetes annotations to Service, Deployment, and Pod resources for `mini_runtime`:

- `mini_runtime.deploymentAnnotations` - Applied to Deployment metadata
- `mini_runtime.podAnnotations` - Applied to Pod template metadata
- `mini_runtime.serviceAnnotations` - Applied to Service metadata

## Upgrading to a new version

```bash
helm repo update
helm show chart akto/akto-runtime
helm upgrade akto-mini-runtime akto/akto-runtime -n <namespace> --version <latest-version>
```

## Get Support for your Akto setup

There are multiple ways to request support from Akto. We are 24X7 available on the following:

1. In-app `intercom` support. Message us with your query on intercom in Akto dashboard and someone will reply.
2. Join our [discord channel](https://www.akto.io/community) for community support.
3. Contact `help@akto.io` for email support.
4. Contact us [here](https://www.akto.io/contact-us).
