#!/bin/bash

set -e
set -o errexit
set -o nounset

function common::log () {
  GREEN="$1"
  shift
  if [ -t 2 ] ; then
    echo -e "[$(date +%H:%M:%S)] \e[1m \x1B[97m* \x1B[92m${GREEN}\x1B[39m \e[0m $*" 1>&2
  else
    echo "* ${GREEN} $*" 1>&2
  fi
}

function common::lognewline () {
    common::log "$* \n"  >&2
}

function common::die () {
    common::log "\e[31m[ ERROR ] \e[0m $*"  >&2
    exit 1
}

function common::warn() {
    common::log "\e[33m[ WARNING ]  \e[0m$*"
}

function common::debug() {
    common::log "\e[39m[ DEBUG ]  \e[0m$*"
}

function common::bold(){
    echo -e "\e[1m$*\e[0m"
}

function common::title(){
    echo -e "\e[1m\x1B[92m************ $* ************\x1B[39m\e[0m"
}

function common::underline(){
    echo -e "\e[4m$*\e[0m"
}

function common::text(){
    echo -e "$*"
}

function common::paragraph(){
    echo -e "$*\n"
}

set +o nounset #turning this off, will allow to test the NON-EMPTYNESS of variables without failing with 'unbound variable'

show_info() {
  KIBANA_PASSWORD=$(kubectl get secret elasticsearch-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo)
  JENKINS_PASSWORD=$(kubectl exec -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo)

  common::title "Tools info"
  common::bold "Accessing Jenkins:"
  common::paragraph "User: admin Password: ${JENKINS_PASSWORD}"

  common::bold "Accessing Nexus:"
  common::underline "minikube service nexus-service-web-ui -n dan-ci-cd --url"
  common::paragraph "User: admin Default password: kubectl exec -it svc/nexus-rm -- /bin/cat /nexus-data/admin.password && echo"

  common::bold "Accessing kibana:"
  common::underline "k port-forward svc/kibana-kb-http 5601"
  common::paragraph "User: elastic Password: ${KIBANA_PASSWORD}"
}

show_next_steps() {
  common::title "After installations"
  common::bold "Create Nexus users:"
  common::paragraph "User: jenkins. Password: jenkins"

  common::bold "Create Nexus repositories:"
  common::paragraph "Type: docker. Name: nexus-dan-helm-release-http. Port: 30600"
  common::paragraph "Type: docker. Name: nexus-dan-helm-snapshot-http. Port: 30601"
  common::paragraph "Type: docker. Name: nexus-dan-docker-release-http. Port: 30500"
  common::paragraph "Type: docker. Name: nexus-dan-docker-snapshot-http. Port: 30501"
  common::text "Type: docker proxy. Name: nexus-docker-proxy-http. Port: 30400"
  common::paragraph "More info: https://mtijhof.wordpress.com/2018/07/23/using-nexus-oss-as-a-proxy-cache-for-docker-images/"

  common::bold "Create Kibana indexes:"
  common::text "Pattern: kube-*."
  common::paragraph "Pattern: service-*."


  common::title "Testing kafka"
  common::bold "Create a producer:"
  common::text "kubectl run kafka-producer -ti --image=quay.io/strimzi/kafka:0.36.1-kafka-3.5.1 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server dan-kafka-cluster-kafka-bootstrap:9092 --topic dan-service-logs"
  common::bold "Create a consumer:"
  common::text "kubectl run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.36.1-kafka-3.5.1 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server dan-kafka-cluster-kafka-bootstrap:9092 --topic dan-service-logs --from-beginning"
}

set +u
 while :
 do
     case $1 in
         -i|--info)
             show_info
             show_next_steps

             exit
             ;;
        *)               # Default case: No more options, so break out of the loop.
             break
     esac

     shift
 done
 set -u

NAMESPACE=dan-ci-cd

common::log "Adding helm repositories..."
helm repo add elastic https://helm.elastic.co
helm repo add jenkins https://charts.jenkins.io
helm repo add fluent https://fluent.github.io/helm-charts
helm repo add sonatype https://sonatype.github.io/helm3-charts/

common::log "Creating Minikube cluster..."
minikube start \
  --container-runtime=containerd \
  --registry-mirror http://minikube.nexus-docker-proxy-http:30400 \
  --insecure-registry minikube.nexus-docker-proxy-http:30400 \
  --insecure-registry minikube.nexus-dan-helm-release-http:30600 \
  --insecure-registry minikube.nexus-dan-helm-snapshot-http:30601 \
  --insecure-registry minikube.nexus-dan-docker-release-http:30500 \
  --insecure-registry minikube.nexus-dan-docker-snapshot-http:30501

common::log "Enabling minikube ingress addon..."
minikube addons enable ingress

common::log "Enabling minikube metrics-server addon..."
minikube addons enable metrics-server

common::log "Creating namespace ${NAMESPACE} if not exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl ns "${NAMESPACE}"

common::log "Creating cluster ingress..."
kubectl apply -n "${NAMESPACE}" -f k8s/dan-ingress.yml

common::log "Creating cluster roles..."
kubectl apply -n "${NAMESPACE}" -f k8s/dan-roles.yml

common::log "Installing Nexus..."
kubectl apply -n "${NAMESPACE}" -f components/nexus/k8s
helm upgrade --install -n "${NAMESPACE}" nexus-rm sonatype/nexus-repository-manager -f components/nexus/helm/nexus-values.yaml
minikube ssh 'sudo mkdir -p /data/nexus-pv'
minikube ssh 'sudo chown -R 200:200 /data/nexus-pv/'

common::log "Installing Jenkins..."
kubectl apply -n "${NAMESPACE}" -f components/jenkins/k8s
helm upgrade --install -n "${NAMESPACE}" jenkins jenkins/jenkins -f components/jenkins/helm/jenkins-values.yaml
minikube ssh 'sudo mkdir -p /data/jenkins-pv'
minikube ssh 'sudo chown -R 1000:1000 /data/jenkins-pv/'

common::log "Installing ELK..."
helm upgrade --install -n "${NAMESPACE}" elastic-operator elastic/eck-operator
kubectl apply -n "${NAMESPACE}" -f components/elk/k8s

common::log "Installing Fluentbit..."
helm upgrade --install -n "${NAMESPACE}" fluent-bit fluent/fluent-bit -f components/fluentbit/helm/fluentbit-values.yml

common::log "Creating Kafka cluster..."
helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
kubectl apply -n "${NAMESPACE}" -f components/kafka/k8s

common::lognewline "Done!"

show_next_steps