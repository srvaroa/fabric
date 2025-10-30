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
VERSION=$(cd "$FABRIC_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo "unknown")

info "Fabric root: $FABRIC_ROOT"
info "Version: $VERSION"

# Check if KIND is installed
if ! command -v kind &> /dev/null; then
    error "KIND is not installed."
    exit 1
fi

# Check if cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    error "Cluster '$CLUSTER_NAME' does not exist."
    info "Create it first with: ./setup-kind.sh"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if binaries exist in docker directories
info "Checking for binaries in docker directories..."
IMAGES=(
    "fabric"
    "fabric-dhcpd"
    "fabric-boot"
)

MISSING_BINARIES=()
for img in "${IMAGES[@]}"; do
    if [[ ! -f "$FABRIC_ROOT/config/docker/$img/$img" ]]; then
        MISSING_BINARIES+=("$img")
    fi
done

if [[ ${#MISSING_BINARIES[@]} -gt 0 ]]; then
    error "The following binaries are missing in config/docker directories:"
    for img in "${MISSING_BINARIES[@]}"; do
        echo "  - config/docker/$img/$img"
    done
    echo ""
    warn "Copy binaries first:"
    echo "  cd $FABRIC_ROOT"
    echo "  cp bin/fabric config/docker/fabric/"
    echo "  cp bin/fabric-dhcpd config/docker/fabric-dhcpd/"
    echo "  cp bin/fabric-boot config/docker/fabric-boot/"
    exit 1
fi

# Build and load Docker images into KIND
info "Building and loading Docker images into KIND cluster '$CLUSTER_NAME'..."
echo ""

LOADED_IMAGES=()
for img in "${IMAGES[@]}"; do
    IMAGE_NAME="githedgehog/fabric/$img:$VERSION"
    info "Building image: $IMAGE_NAME"

    if docker build \
        --platform=linux/amd64 \
        -t "$IMAGE_NAME" \
        -f "$FABRIC_ROOT/config/docker/$img/Dockerfile" \
        "$FABRIC_ROOT/config/docker/$img/" > /tmp/docker-build-$img.log 2>&1; then
        info "✓ Built successfully"
    else
        error "Failed to build $IMAGE_NAME"
        cat /tmp/docker-build-$img.log
        exit 1
    fi

    info "Loading image into KIND cluster..."
    if kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME" > /tmp/kind-load-$img.log 2>&1; then
        info "✓ Loaded successfully"
        LOADED_IMAGES+=("$IMAGE_NAME")
    else
        error "Failed to load $IMAGE_NAME into cluster"
        cat /tmp/kind-load-$img.log
        exit 1
    fi
    echo ""
done

# Verify images are loaded
info "Verifying images in cluster..."
echo ""
docker exec "${CLUSTER_NAME}-control-plane" crictl images | grep -E "(fabric|REPOSITORY)"

echo ""
info "======================================"
info "Images loaded successfully!"
info "======================================"
echo ""
info "Loaded images:"
for img in "${LOADED_IMAGES[@]}"; do
    echo "  ✓ $img"
done
echo ""
info "Cluster: $CLUSTER_NAME"
info "Context: kind-${CLUSTER_NAME}"
echo ""
info "Next steps:"
echo "  # Verify images in cluster"
echo "  docker exec ${CLUSTER_NAME}-control-plane crictl images | grep fabric"
echo ""
echo "  # Deploy CRDs"
echo "  kubectl apply -f $FABRIC_ROOT/config/crd/bases/"
echo ""
echo "  # Or install using Helm"
echo "  kubectl create namespace fabric"
echo "  helm install fabric-api $FABRIC_ROOT/config/helm/fabric-api-*.tgz -n fabric"
echo ""
