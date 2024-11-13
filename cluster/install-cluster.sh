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
export IS_WINDOWS_OS=false
export NAMESPACE=dan-ci-cd
export SKIP_INSECURE_REGISTRY=false

case "$(uname -sr)" in
   CYGWIN*|MINGW*|MINGW32*|MSYS*)
     IS_WINDOWS_OS=true
     ;;
esac

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
bash "$PROJECT_DIRECTORY/cluster/parts/helm-init.sh"

common::log "Creating namespace ${NAMESPACE} if not exists..."
my_kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | my_kubectl apply -f -
my_kubectl config set-context --current --namespace="${NAMESPACE}"

common::log "Creating cluster ingress..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/k8s/dan-ingress.yaml"

common::log "Creating cluster roles..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/k8s/dan-roles.yaml"

common::log "Creating cluster secrets for nexus docker repositories if they don't already exist..."
if my_kubectl get secrets nexus-release-http-secret
then
  common::log "Skipping adding secret [nexus-release-http-secret] as already exist"
else
  my_kubectl create secret docker-registry nexus-release-http-secret --docker-server=nexus-dan-docker-release-http.k8s.local:30500 --docker-username=jenkins --docker-password=jenkins
fi


if my_kubectl get secrets nexus-snapshot-http-secret
then
  common::log "Skipping adding secret [nexus-snapshot-http-secret] as already exist"
else
  my_kubectl create secret docker-registry nexus-snapshot-http-secret --docker-server=nexus-dan-docker-snapshot-http.k8s.local:30501 --docker-username=jenkins --docker-password=jenkins
fi

cat "$PROJECT_DIRECTORY/components/elk/bash/elk-init.sh" > elk-init.sh
cat "$PROJECT_DIRECTORY/components/nexus/bash/nexus-init.sh" > nexus-init.sh
cat "$PROJECT_DIRECTORY/components/consul/bash/consul-init.sh" > consul-init.sh
cat "$PROJECT_DIRECTORY/components/nexus/helm/nexus-values.yaml" > nexus-values.yaml
cat "$PROJECT_DIRECTORY/components/zipkin/helm/zipkin-values.yaml" > zipkin-values.yaml
cat "$PROJECT_DIRECTORY/components/consul/helm/consul-values.yaml" > consul-values.yaml
cat "$PROJECT_DIRECTORY/components/jenkins/helm/jenkins-values.yaml" > jenkins-values.yaml
cat "$PROJECT_DIRECTORY/components/mariadb/helm/mariadb-values.yaml" > mariadb-values.yaml
cat "$PROJECT_DIRECTORY/components/kafka-ui/helm/kafka-ui-values.yaml" > kafka-ui-values.yaml
cat "$PROJECT_DIRECTORY/components/fluentbit/helm/fluentbit-values.yaml" > fluentbit-values.yaml
cat "$PROJECT_DIRECTORY/components/prometheus-adapter/helm/prometheus-adapter-values.yaml" > prometheus-adapter-values.yaml
cat "$PROJECT_DIRECTORY/components/kube-prometheus-stack/helm/kube-prometheus-stack-values.yaml" > kube-prometheus-stack-values.yaml

if [ "$CLUSTER_TYPE" == "microk8s" ] && [ "$IS_WINDOWS_OS" = true ] ; then
  # Microk8s is usually installed on multipass on Windows systems. Therefore we have to transfer the files to the multipass microk8s instance
  # or they would not be found by helm while executing microk8s helm3 commands.
  common::log "Transfering yaml and bash resources to multipass microk8s instance..."
  multipass transfer -vvvv elk-init.sh consul-init.sh nexus-init.sh nexus-values.yaml zipkin-values.yaml consul-values.yaml jenkins-values.yaml kafka-ui-values.yaml fluentbit-values.yaml mariadb-values.yaml kube-prometheus-stack-values.yaml prometheus-adapter-values.yaml microk8s-vm:
fi

common::log "Installing Nexus..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/nexus/k8s"
my_helm3 upgrade --install -n "${NAMESPACE}" nexus-rm sonatype/nexus-repository-manager -f nexus-values.yaml
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  my_minikube ssh 'sudo mkdir -p /data/nexus-pv'
  my_minikube ssh 'sudo chown -R 200:200 /data/nexus-pv/'
fi

common::log "Installing Jenkins..."
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/jenkins/k8s"
my_helm3 upgrade --install -n "${NAMESPACE}" jenkins jenkins/jenkins -f jenkins-values.yaml
if [ "$CLUSTER_TYPE" == "minikube" ]
then
  my_minikube ssh 'sudo mkdir -p /data/jenkins-pv'
  my_minikube ssh 'sudo chown -R 1000:1000 /data/jenkins-pv/'
fi

common::log "Installing ELK..."
my_helm3 upgrade --install -n "${NAMESPACE}" elastic-operator elastic/eck-operator
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/elk/k8s"

common::log "Installing Fluentbit..."
my_helm3 upgrade --install -n "${NAMESPACE}" fluent-bit fluent/fluent-bit -f fluentbit-values.yaml

common::log "Installing MariaDB cluster..."
my_helm3 upgrade --install -n "${NAMESPACE}" mariadb oci://registry-1.docker.io/bitnamicharts/mariadb -f mariadb-values.yaml

common::log "Installing Kube Prometheus Stack (Prometheus, Operator, Grafana, AlertManager, Kube state metrics)..."
my_helm3 upgrade --install -n "${NAMESPACE}" kube-prometheus-stack prometheus-community/kube-prometheus-stack -f kube-prometheus-stack-values.yaml

common::log "Installing Prometheus Adapter ..."
my_helm3 upgrade --install -n "${NAMESPACE}" prometheus-adapter prometheus-community/prometheus-adapter -f prometheus-adapter-values.yaml

common::log "Installing Zipkin..."
my_helm3 upgrade --install -n "${NAMESPACE}" zipkin zipkin/zipkin -f zipkin-values.yaml

common::log "Installing Kafka cluster..."
my_helm3 upgrade --install -n "${NAMESPACE}" strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/kafka/k8s"
my_kubectl apply -n "${NAMESPACE}" -f "$PROJECT_DIRECTORY/components/kafka/k8s/topic"

common::log "Installing Kafka UI..."
my_helm3 upgrade --install -n "${NAMESPACE}" kafka-ui kafka-ui/kafka-ui -f kafka-ui-values.yaml

common::log "Installing Consul..."
my_helm3 upgrade --install -n "${NAMESPACE}" consul hashicorp/consul -f consul-values.yaml

common::log "Adding k8s.local to hosts file..."
if ! grep -q k8s.local "/etc/hosts"; then
  echo "127.0.0.1 k8s.local" | sudo tee -a /etc/hosts
else
  common::log "was already there."
fi

common::log "Initializing Consul..."
bash consul-init.sh

common::log "Initializing Nexus..."
bash nexus-init.sh

common::log "Initializing ELK components..."
bash elk-init.sh

rm elk-init.sh
rm nexus-init.sh
rm consul-init.sh
rm nexus-values.yaml
rm zipkin-values.yaml
rm consul-values.yaml
rm jenkins-values.yaml
rm mariadb-values.yaml
rm kafka-ui-values.yaml
rm fluentbit-values.yaml
rm prometheus-adapter-values.yaml
rm kube-prometheus-stack-values.yaml

common::lognewline "Cluster is ready. Done!"
