#!/bin/bash

set -e
set -o errexit
set -o nounset

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')

source "$PROJECT_DIRECTORY/common/common.sh"


common::log "Creating microk8s cluster..."
microk8s start

common::log "Enabling microk8s ingress addon..."
microk8s enable ingress

common::log "Enabling microk8s DNS addon..."
microk8s enable dns

common::log "Enabling microk8s hostpath-storage addon..."
microk8s enable hostpath-storage

common::log "Enabling microk8s metrics-server addon..."
microk8s enable metrics-server

common::log "Adding insecure registries configuration..."
sudo mkdir -p /var/snap/microk8s/current/args/certs.d/nexus-dan-docker-release-http.k8s.local:30500
sudo cat <<EOF >"/var/snap/microk8s/current/args/certs.d/nexus-dan-docker-release-http.k8s.local:30500/hosts.toml"
server = "http://nexus-dan-docker-release-http.k8s.local:30500"

[host."nexus-dan-docker-release-http.k8s.local:30500"]
capabilities = ["pull", "resolve"]
EOF

sudo mkdir -p /var/snap/microk8s/current/args/certs.d/nexus-dan-docker-snapshot-http.k8s.local:30501
sudo cat <<EOF >"/var/snap/microk8s/current/args/certs.d/nexus-dan-docker-snapshot-http.k8s.local:30501/hosts.toml"
server = "http://nexus-dan-docker-snapshot-http.k8s.local:30501"

[host."nexus-dan-docker-snapshot-http.k8s.local:30501"]
capabilities = ["pull", "resolve"]
EOF
