# Akto Threat Backend

Helm chart for installing Akto's threat detection backend — a standalone service that ingests malicious event data (via API or Kafka) and serves it back to an Akto dashboard for threat detection / guardrails.

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find this chart on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-threat-backend).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)
3. A Mongo connection string (see the [akto-dashboard chart's README](../akto-setup-dashboard/README.md#create-mongo-instance) for setup options — this chart should point at the **same** Mongo instance/database as your Akto dashboard)

## Install via Helm

1. Add Akto repo
   ```
   helm repo add akto https://akto-api-security.github.io/helm-charts
   ```
2. Install the chart
   ```
   helm install akto-threat-backend akto/akto-threat-backend -n dev --create-namespace --set mongo.aktoMongoConn="<AKTO_CONNECTION_STRING>"
   ```
3. Run `kubectl get pods -n <NAMESPACE>` and verify the threat backend pod is `Running` (2/2 — it also runs an embedded Kafka broker as a sidecar).

## Required one-time setup: HYBRID_SAAS auth config

Requests between the dashboard and this threat backend are authenticated via a JWT signed with an RSA keypair. Before the dashboard and threat backend can talk to each other, insert this keypair into the **shared** Mongo instance, in the `common.configs` collection:

```js
db.configs.insertOne({
  "_id": "HYBRID_SAAS",
  "_t": "com.akto.dto.Config$HybridSaasConfig",
  "configType": "HYBRID_SAAS",
  "privateKey": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "publicKey": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n"
})
```

- The threat backend uses the **public** key to verify inbound JWTs (e.g. on `/api/threat_detection/record_malicious_event`).
- The dashboard uses the **private** key to sign outbound JWTs when it queries this service for threat data.

Without this document, the dashboard's requests to this service will fail with `401 Unauthorized`, and any external service posting events will get the same.

## Wiring up the dashboard

By default, the `akto-dashboard` chart points at Akto's SaaS threat backend (`https://tbs.akto.io`). To have your dashboard read from **this** self-hosted threat backend instead, set on the dashboard's install/upgrade:

```
--set dashboard.aktoApiSecurityDashboard.env.threatDetectionBackendUrl=http://<this-service-name>.<namespace>.svc.cluster.local:9090
```

## Verify

```
kubectl logs -n <NAMESPACE> <threat-backend-pod> -c akto-api-security-threat-backend
```

A healthy pod shows `HTTP server started on port 9090` and periodic cron log lines (`RiskScoreSyncCron`, `SkillsRiskScoreSyncCron`) with no Mongo connection errors.
