#!/bin/bash
# Pre-Change Backup Script for Kyverno Policies
#
# Creates a backup before making policy changes for audit and rollback purposes.
#
# Usage: ./pre-change-backup.sh "Description of change"
#
# Example: ./pre-change-backup.sh "Adding new image verification policy"

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CHANGE_DESCRIPTION="${1:-Manual backup}"
BACKUP_DIR="/tmp/kyverno-backup"
ENCRYPTED_DIR="/tmp/kyverno-encrypted"

# Create directories
mkdir -p "$BACKUP_DIR"
mkdir -p "$ENCRYPTED_DIR"

echo -e "${GREEN}=== Pre-Change Backup ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Change Description: $CHANGE_DESCRIPTION"
echo ""

# Export ClusterPolicies
echo "Exporting ClusterPolicies..."
kubectl get clusterpolicies -o yaml > "$BACKUP_DIR/clusterpolicies-${TIMESTAMP}.yaml"
CLUSTER_POLICY_COUNT=$(grep -c "^  name:" "$BACKUP_DIR/clusterpolicies-${TIMESTAMP}.yaml" || echo 0)
echo "  Found $CLUSTER_POLICY_COUNT ClusterPolicies"

# Export Policies
echo "Exporting Policies..."
kubectl get policies --all-namespaces -o yaml > "$BACKUP_DIR/policies-${TIMESTAMP}.yaml"
POLICY_COUNT=$(grep -c "^  name:" "$BACKUP_DIR/policies-${TIMESTAMP}.yaml" || echo 0)
echo "  Found $POLICY_COUNT Policies"

# Export PolicyReports
echo "Exporting PolicyReports..."
kubectl get policyreports --all-namespaces -o yaml > "$BACKUP_DIR/policyreports-${TIMESTAMP}.yaml" || true

# Export ClusterPolicyReports
echo "Exporting ClusterPolicyReports..."
kubectl get clusterpolicyreports -o yaml > "$BACKUP_DIR/clusterpolicyreports-${TIMESTAMP}.yaml" || true

# Create combined backup
echo ""
echo "Creating combined backup..."
cat "$BACKUP_DIR"/*-${TIMESTAMP}.yaml > "$BACKUP_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml"

# Create metadata file
cat > "$BACKUP_DIR/metadata-${TIMESTAMP}.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "change_description": "$CHANGE_DESCRIPTION",
  "cluster_policies": $CLUSTER_POLICY_COUNT,
  "policies": $POLICY_COUNT,
  "backup_type": "pre-change",
  "created_by": "$(whoami)",
  "hostname": "$(hostname)"
}
EOF

# Encrypt with SOPS (if SOPS is available)
if command -v sops &> /dev/null; then
    echo ""
    echo "Encrypting with SOPS..."
    
    # Try Age encryption
    if [ -n "$SOPS_AGE_KEY" ]; then
        sops --encrypt \
            --age "$SOPS_AGE_KEY" \
            "$BACKUP_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml" \
            > "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc"
        echo "  Encrypted with Age key"
    # Try PGP encryption
    elif [ -n "$SOPS_PGP_FP" ]; then
        sops --encrypt \
            --pgp "$SOPS_PGP_FP" \
            "$BACKUP_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml" \
            > "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc"
        echo "  Encrypted with PGP key"
    else
        echo -e "${YELLOW}Warning: No encryption key found. Backup will be unencrypted.${NC}"
        cp "$BACKUP_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml" \
           "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc"
    fi
    
    # Create checksum
    sha256sum "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc" > \
        "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc.sha256"
    
    echo "  Checksum created"
else
    echo -e "${YELLOW}Warning: SOPS not found. Backup will be unencrypted.${NC}"
    cp "$BACKUP_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml" \
       "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc"
fi

# Upload to cloud storage (if available)
echo ""
echo "Uploading to cloud storage..."

if command -v aws &> /dev/null && [ -n "$BACKUP_BUCKET" ]; then
    aws s3 cp "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc" \
        "s3://${BACKUP_BUCKET}/kyverno/pre-change/" || \
    echo -e "${YELLOW}Warning: S3 upload failed${NC}"
    
    aws s3 cp "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc.sha256" \
        "s3://${BACKUP_BUCKET}/kyverno/pre-change/" || \
    echo -e "${YELLOW}Warning: Checksum upload failed${NC}"
    
    echo "  Uploaded to s3://${BACKUP_BUCKET}/kyverno/pre-change/"
elif command -v gcloud &> /dev/null && [ -n "$BACKUP_BUCKET" ]; then
    gcloud storage cp "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc" \
        "gs://${BACKUP_BUCKET}/kyverno/pre-change/" || \
    echo -e "${YELLOW}Warning: GCS upload failed${NC}"
    
    gcloud storage cp "$ENCRYPTED_DIR/kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc.sha256" \
        "gs://${BACKUP_BUCKET}/kyverno/pre-change/" || \
    echo -e "${YELLOW}Warning: Checksum upload failed${NC}"
    
    echo "  Uploaded to gs://${BACKUP_BUCKET}/kyverno/pre-change/"
else
    echo -e "${YELLOW}Warning: No cloud storage configured. Backup saved locally.${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo "Backup file: kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc"
echo "Location: $ENCRYPTED_DIR/"
if [ -n "$BACKUP_BUCKET" ]; then
    echo "Cloud: ${BACKUP_BUCKET}/kyverno/pre-change/"
fi
echo ""
echo "To restore:"
echo "  sops --decrypt kyverno-pre-change-backup-${TIMESTAMP}.yaml.enc > restore.yaml"
echo "  kubectl apply -f restore.yaml"
echo ""
echo "Remember to document the change in GitLab:"
echo "  git commit -m \"chore: $(echo $CHANGE_DESCRIPTION | head -c 50)...\""
