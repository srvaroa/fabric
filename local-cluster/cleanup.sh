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

# Check if KIND is installed
if ! command -v kind &> /dev/null; then
    error "KIND is not installed."
    exit 1
fi

# Check if cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "Cluster '$CLUSTER_NAME' does not exist."
    exit 0
fi

info "Deleting KIND cluster '$CLUSTER_NAME'..."
kind delete cluster --name "$CLUSTER_NAME"

info "Cluster deleted successfully!"
info "All resources have been cleaned up. Your machine is clean."
