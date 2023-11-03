#!/bin/bash

set -e
set -o errexit
set -o nounset

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')

source "$PROJECT_DIRECTORY/common/common.sh"


common::log "Creating Minikube cluster..."
my_minikube start \
  --nodes=3 \
  --cpus='4' \
  --memory='8g' \
  --namespace="${NAMESPACE}" \
  --container-runtime=containerd \
  --registry-mirror http://minikube.nexus-docker-proxy-http:30400 \
  --insecure-registry minikube.nexus-docker-proxy-http:30400 \
  --insecure-registry minikube.nexus-dan-helm-release-http:30600 \
  --insecure-registry minikube.nexus-dan-helm-snapshot-http:30601 \
  --insecure-registry minikube.nexus-dan-docker-release-http:30500 \
  --insecure-registry minikube.nexus-dan-docker-snapshot-http:30501

common::log "Enabling minikube ingress addon..."
my_minikube addons enable ingress

common::log "Enabling minikube metrics-server addon..."
my_minikube addons enable metrics-server