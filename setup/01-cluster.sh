#!/bin/bash
# Create k3d cluster for eBPF network monitoring demo.
# Requires: k3d >= 5.6, docker >= 24, Linux host (or Docker Desktop on macOS)
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ebpf-travel-demo}"

echo "==> Creating k3d cluster: ${CLUSTER_NAME}"

# --k3s-arg disables Traefik (we don't need an ingress for this demo)
# NodePort 30080 is mapped to localhost:8080 for the load generator
k3d cluster create "${CLUSTER_NAME}" \
  --k3s-arg "--disable=traefik@server:0" \
  -p "8080:30080@loadbalancer" \
  --wait

echo "==> Verifying cluster..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "Cluster '${CLUSTER_NAME}' ready."
echo "Orchestrator NodePort will be accessible at http://localhost:8080 after app deploy."
