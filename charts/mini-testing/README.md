# Akto setup

You can install Akto via Helm charts. 

## Resources
Akto's Helm chart repo is on GitHub [here](https://github.com/akto-api-security/helm-charts).
You can also find Akto mini-testing module on Helm.sh [here](https://artifacthub.io/packages/helm/akto/akto-mini-testing).

## Prerequisites
Please ensure you have the following -
1. A Kubernetes cluster where you have deploy permissions
2. `helm` command installed. Check [here](https://helm.sh/docs/intro/install/)

## Steps 
Here are the steps to install Akto mini-testing via Helm charts - 

### Collect the env variables needed to install mini-testing

1. AKTO_TOKEN : You'll find this token in akto saas dashboard under quick start > hybrid saas . To see the complete docs, visit https://docs.akto.io/traffic-connections/traffic-data-sources/hybrid-saas .
2. PROXY_URI, NO_PROXY_URLS: Proxy variables to be used if internet connectivity is behind a proxy, skip these variables.

### Install Akto via Helm

1. Add Akto repo
   ```helm repo add akto https://akto-api-security.github.io/helm-charts```
2. Install Akto via helm
   ```bash
   helm install akto-mini-testing akto/akto-mini-testing -n <NAMESPACE> \
    --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>"
   ```
   ```bash
   helm install akto-mini-testing akto/akto-mini-testing -n <NAMESPACE> \
    --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>" \
    --set tokens.env.proxyUri="<PROXY_URI>" \
    --set tokens.env.noProxy="<NO_PROXY_URLS>"
   ```
3. Run `kubectl get pods -n <NAMESPACE>` and verify you can see 1 mini-testing pod with 4 containers and 1 keel pod.

### Upgrading to new version

1. Update helm repo
   ```helm repo update```
2. Check the latest version for mini-testing module
   ```helm show chart akto/akto-mini-testing```
3. Upgrade
   ```bash
   helm upgrade akto-mini-testing akto/akto-mini-testing -n <namespace> --version <latest-version> \
    --set testing.aktoApiSecurityTesting.env.databaseAbstractorToken="<AKTO_TOKEN>
   ```

## Get Support for your Akto setup

There are multiple ways to request support from Akto. We are 24X7 available on the following:

1. In-app `intercom` support. Message us with your query on intercom in Akto dashboard and someone will reply.
2. Join our [discord channel](https://www.akto.io/community) for community support.
3. Contact `help@akto.io` for email support.
4. Contact us [here](https://www.akto.io/contact-us).