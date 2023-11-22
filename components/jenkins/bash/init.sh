#!/bin/bash

# API Reference:
# api/

set -e
set -o errexit
set -o nounset

shopt -s expand_aliases
alias my_kubectl="microk8s kubectl"
alias my_minikube="minikube --profile='dan-cluster'"

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')
SCRIPT_DIRECTORY="$PROJECT_DIRECTORY/components/jenkins/bash"

source "$PROJECT_DIRECTORY/common/common.sh"

# Args: jobName
function postNewJobIfNotFound() {
  local getResult;
  local endpoint;
  local xmlBodyFile;
  local jobName;
  jobName=$1
  xmlBodyFile="${jobName}.xml"
  getResult=$(curl -s -o /dev/null -u ${JENKINS_USER}:11149d32de225c827c8a4841d3ad7bfc78 -w "%{http_code}" "${JENKINS_JOB_PATH}/${jobName}/config.xml")

  if [ "$getResult" != 200 ]
  then
    local postResult;
    postResult=$(curl -s -u ${JENKINS_USER}:${JENKINS_PASSWORD} -X POST -H "Content-Type: application/xml" -d "@$SCRIPT_DIRECTORY/${xmlBodyFile}" "${JENKINS_CREATE_ITEM_PATH}?name=${jobName}")

    common::log "Executed POST against [${JENKINS_CREATE_ITEM_PATH}]: ${postResult}";
  else
    common::warn "Repository [${jobName}] already exists."
  fi
}

# Args: endpoint, jsonBodyFile
function put() {
  local endpoint;
  local apiCallUri;
  local putResult;
  local jsonBodyFile;
  endpoint=$1
  jsonBodyFile=$2
  apiCallUri=${JENKINS_JOB_PATH}${endpoint}

  putResult=$(curl -s -u ${JENKINS_USER}:${JENKINS_PASSWORD} -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d "@$SCRIPT_DIRECTORY/${jsonBodyFile}" "${apiCallUri}")

  common::log "Executed PUT against [${endpoint}]: ${putResult}";
}

# Args: endpoint, jsonBodyFile
function post() {
  local endpoint;
  local apiCallUri;
  local putResult;
  local jsonBodyFile;
  endpoint=$1
  jsonBodyFile=$2
  apiCallUri=${JENKINS_JOB_PATH}${endpoint}

  putResult=$(curl -s -u ${JENKINS_USER}:${JENKINS_PASSWORD} -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "@$SCRIPT_DIRECTORY/${jsonBodyFile}" "${apiCallUri}")

  common::log "Executed PUT against [${endpoint}]: ${putResult}";
}

CLUSTER_TYPE=-1

set +u
 while :
 do
     case $1 in
         --microk8s)
              CLUSTER_TYPE="microk8s"
              ;;
         --minikube)
              CLUSTER_TYPE="minikube"
              ;;
        *)               # Default case: No more options, so break out of the loop.
             break
     esac
     shift
 done
 set -u

if [ "$CLUSTER_TYPE" == -1 ]
then
  common::die "Cluster type option is mandatory (--microk8s or --minikube)"
fi


if [ "$CLUSTER_TYPE" == "minikube" ]
then
  if [[ $(my_minikube status --format='{{.Host}}') != 'Running' ]]; then
    common::die "It seems minikube is not up and running."
  fi

  CLUSTER_IP=$(my_minikube ip)

elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  if [[ $(microk8s status) == *"microk8s is not running"* ]]; then
    common::die "It seems microk8s is not up and running."
  fi

  CLUSTER_IP="127.0.0.1"
else
  common::die "Cluster type value [${CLUSTER_TYPE}] is unexpected"
fi

JENKINS_PORT=32000
JENKINS_URL="http://${CLUSTER_IP}:${JENKINS_PORT}"
JENKINS_JOB_PATH="${JENKINS_URL}/job"
JENKINS_CREATE_ITEM_PATH="${JENKINS_URL}/createItem"

common::log "Waiting for Jenkins to be ready..."
while [ "$(curl -s -o /dev/null -w "%{http_code}" ${JENKINS_URL}/login)" != 200 ];
do echo -n "."; sleep 2 ; done
echo ""
common::log "Jenkins is ready!"

JENKINS_USER="admin"
JENKINS_PASSWORD=$(my_kubectl exec -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo)

common::log "Creating job dan-service-starter-parent..."
postNewJobIfNotFound "dan-service-starter-parent"

common::log "Creating job dan-service-tech-starter..."
postNewJobIfNotFound "dan-service-tech-starter"

common::log "Creating job dan-gateway-service..."
postNewJobIfNotFound "dan-gateway-service"

common::log "Creating job dan-shop-inventory-service..."
postNewJobIfNotFound "dan-shop-inventory-service"

common::log "Creating job dan-shop-products-service..."
postNewJobIfNotFound "dan-shop-products-service"


common::log "Finished!"