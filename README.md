# My homemade cluster with CI/CD

## Troubleshotting

* _microk8s kubectl_ throws the following error:

```
error: error upgrading connection: error dialing backend: tls: failed to verify certificate: x509
```

**Solution:**
Run the following commands:

* sudo microk8s.refresh-certs -e server.crt
* sudo microk8s.refresh-certs -e front-proxy-client.crt
* sudo microk8s.refresh-certs -e ca.crt