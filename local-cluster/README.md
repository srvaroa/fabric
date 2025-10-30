# Local Kubernetes Cluster Setup

Get Fabric running in a local KIND cluster in 3 steps.

## Quick Start

```bash
# 1. Create cluster
./setup-kind.sh

# 2. Load images
./load-images.sh

# 3. Deploy (includes controller configuration)
./deploy-fabric.sh

# Verify
kubectl get pods -n fabric
kubectl get crds | grep githedgehog

# When done
./cleanup.sh
```

## Prerequisites

- **Docker** - Must be running
- **kubectl** - Kubernetes CLI
- **KIND** - Install with:
  ```bash
  # On Linux
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind

  # On macOS
  brew install kind
  ```

- **Built binaries and Helm charts** - Build first:
  ```bash
  cd ..
  just build

  # Copy binaries to docker directories
  cp bin/fabric config/docker/fabric/
  cp bin/fabric-dhcpd config/docker/fabric-dhcpd/
  cp bin/fabric-boot config/docker/fabric-boot/

  # Build Helm charts (required for deployment)
  just _helm-fabric-api
  just _helm-fabric
  ```

## What Each Script Does

### `./setup-kind.sh`
Creates a KIND cluster named `fabric-local`. 

### `./load-images.sh`
Builds Docker images from your binaries and loads them into the cluster:
- `githedgehog/fabric/fabric:<version>`
- `githedgehog/fabric/fabric-dhcpd:<version>`
- `githedgehog/fabric/fabric-boot:<version>`

### `./deploy-fabric.sh`
Deploys Fabric to the cluster:
- Creates `fabric` namespace
- Installs cert-manager (required for webhooks)
- Installs CRDs via Helm charts
- Deploys controller using Helm (must build charts first with `just _helm-fabric-api` and `just _helm-fabric`)
- Creates required ConfigMaps and Secrets (fab-ca, fabric-ctrl-config, registry-user-reader)
- Waits for controller to be ready

### `./cleanup.sh`
Deletes the cluster completely. Your machine is clean.

## Troubleshooting

### Docker not running
```bash
sudo systemctl start docker  # Linux
# or start Docker Desktop on macOS
```

### KIND cluster already exists
```bash
kind delete cluster --name fabric-local
```

### Images not loading
Check binaries are copied:
```bash
ls -la ../config/docker/fabric/fabric
ls -la ../config/docker/fabric-dhcpd/fabric-dhcpd
ls -la ../config/docker/fabric-boot/fabric-boot
```

### Deployment fails - Helm charts not found
Build the Helm charts first:
```bash
cd ..
just _helm-fabric-api
just _helm-fabric
```

### Can't connect to cluster
```bash
kubectl cluster-info --context kind-fabric-local
```

## Manual Deployment

If you prefer manual control:

```bash
# Create cluster
kind create cluster --name fabric-local

# Build and load images
cd ../config/docker/fabric
docker build -t githedgehog/fabric/fabric:latest .
kind load docker-image githedgehog/fabric/fabric:latest --name fabric-local

# Deploy
kubectl create namespace fabric
kubectl apply -f ../config/crd/bases/
helm install fabric-api ../config/helm/fabric-api-*.tgz -n fabric

# Watch
kubectl get pods -n fabric -w
```

## Custom Cluster Name

```bash
CLUSTER_NAME=my-cluster ./setup-kind.sh
CLUSTER_NAME=my-cluster ./load-images.sh
CLUSTER_NAME=my-cluster ./deploy-fabric.sh
```
