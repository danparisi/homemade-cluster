#!/bin/bash

set -e
set -o errexit
set -o nounset
shopt -s expand_aliases

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')

source "$PROJECT_DIRECTORY/common/common.sh"

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
