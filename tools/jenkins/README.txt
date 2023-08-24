Installation:
    1. Apply configuration in k8s/
    2.
        - kubectl create configmap etc-default-docker --from-file=support/docker
        - kubectl create configmap etc-docker-daemon --from-file=support/daemon.json
    3.
        Execute:
            - minikube ssh
            - sudo chown -R 1000:1000 /data/jenkins-pv/
    4.
        - helm repo add jenkins https://charts.jenkins.io
        - helm install jenkins -n dan-ci-cd -f helm/jenkins-values.yaml jenkins/jenkins
        # - echo "$(minikube ip) minikube.jenkins" | sudo tee -a /etc/hosts

    5.
        - Add credentials
            - nexus
            - bitbucket
            - Setup configuration for Thin Backup plugin (folder: /var/jenkins_home/backup)

Upgrade:
helm upgrade jenkins jenkins/jenkins -f helm/jenkins-values.yaml

Hot to access:
minikube service jenkins -n dan-ci-cd --url

Usefult notes
Generated admin password:
kubectl exec --namespace dan-ci-cd -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo

PAIN POINTS about minikube - nexus - docker combination
keep in mind that you are working with (at least) 2 docker daemons: 1 in your (host) machine and 1 running on minikube container

Jenkins worker container will need to build and push a docker image within the pipeline.
In order to do that, it can connect to the minikube docker daemon socket and do his job. The issue is that such daemon runs over the minikube container but now within the k8s environment and therefore may have issues to resolve the DNS name (k8s service you created to expose nexus repository).
Probably best option is to run also a new docker daemon inside the jenkins worker, as it's going to be part of the k8s environment end therefore no issues in resolving the DNS from the k8s service name. => TO BE TESTED
