#!/bin/bash
set -e

REGISTRY_NAME=acr5gpocfnzn
ACR_URL="acr5gpocfnzn.azurecr.io"
RESOURCE_GROUP="rg5gpocclouddev"
AKS_CLUSTER="nttaks"
PUBLIC_IP_ADDRESS_NAME="pip5gpocclouddev"
DNS_LABEL="aks5gpocclouddev"
INGRESS_NAMESPACE="clouddev"
NAMESPACE="clouddev"
SERVICE_NAME="webapp"
SERVICE_PORT="80"

SOURCE_REGISTRY=k8s.gcr.io
CONTROLLER_IMAGE=ingress-nginx/controller
CONTROLLER_TAG=v1.2.1
PATCH_IMAGE=ingress-nginx/kube-webhook-certgen
PATCH_TAG=v1.1.1
DEFAULTBACKEND_IMAGE=defaultbackend-amd64
DEFAULTBACKEND_TAG=1.5

echo "Importing nginx controller, kube-webhook-certgen, defaultbackend-amd64"
SOURCE_NAME=$(az acr repository show --name $REGISTRY_NAME --image $CONTROLLER_IMAGE:$CONTROLLER_TAG | jq -r '.name')
if [ "${SOURCE_NAME}" != "${CONTROLLER_TAG}" ]
then
  az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$CONTROLLER_IMAGE:$CONTROLLER_TAG --image $CONTROLLER_IMAGE:$CONTROLLER_TAG
fi

SOURCE_NAME=$(az acr repository show --name $REGISTRY_NAME --image $PATCH_IMAGE:$PATCH_TAG | jq -r '.name')
if [ "${SOURCE_NAME}" != "${PATCH_TAG}" ]
then
az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$PATCH_IMAGE:$PATCH_TAG --image $PATCH_IMAGE:$PATCH_TAG
fi

SOURCE_NAME=$(az acr repository show --name $REGISTRY_NAME --image $DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG | jq -r '.name')
if [ "${SOURCE_NAME}" != "${DEFAULTBACKEND_TAG}" ]
then
  az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG --image $DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG
fi

echo "Get kubectl credentials"
cmd="az aks get-credentials --name ${AKS_CLUSTER} --resource-group ${RESOURCE_GROUP}"
# echo "${cmd}"
eval "${cmd}"
echo "Create Name Space: ${INGRESS_NAMESPACE}"
cmd="kubectl create namespace ${INGRESS_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -"
# echo "${cmd}"
eval "${cmd}"

helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
# Label the ingress-basic namespace to disable resource validation
kubectl label namespace ${INGRESS_NAMESPACE} cert-manager.io/disable-validation=true

helm repo update

echo "Importing  cert-manager-controller, cert-manager-webhook, cert-manager-cainjector"
CERT_MANAGER_REGISTRY=quay.io
CERT_MANAGER_TAG=v1.8.0
CERT_MANAGER_IMAGE_CONTROLLER=jetstack/cert-manager-controller
CERT_MANAGER_IMAGE_WEBHOOK=jetstack/cert-manager-webhook
CERT_MANAGER_IMAGE_CAINJECTOR=jetstack/cert-manager-cainjector

SOURCE_NAME=$(az acr repository show --name $REGISTRY_NAME --image $CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG | jq -r '.name')
if [ "${SOURCE_NAME}" != "${CERT_MANAGER_TAG}" ]
then
  az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG
fi

SOURCE_NAME=$(az acr repository show --name $REGISTRY_NAME --image $CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG | jq -r '.name')
if [ "${SOURCE_NAME}" != "${CERT_MANAGER_TAG}" ]
then
  az  acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG
fi

SOURCE_NAME=$(az acr repository show --name $REGISTRY_NAME --image $CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG | jq -r '.name')
if [ "${SOURCE_NAME}" != "${CERT_MANAGER_TAG}" ]
then
  az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG
fi

echo "Check if AKS Public IP address is already available"
NODE_RESOURCE_GROUP=$(az aks show --resource-group ${RESOURCE_GROUP} --name ${AKS_CLUSTER} --query nodeResourceGroup -o tsv)
INGRESS_IP=$(az network public-ip show --resource-group ${NODE_RESOURCE_GROUP} --name ${PUBLIC_IP_ADDRESS_NAME} | jq -r '.ipAddress' 2>/dev/null) || true 
if [ -z ${INGRESS_IP} ] 
then
  echo "Creating Public IP address for ingress..."
  INGRESS_IP=$(az network public-ip create --resource-group ${NODE_RESOURCE_GROUP} --name ${PUBLIC_IP_ADDRESS_NAME} --sku Standard --allocation-method static --query publicIp.ipAddress -o tsv)
fi
echo "AKS Public IP address ${INGRESS_IP}"

echo "Undeploying nginx controller"
helm delete ingress-nginx   --namespace $INGRESS_NAMESPACE 2>/dev/null || true 

echo "Deploying nginx controller"
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace \
  --namespace $INGRESS_NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

echo "Associate public IP address: ${INGRESS_IP}  with DNS name: ${DNS_LABEL}"
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$INGRESS_IP')].[id]" --output tsv)
if [ ! -z ${PUBLICIPID} ]
then
  az network public-ip update --ids $PUBLICIPID --dns-name $DNS_LABEL
else
  echo "IP address: ${INGRESS_IP} not found"
  exit 1
fi

echo "Getting DNS name for the AKS Cluster"
FQDN=$(az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv)
echo "AKS Cluster DNS name ${FQDN}"

if [ -z ${FQDN} ]
then
  echo "AKS Cluster DNS name not found"
  exit 1
fi

echo "Updating the Ingress controller with public IP address: ${INGRESS_IP} and DNS name: ${DNS_LABEL}"
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace $INGRESS_NAMESPACE \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNS_LABEL \
  --set controller.service.loadBalancerIP=${INGRESS_IP}

CONTROLLER_IP=$(kubectl get services -n $INGRESS_NAMESPACE  -ojson | jq -r '.items[] | select(.metadata.name == "ingress-nginx-controller").status.loadBalancer.ingress[0].ip')
COUNT=0
while [ -z ${CONTROLLER_IP} ] || [ "${CONTROLLER_IP}" == "null" ]; do                       
    echo 'Ingress Controller IP not available yet, waiting...'  
    sleep 10
    ((COUNT=COUNT+10))
    if [ ${COUNT} -gt 60 ]; then
        echo "Ingress Controller IP is still not available after 60 seconds" 
        exit 1
    fi
    CONTROLLER_IP=$(kubectl get services -n $INGRESS_NAMESPACE  -ojson | jq -r '.items[] | select(.metadata.name == "ingress-nginx-controller").status.loadBalancer.ingress[0].ip')
done

echo "Public IP address ${CONTROLLER_IP} enable on AKS "


echo "Deploy cert-manager with helm"
# Install the cert-manager Helm chart
helm uninstall cert-manager   --namespace ${INGRESS_NAMESPACE} 2>/dev/null || true
helm install cert-manager jetstack/cert-manager \
  --namespace ${INGRESS_NAMESPACE} \
  --version $CERT_MANAGER_TAG \
  --set installCRDs=true \
  --set nodeSelector."kubernetes\.io/os"=linux \
  --set image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CONTROLLER \
  --set image.tag=$CERT_MANAGER_TAG \
  --set webhook.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_WEBHOOK \
  --set webhook.image.tag=$CERT_MANAGER_TAG \
  --set cainjector.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CAINJECTOR \
  --set cainjector.image.tag=$CERT_MANAGER_TAG

echo "Deploy cluster-issuer with kubectl"
EMAIL="admin@myorg.com"
sed 's/\[MY_EMAIL_ADDRESS\]/'${EMAIL}'/g' ./cluster-issuer-template.yml > "${TEMP_DIR}/cluster-issuer.yml" 
echo "${TEMP_DIR}/cluster-issuer.yml" 
cat "${TEMP_DIR}/cluster-issuer.yml" 
kubectl delete -f "${TEMP_DIR}/cluster-issuer.yml"  --namespace $NAMESPACE  2>/dev/null || true
echo "kubectl apply -f ${TEMP_DIR}/cluster-issuer.yml --namespace $NAMESPACE "
kubectl apply -f "${TEMP_DIR}/cluster-issuer.yml"  --namespace $NAMESPACE

echo "Deploy webapp-ingress-ssl with kubectl"
sed 's/\[FQDN\]/'${FQDN}'/g' ./webapp-ingress-ssl-template.yml > "${TEMP_DIR}/webapp-ingress-ssl.yml" 
sed -i 's/\[SERVICE_NAME\]/'${SERVICE_NAME}'/g' "${TEMP_DIR}/webapp-ingress-ssl.yml"
sed -i 's/\[SERVICE_PORT\]/'${SERVICE_PORT}'/g' "${TEMP_DIR}/webapp-ingress-ssl.yml"
echo "${TEMP_DIR}/webapp-ingress-ssl.yml" 
cat "${TEMP_DIR}/webapp-ingress-ssl.yml" 
kubectl delete -f "${TEMP_DIR}/webapp-ingress-ssl.yml"  --namespace "${NAMESPACE}"  2>/dev/null || true
echo "kubectl apply -f ${TEMP_DIR}/webapp-ingress-ssl.yml  --namespace ${NAMESPACE}"
kubectl apply -f "${TEMP_DIR}/webapp-ingress-ssl.yml"  --namespace "${NAMESPACE}"

echo "Check Certificate status"
kubectl get certificate --namespace ${NAMESPACE}

echo "Deploy service ${SERVICE_NAME} on AKS "
TEMP_DIR=$(mktemp -d)
sed 's/\[SERVICE_NAME\]/'${SERVICE_NAME}'/g' ./webapp-template.yml > "${TEMP_DIR}/webapp.yml" 
echo "${TEMP_DIR}/webapp.yml" 
cat "${TEMP_DIR}/webapp.yml" 
kubectl delete -f "${TEMP_DIR}/webapp.yml" --namespace $NAMESPACE  2>/dev/null || true
echo "kubectl apply -f ${TEMP_DIR}/webapp.yml --namespace $NAMESPACE"
kubectl apply -f "${TEMP_DIR}/webapp.yml" --namespace $NAMESPACE

echo "Wait 20 seconds"
sleep 20


echo "Wait 30 seconds"
sleep 30

echo "Test the service on AKS: https://${FQDN}/${SERVICE_NAME}"
RESULT=$(curl -i -s -X GET https://${FQDN}/${SERVICE_NAME} | grep  "<title>Welcome") || true
echo "RESULT: ${RESULT}"
if [ -z "${RESULT}" ]
then
  echo "Ingress Deployment failed: https://${FQDN}/${SERVICE_NAME}"
else
  echo "Ingress Deployment successful: https://${FQDN}/${SERVICE_NAME}"
fi

echo "To remove all the resources run:"
echo "kubectl delete -f ${TEMP_DIR}/cluster-issuer.yml --namespace $NAMESPACE"
echo "helm uninstall cert-manager nginx --namespace  $INGRESS_NAMESPACE"
echo "helm uninstall ingress-nginx --namespace $INGRESS_NAMESPACE"
echo "kubectl delete -f ${TEMP_DIR}/webapp.yml --namespace $NAMESPACE"
echo "kubectl delete -f ${TEMP_DIR}/webapp-ingress-ssl.yml --namespace $NAMESPACE"
echo "kubectl delete namespace $INGRESS_NAMESPACE"