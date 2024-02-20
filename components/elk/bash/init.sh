#!/bin/bash

set -e
set -o errexit
set -o nounset
shopt -s expand_aliases

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')
SCRIPT_DIRECTORY="$PROJECT_DIRECTORY/components/elk/bash"

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

elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  if [[ $(microk8s status) == *"microk8s is not running"* ]]; then
    common::die "It seems microk8s is not up and running."
  fi

  alias my_kubectl="microk8s kubectl"
else
  common::die "Cluster type value [${CLUSTER_TYPE}] is unexpected"
fi


KIBANA_URL="http://k8s.local/kibana/"
KIBANA_API_BASE_PATH="${KIBANA_URL}api/"

KIBANA_USER='elastic'
KIBANA_PASSWORD=$(my_kubectl get secret elasticsearch-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo)

source "$PROJECT_DIRECTORY/common/common.sh"

function kibanaClusterIsUp() {
  local httpCode;
  httpCode="$(curl -s -o /dev/null -w "%{http_code}" ${KIBANA_URL})"

  if [ "${httpCode}" -lt 200 ] || [ "${httpCode}" -gt 399 ]; then
    return 1;
  else
    return 0;
  fi
}

# Args: dataViewName
function postNewDataView() {
  local endpoint;
  local apiCallUri;
  local jsonBodyFile;
  local dataViewName;

  dataViewName=$1
  jsonBodyFile="data-view-${dataViewName}.json"
  endpoint='data_views/data_view'
  apiCallUri=${KIBANA_API_BASE_PATH}${endpoint}

  local postResult;
  postResult=$(curl -s -o /dev/null -w "%{http_code}" -u ${KIBANA_USER}:${KIBANA_PASSWORD} -X POST -H "kbn-xsrf: reporting" -H "Content-Type: application/json" -d "@$SCRIPT_DIRECTORY/${jsonBodyFile}" "${apiCallUri}")

  common::log "Executed POST against [${apiCallUri}]: ${postResult}";
}

# Args: indexLifecyclePolicyName
function putNewIndexLifecyclePolicy() {
  local endpoint;
  local jsonBody;
  local apiCallUri;
  local jsonBodyFile;
  local indexLifecyclePolicyName;

  indexLifecyclePolicyName=$1
  endpoint="_ilm/policy/${indexLifecyclePolicyName}"
  jsonBodyFile="index-lifecycle-policy-${indexLifecyclePolicyName}.json"
  apiCallUri="http://localhost:9200/${endpoint}"
  jsonBody=$(<"$SCRIPT_DIRECTORY/${jsonBodyFile}")

  local putResult;
  putResult=$(my_kubectl exec elasticsearch-es-default-0 -c elasticsearch -- curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d "${jsonBody}" "${apiCallUri}")

  common::log "Executed PUT against [${apiCallUri}]: ${putResult}";
}

# Args: indexTemplateName
function putNewIndexTemplate() {
  local endpoint;
  local apiCallUri;
  local jsonBodyFile;
  local indexTemplateName;

  indexTemplateName=$1
  endpoint="_index_template/${indexTemplateName}"
  jsonBodyFile="index-template-${indexTemplateName}.json"
  apiCallUri="http://localhost:9200/${endpoint}"
  jsonBody=$(<"$SCRIPT_DIRECTORY/${jsonBodyFile}")

  local putResult;
  putResult=$(my_kubectl exec elasticsearch-es-default-0 -c elasticsearch -- curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d "${jsonBody}" "${apiCallUri}")

  common::log "Executed PUT against [${apiCallUri}]: ${putResult}";
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

common::log "Waiting for Kibana cluster to be ready..."
while ! kibanaClusterIsUp
do
    echo -n "."; sleep 2 ;
done
echo ""
common::log "Kibana cluster is ready!"

common::log "Creating Data view for kube-* index pattern..."
postNewDataView "kube"

common::log "Creating Data view for service-* index pattern..."
postNewDataView "service"


common::log "Creating Index Lifecycle Policy for kube-* indexes..."
putNewIndexLifecyclePolicy "kube"

common::log "Creating Index Lifecycle Policy for service-* indexes..."
putNewIndexLifecyclePolicy "service"


common::log "Creating Index Template for kube-* indexes..."
putNewIndexTemplate "kube"

common::log "Creating Index Template for service-* indexes..."
putNewIndexTemplate "service"




common::log "Finished!"