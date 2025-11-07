# Grafana Cloud Setup Helm Chart

This Helm chart deploys Grafana Alloy to scrape Prometheus metrics from Kubernetes pods and push them to Grafana Cloud.

## Prerequisites

- Kubernetes cluster
- Helm 3.x
- Grafana Cloud account with Prometheus enabled
- Grafana Cloud API tokens (read and write)

## Installation

### 1. Get Grafana Cloud Credentials

From your Grafana Cloud account:
- Navigate to your Prometheus instance details
- Note down:
  - **Remote Write URL**: `https://prometheus-prod-XX-prod-XX-XX.grafana.net/api/prom/push`
  - **Query URL**: `https://prometheus-prod-XX-prod-XX-XX.grafana.net/api/prom`
  - **Username**: Your numeric instance ID (e.g., `2781763`)
  - **Write Token**: Create an access policy with `metrics:write` permission

### 2. Install the Chart

```bash
helm install grafana-cloud-setup ./charts/grafana-cloud-setup \
  --set grafanaCloud.remoteWriteUrl="https://prometheus-prod-XX-prod-XX-XX.grafana.net/api/prom/push" \
  --set grafanaCloud.username="2781763" \
  --set grafanaCloud.writeToken="YOUR_WRITE_TOKEN" \
  --set grafanaCloud.clusterName="prod-eks-us-east-1" \
  --set namespaces[0]="default" \
  --set namespaces[1]="akto-ci-cd"
```

**Note on clusterName:**
- This adds a `cluster` label to all metrics in Grafana Cloud
- Use descriptive names: `"minikube-local"`, `"staging-gke"`, `"prod-eks-us-east-1"`
- Helps distinguish metrics when multiple clusters send to same Grafana Cloud account
- For single cluster setups, any meaningful name works (e.g., `"main-cluster"`)

### 3. Annotate Your Pods

For Grafana Alloy to scrape metrics from your pods, add these annotations to your pod spec:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9400"
    prometheus.io/path: "/metrics"
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafanaCloud.remoteWriteUrl` | Grafana Cloud Prometheus push endpoint | `""` (required) |
| `grafanaCloud.username` | Grafana Cloud username/instance ID | `""` (required) |
| `grafanaCloud.writeToken` | Grafana Cloud write API token | `""` (required) |
| `grafanaCloud.clusterName` | Cluster identifier for metrics | `""` (required) |
| `namespaces` | List of namespaces to scrape | `["default"]` |
| `scrape.interval` | Scrape interval | `"15s"` |
| `scrape.timeout` | Scrape timeout | `"10s"` |
| `alloy.image.repository` | Alloy image repository | `grafana/alloy` |
| `alloy.image.tag` | Alloy image tag | `latest` |
| `alloy.resources.requests.cpu` | CPU request | `50m` |
| `alloy.resources.requests.memory` | Memory request | `64Mi` |
| `alloy.resources.limits.cpu` | CPU limit | `200m` |
| `alloy.resources.limits.memory` | Memory limit | `256Mi` |

## How It Works

1. **Discovery**: Grafana Alloy discovers pods in specified namespaces with `prometheus.io/scrape: "true"` annotation
2. **Scrape**: It scrapes metrics from the annotated pods at the specified port and path
3. **Push**: Metrics are pushed to Grafana Cloud via remote write
4. **Query**: External systems (like KEDA) can query these metrics from Grafana Cloud

## Verification

Check if Alloy is running:
```bash
kubectl get pods -l app.kubernetes.io/name=grafana-cloud-setup
```

Check Alloy logs:
```bash
kubectl logs -l app.kubernetes.io/name=grafana-cloud-setup
```

Verify metrics in Grafana Cloud:
- Go to your Grafana Cloud dashboard
- Navigate to Explore
- Query: `{namespace="your-namespace"}`

## Uninstallation

```bash
helm uninstall grafana-cloud-setup
```

## Integration with KEDA

After installing this chart, you can configure KEDA in your application charts to query metrics from Grafana Cloud. See the `mini-testing` chart for an example.
