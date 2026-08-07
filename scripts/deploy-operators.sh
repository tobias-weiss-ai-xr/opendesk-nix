#!/bin/bash
# Deploy OpenDesk Edu Operators to Kubernetes Cluster
#
# This script deploys the Compliance Operator and Image Builder Operator
# along with all necessary RBAC configurations and CRDs.
#
# Usage: ./deploy-operators.sh [OPTIONS]
#
# Options:
#   --namespace      Target namespace (default: opendesk)
#   --dry-run        Show what would be deployed without applying
#   --skip-crd       Skip CRD deployment (if already installed)
#   --skip-rbac      Skip RBAC deployment (if already configured)
#   --wait           Wait for all deployments to be ready
#   --timeout        Wait timeout in seconds (default: 300)
#   --help           Show this help message
#
# Example:
#   ./deploy-operators.sh --namespace opendesk --wait
#   ./deploy-operators.sh --dry-run

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
NAMESPACE="opendesk"
DRY_RUN=false
SKIP_CRD=false
SKIP_RBAC=false
WAIT=false
TIMEOUT=300

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp] [INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    if [ "$DRY_RUN" = false ] && ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log "INFO" "Creating namespace $NAMESPACE..."
        kubectl create namespace "$NAMESPACE"
    fi
    
    log "INFO" "Prerequisites check passed"
}

# Show usage
usage() {
    cat << EOF
Deploy OpenDesk Edu Operators to Kubernetes Cluster

Usage: $0 [OPTIONS]

Options:
  --namespace      Target namespace (default: opendesk)
  --dry-run        Show what would be deployed without applying
  --skip-crd       Skip CRD deployment (if already installed)
  --skip-rbac      Skip RBAC deployment (if already configured)
  --wait           Wait for all deployments to be ready
  --timeout        Wait timeout in seconds (default: 300)
  --help           Show this help message

Example:
  $0 --namespace opendesk --wait
  $0 --dry-run

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-crd)
            SKIP_CRD=true
            shift
            ;;
        --skip-rbac)
            SKIP_RBAC=true
            shift
            ;;
        --wait)
            WAIT=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    log "INFO" "=== DRY RUN MODE ==="
    log "INFO" "The following manifests would be applied:"
    log "INFO" ""
fi

# ============================================================================
# Deploy CRDs
# ============================================================================

if [ "$SKIP_CRD" = false ]; then
    log "INFO" "=== Deploying Custom Resource Definitions ==="
    
    # Compliance Operator CRD
    log "INFO" "Deploying Compliance Operator CRD..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: compliances.opendesk-edu.org
spec:
  group: opendesk-edu.org
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                framework:
                  type: string
                namespaces:
                  type: array
                  items:
                    type: string
                schedule:
                  type: string
                severityThreshold:
                  type: string
            status:
              type: object
              properties:
                lastScanTime:
                  type: string
                  format: date-time
                score:
                  type: integer
                violations:
                  type: array
                phase:
                  type: string
  scope: Namespaced
  names:
    plural: compliances
    singular: compliance
    kind: Compliance
    shortNames:
      - comp
EOF
    else
        kubectl apply -f - << EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: compliances.opendesk-edu.org
spec:
  group: opendesk-edu.org
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                framework:
                  type: string
                namespaces:
                  type: array
                  items:
                    type: string
                schedule:
                  type: string
                severityThreshold:
                  type: string
            status:
              type: object
              properties:
                lastScanTime:
                  type: string
                  format: date-time
                score:
                  type: integer
                violations:
                  type: array
                phase:
                  type: string
  scope: Namespaced
  names:
    plural: compliances
    singular: compliance
    kind: Compliance
    shortNames:
      - comp
EOF
    fi
    
    # Image Builder Operator CRD
    log "INFO" "Deploying Image Builder Operator CRD..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: imagebuilds.opendesk-edu.org
spec:
  group: opendesk-edu.org
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                service:
                  type: string
                registries:
                  type: array
                  items:
                    type: string
                sign:
                  type: boolean
            status:
              type: object
              properties:
                phase:
                  type: string
                buildLog:
                  type: string
                imageDigest:
                  type: string
                signed:
                  type: boolean
  scope: Namespaced
  names:
    plural: imagebuilds
    singular: imagebuild
    kind: ImageBuild
    shortNames:
      - ib
EOF
    else
        kubectl apply -f - << EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: imagebuilds.opendesk-edu.org
spec:
  group: opendesk-edu.org
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                service:
                  type: string
                registries:
                  type: array
                  items:
                    type: string
                sign:
                  type: boolean
            status:
              type: object
              properties:
                phase:
                  type: string
                buildLog:
                  type: string
                imageDigest:
                  type: string
                signed:
                  type: boolean
  scope: Namespaced
  names:
    plural: imagebuilds
    singular: imagebuild
    kind: ImageBuild
    shortNames:
      - ib
EOF
    fi
    
    log "INFO" "CRDs deployed successfully"
fi

# ============================================================================
# Deploy RBAC
# ============================================================================

if [ "$SKIP_RBAC" = false ]; then
    log "INFO" "=== Deploying RBAC Configurations ==="
    
    # Compliance Operator ServiceAccount
    log "INFO" "Creating Compliance Operator ServiceAccount..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: compliance-operator
  namespace: $NAMESPACE
EOF
    else
        kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: compliance-operator
  namespace: $NAMESPACE
EOF
    fi
    
    # Image Builder Operator ServiceAccount
    log "INFO" "Creating Image Builder Operator ServiceAccount..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: image-builder-operator
  namespace: $NAMESPACE
EOF
    else
        kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: image-builder-operator
  namespace: $NAMESPACE
EOF
    fi
    
    # Compliance Operator ClusterRole
    log "INFO" "Creating Compliance Operator ClusterRole..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: compliance-operator
rules:
  - apiGroups: ["opendesk-edu.org"]
    resources: ["compliances", "compliances/status", "compliances/finalizers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["kyverno.io"]
    resources: ["clusterpolicies", "policies", "policystatus"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["reports.kyverno.com"]
    resources: ["policyreports", "clusterpolicyreports"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["namespaces", "pods", "services", "deployments"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "watch"]
EOF
    else
        kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: compliance-operator
rules:
  - apiGroups: ["opendesk-edu.org"]
    resources: ["compliances", "compliances/status", "compliances/finalizers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["kyverno.io"]
    resources: ["clusterpolicies", "policies", "policystatus"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["reports.kyverno.com"]
    resources: ["policyreports", "clusterpolicyreports"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["namespaces", "pods", "services", "deployments"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "watch"]
EOF
    fi
    
    # Image Builder Operator ClusterRole
    log "INFO" "Creating Image Builder Operator ClusterRole..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: image-builder-operator
rules:
  - apiGroups: ["opendesk-edu.org"]
    resources: ["imagebuilds", "imagebuilds/status", "imagebuilds/finalizers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods", "pods/log", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
EOF
    else
        kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: image-builder-operator
rules:
  - apiGroups: ["opendesk-edu.org"]
    resources: ["imagebuilds", "imagebuilds/status", "imagebuilds/finalizers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods", "pods/log", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
EOF
    fi
    
    # Compliance Operator ClusterRoleBinding
    log "INFO" "Creating Compliance Operator ClusterRoleBinding..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: compliance-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: compliance-operator
subjects:
  - kind: ServiceAccount
    name: compliance-operator
    namespace: $NAMESPACE
EOF
    else
        kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: compliance-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: compliance-operator
subjects:
  - kind: ServiceAccount
    name: compliance-operator
    namespace: $NAMESPACE
EOF
    fi
    
    # Image Builder Operator ClusterRoleBinding
    log "INFO" "Creating Image Builder Operator ClusterRoleBinding..."
    if [ "$DRY_RUN" = true ]; then
        cat << EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: image-builder-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: image-builder-operator
subjects:
  - kind: ServiceAccount
    name: image-builder-operator
    namespace: $NAMESPACE
EOF
    else
        kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: image-builder-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: image-builder-operator
subjects:
  - kind: ServiceAccount
    name: image-builder-operator
    namespace: $NAMESPACE
EOF
    fi
    
    log "INFO" "RBAC configurations deployed successfully"
fi

# ============================================================================
# Deploy Operators
# ============================================================================

log "INFO" "=== Deploying Operators ==="

# Compliance Operator Deployment
log "INFO" "Deploying Compliance Operator..."
if [ "$DRY_RUN" = true ]; then
    cat << EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compliance-operator
  namespace: $NAMESPACE
  labels:
    app: compliance-operator
    app.kubernetes.io/name: compliance-operator
spec:
  replicas: 2
  selector:
    matchLabels:
      app: compliance-operator
  template:
    metadata:
      labels:
        app: compliance-operator
        app.kubernetes.io/name: compliance-operator
    spec:
      serviceAccountName: compliance-operator
      containers:
        - name: compliance-operator
          image: opendesk-edu/compliance-operator:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: metrics
            - containerPort: 9443
              name: webhook
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          env:
            - name: WATCH_NAMESPACE
              value: ""
            - name: OPERATOR_NAME
              value: "compliance-operator"
            - name: LOG_LEVEL
              value: "info"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
EOF
else
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compliance-operator
  namespace: $NAMESPACE
  labels:
    app: compliance-operator
    app.kubernetes.io/name: compliance-operator
spec:
  replicas: 2
  selector:
    matchLabels:
      app: compliance-operator
  template:
    metadata:
      labels:
        app: compliance-operator
        app.kubernetes.io/name: compliance-operator
    spec:
      serviceAccountName: compliance-operator
      containers:
        - name: compliance-operator
          image: opendesk-edu/compliance-operator:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: metrics
            - containerPort: 9443
              name: webhook
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          env:
            - name: WATCH_NAMESPACE
              value: ""
            - name: OPERATOR_NAME
              value: "compliance-operator"
            - name: LOG_LEVEL
              value: "info"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
EOF
fi

# Image Builder Operator Deployment
log "INFO" "Deploying Image Builder Operator..."
if [ "$DRY_RUN" = true ]; then
    cat << EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-builder-operator
  namespace: $NAMESPACE
  labels:
    app: image-builder-operator
    app.kubernetes.io/name: image-builder-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-builder-operator
  template:
    metadata:
      labels:
        app: image-builder-operator
        app.kubernetes.io/name: image-builder-operator
    spec:
      serviceAccountName: image-builder-operator
      containers:
        - name: image-builder-operator
          image: opendesk-edu/image-builder-operator:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8081
              name: metrics
            - containerPort: 9444
              name: webhook
          resources:
            requests:
              memory: "512Mi"
              cpu: "200m"
            limits:
              memory: "2Gi"
              cpu: "2000m"
          env:
            - name: WATCH_NAMESPACE
              value: "$NAMESPACE"
            - name: OPERATOR_NAME
              value: "image-builder-operator"
            - name: LOG_LEVEL
              value: "info"
            - name: NIX_STORE
              value: "/nix/store"
            - name: BUILD_TIMEOUT
              value: "3600"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
EOF
else
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-builder-operator
  namespace: $NAMESPACE
  labels:
    app: image-builder-operator
    app.kubernetes.io/name: image-builder-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-builder-operator
  template:
    metadata:
      labels:
        app: image-builder-operator
        app.kubernetes.io/name: image-builder-operator
    spec:
      serviceAccountName: image-builder-operator
      containers:
        - name: image-builder-operator
          image: opendesk-edu/image-builder-operator:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8081
              name: metrics
            - containerPort: 9444
              name: webhook
          resources:
            requests:
              memory: "512Mi"
              cpu: "200m"
            limits:
              memory: "2Gi"
              cpu: "2000m"
          env:
            - name: WATCH_NAMESPACE
              value: "$NAMESPACE"
            - name: OPERATOR_NAME
              value: "image-builder-operator"
            - name: LOG_LEVEL
              value: "info"
            - name: NIX_STORE
              value: "/nix/store"
            - name: BUILD_TIMEOUT
              value: "3600"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
EOF
fi

log "INFO" "Operators deployed successfully"

# ============================================================================
# Wait for Deployments (if requested)
# ============================================================================

if [ "$WAIT" = true ]; then
    log "INFO" "=== Waiting for Deployments ==="
    
    log "INFO" "Waiting for Compliance Operator to be ready..."
    kubectl rollout status deployment/compliance-operator -n "$NAMESPACE" --timeout="${TIMEOUT}s" || {
        log "ERROR" "Compliance Operator deployment failed"
        kubectl describe deployment/compliance-operator -n "$NAMESPACE"
        exit 1
    }
    
    log "INFO" "Waiting for Image Builder Operator to be ready..."
    kubectl rollout status deployment/image-builder-operator -n "$NAMESPACE" --timeout="${TIMEOUT}s" || {
        log "ERROR" "Image Builder Operator deployment failed"
        kubectl describe deployment/image-builder-operator -n "$NAMESPACE"
        exit 1
    }
    
    log "INFO" "All deployments are ready"
fi

# ============================================================================
# Summary
# ============================================================================

log "INFO" "=== Deployment Complete ==="
log "INFO" ""
log "INFO" "Deployed components:"
log "INFO" "  Namespace: $NAMESPACE"
log "INFO" "  CRDs: Compliance, ImageBuild"
log "INFO" "  ServiceAccounts: compliance-operator, image-builder-operator"
log "INFO" "  ClusterRoles: compliance-operator, image-builder-operator"
log "INFO" "  ClusterRoleBindings: compliance-operator, image-builder-operator"
log "INFO" "  Deployments: compliance-operator (2 replicas), image-builder-operator (1 replica)"
log "INFO" ""
log "INFO" "Verify deployment:"
log "INFO" "  kubectl get pods -n $NAMESPACE -l app=compliance-operator"
log "INFO" "  kubectl get pods -n $NAMESPACE -l app=image-builder-operator"
log "INFO" "  kubectl get crd | grep opendesk-edu.org"
log "INFO" ""
log "INFO" "View logs:"
log "INFO" "  kubectl logs -n $NAMESPACE -l app=compliance-operator"
log "INFO" "  kubectl logs -n $NAMESPACE -l app=image-builder-operator"
log "INFO" ""
log "INFO" "Create Compliance instance:"
log "INFO" "  kubectl apply -f examples/compliance/compliance-instance.yaml"
log "INFO" ""
log "INFO" "Create ImageBuild instance:"
log "INFO" "  kubectl apply -f examples/advanced/imagebuild-instance.yaml"
