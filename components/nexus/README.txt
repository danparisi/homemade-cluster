Doc:
https://artifacthub.io/packages/helm/sonatype/nexus-repository-manager

Repo:
helm repo add sonatype https://sonatype.github.io/helm3-charts/

Installation:
    1. Apply configuration in k8s/
    2. helm install nexus-rm sonatype/nexus-repository-manager -f helm/nexus-values.yaml
    3. Execute:
        - minikube ssh
        - sudo chown -R 200:200 /data/nexus-pv/

Upgrade:
helm upgrade nexus-rm sonatype/nexus-repository-manager -f helm/nexus-values.yaml

Hot to access:
minikube service nexus-service-web-ui -n dan-ci-cd --url


URL:
# http://minikube:32419/
http://192.168.49.2:32232/