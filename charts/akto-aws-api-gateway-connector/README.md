# Akto AWS API Gateway Connector

Helm chart to run the **Akto API Gateway connector** on EKS. The connector reads API Gateway traffic from AWS CloudWatch Logs and sends it to Akto (Kafka + Cyborg).

**Prerequisites:** EKS cluster, `kubectl` and `helm` installed, AWS CLI configured.

---

## Step 1: Choose or create a namespace

- **Use the same namespace as mini-runtime**  
  If Akto mini-runtime is already running in a namespace (e.g. `akto`), use that namespace when installing the chart so the connector can reach Kafka in the same namespace. No need to create it.

- **Use a new namespace**  
  Create it before installing:

  ```bash
  kubectl create namespace akto
  ```

  Replace `akto` with the namespace you want. Use this same namespace in Step 2 (IAM trust policy) and Step 3 (Helm install). If you use an existing namespace (e.g. where mini-runtime runs), use that name in the IAM trust policy and in the install command.

---

## Step 2: Create IAM role and policy (IRSA)

Do this once in your AWS account. The connector pod uses this role to read CloudWatch Logs and call API Gateway (OpenAPI discovery).

### 2.1 Get EKS OIDC provider ID

1. In **AWS Console** → **EKS** → your cluster → **Overview** → **Details**.
2. Copy the **OpenID Connect provider URL** (e.g. `https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716EXAMPLE`).
3. The **OIDC provider ID** is the part after `/id/` (e.g. `EXAMPLED539D4633E53DE1B716EXAMPLE`).

Note your **AWS Region**, **AWS Account ID**, and the **namespace** you will use for the chart (e.g. `akto`).

### 2.2 Create IAM policy

1. Go to **IAM** → **Policies** → **Create policy**.
2. **JSON** tab, paste the policy below.
3. Replace `REGION` and `ACCOUNT_ID` with your region and account ID. For CloudWatch you can use `arn:aws:logs:REGION:ACCOUNT_ID:log-group:*` or restrict to specific log group ARNs.
4. **Next** → name the policy (e.g. `ApiGatewayConnectorPolicy`) → **Create policy**.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents",
        "logs:GetLogEvents"
      ],
      "Resource": "arn:aws:logs:REGION:ACCOUNT_ID:log-group:*"
    },
    {
      "Effect": "Allow",
      "Action": ["apigateway:GET"],
      "Resource": [
        "arn:aws:apigateway:REGION::/restapis",
        "arn:aws:apigateway:REGION::/restapis/*",
        "arn:aws:apigateway:REGION::/apis",
        "arn:aws:apigateway:REGION::/apis/*"
      ]
    }
  ]
}
```

### 2.3 Create IAM role

1. Go to **IAM** → **Roles** → **Create role**.
2. **Trusted entity type:** Web identity.
3. **Identity provider:** your EKS OIDC provider (e.g. `oidc.eks.REGION.amazonaws.com/id/OIDC_ID`).
4. **Audience:** `sts.amazonaws.com` → **Next**.
5. Attach the policy from 2.2 (e.g. `ApiGatewayConnectorPolicy`) → **Next**.
6. Name the role (e.g. `akto-api-gateway-connector-eks-role`) → **Create role**.

### 2.4 Update role trust policy

1. Open the role → **Trust relationships** → **Edit**.
2. Replace with the JSON below. Replace:
   - `ACCOUNT_ID` – your AWS account ID  
   - `REGION` – EKS region (e.g. `us-east-1`)  
   - `OIDC_ID` – OIDC provider ID from 2.1  
   - `NAMESPACE` – namespace where you will install the chart (e.g. `akto`)
3. **Save**.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com",
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:NAMESPACE:service-account-eks"
        }
      }
    }
  ]
}
```

4. Copy the **role ARN** (e.g. `arn:aws:iam::123456789012:role/akto-api-gateway-connector-eks-role`). You need it for the Helm install.

---

## Step 3: Deploy the Helm chart

### 3.1 Add the Helm repo (if installing from repo)

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts/
helm repo update
```

### 3.2 Install with required values

Replace the placeholders and run from the repo root (or use the chart path you have):

**From local chart directory:**

```bash
helm install akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n akto --create-namespace \
  --set serviceAccount.roleArn=arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME \
  --set env.AWS_REGION=ap-south-1 \
  --set env.LOG_GROUP_NAME="your-log-group-name" \
  --set env.AKTO_KAFKA_BROKER_MAL="kafka-broker:9092" \
  --set env.DATABASE_ABSTRACTOR_TOKEN="your-token"
```

**From Helm repo:**

```bash
helm install akto-aws-api-gateway-connector akto/akto-aws-api-gateway-connector -n akto --create-namespace \
  --set serviceAccount.roleArn=arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME \
  --set env.AWS_REGION=ap-south-1 \
  --set env.LOG_GROUP_NAME="your-log-group-name" \
  --set env.AKTO_KAFKA_BROKER_MAL="kafka-broker:9092" \
  --set env.DATABASE_ABSTRACTOR_TOKEN="your-token"
```

**Required values:**

| Value | Description |
|-------|-------------|
| `serviceAccount.roleArn` | IAM role ARN from Step 1 (IRSA). |
| `env.AWS_REGION` | AWS region (e.g. `ap-south-1`, `us-east-1`). |
| `env.LOG_GROUP_NAME` | CloudWatch log group name (or comma-separated names). |
| `env.AKTO_KAFKA_BROKER_MAL` | Kafka broker address (e.g. from Akto mini-runtime). |
| `env.DATABASE_ABSTRACTOR_TOKEN` | Token from Akto dashboard (for Cyborg / OpenAPI discovery). |

Other env vars (batch sizes, intervals, etc.) have defaults in `values.yaml`; override with `--set` or a custom values file if needed.

### 3.3 Verify

```bash
kubectl get pods -n akto
kubectl logs -f deployment/api-gateway-logging -n akto
```

### 3.4 Upgrade or uninstall

**Upgrade (after changing values or chart):**

```bash
helm upgrade akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n akto \
  --set serviceAccount.roleArn=... \
  --set env.AWS_REGION=... \
  --set env.LOG_GROUP_NAME=... \
  --set env.AKTO_KAFKA_BROKER_MAL=... \
  --set env.DATABASE_ABSTRACTOR_TOKEN=...
```

**Uninstall:**

```bash
helm uninstall akto-aws-api-gateway-connector -n akto
```
