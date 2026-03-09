# Akto AWS API Gateway Connector

Helm chart to run the **Akto API Gateway connector** on EKS. The connector reads API Gateway traffic from AWS CloudWatch Logs and sends it to Akto (Kafka + Cyborg).

**Prerequisites:** EKS cluster, `kubectl` and `helm` installed, AWS CLI configured.

---

## Step 1: Choose or create a namespace

- **Use the same namespace as mini-runtime**  
  If Akto mini-runtime is already running in a namespace (e.g. `akto`), use that namespace when installing the chart so the connector can reach Kafka in the same namespace. No need to create it.

- **Use a new namespace**  
  Run the following (replace `akto` with the name you want). Use this same namespace in Step 2 (IAM trust policy) and Step 3 (Helm install).

  ```bash
  kubectl create namespace akto
  ```

---

## Step 2: Create IAM role and policy (IRSA)

Do this once in your AWS account. The connector pod uses this role to read CloudWatch Logs and call API Gateway (OpenAPI discovery).

### 2.1 Get EKS OIDC provider ID

- In **AWS Console** → **EKS** → your cluster → **Overview** → **Details**.
- Copy the **OpenID Connect provider URL** (e.g. `https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716EXAMPLE`).
- The **OIDC provider ID** is the part after `/id/` (e.g. `EXAMPLED539D4633E53DE1B716EXAMPLE`).
- Note your **AWS Region**, **AWS Account ID**, and the **namespace** you will use (e.g. `akto`).

### 2.2 Create IAM policy

- Go to **IAM** → **Policies** → **Create policy**.
- Open the **JSON** tab and paste the policy below.
- Replace `REGION` and `ACCOUNT_ID` with your region and account ID. For CloudWatch you can use `arn:aws:logs:REGION:ACCOUNT_ID:log-group:*` or restrict to specific log group ARNs.
- **Next** → name the policy (e.g. `ApiGatewayConnectorPolicy`) → **Create policy**.

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

- Go to **IAM** → **Roles** → **Create role**.
- **Trusted entity type:** Web identity.
- **Identity provider:** choose your EKS OIDC provider (e.g. `oidc.eks.REGION.amazonaws.com/id/OIDC_ID`).

  **If the EKS OIDC provider is not listed**, create it in the AWS Console first:
  - Go to **IAM** → **Identity providers** → **Add provider**.
  - **Provider type:** OpenID Connect.
  - **Provider URL:** use the OpenID Connect provider URL from **EKS** → your cluster → **Overview** → **Details**.
  - **Audience:** `sts.amazonaws.com` → **Add provider**. Then create the role again; the new provider will appear in the list.

- **Audience:** `sts.amazonaws.com` → **Next**.
- Attach the policy from 2.2 (e.g. `ApiGatewayConnectorPolicy`) → **Next**.
- Name the role (e.g. `akto-api-gateway-connector-eks-role`) → **Create role**.

### 2.4 Update role trust policy

- Open the role → **Trust relationships** → **Edit**.
- Replace the policy with the JSON below. Replace:
  - `ACCOUNT_ID` – your AWS account ID  
  - `REGION` – EKS region (e.g. `us-east-1`)  
  - `OIDC_ID` – OIDC provider ID from 2.1  
  - `NAMESPACE` – namespace where you will install the chart (e.g. `akto`)
- **Save**.
- Copy the **role ARN** (e.g. `arn:aws:iam::123456789012:role/akto-api-gateway-connector-eks-role`) for the Helm install.

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

---

## Step 3: Deploy the Helm chart

### 3.1 Add the Helm repo (if installing from repo)

```bash
helm repo add akto https://akto-api-security.github.io/helm-charts/
helm repo update
```

### 3.2 Install with required values

**If you are not using the Helm repo** (install from source):

- Clone the repo and checkout the branch that contains this chart. Then run `helm install` from the repo root.

```bash
git clone https://github.com/akto-api-security/helm-charts.git
cd helm-charts
git checkout aws_apig_helm_chart
```

- Install the chart (replace placeholders). Run from the repo root so the path `./charts/akto-aws-api-gateway-connector` is correct:

```bash
helm install akto-aws-api-gateway-connector ./charts/akto-aws-api-gateway-connector -n akto \
  --set serviceAccount.roleArn=arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME \
  --set env.AWS_REGION=ap-south-1 \
  --set env.LOG_GROUP_NAME="your-log-group-name" \
  --set env.AKTO_KAFKA_BROKER_MAL="kafka-broker:9092" \
  --set env.DATABASE_ABSTRACTOR_TOKEN="your-token"
```

**From Helm repo:**

- Add the repo and update (if not already done). Use this when the chart is published to the Helm repo.

```bash
helm install akto-aws-api-gateway-connector akto/akto-aws-api-gateway-connector -n akto \
  --set serviceAccount.roleArn=arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME \
  --set env.AWS_REGION=ap-south-1 \
  --set env.LOG_GROUP_NAME="your-log-group-name" \
  --set env.AKTO_KAFKA_BROKER_MAL="kafka-broker:9092" \
  --set env.DATABASE_ABSTRACTOR_TOKEN="your-token"
```

**Using values.yaml:**

- Modify `values.yaml` with your values (role ARN, region, log group, Kafka broker, token). Then from the chart directory:

```bash
helm install akto-aws-api-gateway-connector . -n akto -f values.yaml
```

**Required values:**

- `serviceAccount.roleArn` – IAM role ARN from Step 2 (IRSA).
- `env.AWS_REGION` – AWS region (e.g. `ap-south-1`, `us-east-1`).
- `env.LOG_GROUP_NAME` – CloudWatch log group name (or comma-separated names).
- `env.AKTO_KAFKA_BROKER_MAL` – Kafka broker address (e.g. from Akto mini-runtime).
- `env.DATABASE_ABSTRACTOR_TOKEN` – Token from Akto dashboard (for Cyborg / OpenAPI discovery).

**Multiple log groups with `--set`:** If `LOG_GROUP_NAME` contains commas (e.g. `log-group-1,log-group-2`), Helm treats commas as separators and fails. Escape each comma with a backslash: use `\,` inside the value. Example:

```bash
--set 'env.LOG_GROUP_NAME=API-Gateway-Execution-Logs_abc/demo\,API-Gateway-Execution-Logs_xyz/prod'
```

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
