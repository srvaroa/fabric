#!/usr/bin/env bash
set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

NAMESPACE="${NAMESPACE:-fabric}"
CLUSTER_NAME="${CLUSTER_NAME:-fabric-local}"

info "Creating minimal configs for Fabric controller in namespace '$NAMESPACE'"
echo ""

# Check if cluster exists
if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" &> /dev/null; then
    echo "Error: Cluster 'kind-${CLUSTER_NAME}' not found"
    exit 1
fi

# Create fabric-ctrl-config ConfigMap with minimal config
step "Creating fabric-ctrl-config ConfigMap..."
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
echo ""

# Create fab-ca ConfigMap with a self-signed CA
step "Creating fab-ca ConfigMap..."

# Generate a simple self-signed CA certificate
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout /tmp/ca.key -out /tmp/ca.crt \
    -subj "/CN=Fabric Local CA/O=Hedgehog/C=US" 2>/dev/null

kubectl create configmap fab-ca -n "$NAMESPACE" \
    --from-file=ca.crt=/tmp/ca.crt \
    --dry-run=client -o yaml | kubectl apply -f -

rm -f /tmp/ca.key /tmp/ca.crt

info "✓ fab-ca created"
echo ""

# Create registry-user-reader Secret with dummy credentials
step "Creating registry-user-reader Secret..."
kubectl create secret generic registry-user-reader -n "$NAMESPACE" \
    --from-literal=username=local \
    --from-literal=password=local \
    --dry-run=client -o yaml | kubectl apply -f -

info "✓ registry-user-reader created"
echo ""

info "======================================"
info "Configuration created successfully!"
info "======================================"
echo ""
info "The Fabric controller should now start."
info "Monitor the pod with:"
echo "  kubectl get pods -n $NAMESPACE -w"
echo ""
info "View logs:"
echo "  kubectl logs -n $NAMESPACE -l control-plane=controller-manager --follow"
echo ""
