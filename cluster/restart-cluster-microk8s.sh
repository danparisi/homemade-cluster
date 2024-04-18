sudo microk8s stop

sudo microk8s.refresh-certs -e server.crt
sudo microk8s.refresh-certs -e front-proxy-client.crt
sudo microk8s.refresh-certs -e ca.crt

sudo microk8s start

microk8s kubectl config set-context --current --namespace=dan-ci-cd

watch "microk8s kubectl get pods"