#!/bin/bash

SUDO_COMMAND=sudo
PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')
source "$PROJECT_DIRECTORY/common/common.sh"

set +u
while :
do
     case $1 in
         --skip-sudo)
              SUDO_COMMAND=""
              ;;

        *) # Default case: No more options, so break out of the loop.
             break
     esac
     shift
done
set -u

MICROK8S_STATUS=$($SUDO_COMMAND microk8s status --wait)
if [[ $MICROK8S_STATUS == *"is not running"* ]]; then
  common::log "Microk8s is not running. Starting up now..."

  $SUDO_COMMAND microk8s start
fi

$SUDO_COMMAND microk8s refresh-certs -e server.crt
$SUDO_COMMAND microk8s refresh-certs -e front-proxy-client.crt
$SUDO_COMMAND microk8s refresh-certs -e ca.crt

microk8s kubectl config set-context --current --namespace=dan-ci-cd

watch "microk8s kubectl get pods"