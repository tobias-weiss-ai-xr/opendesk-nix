# Kyverno Webhook TLS Configuration

**Status:** ⏳ In Preparation  
**Created:** 2026-08-07  
**Purpose:** Secure Kyverno webhook communication with TLS

---

## Overview

This directory contains the TLS configuration for Kyverno webhooks to ensure:
- Encrypted webhook communication (TLS 1.3)
- Client certificate authentication
- ZKI-Compliance INF.1.A10 (Zugriffskontrolle)
- ZKI-Compliance INF.5.A1 (Netzwerksicherheit)

---

## Certificate Generation

### Generate CA Certificate

```bash
# Generate CA private key
openssl genrsa -out ca.key 4096

# Generate CA certificate (valid for 10 years)
openssl req -x509 -new -nodes -key ca.key \
  -sha256 -days 3650 \
  -subj "/C=DE/ST=Hesse/O=University Marburg/CN=opendesk-edu CA" \
  -out ca.crt
```

### Generate Server Certificate for Kyverno

```bash
# Generate server private key
openssl genrsa -out kyverno.key 4096

# Generate certificate signing request
openssl req -new -key kyverno.key \
  -subj "/C=DE/ST=Hesse/O=University Marburg/CN=kyverno.kyverno.svc" \
  -out kyverno.csr

# Create extensions file for SAN
cat > kyverno.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = kyverno.kyverno.svc
DNS.2 = kyverno.kyverno.svc.cluster.local
IP.1 = 10.96.0.1
EOF

# Sign the certificate
openssl x509 -req -in kyverno.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 3650 -sha256 -extfile kyverno.ext \
  -out kyverno.crt
```

### Generate Client Certificate for Admission

```bash
# Generate client private key
openssl genrsa -out admission-client.key 4096

# Generate client certificate signing request
openssl req -new -key admission-client.key \
  -subj "/C=DE/ST=Hesse/O=University Marburg/CN=kyverno-admission-client" \
  -out admission-client.csr

# Sign the client certificate
openssl x509 -req -in admission-client.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 3650 -sha256 \
  -out admission-client.crt
```

---

## Kubernetes Secrets

### Create CA Bundle Secret

```bash
# Encode CA certificate
CA_BUNDLE=$(base64 -w0 < ca.crt)

# Create secret
kubectl create secret generic kyverno-ca-bundle \
  --from-literal=ca.crt="${CA_BUNDLE}" \
  --namespace=kyverno \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Create Server Certificate Secret

```bash
# Create secret with server certificate and key
kubectl create secret tls kyverno-webhook-tls \
  --cert=kyverno.crt \
  --key=kyverno.key \
  --namespace=kyverno
```

### Create Client Certificate Secret

```bash
# Create secret with client certificate and key
kubectl create secret generic kyverno-admission-client \
  --from-file=client.crt=admission-client.crt \
  --from-file=client.key=admission-client.key \
  --namespace=kyverno
```

---

## ValidatingWebhookConfiguration

```yaml
# kyverno-validation-webhook.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: kyverno-validation-webhook
  annotations:
    cert-manager.io/inject-ca-from: kyverno/kyverno-serving-cert
webhooks:
  - name: validate.kyverno.svc
    clientConfig:
      service:
        namespace: kyverno
        name: kyverno
        path: "/validate"
      caBundle: <base64-encoded-ca.crt>
    rules:
      - apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["*"]
        excludeResourceRules:
          - apiGroups: [""]
            apiVersions: ["v1"]
            resources: ["secrets"]
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
        - key: kyverno-exclude
          operator: DoesNotExist
```

### MutatingWebhookConfiguration

```yaml
# kyverno-mutating-webhook.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: kyverno-mutating-webhook
webhooks:
  - name: mutate.kyverno.svc
    clientConfig:
      service:
        namespace: kyverno
        name: kyverno
        path: "/mutate"
      caBundle: <base64-encoded-ca.crt>
    rules:
      - apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["*"]
        excludeResourceRules:
          - apiGroups: [""]
            apiVersions: ["v1"]
            resources: ["secrets"]
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
        - key: kyverno-exclude
          operator: DoesNotExist
```

---

## Kyverno Deployment Configuration

Update Kyverno deployment to use TLS:

```yaml
# kyverno-deployment-tls.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kyverno
  namespace: kyverno
spec:
  template:
    spec:
      containers:
        - name: kyverno
          args:
            - --tlsCertFile=/etc/kyverno/tls/tls.crt
            - --tlsPrivateKeyFile=/etc/kyverno/tls/tls.key
          volumeMounts:
            - name: webhook-tls
              mountPath: /etc/kyverno/tls
              readOnly: true
      volumes:
        - name: webhook-tls
          secret:
            secretName: kyverno-webhook-tls
```

---

## Verification

### Check Webhook Configuration

```bash
# Verify webhook is configured
kubectl get validatingwebhookconfiguration kyverno-validation-webhook -o yaml

# Check CA bundle
kubectl get validatingwebhookconfiguration kyverno-validation-webhook -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | base64 -d
```

### Test Webhook Connectivity

```bash
# Test HTTPS connectivity
kubectl run test-pod --rm -it --image=busybox --namespace=kyverno -- \
  wget -qO- --timeout=10 https://kyverno.kyverno.svc:443/healthz

# Check Kyverno logs
kubectl logs -n kyverno -l app=kyverno --tail=100 | grep -i tls
```

### Verify Certificate Expiration

```bash
# Check server certificate
openssl x509 -in kyverno.crt -noout -dates

# Check client certificate
openssl x509 -in admission-client.crt -noout -dates

# Check CA certificate
openssl x509 -in ca.crt -noout -dates
```

---

## Certificate Rotation

### Automated Rotation with cert-manager

```yaml
# kyverno-certificates.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kyverno-serving
  namespace: kyverno
spec:
  secretName: kyverno-webhook-tls
  duration: 2160h  # 90 days
  renewBefore: 360h  # 15 days
  subject:
    organizations:
      - University Marburg
  commonName: kyverno.kyverno.svc
  isCA: false
  usages:
    - digital signature
    - key encipherment
  dnsNames:
    - kyverno.kyverno.svc
    - kyverno.kyverno.svc.cluster.local
  issuerRef:
    name: opendesk-ca
    kind: ClusterIssuer
    group: cert-manager.io
```

### Manual Rotation

```bash
# Rotate server certificate (valid for 1 year)
./generate-certificates.sh --server --days=365

# Apply new certificate
kubectl apply -f kyverno-webhook-tls.yaml

# Restart Kyverno pods
kubectl rollout restart deployment/kyverno -n kyverno
```

---

## Troubleshooting

### Webhook Not Working

```bash
# Check webhook configuration
kubectl describe validatingwebhookconfiguration kyverno-validation-webhook

# Check Kyverno pod logs
kubectl logs -n kyverno -l app=kyverno | grep -i webhook

# Test webhook endpoint
curl -k https://<kyverno-pod-ip>:9443/healthz
```

### Certificate Errors

```bash
# Verify certificate chain
openssl verify -CAfile ca.crt kyverno.crt

# Check certificate details
openssl x509 -in kyverno.crt -noout -text

# Verify SAN includes service name
openssl x509 -in kyverno.crt -noout -text | grep -A1 "Subject Alternative Name"
```

---

## Compliance Mapping

| ZKI-Anforderung | BSI-Baustein | Umsetzung |
|-----------------|--------------|-----------|
| INF.1.A10 | Zugriffskontrolle | Client-Zertifikate für Webhook |
| INF.5.A1 | Netzwerksicherheit | TLS für alle Webhook-Kommunikation |
| INF.1.A15 | Audit | Webhook-Logs im SIEM |
| APP.3.A1 | Anwendungssicherheit | Verschlüsselte API-Kommunikation |

---

**Next Steps:**
1. Generate certificates using the commands above
2. Apply Kubernetes secrets
3. Update Kyverno deployment
4. Verify webhook configuration
5. Test with sample resource creation
6. Monitor logs for errors
