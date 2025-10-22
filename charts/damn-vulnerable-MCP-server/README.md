# Damn Vulnerable MCP Server Helm Chart

A Helm chart for deploying the [Damn Vulnerable Model Context Protocol (DVMCP) Server](https://github.com/harishsg993010/damn-vulnerable-MCP-server) - an educational security testing platform with 10 intentionally vulnerable MCP challenge servers.

## ⚠️ Security Warning

This chart deploys **intentionally vulnerable servers** for educational purposes only.

**DO NOT:**
- Deploy to production environments
- Expose to public internet
- Use with real credentials or data
- Deploy on shared/production Kubernetes clusters

**USE FOR:**
- Security training and education
- Understanding MCP vulnerabilities
- Developing security testing skills
- Research in controlled environments

## Overview

The Damn Vulnerable MCP Server provides 10 security challenges across three difficulty levels:

- **Easy (Challenges 1-3)**: Basic vulnerabilities like prompt injection
- **Medium (Challenges 4-7)**: Tool shadowing, permission misconfigurations
- **Hard (Challenges 8-10)**: Advanced multi-vector attacks

Each challenge runs on its own port (9001-9010) within a single container managed by supervisord.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Docker (for building the image)
- (Optional) LoadBalancer support for external access
- (Optional) PersistentVolume provisioner for challenge data persistence

## Building the Docker Image

**Important:** The damn-vulnerable-MCP-server image is not available on Docker Hub. You must build it locally first.

### For Minikube

```bash
# Point Docker to minikube's Docker daemon
eval $(minikube docker-env)

# Clone and build the image
git clone https://github.com/harishsg993010/damn-vulnerable-MCP-server.git
cd damn-vulnerable-MCP-server
docker build -t dvmcp:latest .
```

### For Other Kubernetes Clusters

```bash
# Build and push to your registry
git clone https://github.com/harishsg993010/damn-vulnerable-MCP-server.git
cd damn-vulnerable-MCP-server
docker build -t your-registry/dvmcp:latest .
docker push your-registry/dvmcp:latest
```

## Installation

### Basic Installation (Minikube)

After building the image locally:

```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set image.repository=dvmcp \
  --set image.tag=latest \
  --set image.pullPolicy=Never
```

### Basic Installation (Other Clusters)

After pushing to your registry:

```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set image.repository=your-registry/dvmcp \
  --set image.tag=latest
```

### With LoadBalancer for External Access

```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set image.repository=dvmcp \
  --set image.tag=latest \
  --set image.pullPolicy=Never \
  --set service.type=LoadBalancer
```

### With NodePort for External Access

```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set image.repository=dvmcp \
  --set image.tag=latest \
  --set image.pullPolicy=Never \
  --set service.type=NodePort
```

### With Persistence Enabled

```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set image.repository=dvmcp \
  --set image.tag=latest \
  --set image.pullPolicy=Never \
  --set persistence.enabled=true \
  --set persistence.size=2Gi
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `harishsg993010/damn-vulnerable-mcp-server` |
| `image.tag` | Image tag | `""` (uses appVersion) |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Service type (ClusterIP/NodePort/LoadBalancer) | `ClusterIP` |
| `service.ports` | Port configurations for all 10 challenges | See values.yaml |
| `resources.limits.cpu` | CPU limit | `2000m` |
| `resources.limits.memory` | Memory limit | `2Gi` |
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `persistence.enabled` | Enable persistent storage | `false` |
| `persistence.size` | Size of persistent volume | `1Gi` |
| `ingress.enabled` | Enable ingress for HTTP routing | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.hosts` | Ingress host configurations | See values.yaml |

### Service Types

#### ClusterIP (Default)
- Only accessible within the cluster
- Use `kubectl port-forward` for local access
- Most secure for isolated testing

#### NodePort
- Accessible via node IP and high-numbered ports (30000-32767)
- Good for development clusters
- Configure specific ports via `service.nodePorts`

#### LoadBalancer
- Gets external IP from cloud provider
- Best for cloud-based testing environments
- May incur cloud provider costs

#### Ingress
- Enable with `ingress.enabled=true`
- Provides domain-based routing with path prefixes
- Requires ingress controller (nginx, traefik, etc.)
- All challenges accessible via single domain:
  - `http://dvmcp.local/challenge1`
  - `http://dvmcp.local/challenge2`
  - ... etc

**Enable Ingress:**
```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=dvmcp.example.com
```

## Accessing the Challenges

After installation, follow the instructions shown in the NOTES output.

### Option 1: Port Forward (Works on All Clusters)

```bash
kubectl port-forward svc/dvmcp-damn-vulnerable-mcp-server 9001:9001 9002:9002 9003:9003 9004:9004 9005:9005 9006:9006 9007:9007 9008:9008 9009:9009 9010:9010
```

Then access via `http://localhost:9001` through `http://localhost:9010`

### Option 2: Minikube Service (Recommended for Minikube)

**Get all service URLs:**
```bash
minikube service dvmcp-damn-vulnerable-mcp-server --url
```

This returns accessible URLs like:
```
http://127.0.0.1:54321  <- Challenge 1
http://127.0.0.1:54322  <- Challenge 2
...
http://127.0.0.1:54330  <- Challenge 10
```

**Or open in browser:**
```bash
minikube service dvmcp-damn-vulnerable-mcp-server
```

### Option 3: NodePort (Cloud/Other Clusters)

```bash
# Get node IP
kubectl get nodes -o wide

# Get service ports
kubectl get svc dvmcp-damn-vulnerable-mcp-server
```

Access via `http://<NODE-IP>:<NODE-PORT>`

### Option 4: LoadBalancer (Cloud Providers)

```bash
kubectl get svc dvmcp-damn-vulnerable-mcp-server
```

Wait for `EXTERNAL-IP` to be assigned, then access via:
- Challenge 1: `http://<EXTERNAL-IP>:9001`
- Challenge 2: `http://<EXTERNAL-IP>:9002`
- ... etc

**For Minikube:**
```bash
# Run in separate terminal
minikube tunnel

# Then get external IP
kubectl get svc dvmcp-damn-vulnerable-mcp-server
```

### Option 5: Ingress (Domain-based Routing)

**Prerequisites:**
1. Ingress controller installed (for minikube: `minikube addons enable ingress`)
2. DNS/hosts file configured

**Install with Ingress:**
```bash
helm install dvmcp ./damn-vulnerable-mcp-server \
  --set image.repository=dvmcp \
  --set image.tag=latest \
  --set image.pullPolicy=Never \
  --set ingress.enabled=true \
  --set ingress.className=nginx
```

**For Minikube:**
```bash
# 1. Start tunnel in separate terminal
minikube tunnel

# 2. Add to /etc/hosts
echo "127.0.0.1 dvmcp.local" | sudo tee -a /etc/hosts

# 3. Access challenges
curl http://dvmcp.local/challenge1
curl http://dvmcp.local/challenge2
# ... etc
```

Access all challenges at:
- `http://dvmcp.local/challenge1` through `http://dvmcp.local/challenge10`

**For MCP Inspector/Clients:**
The ingress includes automatic path rewriting. Use URLs like:
- `http://dvmcp.local/challenge1/sse` - automatically rewrites to backend `/sse`
- `http://dvmcp.local/challenge2/sse` - automatically rewrites to backend `/sse`
- etc.

**Note:** Ingress adds extra latency due to additional routing layer. Use NodePort/Service for better performance in development.

## MCP Client Configuration

Configure your MCP clients (Claude Desktop, Cursor, MCP Inspector) to connect to each challenge.

**Note:** Use direct service access (Option 1 or 2 from "Accessing the Challenges" above) for MCP clients, not ingress. Ingress path rewriting can interfere with MCP SSE transport.

### Example: Claude Desktop Config

```json
{
  "mcpServers": {
    "dvmcp-challenge-1": {
      "url": "http://localhost:9001"
    },
    "dvmcp-challenge-2": {
      "url": "http://localhost:9002"
    }
  }
}
```

Replace URLs with output from `minikube service dvmcp-damn-vulnerable-mcp-server --url` or use port-forward URLs.

## Architecture

### Single Pod Design
The chart deploys a single pod containing all 10 challenge servers managed by supervisord. This mirrors the original Docker architecture and ensures:
- All challenges share the same lifecycle
- Simplified networking between challenges
- Consistent with upstream project design

### Port Mapping
- Challenge 1: Port 9001
- Challenge 2: Port 9002
- Challenge 3: Port 9003
- Challenge 4: Port 9004
- Challenge 5: Port 9005
- Challenge 6: Port 9006
- Challenge 7: Port 9007
- Challenge 8: Port 9008
- Challenge 9: Port 9009
- Challenge 10: Port 9010

### Persistence
Some challenges require persistent storage for challenge data:
- Challenge 3: File system traversal data
- Challenge 4: State tracking
- Challenge 6: User uploads
- Challenge 8: Sensitive files
- Challenge 10: Configuration files

Enable persistence to maintain challenge state across pod restarts.

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -l app.kubernetes.io/name=damn-vulnerable-mcp-server
kubectl logs -l app.kubernetes.io/name=damn-vulnerable-mcp-server
```

### Service has no external IP (LoadBalancer)
- Ensure your cluster supports LoadBalancer services
- Check cloud provider integration
- Consider using NodePort instead

### Cannot access via NodePort
```bash
# Get node IP
kubectl get nodes -o wide

# Verify service ports
kubectl get svc dvmcp-damn-vulnerable-mcp-server
```

### Health checks failing
```bash
# Check if servers are running
kubectl exec -it <pod-name> -- supervisorctl status
```

## Uninstallation

```bash
helm uninstall dvmcp
```

If persistence was enabled, manually delete PVCs:
```bash
kubectl delete pvc -l app.kubernetes.io/name=damn-vulnerable-mcp-server
```

## Contributing

This chart is maintained as part of the Akto Security Helm charts repository. Contributions welcome!

## Resources

- [Upstream Project](https://github.com/harishsg993010/damn-vulnerable-MCP-server)
- [MCP Documentation](https://modelcontextprotocol.io/)
- [Akto Security](https://github.com/akto-api-security)

## License

This chart follows the same MIT license as the upstream project.
