Chart documentation:
https://docs.fluentbit.io/manual/installation/kubernetes
https://github.com/fluent/helm-charts/blob/main/charts/fluent-bit/values.yaml

Installation:
    1. helm repo add fluent https://fluent.github.io/helm-charts
    2. helm upgrade --install fluent-bit fluent/fluent-bit -f helm/fluentbit-values.yml