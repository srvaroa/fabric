#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-fabric-local}"
FABRIC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=$(cd "$FABRIC_ROOT" && git describe --tags --always --dirty)

info "Fabric root: $FABRIC_ROOT"
info "Version: $VERSION"

# Check if KIND is installed
if ! command -v kind &> /dev/null; then
    error "KIND is not installed. Please install it first:"
    echo ""
    echo "  # On Linux:"
    echo "  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64"
    echo "  chmod +x ./kind"
    echo "  sudo mv ./kind /usr/local/bin/kind"
    echo ""
    echo "  # On macOS:"
    echo "  brew install kind"
    echo ""
    echo "  # Or download from: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "Cluster '$CLUSTER_NAME' already exists."
    read -p "Do you want to delete and recreate it? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    else
        info "Using existing cluster."
        CLUSTER_EXISTS=true
    fi
fi

# Create KIND cluster if it doesn't exist
if [[ "${CLUSTER_EXISTS:-false}" != "true" ]]; then
    info "Creating KIND cluster '$CLUSTER_NAME'..."

    # Create KIND config with registry
    cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
EOF

    kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml
    rm /tmp/kind-config.yaml

    info "Cluster created successfully!"
fi

# Set kubectl context
info "Setting kubectl context..."
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# Check if images exist
info "Checking for built images..."
IMAGES=(
    "fabric"
    "fabric-dhcpd"
    "fabric-boot"
)

MISSING_IMAGES=()
for img in "${IMAGES[@]}"; do
    if [[ ! -f "$FABRIC_ROOT/config/docker/$img/$img" ]]; then
        MISSING_IMAGES+=("$img")
    fi
done

if [[ ${#MISSING_IMAGES[@]} -gt 0 ]]; then
    error "The following binaries are missing in config/docker directories:"
    for img in "${MISSING_IMAGES[@]}"; do
        echo "  - $img"
    done
    echo ""
    warn "Please build the images first:"
    echo "  cd $FABRIC_ROOT"
    echo "  cp bin/fabric config/docker/fabric/"
    echo "  cp bin/fabric-dhcpd config/docker/fabric-dhcpd/"
    echo "  cp bin/fabric-boot config/docker/fabric-boot/"
    exit 1
fi

# Build and load Docker images into KIND
info "Building and loading Docker images into KIND cluster..."

for img in "${IMAGES[@]}"; do
    IMAGE_NAME="githedgehog/fabric/$img:$VERSION"
    info "Building image: $IMAGE_NAME"

    docker build \
        --platform=linux/amd64 \
        -t "$IMAGE_NAME" \
        -f "$FABRIC_ROOT/config/docker/$img/Dockerfile" \
        "$FABRIC_ROOT/config/docker/$img/"

    info "Loading image into KIND cluster: $IMAGE_NAME"
    kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"
done

info "All images loaded successfully!"

# Verify images are loaded
info "Verifying images in cluster..."
docker exec "${CLUSTER_NAME}-control-plane" crictl images | grep -E "(fabric|REPOSITORY)" || true

echo ""
info "======================================"
info "Cluster setup complete!"
info "======================================"
echo ""
info "Cluster name: $CLUSTER_NAME"
info "Kubectl context: kind-${CLUSTER_NAME}"
echo ""
info "Loaded images:"
for img in "${IMAGES[@]}"; do
    echo "  - githedgehog/fabric/$img:$VERSION"
done
echo ""
info "Next steps:"
echo "  1. Install CRDs: kubectl apply -f $FABRIC_ROOT/config/crd/bases/"
echo "  2. Or use Helm charts from: $FABRIC_ROOT/config/helm/"
echo ""
info "To delete the cluster when done:"
echo "  kind delete cluster --name $CLUSTER_NAME"
echo ""
