#!/bin/bash

# API Reference:
# http://192.168.49.2:30000/#admin/system/api

set -e
set -o errexit
set -o nounset
shopt -s expand_aliases

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')
SCRIPT_DIRECTORY="$PROJECT_DIRECTORY/components/nexus/bash"

source "$PROJECT_DIRECTORY/common/common.sh"

# Args: endpoint, repositoryName
function postNewRepositoryIfNotFound() {
  local getResult;
  local endpoint;
  local jsonBodyFile;
  local apiCallUri;
  local repositoryName;
  endpoint=$1
  repositoryName=$2
  jsonBodyFile="${repositoryName}.json"
  apiCallUri=${NEXUS_API_BASE_PATH}${endpoint}
  getResult=$(curl -s -o /dev/null -u ${NEXUS_USER}:${NEXUS_PASSWORD} -w "%{http_code}" "${apiCallUri}/${repositoryName}")

  if [ "$getResult" != 200 ]
  then
    local postResult;
    postResult=$(curl -s -u ${NEXUS_USER}:${NEXUS_PASSWORD} -X POST -H "Content-Type: application/json" -d "@$SCRIPT_DIRECTORY/${jsonBodyFile}" "${apiCallUri}")

    common::log "Executed POST against [${endpoint}]: ${postResult}";
  else
    common::warn "Repository [${repositoryName}] already exists."
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
  apiCallUri=${NEXUS_API_BASE_PATH}${endpoint}

  putResult=$(curl -s -u ${NEXUS_USER}:${NEXUS_PASSWORD} -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d "@$SCRIPT_DIRECTORY/${jsonBodyFile}" "${apiCallUri}")

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
  apiCallUri=${NEXUS_API_BASE_PATH}${endpoint}

  putResult=$(curl -s -u ${NEXUS_USER}:${NEXUS_PASSWORD} -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "@$SCRIPT_DIRECTORY/${jsonBodyFile}" "${apiCallUri}")

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
  if [[ $(minikube --profile='dan-cluster' status --format='{{.Host}}') != 'Running' ]]; then
    common::die "It seems minikube is not up and running."
  fi

  alias my_kubectl="kubectl"
  CLUSTER_IP=$(my_minikube ip)

elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  if [[ $(microk8s status) == *"microk8s is not running"* ]]; then
    common::die "It seems microk8s is not up and running."
  fi

  CLUSTER_IP="127.0.0.1"
  alias my_kubectl="microk8s kubectl"
else
  common::die "Cluster type value [${CLUSTER_TYPE}] is unexpected"
fi

NEXUS_PORT=30000
NEXUS_URL="http://${CLUSTER_IP}:${NEXUS_PORT}"
NEXUS_API_BASE_PATH="${NEXUS_URL}/service/rest"

common::log "Waiting for Nexus cluster to be ready..."
while [ "$(curl -s -o /dev/null -w "%{http_code}" ${NEXUS_URL})" != 200 ];
do echo -n "."; sleep 2 ; done
echo ""
common::log "Nexus cluster is ready!"

NEXUS_USER="admin"
NEXUS_PASSWORD=$(my_kubectl exec svc/nexus-rm -- bash -c 'if test -f /nexus-data/admin.password; then /bin/cat /nexus-data/admin.password && echo; else echo "admin"; fi')

common::log "Creating docker proxy repository..."
postNewRepositoryIfNotFound "/v1/repositories/docker/proxy" "nexus-docker-proxy-http"

common::log "Creating helm hosted repositories..."
postNewRepositoryIfNotFound "/v1/repositories/docker/hosted" "nexus-dan-helm-release-http"
postNewRepositoryIfNotFound "/v1/repositories/docker/hosted" "nexus-dan-helm-snapshot-http"

common::log "Creating docker hosted repositories..."
postNewRepositoryIfNotFound "/v1/repositories/docker/hosted" "nexus-dan-docker-release-http"
postNewRepositoryIfNotFound "/v1/repositories/docker/hosted" "nexus-dan-docker-snapshot-http"

common::log "Updating security Realms..."
put "/v1/security/realms/active" "realm-ids.json"

common::log "Creating Jenkins user..."
post "/v1/security/users" "user-jenkins.json"


common::log "Finished!"