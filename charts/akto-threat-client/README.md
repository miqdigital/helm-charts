# Akto Threat Client

Helm chart for installing Akto's threat detection client. Bundles its own Kafka broker by default, or can point at an existing Kafka cluster (e.g. the one bundled with an `akto-mini-runtime` install).

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find this chart on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-threat-client).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)
3. A Postgres database reachable from the cluster (used for storing threat detection data)

## Install via Helm

1. Add Akto repo
   ```bash
   helm repo add akto https://akto-api-security.github.io/helm-charts
   helm repo update
   ```
2. Install the chart, with your own Postgres and database abstractor token:
   ```bash
   helm install akto-threat-client akto/akto-threat-client -n dev --create-namespace \
     --set threat_client.aktoApiSecurityThreatClient.env.postgresUrl="jdbc:postgresql://<host>:5432/akto" \
     --set threat_client.aktoApiSecurityThreatClient.env.postgresUser="<user>" \
     --set threat_client.aktoApiSecurityThreatClient.env.postgresPassword="<password>" \
     --set threat_client.aktoApiSecurityThreatClient.env.databaseAbstractorToken="<your-database-abstractor-token>"
   ```
3. Run `kubectl get pods -n <NAMESPACE>` and verify the threat-client pod is `Running` (2 containers: the client + its bundled Kafka broker).

## Using an existing Kafka cluster instead of the bundled one

If you already have a Kafka broker (e.g. from an `akto-mini-runtime` install in the same cluster) and want this client to read from it instead of deploying its own:

```bash
--set threat_client.useExternalKafka=true \
--set threat_client.externalKafka.brokerUrl="<mini-runtime-release>-mini-runtime.<namespace>.svc.cluster.local:9092"
```

## Storing the database abstractor token in a secret

```bash
--set threat_client.aktoApiSecurityThreatClient.env.useSecretsForDatabaseAbstractorToken=true \
--set threat_client.aktoApiSecurityThreatClient.env.databaseAbstractorTokenSecrets.token="<your-database-abstractor-token>"
```

## Configuring Annotations

You can add custom Kubernetes annotations to Service, Deployment, and Pod resources for `threat_client`:

- `<component>.deploymentAnnotations` - Applied to Deployment metadata
- `<component>.podAnnotations` - Applied to Pod template metadata
- `<component>.serviceAnnotations` - Applied to Service metadata

## Upgrading to a new version

```bash
helm repo update
helm show chart akto/akto-threat-client
helm upgrade akto-threat-client akto/akto-threat-client -n <namespace> --version <latest-version>
```

## Get Support for your Akto setup

There are multiple ways to request support from Akto. We are 24X7 available on the following:

1. In-app `intercom` support. Message us with your query on intercom in Akto dashboard and someone will reply.
2. Join our [discord channel](https://www.akto.io/community) for community support.
3. Contact `help@akto.io` for email support.
4. Contact us [here](https://www.akto.io/contact-us).
