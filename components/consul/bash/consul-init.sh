#!/bin/bash

set -e
set -o errexit
set -o nounset

shopt -s expand_aliases
alias my_kubectl="microk8s kubectl"
alias my_minikube="minikube --profile='dan-cluster'"

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')
SCRIPT_DIRECTORY="$PROJECT_DIRECTORY/components/consul/bash"

source "$PROJECT_DIRECTORY/common/common.sh"

# Args: serviceName
function putKeyValue() {
  local apiUri;
  local jsonBody;
  local putResult;
  local serviceName;
  local jsonBodyFile;
  serviceName=$1
  jsonBodyFile="${serviceName}.yaml"
  jsonBody=$(<"$SCRIPT_DIRECTORY/${jsonBodyFile}")
  apiUri="http://localhost:8500/v1/kv/config/${serviceName}/data"

  putResult=$(my_kubectl exec consul-server-0 -c consul -- curl -s -X PUT -H "Accept: application/json" -H "Content-Type: application/json" -d "${jsonBody}" "${apiUri}")

  common::log "Executed PUT against [${apiUri}]: ${putResult}";
}


if [ -z ${CLUSTER_TYPE+x} ]; then
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

CONSUL_URL="http://localhost:8500/consul-ui/dc1/services"

common::log "Waiting for Consul to be ready..."
while [ "$(my_kubectl exec consul-server-0 -c consul -- curl -s -o /dev/null -w "%{http_code}" ${CONSUL_URL})" != 200 ];
do echo -n "."; sleep 2 ; done
echo ""
common::log "Consul is ready!"

common::log "Creating KV entry for dan-gateway-service..."
putKeyValue "dan-gateway-service"


common::log "Finished!"