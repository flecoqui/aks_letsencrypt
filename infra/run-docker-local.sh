#!/bin/bash
set -e
export PORT_HTTP=5001
export APP_VERSION=$(date +"%y%M%d.%H%M%S")
export REST_API_NAME="webapp"
export IMAGE_NAME="${REST_API_NAME}-image"
export IMAGE_TAG=${APP_VERSION}
export CONTAINER_NAME="${REST_API_NAME}-container"
export ALTERNATIVE_TAG="latest"

echo "PORT_HTTP $PORT_HTTP"
echo "APP_VERSION $APP_VERSION"
echo "IMAGE_NAME $IMAGE_NAME"
echo "IMAGE_TAG $IMAGE_TAG"
echo "ALTERNATIVE_TAG $ALTERNATIVE_TAG"


export RESOURCE_GROUP="rg5gpocclouddev"
export STORAGE_ACCOUNT="st5gpocfnzn"
export REFERENCE_STORAGE_CONTAINER="referenceextraction"
export REALTIME_STORAGE_CONTAINER="realtimeextraction"
export SOURCE_RTSP_URI="rtsp://acisimcam.westeurope.azurecontainer.io:554/media/sfence1.mp4"

echo "Get resource names from ${RESOURCE_GROUP}"
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

echo "Configuring the access Azure Key Vault ${KEYVAULT_NAME}"
KEYVAULT_NAME=$(az keyvault list --resource-group ${RESOURCE_GROUP} | jq -r '.[0].name')
USER_SP_ID=$(az ad signed-in-user show --query id --output tsv 2>/dev/null) || true
if [ -z ${USER_SP_ID} ]
then
    USER_SP_ID=$(az ad sp show --id "$(az account show | jq -r .user.name)" --query id --output tsv  2> /dev/null) || true
fi
IP_ADDRESS=$(curl -s ifconfig.me)
az keyvault network-rule add --name ${KEYVAULT_NAME}  --resource-group ${RESOURCE_GROUP} --ip-address ${IP_ADDRESS} >/dev/null || true
if [ ! -z "${USER_SP_ID}" ] 
then
  az keyvault set-policy -n "${KEYVAULT_NAME}"  --resource-group "${RESOURCE_GROUP}" --secret-permissions get list --object-id "${USER_SP_ID}" >/dev/null
fi

echo "Reading secret in Azure Key Vault ${KEYVAULT_NAME}"
COMPUTER_VISION_ENDPOINT=$(az keyvault secret show --name "computerVisionEndpoint" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
COMPUTER_VISION_KEY=$(az keyvault secret show --name "computerVisionPrimaryAccessKey" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_LOGIN=$(az keyvault secret show --name "postgresqlServerLogin" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_PASSWORD=$(az keyvault secret show --name "postgresqlServerPassword" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_FQDN=$(az keyvault secret show --name "postgresqlServerFqdn" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
POSTGRESSQL_DB=$(az keyvault secret show --name "postgresqlDbName" --vault-name "${KEYVAULT_NAME}"   --query "value" --output tsv)
DB_STRING="postgresql://${POSTGRESSQL_LOGIN}@${POSTGRESQL_ACCOUNT}:${POSTGRESSQL_PASSWORD}@${POSTGRESSQL_FQDN}:5432/${POSTGRESSQL_DB}"
VIDEO_INGESTION_URI="http://127.0.0.1:5000/v1"
REALTIME_ANALYSIS_URL="http://127.0.0.1:4000/v1"
REFERENCE_ANALYSIS_URL="http://127.0.0.1:3000/v1"

echo "DB_STRING: ${DB_STRING}"





result=$(docker image inspect $IMAGE_NAME:$ALTERNATIVE_TAG  2>/dev/null) || true
#if [[ ${result} == "[]" ]]; then
    cmd="docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile --build-arg ARG_APP_VERSION=${IMAGE_TAG} --build-arg ARG_PORT_HTTP=${PORT_HTTP}  ."
    echo "$cmd"
    eval "$cmd"

    #docker push ${IMAGE_NAME}:${IMAGE_TAG}
    # Push with alternative tag
    cmd="docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:${ALTERNATIVE_TAG}"
    echo "$cmd"
    eval "$cmd"
    #docker push ${IMAGE_NAME}:${ALTERNATIVE_TAG}
#fi
docker stop ${CONTAINER_NAME} 2>/dev/null || true
cmd="docker run -d -it -e PORT_HTTP=${PORT_HTTP} \
    -e APP_VERSION=${IMAGE_TAG} \
    -e DB_STRING=\"${DB_STRING}\" \
    -e AZURE_STORAGE_CONNECTION_STRING=\"${ARG_AZURE_STORAGE_CONNECTION_STRING}\" \
    -e REFERENCE_IMAGES_STORAGE_CONTAINER=${REFERENCE_STORAGE_CONTAINER} \
    -e REALTIME_IMAGES_STORAGE_CONTAINER=${REALTIME_STORAGE_CONTAINER} \
    -e COMPUTER_VISION_ENDPOINT=${COMPUTER_VISION_ENDPOINT} \
    -e COMPUTER_VISION_SUBSCRIPTION_KEY=\"${COMPUTER_VISION_KEY}\" \
    -e VIDEO_INGESTION_URI=${VIDEO_INGESTION_URI} \
    -e REALTIME_ANALYSIS_URL=${REALTIME_ANALYSIS_URL} \
    -e REFERENCE_ANALYSIS_URL=${REFERENCE_ANALYSIS_URL} \
    -p ${PORT_HTTP}:${PORT_HTTP}/tcp -v /opt/apps/webapp:/src --rm --name ${CONTAINER_NAME}  ${IMAGE_NAME}:${ALTERNATIVE_TAG}"
echo "$cmd"
eval "$cmd"
echo "Open http://127.0.0.1:${PORT_HTTP}/docs"
