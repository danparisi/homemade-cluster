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
  --registry-mirror http://nexus-docker-proxy-http.k8s.local:30400 \
  --insecure-registry nexus-docker-proxy-http.k8s.local:30400 \
  --insecure-registry nexus-dan-helm-release-http.k8s.local:30600 \
  --insecure-registry nexus-dan-helm-snapshot-http.k8s.local:30601 \
  --insecure-registry nexus-dan-docker-release-http.k8s.local:30500 \
  --insecure-registry nexus-dan-docker-snapshot-http.k8s.local:30501

common::log "Enabling minikube ingress addon..."
my_minikube addons enable ingress

common::log "Enabling minikube metrics-server addon..."
my_minikube addons enable metrics-server