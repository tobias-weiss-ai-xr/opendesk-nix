# Kubernetes Secrets - Template Files

> **IMPORTANT**: These are TEMPLATE files. Do NOT apply as-is.
> Copy, customize with actual credentials, and apply.

---

## 📁 Available Templates

Each file in this directory is a template for creating Kubernetes secrets.
Before deploying, you must:

1. Copy the template file (e.g., `mariadb-secrets-template.yaml`)
2. Rename it (remove `-template` suffix)
3. Replace all placeholder values (`CHANGE_ME`) with actual credentials
4. Apply it to your cluster

---

## 🔐 Secrets Required by OpenDesk Edu

### Database Secrets
- `mariadb-secrets.yaml` - MariaDB credentials
- `postgresql-secrets.yaml` - PostgreSQL credentials
- `redis-secrets.yaml` - Redis password (optional)

### Application Secrets
- `sogo-secrets.yaml` - SOGo database and mail credentials
- `moodle-secrets.yaml` - Moodle database credentials
- `keycloak-secrets.yaml` - Keycloak admin credentials
- `minio-secrets.yaml` - MinIO root credentials

### Identity Provider Secrets
- `keycloak-secrets.yaml` - Keycloak configuration

---

## ⚠️ Security Warning

**NEVER commit actual secrets to version control!**

These template files use placeholder values. After customizing:
- Add to `.gitignore`
- Store in a secure secrets manager
- Use sealed-secrets or SOPS for encryption
- Apply with `kubectl apply -f <file>.yaml`

---

## 📊 How to Use

```bash
# Database secrets (required)
cp mariadb-secrets-template.yaml mariadb-secrets.yaml
# Edit mariadb-secrets.yaml with actual credentials
kubectl apply -f mariadb-secrets.yaml

# Application secrets (required)
cp sogo-secrets-template.yaml sogo-secrets.yaml
kubectl apply -f sogo-secrets.yaml

# Verify
kubectl get secrets -n opendesk
```

---

## 🔄 Updating Secrets

To update a secret without downtime:

```bash
# Update the file
nano sogo-secrets.yaml

# Apply the update (Kubernetes will automatically restart pods if needed)
kubectl apply -f sogo-secrets.yaml
```

---

## 📝 Notes

- All secrets are created in the `opendesk` namespace
- Use strong, randomly generated passwords (32+ characters)
- Consider using a password manager or vault
- Rotate secrets regularly (every 90 days recommended)
