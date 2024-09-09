# Akto setup

You can install Akto via Helm charts. 

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find Akto on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-protection).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)

## Steps 
Here are the steps to install Akto via Helm charts - 

### Collect the env variables needed to install akto-protection

1. AKTO_TOKEN : You'll find this token in akto saas dashboard under quick start > hybrid saas . To see the complete docs, visit https://docs.akto.io/traffic-connections/traffic-data-sources/hybrid-saas .

### Install Akto via Helm

1. Add Akto repo
   ```helm repo add akto https://akto-api-security.github.io/helm-charts```
2. Install Akto via helm
   ```bash
   helm install akto-protection akto/akto-protection -n <NAMESPACE> \
    --set runtime.aktoApiSecurityProtection.env.databaseAbstractorToken="<AKTO_TOKEN>"
   ```
3. Run `kubectl get pods -n <NAMESPACE>` and verify you can see 3 pods
