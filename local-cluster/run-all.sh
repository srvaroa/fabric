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

step() {
    echo "═══════════════════════════════════════"
    echo "$1"
    echo "═══════════════════════════════════════"
    echo ""
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
step "🚀 Fabric Local Cluster - Complete Setup"
echo ""

info "This script will:"
echo "  1. Create a KIND cluster"
echo "  2. Build and load Docker images"
echo "  3. Deploy Fabric to the cluster (with configuration)"
echo ""

read -p "Continue? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    info "Aborted."
    exit 0
fi

echo ""
step "STEP 1: Creating KIND Cluster"
echo ""

if ! "$SCRIPT_DIR/setup-kind.sh"; then
    error "Failed to create KIND cluster"
    exit 1
fi

echo ""
step "STEP 2: Building and Loading Images"
echo ""

if ! "$SCRIPT_DIR/load-images.sh"; then
    error "Failed to load images"
    exit 1
fi

echo ""
step "STEP 3: Deploying Fabric"
echo ""

if ! "$SCRIPT_DIR/deploy-fabric.sh"; then
    error "Failed to deploy Fabric"
    exit 1
fi

echo ""
step "✅ Complete!"
echo ""

info "Your Fabric cluster is ready!"
echo ""
info "Useful commands:"
echo "  kubectl get pods -n fabric          # View pods"
echo "  kubectl get crds | grep githedgehog # View CRDs"
echo "  kubectl logs -n fabric -l app=fabric --follow  # View logs"
echo ""
info "To clean up:"
echo "  ./cleanup.sh"
echo ""
