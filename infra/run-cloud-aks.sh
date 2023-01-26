#!/bin/bash
set -e
export SERVICE_NAME="webapp"
export SERVICE_IMAGE="ntt/${SERVICE_NAME}-image:latest"
export SERVICE_NAME_SPACE="clouddev"
export SERVICE_PORT="5001"
export LOCAL_PORT="6060"
export NAME_SPACE="clouddev"
export RESOURCE_GROUP="rg5gpocclouddev"
export AKS_CLUSTER="nttaks"
export ACR_LOGIN_SERVER="acr5gpocfnzn.azurecr.io"
export STORAGE_ACCOUNT="st5gpocfnzn"
export AZURE_STORAGE_CONNECTION_STRING=""
export REFERENCE_STORAGE_CONTAINER="referenceextraction"
export REALTIME_STORAGE_CONTAINER="realtimeextraction"
export SOURCE_RTSP_URI="rtsp://acisimcam.westeurope.azurecontainer.io:554/media/sfence1.mp4"
export VIDEO_INGESTION_SERVICE_NAME="videoingestion"
export ANOMALY_DETECTION_SERVICE_NAME="anomalydetection"

echo "Get resource names from ${RESOURCE_GROUP}"
ACR_LOGIN_SERVER=$(az acr list --resource-group ${RESOURCE_GROUP} | jq -r '.[0].loginServer')
AKS_CLUSTER=$(az aks list --resource-group ${RESOURCE_GROUP} | jq -r '.[0].name')
STORAGE_ACCOUNT=$(az storage account list --resource-group ${RESOURCE_GROUP} | jq -r '.[0].name')
POSTGRESQL_ACCOUNT=$(az postgres server list --resource-group ${RESOURCE_GROUP} | jq  -r '.[0].name')
POSTGRESQL_FQDN=$(az postgres server list --resource-group ${RESOURCE_GROUP} | jq  -r '.[0].fullyQualifiedDomainName')
POSTGRESQL_DATABASE=""
for i in $(az postgres db list -g ${RESOURCE_GROUP} -s ${POSTGRESQL_ACCOUNT} | jq -r '.[].name') 
do 
  if [ "$i" != 'postgres' ] && [ "$i" != 'azure_sys' ] && [ "$i" != 'azure_maintenance' ] 
  then 
    POSTGRESQL_DATABASE=$i 
    break 
  fi 
done

if [ -z ${POSTGRESQL_DATABASE} ]
then
  echo "Error POSTGRESQL Database not found"
  exit 1
fi

IP_ADDRESS=$(curl -s ifconfig.me)
KEYVAULT_NAME=$(az keyvault list --resource-group ${RESOURCE_GROUP} | jq -r '.[0].name')
USER_SP_ID=$(az ad signed-in-user show --query id --output tsv 2>/dev/null) || true  
if [ -z ${USER_SP_ID} ] 
then
    USER_SP_ID=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null) || true
fi
echo "USER_SP_ID: ${USER_SP_ID}"

echo "Configuring the access Azure Key Vault ${KEYVAULT_NAME}"
az keyvault network-rule add --name ${KEYVAULT_NAME}  --resource-group ${RESOURCE_GROUP} --ip-address ${IP_ADDRESS} >/dev/null || true
if [ ! -z "${USER_SP_ID}" ] 
then
  az keyvault set-policy -n "${KEYVAULT_NAME}"  --resource-group "${RESOURCE_GROUP}" --secret-permissions get list --object-id "${USER_SP_ID}"  >/dev/null
fi

echo "Reading secret in Azure Key Vault ${KEYVAULT_NAME}"
COMPUTER_VISION_ENDPOINT=$(az keyvault secret show --name "computerVisionEndpoint" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
COMPUTER_VISION_KEY=$(az keyvault secret show --name "computerVisionPrimaryAccessKey" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_LOGIN=$(az keyvault secret show --name "postgresqlServerLogin" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_PASSWORD=$(az keyvault secret show --name "postgresqlServerPassword" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)

AZURE_STORAGE_CONNECTION_STRING=$(az keyvault secret show --name "storageConnectionString" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)


POSTGRESSQL_FQDN=$(az keyvault secret show --name "postgresqlServerFqdn" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_DB=$(az keyvault secret show --name "postgresqlDbName" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
DB_STRING="postgresql://${POSTGRESSQL_LOGIN}@${POSTGRESQL_ACCOUNT}:${POSTGRESSQL_PASSWORD}@${POSTGRESSQL_FQDN}:5432/${POSTGRESSQL_DB}"
VIDEO_INGESTION_URI="http://10.244.1.46:5000/v1"
REALTIME_ANALYSIS_URL="http://127.0.0.1:4000/v1"
REFERENCE_ANALYSIS_URL="http://127.0.0.1:3000/v1"


echo "ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}"
echo "AKS_CLUSTER=${AKS_CLUSTER}"
echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT}"
echo "POSTGRESQL_ACCOUNT=${POSTGRESQL_ACCOUNT}"
echo "POSTGRESQL_FQDN=${POSTGRESQL_FQDN}"
echo "POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE}"
echo "DB_STRING: ${DB_STRING}"

echo "Get kubectl credentials"
cmd="az aks get-credentials --name ${AKS_CLUSTER} --resource-group ${RESOURCE_GROUP}"
# echo "${cmd}"
eval "${cmd}"

echo "List of pods"
cmd="kubectl get pods --all-namespaces"
# echo "${cmd}"
eval "${cmd}"


echo "Create Name Space: ${NAME_SPACE}"
cmd="kubectl create namespace ${NAME_SPACE} --dry-run=client -o yaml | kubectl apply -f -"
# echo "${cmd}"
eval "${cmd}"


echo "Get Video Ingestion container IP address in  Name Space: ${NAME_SPACE}"
VIDEO_INGESTION_POD_NAME=$(kubectl get pods -n ${NAME_SPACE} -o json | jq -r '.items[] | select(.metadata.name | startswith("videoingestion")).metadata.name ')
if [ ! -z "${VIDEO_INGESTION_POD_NAME}" ]
then
  VIDEO_INGESTION_POD_IP=$(kubectl get pod ${VIDEO_INGESTION_POD_NAME}  -n ${NAME_SPACE}  --template '{{.status.podIP}}')
  if [ ! -z "${VIDEO_INGESTION_POD_IP}" ]
  then
    VIDEO_INGESTION_URI="http://${VIDEO_INGESTION_POD_IP}:5000/v1"
  fi
fi
VIDEO_INGESTION_URI="http://${VIDEO_INGESTION_SERVICE_NAME}:80/v1"

echo "Preparing deployment file for ${SERVICE_NAME}" 
TEMP_DIR=$(mktemp -d)
sed 's/\[SERVICE_PORT\]/'${SERVICE_PORT}'/g' ./deploy-webapp-template.yaml > "${TEMP_DIR}/deploy.yaml" 
sed -i 's/\[SERVICE_NAME\]/'${SERVICE_NAME}'/g' "${TEMP_DIR}/deploy.yaml"
sed -i 's/\[NAME_SPACE\]/'${NAME_SPACE}'/g' "${TEMP_DIR}/deploy.yaml"
sed -i 's/\[ACR_LOGIN_SERVER\]/'${ACR_LOGIN_SERVER}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_SERVICE_IMAGE=$(printf '%s' "${SERVICE_IMAGE}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[SERVICE_IMAGE\]/'${ESCAPED_SERVICE_IMAGE}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_AZURE_STORAGE_CONNECTION_STRING=$(printf '%s' "${AZURE_STORAGE_CONNECTION_STRING}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[AZURE_STORAGE_CONNECTION_STRING\]/'${ESCAPED_AZURE_STORAGE_CONNECTION_STRING}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_DB_STRING=$(printf '%s' "${DB_STRING}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[DB_STRING\]/'${ESCAPED_DB_STRING}'/g' "${TEMP_DIR}/deploy.yaml"
sed -i 's/\[REFERENCE_IMAGES_STORAGE_CONTAINER\]/'${REFERENCE_STORAGE_CONTAINER}'/g' "${TEMP_DIR}/deploy.yaml"
sed -i 's/\[REALTIME_IMAGES_STORAGE_CONTAINER\]/'${REALTIME_STORAGE_CONTAINER}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_COMPUTER_VISION_ENDPOINT=$(printf '%s' "${COMPUTER_VISION_ENDPOINT}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[COMPUTER_VISION_ENDPOINT\]/'${ESCAPED_COMPUTER_VISION_ENDPOINT}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_COMPUTER_VISION_KEY=$(printf '%s' "${COMPUTER_VISION_KEY}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[COMPUTER_VISION_SUBSCRIPTION_KEY\]/'${ESCAPED_COMPUTER_VISION_KEY}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_VIDEO_INGESTION_URI=$(printf '%s' "${VIDEO_INGESTION_URI}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[VIDEO_INGESTION_URI\]/'${ESCAPED_VIDEO_INGESTION_URI}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_REALTIME_ANALYSIS_URL=$(printf '%s' "${REALTIME_ANALYSIS_URL}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[REALTIME_ANALYSIS_URL\]/'${ESCAPED_REALTIME_ANALYSIS_URL}'/g' "${TEMP_DIR}/deploy.yaml"
ESCAPED_REFERENCE_ANALYSIS_URL=$(printf '%s' "${REFERENCE_ANALYSIS_URL}" | sed -e 's/[\/&]/\\&/g')
sed -i 's/\[REFERENCE_ANALYSIS_URL\]/'${ESCAPED_REFERENCE_ANALYSIS_URL}'/g' "${TEMP_DIR}/deploy.yaml"

cat "${TEMP_DIR}/deploy.yaml"

POD_STATUS=$(kubectl get pods -n ${NAME_SPACE} -o json | jq -r '.items[] | select(.metadata.name | startswith("'${SERVICE_NAME}'")).status.phase ') || true
echo "POD_STATUS: ${POD_STATUS}"
if [ ! -z "${POD_STATUS}" ]
then
  echo "Undeploy service ${SERVICE_NAME} if already running" 
  cmd="kubectl delete -f ${TEMP_DIR}/deploy.yaml -n ${NAME_SPACE} "
  echo "${cmd}"
  eval "${cmd}" || true
  echo "Wait 60 seconds"
  sleep 60 
fi

echo "Deploy service ${SERVICE_NAME}" 
cmd="kubectl apply -f ${TEMP_DIR}/deploy.yaml"
echo "${cmd}"
eval "${cmd}"

cmd="kubectl get pods -n ${NAME_SPACE}"
echo "${cmd}"
eval "${cmd}"

POD_NAME=$(kubectl get pods -n ${NAME_SPACE} -o json | jq -r '.items[] | select(.metadata.name | startswith("'${SERVICE_NAME}'")).metadata.name ')
POD_STATUS=$(kubectl get pods -n ${NAME_SPACE} -o json | jq -r '.items[] | select(.metadata.name | startswith("'${SERVICE_NAME}'")).status.phase ')


COUNT=0
while [ ${POD_STATUS} != "Running" ]; do                       
    echo 'Pod not running yet, waiting...'  
    sleep 10
    ((COUNT=COUNT+10))
    if [ ${COUNT} -gt 60 ]; then
        echo "Service ${SERVICE_NAME} is not running after 60 seconds, status: ${POD_STATUS}" 
        exit 1
    fi
    POD_STATUS=$(kubectl get pods -n ${NAME_SPACE} -o json | jq -r '.items[] | select(.metadata.name | startswith("'${SERVICE_NAME}'")).status.phase ')
done
echo "Service ${SERVICE_NAME} is now ${POD_STATUS}" 


echo "Forwarding port" 
cmd="kubectl port-forward ${POD_NAME} -n ${NAME_SPACE} ${LOCAL_PORT}:${SERVICE_PORT}"
echo "${cmd}"
eval "${cmd}"&

sleep 10
echo "Get health probe response" 
curl -X "GET"\
  "http://127.0.0.1:${LOCAL_PORT}/health" \
  -H "accept: application/json"

echo "Create SAS Token for Azure Storage Account  ${STORAGE_ACCOUNT}" 
END_DATE=$(date -u -d "2 days" '+%Y-%m-%dT%H:%MZ')
STORAGE_KEY=$(az storage account keys list --account-name ${STORAGE_ACCOUNT} --resource-group ${RESOURCE_GROUP} | jq -r '.[0].value')
SAS_TOKEN=$(az storage container generate-sas \
    --account-name ${STORAGE_ACCOUNT} \
    --name ${REFERENCE_STORAGE_CONTAINER} \
    --permissions acdlrw \
    --expiry ${END_DATE} \
    --account-key ${STORAGE_KEY} -o tsv)

echo "SAS Token: ${SAS_TOKEN}"

PROCESS_NAME="PROCESS-$(date -u  '+%Y-%m-%d-%H-%M-%S')"
FOLDER_NAME="$(date -u  '+%Y-%m-%d')"


echo "Create a video ingestion process" 

cmd="curl -s -X 'POST' \
  '"http://127.0.0.1:${LOCAL_PORT}/v1/video-recording/start"' \
  -H 'accept: application/json'  -H 'Content-Type: application/json' \
  -d '{\"process_name\":\"${PROCESS_NAME}\",\"video_resource_url\":\"${SOURCE_RTSP_URI}\",\"storage_account\":\"${STORAGE_ACCOUNT}\",\"storage_container\":\"${REFERENCE_STORAGE_CONTAINER}\",\"storage_folder\":\"${FOLDER_NAME}\",\"storage_sas_token\":\"${SAS_TOKEN}\"}'"
echo "$cmd"
PROCESS_ID=$(eval "$cmd" | jq -r '.process_id') || true
if [ -z "${PROCESS_ID}" ] || [ "${PROCESS_ID}" == "null" ]; then
    echo "Error no process created, id: ${VIDEO_INGESTION_ID}" 
    echo "Kill kubectl port forwarding" 
    PID=$(pgrep kubectl)
    if [ -n ${PID} ]; then
        kill -9 ${PID}
    fi
    exit 1
else
  echo "Process created: ${PROCESS_ID}"
fi
echo "Wait 60 seconds"
sleep 60 

echo "Stop video ingestion process" 
curl -X "POST"\
  "http://127.0.0.1:${LOCAL_PORT}/v1/video-recording/${PROCESS_ID}/stop" \
  -H "accept: application/json" \
  -d ""

echo "Kill kubectl port forwarding" 
PID=$(pgrep kubectl)
if [ -n ${PID} ]; then
    kill -9 ${PID}
fi


echo "Undeploy the service  ${SERVICE_NAME}" 
cmd="kubectl delete -f ${TEMP_DIR}/deploy.yaml"
echo "${cmd}"
eval "${cmd}"

echo "${SERVICE_NAME} Test sucessful"
