#!/bin/bash

set -e
set -o errexit
set -o nounset

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')

source "$PROJECT_DIRECTORY/common/common.sh"

set +o nounset #turning this off, will allow to test the NON-EMPTYNESS of variables without failing with 'unbound variable'

CLUSTER_TYPE=-1
NAMESPACE=dan-ci-cd

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
         -i|--info)
              bash $PROJECT_DIRECTORY/cluster/parts/info.sh --$CLUSTER_TYPE
              exit
              ;;
        *) # Default case: No more options, so break out of the loop.
             break
     esac
     shift
 done
 set -u

if [ "$CLUSTER_TYPE" == -1 ]
then
  common::die "Cluster type option is mandatory (--microk8s or --minikube)"
fi

shopt -s expand_aliases

common::log "Preparing the cluster..."
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  alias my_helm3="helm"
  alias my_kubectl="kubectl"
  alias my_minikube="minikube --profile='dan-cluster'"

  bash "$PROJECT_DIRECTORY/cluster/parts/minikube-init.sh"
elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  alias my_helm3="microk8s helm3"
  alias my_kubectl="microk8s kubectl"

  bash "$PROJECT_DIRECTORY/cluster/parts/microk8s-init.sh"
else
  common::die "Cluster type value [${CLUSTER_TYPE}] is unexpected"
fi

common::log "Initializing Helm..."
bash $PROJECT_DIRECTORY/cluster/parts/helm-init.sh --$CLUSTER_TYPE

common::log "Creating namespace ${NAMESPACE} if not exists..."
my_kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | my_kubectl apply -f -
my_kubectl config set-context --current --namespace="${NAMESPACE}"

common::log "Creating cluster ingress..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/k8s/dan-ingress.yaml"

common::log "Creating cluster roles..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/k8s/dan-roles.yaml"

common::log "Creating cluster secrets for nexus docker repositories..."
my_kubectl create secret docker-registry nexus-release-http-secret --docker-server=minikube.nexus-dan-docker-release-http:30500 --docker-username=jenkins --docker-password=jenkins
my_kubectl create secret docker-registry nexus-snapshot-http-secret --docker-server=minikube.nexus-dan-docker-snapshot-http:30501 --docker-username=jenkins --docker-password=jenkins

common::log "Installing Nexus..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/nexus/k8s"
my_helm3 upgrade --install -n "${NAMESPACE}" nexus-rm sonatype/nexus-repository-manager -f "$PROJECT_DIRECTORY/components/nexus/helm/nexus-values.yaml"
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  my_minikube ssh 'sudo mkdir -p /data/nexus-pv'
  my_minikube ssh 'sudo chown -R 200:200 /data/nexus-pv/'
fi

common::log "Installing Jenkins..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/jenkins/k8s"
my_helm3 upgrade --install -n "${NAMESPACE}" jenkins jenkins/jenkins -f "$PROJECT_DIRECTORY/components/jenkins/helm/jenkins-values.yaml"
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  my_minikube ssh 'sudo mkdir -p /data/jenkins-pv'
  my_minikube ssh 'sudo chown -R 1000:1000 /data/jenkins-pv/'
fi

common::log "Installing ELK..."
my_helm3 upgrade --install -n "${NAMESPACE}" elastic-operator elastic/eck-operator
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/elk/k8s"

common::log "Installing Fluentbit..."
my_helm3 upgrade --install -n "${NAMESPACE}" fluent-bit fluent/fluent-bit -f "$PROJECT_DIRECTORY/components/fluentbit/helm/fluentbit-values.yaml"

common::log "Installing Kafka cluster..."
my_helm3 upgrade --install -n "${NAMESPACE}" strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/kafka/k8s"

common::log "Installing MariaDB cluster..."
my_helm3 upgrade --install -n "${NAMESPACE}" mariadb oci://registry-1.docker.io/bitnamicharts/mariadb -f "$PROJECT_DIRECTORY/components/mariadb/helm/mariadb-values.yaml"

common::log "Installing Prometheus..."
my_helm3 upgrade --install -n "${NAMESPACE}" prometheus prometheus-community/prometheus -f "$PROJECT_DIRECTORY/components/prometheus/helm/prometheus-values.yaml"

common::log "Installing Grafana..."
my_helm3 upgrade --install -n "${NAMESPACE}" grafana grafana/grafana -f "$PROJECT_DIRECTORY/components/grafana/helm/grafana-values.yaml"

common::log "Installing Zipkin..."
my_helm3 upgrade --install -n "${NAMESPACE}" zipkin openzipkin/zipkin -f "$PROJECT_DIRECTORY/components/zipkin/helm/zipkin-values.yaml"

common::log "Installing Kafka UI..."
my_helm3 upgrade --install -n "${NAMESPACE}" kafka-ui kafka-ui/kafka-ui -f "$PROJECT_DIRECTORY/components/kafka-ui/helm/kafka-ui-values.yaml"

common::log "Installing Consul..."
my_helm3 upgrade --install -n "${NAMESPACE}" consul hashicorp/consul -f "$PROJECT_DIRECTORY/components/consul/helm/consul-values.yaml"

common::log "Initializing Consul..."
bash $PROJECT_DIRECTORY/components/consul/bash/init.sh --${CLUSTER_TYPE}

common::log "Initializing Nexus..."
bash $PROJECT_DIRECTORY/components/nexus/bash/init.sh --${CLUSTER_TYPE}

common::lognewline "Done!"
