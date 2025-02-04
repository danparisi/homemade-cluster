#!/bin/bash

set -e
set -o errexit
set -o nounset

export PROJECT_DIRECTORY
PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')
source "$PROJECT_DIRECTORY/common/common.sh"
common::log "Calculated project directory: [$PROJECT_DIRECTORY]"

set +o nounset #turning this off, will allow to test the NON-EMPTYNESS of variables without failing with 'unbound variable'

export CLUSTER_TYPE=-1
export NAMESPACE=dan-ci-cd
export SKIP_INSECURE_REGISTRY=false

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
         --skip-insecure-registry)
              SKIP_INSECURE_REGISTRY=true
              ;;
         -i|--info)
              bash "$PROJECT_DIRECTORY/cluster/parts/info.sh"
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
  alias my_minikube="minikube --profile='dan-cluster'"

  bash "$PROJECT_DIRECTORY/cluster/parts/minikube-init.sh"
elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  bash "$PROJECT_DIRECTORY/cluster/parts/microk8s-init.sh"
else
  common::die "Cluster type value [${CLUSTER_TYPE}] is unexpected"
fi

common::log "Initializing Helm..."
bash "$PROJECT_DIRECTORY/cluster/parts/helm-init.sh"

common::log "Creating namespace ${NAMESPACE} if not exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace="${NAMESPACE}"

common::log "Creating cluster ingress..."
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/k8s/dan-ingress.yaml"

common::log "Creating cluster roles..."
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/k8s/dan-roles.yaml"

common::log "Creating cluster secrets for nexus docker repositories if they don't already exist..."
if kubectl get secrets nexus-release-http-secret
then
  common::log "Skipping adding secret [nexus-release-http-secret] as already exist"
else
  kubectl create secret docker-registry nexus-release-http-secret --docker-server=nexus-dan-docker-release-http.k8s.local:30500 --docker-username=jenkins --docker-password=jenkins
fi

if kubectl get secrets nexus-snapshot-http-secret
then
  common::log "Skipping adding secret [nexus-snapshot-http-secret] as already exist"
else
  kubectl create secret docker-registry nexus-snapshot-http-secret --docker-server=nexus-dan-docker-snapshot-http.k8s.local:30501 --docker-username=jenkins --docker-password=jenkins
fi

common::log "Installing Nexus..."
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/nexus/k8s"
helm upgrade --install -n "${NAMESPACE}" nexus-rm sonatype/nexus-repository-manager -f "$PROJECT_DIRECTORY/components/nexus/helm/nexus-values.yaml"
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  my_minikube ssh 'sudo mkdir -p /data/nexus-pv'
  my_minikube ssh 'sudo chown -R 200:200 /data/nexus-pv/'
fi

common::log "Installing Jenkins..."
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/jenkins/k8s"
helm upgrade --install -n "${NAMESPACE}" jenkins jenkins/jenkins -f "$PROJECT_DIRECTORY/components/jenkins/helm/jenkins-values.yaml"
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  my_minikube ssh 'sudo mkdir -p /data/jenkins-pv'
  my_minikube ssh 'sudo chown -R 1000:1000 /data/jenkins-pv/'
fi

common::log "Installing ELK..."
helm upgrade --install -n "${NAMESPACE}" elastic-operator elastic/eck-operator
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/elk/k8s"

common::log "Installing Fluentbit..."
helm upgrade --install -n "${NAMESPACE}" fluent-bit fluent/fluent-bit -f "$PROJECT_DIRECTORY/components/fluentbit/helm/fluentbit-values.yaml"

common::log "Installing Kafka cluster..."
helm upgrade --install -n "${NAMESPACE}" strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/kafka/k8s"
kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/kafka/k8s/topic"

common::log "Installing MariaDB cluster..."
helm upgrade --install -n "${NAMESPACE}" mariadb oci://registry-1.docker.io/bitnamicharts/mariadb -f "$PROJECT_DIRECTORY/components/mariadb/helm/mariadb-values.yaml"

common::log "Installing Kube Prometheus Stack (Prometheus, Operator, Grafana, AlertManager, Kube state metrics)..."
helm upgrade --install -n "${NAMESPACE}" kube-prometheus-stack prometheus-community/kube-prometheus-stack -f "$PROJECT_DIRECTORY/components/kube-prometheus-stack/helm/kube-prometheus-stack-values.yaml"

common::log "Installing Prometheus Adapter ..."
helm upgrade --install -n "${NAMESPACE}" prometheus-adapter prometheus-community/prometheus-adapter -f "$PROJECT_DIRECTORY/components/prometheus-adapter/helm/prometheus-adapter-values.yaml"

common::log "Installing Zipkin..."
helm upgrade --install -n "${NAMESPACE}" zipkin zipkin/zipkin -f "$PROJECT_DIRECTORY/components/zipkin/helm/zipkin-values.yaml"

common::log "Installing Kafka UI..."
helm upgrade --install -n "${NAMESPACE}" kafka-ui kafka-ui/kafka-ui -f "$PROJECT_DIRECTORY/components/kafka-ui/helm/kafka-ui-values.yaml"

common::log "Installing Consul..."
helm upgrade --install -n "${NAMESPACE}" consul hashicorp/consul -f "$PROJECT_DIRECTORY/components/consul/helm/consul-values.yaml"

common::log "Adding k8s.local to hosts file..."
if ! grep -q k8s.local "/etc/hosts"; then
  echo "127.0.0.1 k8s.local" | sudo tee -a /etc/hosts
else
  common::log "was already there."
fi

common::log "Initializing Consul..."
bash "$PROJECT_DIRECTORY/components/consul/bash/consul-init.sh"

common::log "Initializing Nexus..."
bash "$PROJECT_DIRECTORY/components/nexus/bash/nexus-init.sh"

common::log "Initializing Jenkins..."
bash "$PROJECT_DIRECTORY/components/jenkins/bash/jenkins-init.sh"

common::log "Initializing ELK components..."
bash "$PROJECT_DIRECTORY/components/elk/bash/elk-init.sh"

common::lognewline "Cluster is ready. Done!"
