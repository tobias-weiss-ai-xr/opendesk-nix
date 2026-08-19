# openDesk Edu - Production Deployment Guide

**Version:** 1.0  
**Created:** 2026-08-07  
**Status:** Ready for Production

---

## Overview

This guide provides step-by-step instructions for deploying openDesk Edu to the HRZ K3s cluster.

### Prerequisites

- kubectl configured for K3s cluster
- GitLab PAT with `read_registry` scope
- SOPS encryption keys for backup
- TLS certificates for Kyverno webhook
- DPO approval for SECURITY_POLICY.md

---

## Deployment Checklist

### Phase 1: Pre-Deployment (Day 1)

- [ ] Generate TLS certificates for Kyverno webhook
- [ ] Deploy backup CronJob
- [ ] Configure SOPS encryption
- [ ] Verify registry authentication

### Phase 2: Security Infrastructure (Day 2)

- [ ] Deploy Kyverno policies
- [ ] Enable policy enforcement
- [ ] Verify compliance scans
- [ ] Configure monitoring alerts

### Phase 3: Operators (Day 3)

- [ ] Deploy Compliance Operator
- [ ] Deploy Image Builder Operator
- [ ] Create Compliance instance
- [ ] Verify operator functionality

### Phase 4: Services (Day 4-5)

- [ ] Deploy Stalwart (mail)
- [ ] Deploy SOGo 5 (groupware)
- [ ] Deploy SOGo 6 (groupware)
- [ ] Deploy openCloud (files)

### Phase 5: Validation (Day 6-7)

- [ ] Run compliance scan
- [ ] Verify all services
- [ ] Test backup/restore
- [ ] Document deployment

---

## Phase 1: Pre-Deployment

### 1.1 Generate TLS Certificates

```bash
# Navigate to scripts directory
cd /home/weissto_local/git/opendesk_git/opendesk-nix/scripts/

# Generate all certificates
./generate-tls-certificates.sh --all --days 3650 --output-dir ./certs

# Verify certificates
ls -la ./certs/
openssl x509 -in ./certs/ca.crt -noout -dates
```

**Expected Output:**
```
[INFO] Generating TLS certificates
[INFO] Output directory: ./certs
[INFO] Validity: 3650 days
[INFO] === Generating CA Certificate ===
[INFO] === Generating Server Certificate ===
[INFO] === Generating Client Certificate ===
[INFO] === Creating Kubernetes Secrets ===
[INFO] === Certificate Generation Complete ===
```

### 1.2 Apply Kubernetes Secrets

```bash
# Apply CA bundle
kubectl apply -f ./certs/ca-bundle-secret.yaml

# Apply server certificate
kubectl apply -f ./certs/kyverno-webhook-tls-secret.yaml

# Apply client certificate
kubectl apply -f ./certs/admission-client-secret.yaml

# Verify secrets
kubectl get secrets -n kyverno
```

### 1.3 Deploy Backup CronJob

```bash
# Configure SOPS encryption key
export SOPS_AGE_KEY="age1234567890abcdefghijklmnopqrstuvwxyz"

# Configure backup bucket
export BACKUP_BUCKET="opendesk-backup"

# Deploy backup CronJob
kubectl apply -f k8s/security/policy-backup/kyverno-policy-backup-cronjob.yaml

# Verify CronJob
kubectl get cronjob -n kyverno-backup
kubectl get pods -n kyverno-backup -l app.kubernetes.io/name=kyverno-policy-backup
```

### 1.4 Verify Registry Authentication

```bash
# Test registry access
docker pull registry.opencode.de/umr/opendesk-edu/opendesk-nix/sogo5:latest

# Or using kubectl
kubectl run test-pull --rm -it --image=registry.opencode.de/umr/opendesk-edu/opendesk-nix/sogo5:latest --namespace=default -- /bin/sh
```

---

## Phase 2: Security Infrastructure

### 2.1 Deploy Kyverno Policies

```bash
# Build compliance policies
cd examples/compliance
nix build .#packages.x86_64-linux.compliance-policies

# Apply policies
kubectl apply -f result/

# Verify policies
kubectl get clusterpolicies
```

**Expected Output:**
```
NAME                         VALIDATIONACTION   BACKGROUND   READY
require-non-root             Enforce            true         true
require-network-policy       Audit              true         true
require-resource-labels      Enforce            true         true
require-resource-limits      Enforce            true         true
verify-image-signatures      Enforce            false        true
require-read-only-rootfs     Enforce            true         true
drop-capabilities            Enforce            true         true
```

### 2.2 Configure Webhook Configuration

```bash
# Apply validating webhook
kubectl apply -f ./certs/kyverno-validation-webhook.yaml

# Apply mutating webhook
kubectl apply -f ./certs/kyverno-mutating-webhook.yaml

# Verify webhook configuration
kubectl get validatingwebhookconfiguration kyverno-validation-webhook -o yaml
kubectl get mutatingwebhookconfiguration kyverno-mutating-webhook -o yaml
```

### 2.3 Test Policy Enforcement

```bash
# This should FAIL (no resource limits)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-no-limits
  labels:
    app: test
spec:
  containers:
    - name: nginx
      image: nginx:latest
EOF

# Expected: Error - Containers must have resource limits

# This should PASS
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-compliant
  labels:
    app: test
spec:
  securityContext:
    runAsNonRoot: true
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
  containers:
    - name: nginx
      image: registry.opencode.de/umr/opendesk-edu/opendesk-nix/nginx:latest
      resources:
        requests:
          memory: "64Mi"
          cpu: "250m"
        limits:
          memory: "128Mi"
          cpu: "500m"
      securityContext:
        runAsNonRoot: true
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
EOF

# Expected: Pod created successfully
```

### 2.4 Verify Compliance Scans

```bash
# Check policy reports
kubectl get policyreports --all-namespaces

# Check cluster policy reports
kubectl get clusterpolicyreports -o wide

# View compliance score
kubectl get clusterpolicyreports -o jsonpath='{.items[0].status.summary}'
```

---

## Phase 3: Operators

### 3.1 Deploy Operators

```bash
# Navigate to scripts directory
cd scripts/

# Deploy with wait
./deploy-operators.sh --namespace opendesk --wait --timeout 300
```

**Expected Output:**
```
[INFO] === Deploying Custom Resource Definitions ===
[INFO] Deploying Compliance Operator CRD...
[INFO] Deploying Image Builder Operator CRD...
[INFO] === Deploying RBAC Configurations ===
[INFO] Creating Compliance Operator ServiceAccount...
[INFO] Creating Image Builder Operator ServiceAccount...
[INFO] === Deploying Operators ===
[INFO] Deploying Compliance Operator...
[INFO] Deploying Image Builder Operator...
[INFO] === Waiting for Deployments ===
[INFO] All deployments are ready
```

### 3.2 Verify Operator Deployment

```bash
# Check operator pods
kubectl get pods -n opendesk -l app=compliance-operator
kubectl get pods -n opendesk -l app=image-builder-operator

# Check operator logs
kubectl logs -n opendesk -l app=compliance-operator --tail=50
kubectl logs -n opendesk -l app=image-builder-operator --tail=50

# Check CRDs
kubectl get crd | grep opendesk-edu.org
```

### 3.3 Create Compliance Instance

```bash
# Create compliance scan instance
cat <<EOF | kubectl apply -f -
apiVersion: opendesk-edu.org/v1alpha1
kind: Compliance
metadata:
  name: zki-daily-scan
  namespace: opendesk
spec:
  framework: "zki-it-grundschutz"
  namespaces:
    - opendesk
    - kyverno
    - monitoring
  schedule: "0 2 * * *"  # Daily at 2 AM
  severityThreshold: "high"
EOF

# Verify instance
kubectl get compliance -n opendesk
```

### 3.4 Create ImageBuild Instance

```bash
# Create image build instance
cat <<EOF | kubectl apply -f -
apiVersion: opendesk-edu.org/v1alpha1
kind: ImageBuild
metadata:
  name: sogo6-build
  namespace: opendesk
spec:
  service: sogo6
  registries:
    - registry.opencode.de/umr/opendesk-edu/opendesk-nix
    - ghcr.io/opendesk-edu
  sign: true
EOF

# Verify instance
kubectl get imagebuild -n opendesk
```

---

## Phase 4: Services

### 4.1 Deploy Stalwart (Mail Server)

```bash
# Deploy from examples
kubectl apply -k k8s/groupware/stalwart/ -n opendesk

# Wait for deployment
kubectl wait --for=condition=available deployment/stalwart -n opendesk --timeout=300s

# Verify
kubectl get pods -n opendesk -l app=stalwart
kubectl get svc -n opendesk -l app=stalwart
```

### 4.2 Deploy SOGo 5 (Groupware)

```bash
# Deploy from examples
kubectl apply -k k8s/groupware/sogo5/ -n opendesk

# Wait for deployment
kubectl wait --for=condition=available deployment/sogo5 -n opendesk --timeout=300s

# Verify
kubectl get pods -n opendesk -l app=sogo5
kubectl get svc -n opendesk -l app=sogo5
```

### 4.3 Deploy SOGo 6 (Groupware)

```bash
# Deploy from examples
kubectl apply -k k8s/groupware/sogo6/ -n opendesk

# Wait for deployment
kubectl wait --for=condition=available deployment/sogo6 -n opendesk --timeout=300s

# Verify
kubectl get pods -n opendesk -l app=sogo6
kubectl get svc -n opendesk -l app=sogo6
```

### 4.4 Deploy openCloud (Files)

```bash
# Deploy from examples
kubectl apply -k k8s/services/opencloud/ -n opendesk

# Wait for deployment
kubectl wait --for=condition=available deployment/opencloud -n opendesk --timeout=300s

# Verify
kubectl get pods -n opendesk -l app=opencloud
kubectl get svc -n opendesk -l app=opencloud
```


### 4.6 Verify All Services

```bash
# Check all pods
kubectl get pods -n opendesk -l app=opendesk

# Check all services
kubectl get svc -n opendesk -l app=opendesk

# Check all deployments
kubectl get deployments -n opendesk -l app=opendesk
```

**Expected Output:**
```
NAME                         READY   STATUS    RESTARTS   AGE
stalwart-7f8c9d5e6-n3j5l     1/1     Running   0          5m
sogo5-6d4b8f9c7-x2k4m        1/1     Running   0          5m
sogo6-5c6d7e8f9-a1b2c        1/1     Running   0          5m
opencloud-4b5c6d7e8-d3e4f    1/1     Running   0          5m
```

---

## Phase 5: Validation

### 5.1 Run Compliance Scan

```bash
# Trigger manual compliance scan
kubectl create job --from=cronjob/kyverno-policy-backup manual-compliance-scan -n kyverno-backup

# Wait for job completion
kubectl wait --for=condition=complete job/manual-compliance-scan -n kyverno-backup --timeout=600s

# View results
kubectl get policyreports --all-namespaces
kubectl get clusterpolicyreports -o wide
```

### 5.2 Test Backup/Restore

```bash
# Trigger manual backup
kubectl create job --from=cronjob/kyverno-policy-backup manual-backup-test -n kyverno-backup

# Wait for job completion
kubectl wait --for=condition=complete job/manual-backup-test -n kyverno-backup --timeout=600s

# Verify backup in cloud storage
aws s3 ls s3://${BACKUP_BUCKET}/kyverno/
# or
gcloud storage ls gs://${BACKUP_BUCKET}/kyverno/
```

### 5.3 Verify Monitoring

```bash
# Check Prometheus metrics
curl -s http://kyverno-metrics:8000/metrics | grep kyverno_policy_rule_result_total

# Check Grafana dashboard
# Navigate to: https://grafana.opendesk-edu.org/d/kyverno-compliance/kyverno-compliance

# Check alert status
kubectl get alerts -n monitoring
```

### 5.4 Document Deployment

```bash
# Generate deployment report
cat > deployment-report.md << EOF
# Deployment Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Cluster:** HRZ K3s
**Namespace:** opendesk

## Components Deployed

### Operators
$(kubectl get deployments -n opendesk -l app=opendesk -o wide)

### Services
$(kubectl get pods -n opendesk -l app=opendesk -o wide)

## Compliance Status

$(kubectl get clusterpolicyreports -o wide)

## Backup Status

Last backup: $(kubectl get cronjob kyverno-policy-backup -n kyverno-backup -o jsonpath='{.status.lastSuccessfulTime}')

## Next Steps

- [ ] Schedule DPO review
- [ ] Enable all Kyverno policies to enforce
- [ ] Configure SIEM integration
- [ ] Set up Grafana dashboards
EOF

echo "Deployment report created: deployment-report.md"
```

---

## Troubleshooting

### Operator Not Starting

```bash
# Check operator logs
kubectl logs -n opendesk -l app=compliance-operator --tail=100
kubectl logs -n opendesk -l app=image-builder-operator --tail=100

# Describe deployment
kubectl describe deployment/compliance-operator -n opendesk
kubectl describe deployment/image-builder-operator -n opendesk

# Check events
kubectl get events -n opendesk --sort-by='.lastTimestamp'
```

### Policy Not Enforcing

```bash
# Check policy status
kubectl get clusterpolicies -o wide

# Check policy reports
kubectl get policyreports --all-namespaces

# Check Kyverno logs
kubectl logs -n kyverno -l app=kyverno --tail=100 | grep -i error
```

### Service Not Reachable

```bash
# Check service endpoints
kubectl get endpoints -n opendesk

# Check network policies
kubectl get networkpolicy -n opendesk

# Test connectivity
kubectl run test --rm -it --image=busybox -n opendesk -- wget -qO- http://<service-name>
```

---

## Rollback Procedures

### Rollback Operator

```bash
# Rollback compliance operator
kubectl rollout undo deployment/compliance-operator -n opendesk

# Rollback image builder operator
kubectl rollout undo deployment/image-builder-operator -n opendesk
```

### Rollback Service

```bash
# Rollback specific service
kubectl rollout undo deployment/<service-name> -n opendesk
```

### Emergency Policy Disable

```bash
# Use emergency script
./k8s/security/emergency/emergency-policy-disable.sh L1 <policy-name>

# Or L2 for namespace
./k8s/security/emergency/emergency-policy-disable.sh L2 <namespace>

# Or L3 for full bypass (EMERGENCY ONLY)
./k8s/security/emergency/emergency-policy-disable.sh L3
```

---

## Contact & Escalation

| Issue Type | Contact | Escalation |
|------------|---------|------------|
| Operator Failure | devops@opendesk-edu.org | L2 |
| Policy Violation | security@opendesk-edu.org | L2 |
| Service Down | devops@opendesk-edu.org | L2 |
| Security Breach | security@opendesk-edu.org | L3 |
| Compliance Issue | tobias.weiss@hrz.uni-marburg.de | L3 |

---

**End of Deployment Guide**
