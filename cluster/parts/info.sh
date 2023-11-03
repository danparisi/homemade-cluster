#!/bin/bash

set -e
set -o errexit
set -o nounset
shopt -s expand_aliases

PROJECT_DIRECTORY=$(pwd | sed 's/\(.*homemade-cluster\).*/\1/')

source "$PROJECT_DIRECTORY/common/common.sh"

CLUSTER_TYPE=-1

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
        *)               # Default case: No more options, so break out of the loop.
             break
     esac
     shift
 done
 set -u

if [ "$CLUSTER_TYPE" == -1 ]
then
  common::die "Cluster type option is mandatory (--microk8s or --minikube)"
fi

if [ "$CLUSTER_TYPE" == "minikube" ]
then
  if [[ $(my_minikube status --format='{{.Host}}') != 'Running' ]]; then
    common::die "It seems minikube is not up and running."
  fi

  alias my_kubectl="kubectl"

elif [ "$CLUSTER_TYPE" == "microk8s" ]
then
  if [[ $(microk8s status) == *"microk8s is not running"* ]]; then
    common::die "It seems microk8s is not up and running."
  fi

  alias my_kubectl="microk8s kubectl"
fi


show_info() {
  KIBANA_PASSWORD=$(my_kubectl get secret elasticsearch-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo)
  JENKINS_PASSWORD=$(my_kubectl exec -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo)
  MARIADB_PASSWORD=$(my_kubectl get secret --namespace dan-ci-cd mariadb -o jsonpath="{.data.mariadb-root-password}" | base64 -d)
  GRAFANA_PASSWORD=$(my_kubectl get secret --namespace dan-ci-cd grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo)
  NEXUS_PASSWORD=$(my_kubectl exec svc/nexus-rm -- bash -c 'if test -f /nexus-data/admin.password; then /bin/cat /nexus-data/admin.password && echo; else echo "admin"; fi')

  common::title "Tools info"
  common::bold "Accessing Jenkins:"
  common::paragraph "User: admin Password: ${JENKINS_PASSWORD}"

  common::bold "Accessing Nexus:"
  common::underline "minikube service nexus-service-web-ui -n dan-ci-cd --url"
  common::paragraph "User: admin Default password: ${NEXUS_PASSWORD}"

  common::bold "Accessing Kibana:"
  common::underline "k port-forward svc/kibana-kb-http 5601"
  common::paragraph "User: elastic Password: ${KIBANA_PASSWORD}"

  common::bold "Accessing Grafana:"
  common::underline "k port-forward svc/kibana-kb-http 5601"
  common::paragraph "User: admin Password: ${GRAFANA_PASSWORD}"

  common::bold "Accessing Prometheus:"
  common::underline "k port-forward prometheus-server-7c777fbb9b-98b2c 9090"
  common::paragraph "Note: in Status -> Targets menu, you should see all your services being scraped."

  common::bold "Accessing Zipkin:"
  common::underline "k port-forward svc/zipkin 9411"
  common::paragraph "http://localhost:9411/zipkin/"

  common::bold "Accessing Kafka UI:"
  common::underline "k port-forward svc/kafka-ui 8080:80"
  common::paragraph "http://localhost:8080/"

  common::bold "Accessing MariaDB:"
  common::underline "k port-forward svc/mariadb 3306"
  common::text "User: admin root: ${MARIADB_PASSWORD}"
  common::paragraph "mysql -u root -P 3306 -h localhost --protocol=TCP --password=${MARIADB_PASSWORD}"
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
  common::text "For docker hub mirror (proxy), add security -> realms -> Docker Bearer Token Realm"
  common::text "More info: https://mtijhof.wordpress.com/2018/07/23/using-nexus-oss-as-a-proxy-cache-for-docker-images/"
  common::paragraph "Add (weekly) cleanup policy"

  common::bold "Create Kibana indexes:"
  common::text "Pattern: kube-*."
  common::paragraph "Pattern: service-*."

  common::title "Testing kafka"
  common::bold "Create a producer:"
  common::text "kubectl run kafka-producer -ti --image=quay.io/strimzi/kafka:0.36.1-kafka-3.5.1 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server dan-kafka-cluster-kafka-bootstrap:9092 --topic dan-service-logs"
  common::bold "Create a consumer:"
  common::text "kubectl run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.36.1-kafka-3.5.1 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server dan-kafka-cluster-kafka-bootstrap:9092 --topic dan-service-logs --from-beginning"
}

show_info
show_next_steps