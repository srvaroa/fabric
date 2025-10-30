#!/usr/bin/env bash
set -euo pipefail

info() {
    echo "[INFO] $1"
}

warn() {
    echo "[WARN] $1"
}

error() {
    echo "[ERROR] $1"
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
