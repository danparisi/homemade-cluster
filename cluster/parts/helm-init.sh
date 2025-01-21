#!/bin/bash

set -e
set -o errexit
set -o nounset
shopt -s expand_aliases
source "$PROJECT_DIRECTORY/common/common.sh"


if [ -z ${CLUSTER_TYPE+x} ]; then
  common::die "Cluster type option is mandatory (--microk8s or --minikube)"
fi

if [ "$CLUSTER_TYPE" == "minikube" ]
then
  alias my_helm3="helm"

elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  alias my_helm3="microk8s helm3"

else
  common::die "Cluster type value [${CLUSTER_TYPE}] is unexpected"
fi


common::log "Adding helm repositories..."
my_helm3 repo add elastic https://helm.elastic.co
my_helm3 repo add jenkins https://charts.jenkins.io
my_helm3 repo add zipkin https://zipkin.io/zipkin-helm
my_helm3 repo add fluent https://fluent.github.io/helm-charts
my_helm3 repo add grafana https://grafana.github.io/helm-charts
my_helm3 repo add hashicorp https://helm.releases.hashicorp.com
my_helm3 repo add sonatype https://sonatype.github.io/helm3-charts/
my_helm3 repo add kafka-ui https://provectus.github.io/kafka-ui-charts
my_helm3 repo add prometheus-community https://prometheus-community.github.io/helm-charts
my_helm3 repo update
