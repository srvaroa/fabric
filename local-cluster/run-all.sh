#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
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
