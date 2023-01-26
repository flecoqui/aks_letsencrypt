#!/bin/bash
set -e

REGISTRY_NAME=acr5gpocfnzn
SOURCE_REGISTRY=k8s.gcr.io
CONTROLLER_IMAGE=ingress-nginx/controller
CONTROLLER_TAG=v1.2.1
PATCH_IMAGE=ingress-nginx/kube-webhook-certgen
PATCH_TAG=v1.1.1
DEFAULTBACKEND_IMAGE=defaultbackend-amd64
DEFAULTBACKEND_TAG=1.5

az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$CONTROLLER_IMAGE:$CONTROLLER_TAG --image $CONTROLLER_IMAGE:$CONTROLLER_TAG
az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$PATCH_IMAGE:$PATCH_TAG --image $PATCH_IMAGE:$PATCH_TAG
az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG --image $DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
NAMESPACE="ingress-basic"
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace \
  --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
kubectl get services -n $NAMESPACE


# Use Helm to deploy an NGINX ingress controller


CERT_MANAGER_REGISTRY=quay.io
CERT_MANAGER_TAG=v1.8.0
CERT_MANAGER_IMAGE_CONTROLLER=jetstack/cert-manager-controller
CERT_MANAGER_IMAGE_WEBHOOK=jetstack/cert-manager-webhook
CERT_MANAGER_IMAGE_CAINJECTOR=jetstack/cert-manager-cainjector

az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG
az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG
az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG


NODE_RESOURCE_GROUP=$(az aks show --resource-group rg5gpocclouddev --name nttaks --query nodeResourceGroup -o tsv)

#az network public-ip create --resource-group ${NODE_RESOURCE_GROUP} --name ip5gpocclouddev --sku Standard --allocation-method static --query publicIp.ipAddress -o tsv
INGRESS_IP=$(az network public-ip create --resource-group MC_rg5gpocclouddev_nttaks_westeurope --name ip5gpocclouddev --sku Standard --allocation-method static --query publicIp.ipAddress -o tsv)

DNS_LABEL="aksdns5gpocclouddev"
STATIC_IP="104.214.234.65"

helm repo add stable https://charts.helm.sh/stable


helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNS_LABEL \
  --set controller.service.loadBalancerIP=${STATIC_IP}

kubectl get services -n $NAMESPACE



# Get the resource-id of the public IP
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$STATIC_IP')].[id]" --output tsv)

# Update public IP address with DNS name
az network public-ip update --ids $PUBLICIPID --dns-name $DNS_LABEL

# Display the FQDN
az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv
#FQDN=$(az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv)
#RESULT:
FQDN="aksdns5gpocclouddev.westeurope.cloudapp.azure.com"

helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace $NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNS_LABEL

ACR_URL="acr5gpocfnzn.azurecr.io"

# Label the ingress-basic namespace to disable resource validation
kubectl label namespace ingress-basic cert-manager.io/disable-validation=true

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
helm repo update

# Install the cert-manager Helm chart
helm install cert-manager jetstack/cert-manager \
  --namespace ingress-basic \
  --version $CERT_MANAGER_TAG \
  --set installCRDs=true \
  --set nodeSelector."kubernetes\.io/os"=linux \
  --set image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CONTROLLER \
  --set image.tag=$CERT_MANAGER_TAG \
  --set webhook.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_WEBHOOK \
  --set webhook.image.tag=$CERT_MANAGER_TAG \
  --set cainjector.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CAINJECTOR \
  --set cainjector.image.tag=$CERT_MANAGER_TAG

TEMP_DIR=$(mktemp -d)
EMAIL="admin@global.ntt"
sed 's/\[MY_EMAIL_ADDRESS\]/'${EMAIL}'/g' ./cluster-issuer-template.yml > "${TEMP_DIR}/cluster-issuer.yml" 
echo "${TEMP_DIR}/cluster-issuer.yml" 
cat "${TEMP_DIR}/cluster-issuer.yml" 
kubectl apply -f "${TEMP_DIR}/cluster-issuer.yml"  --namespace ingress-basic



FQDN="aksdns5gpocclouddev.westeurope.cloudapp.azure.com"
SERVICE_NAME="webapp"
SERVICE_PORT="80"
NAME_SPACE="clouddev"
sed 's/\[FQDN\]/'${FQDN}'/g' ./webapp-ingress-template.yml > "${TEMP_DIR}/webapp-ingress.yml" 
sed -i 's/\[SERVICE_NAME\]/'${SERVICE_NAME}'/g' "${TEMP_DIR}/webapp-ingress.yml"
sed -i 's/\[SERVICE_PORT\]/'${SERVICE_PORT}'/g' "${TEMP_DIR}/webapp-ingress.yml"
sed -i 's/\[NAME_SPACE\]/'${NAME_SPACE}'/g' "${TEMP_DIR}/webapp-ingress.yml"
echo "${TEMP_DIR}/webapp-ingress.yml" 
cat "${TEMP_DIR}/webapp-ingress.yml" 
kubectl apply -f "${TEMP_DIR}/webapp-ingress.yml"  

