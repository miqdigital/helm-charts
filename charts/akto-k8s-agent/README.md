akto-k8s-agent

Helm chart for deploying the Akto Kubernetes DaemonSet agent.

Installation

```bash
helm install akto-k8s-agent ./charts/akto-k8s-agent \
  --set namespace=default \
  --set env.AKTO_KAFKA_BROKER_MAL="<AKTO_NLB_IP>:9092" \
  --set env.AKTO_MONGO_CONN="mongodb://0.0.0.0:27017"
```

Values

- namespace: Namespace to deploy into.
- image.repository, image.tag, image.pullPolicy
- env.*: Environment variables for the agent.
- hostNetwork, dnsPolicy
- tolerations, nodeSelector, affinity

