#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-fabric-local}"
NAMESPACE="${NAMESPACE:-fabric}"
FABRIC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=$(cd "$FABRIC_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo "unknown")

info "Fabric root: $FABRIC_ROOT"
info "Version: $VERSION"
info "Target cluster: $CLUSTER_NAME"
info "Target namespace: $NAMESPACE"
echo ""

# Check if kubectl is configured for the cluster
if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" &> /dev/null; then
    error "Cannot connect to cluster 'kind-${CLUSTER_NAME}'"
    info "Make sure the cluster is running: kind get clusters"
    exit 1
fi

# Set context
info "Setting kubectl context to kind-${CLUSTER_NAME}..."
kubectl config use-context "kind-${CLUSTER_NAME}"

# Create namespace
step "Creating namespace '$NAMESPACE'..."
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    warn "Namespace '$NAMESPACE' already exists"
else
    kubectl create namespace "$NAMESPACE"
    info "✓ Namespace created"
fi
echo ""

# Check if we should install CRDs manually (if Helm charts don't exist)
HELM_API_CHART=$(ls "$FABRIC_ROOT"/config/helm/fabric-api-*.tgz 2>/dev/null | head -1 || echo "")

if [[ -z "$HELM_API_CHART" ]]; then
    # No Helm chart, install CRDs manually
    step "Installing Custom Resource Definitions (CRDs)..."
    if [[ -d "$FABRIC_ROOT/config/crd/bases" ]]; then
        kubectl apply -f "$FABRIC_ROOT/config/crd/bases/"
        info "✓ CRDs installed"
    else
        error "CRDs directory not found: $FABRIC_ROOT/config/crd/bases"
        exit 1
    fi
    echo ""

    # Wait for CRDs to be established
    step "Waiting for CRDs to be established..."
    sleep 5

    # List installed CRDs
    info "Installed CRDs:"
    kubectl get crds | grep githedgehog || true
    echo ""
else
    info "Helm charts found - CRDs will be installed via Helm chart"
    echo ""
fi

# Install cert-manager if not present (required for Fabric)
if ! kubectl get namespace cert-manager &> /dev/null; then
    step "Installing cert-manager (required for Fabric webhooks)..."
    info "Applying cert-manager v1.13.0..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

    info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available --timeout=120s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=Available --timeout=120s deployment/cert-manager-webhook -n cert-manager
    kubectl wait --for=condition=Available --timeout=120s deployment/cert-manager-cainjector -n cert-manager
    info "✓ cert-manager installed"
    echo ""
else
    info "cert-manager already installed"
    echo ""
fi

# Check if Helm charts exist
HELM_API_CHART=$(ls "$FABRIC_ROOT"/config/helm/fabric-api-*.tgz 2>/dev/null | head -1 || echo "")
HELM_FABRIC_CHART=$(ls "$FABRIC_ROOT"/config/helm/fabric-v*.tgz 2>/dev/null | head -1 || echo "")

if [[ -n "$HELM_API_CHART" ]]; then
    step "Installing Fabric API Helm chart..."
    info "Chart: $HELM_API_CHART"

    # Check if CRDs already exist without Helm management
    if kubectl get crds | grep -q "githedgehog.com" && ! helm list -n "$NAMESPACE" | grep -q "fabric-api"; then
        warn "CRDs exist but not managed by Helm. Deleting them first..."
        kubectl delete crds -l app.kubernetes.io/part-of=fabric 2>/dev/null || true
        kubectl get crds | grep githedgehog | awk '{print $1}' | xargs -r kubectl delete crd 2>/dev/null || true
        sleep 3
    fi

    # Check if already installed
    if helm list -n "$NAMESPACE" | grep -q "fabric-api"; then
        warn "fabric-api already installed, upgrading..."
        helm upgrade fabric-api "$HELM_API_CHART" -n "$NAMESPACE"
    else
        helm install fabric-api "$HELM_API_CHART" -n "$NAMESPACE"
    fi
    info "✓ Fabric API Helm chart installed"

    # Wait for CRDs to be established
    info "Waiting for CRDs to be established..."
    sleep 5
    kubectl get crds | grep githedgehog || true
    echo ""
else
    warn "Fabric API Helm chart not found in $FABRIC_ROOT/config/helm/"
    info "You may need to build it with: just _helm-fabric-api"
    echo ""
fi

if [[ -n "$HELM_FABRIC_CHART" ]]; then
    step "Installing Fabric Helm chart..."
    info "Chart: $HELM_FABRIC_CHART"

    # Update image pull policy to use local images
    cat > /tmp/fabric-values.yaml <<EOF
ctrl:
  manager:
    image:
      repository: githedgehog/fabric/fabric
      tag: $VERSION
      pullPolicy: Never
EOF

    # Check if already installed (check for STATUS: deployed)
    if helm list -n "$NAMESPACE" -o json | grep -q '"name":"fabric"' && \
       helm status fabric -n "$NAMESPACE" 2>/dev/null | grep -q "STATUS: deployed"; then
        warn "fabric already installed, upgrading..."
        helm upgrade fabric "$HELM_FABRIC_CHART" -n "$NAMESPACE" -f /tmp/fabric-values.yaml
    else
        # Uninstall if exists but not deployed properly
        helm uninstall fabric -n "$NAMESPACE" 2>/dev/null || true
        info "Installing fabric chart..."
        helm install fabric "$HELM_FABRIC_CHART" -n "$NAMESPACE" -f /tmp/fabric-values.yaml
    fi
    info "✓ Fabric Helm chart installed"
    echo ""
else
    warn "Fabric Helm chart not found in $FABRIC_ROOT/config/helm/"
    info "You may need to build it with: just _helm-fabric"
    echo ""
fi

# Create required ConfigMaps and Secrets for controller
step "Creating controller configuration..."

# Create fabric-ctrl-config ConfigMap
info "Creating fabric-ctrl-config ConfigMap..."
kubectl create configmap fabric-ctrl-config -n "$NAMESPACE" --from-literal=config.yaml='
deploymentID: local-dev
controlVIP: 172.30.0.1
apiServer: https://kubernetes.default.svc
agentRepo: githedgehog/fabric
vpcIRBVLANRange:
  - from: 1000
    to: 1999
vpcPeeringVLANRange:
  - from: 2000
    to: 2999
reservedSubnets:
  - 172.30.0.0/16
  - 10.0.0.0/8
fabricMode: spine-leaf
baseVPCCommunity: 50000:0
vpcLoopbackSubnet: 10.99.0.0/16
fabricMTU: 9000
serverFacingMTUOffset: 100
eslagMACBase: 00:00:5e:00:01:01
eslagESIPrefix: "00:f2:00:00:"
mclagSessionSubnet: 169.254.0.0/16
defaultMaxPathsEBGP: 64
gatewayASN: 65100
managementDHCPStart: 172.30.1.10
managementDHCPEnd: 172.30.1.250
' --dry-run=client -o yaml | kubectl apply -f -

info "✓ fabric-ctrl-config created"

# Create fab-ca ConfigMap with self-signed CA
info "Creating fab-ca ConfigMap..."
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout /tmp/ca.key -out /tmp/ca.crt \
    -subj "/CN=Fabric Local CA/O=Hedgehog/C=US" 2>/dev/null

kubectl create configmap fab-ca -n "$NAMESPACE" \
    --from-file=ca.crt=/tmp/ca.crt \
    --dry-run=client -o yaml | kubectl apply -f -

rm -f /tmp/ca.key /tmp/ca.crt
info "✓ fab-ca created"

# Create registry-user-reader Secret
info "Creating registry-user-reader Secret..."
kubectl create secret generic registry-user-reader -n "$NAMESPACE" \
    --from-literal=username=local \
    --from-literal=password=local \
    --dry-run=client -o yaml | kubectl apply -f -

info "✓ registry-user-reader created"
echo ""

info "Waiting for controller pod to start..."
kubectl rollout status deployment/fabric-ctrl-manager -n "$NAMESPACE" --timeout=60s || warn "Controller pod may still be starting"
echo ""

echo ""
info "======================================"
info "Deployment Status"
info "======================================"
echo ""

# Show pods
info "Pods in namespace '$NAMESPACE':"
kubectl get pods -n "$NAMESPACE" -o wide || warn "No pods found yet"
echo ""

# Show CRDs
info "Custom Resources:"
kubectl api-resources --api-group=githedgehog.com || true
kubectl api-resources | grep -E "(wiring|vpc|agent|dhcp)" || warn "No Fabric CRDs found"
echo ""

info "======================================"
info "Next Steps"
info "======================================"
echo ""
info "Monitor pods:"
echo "  kubectl get pods -n $NAMESPACE -w"
echo ""
info "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app=fabric --follow"
echo ""
info "Check CRDs:"
echo "  kubectl get crds | grep githedgehog"
echo ""
info "Access the cluster:"
echo "  kubectl config use-context kind-${CLUSTER_NAME}"
echo ""
