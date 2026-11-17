#!/bin/bash
# Install Chaos Mesh — used for network latency and packet-loss injection.
# Chaos Mesh CRDs (NetworkChaos) are the recommended approach for K8s-native
# fault injection. Avoids the need for privileged host-PID pods.
#
# k3d note: k3d uses k3s which uses containerd with a non-standard socket path.
# The chaos-daemon must be told where the containerd socket lives.
set -euo pipefail

CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.7.0}"

echo "==> Adding Chaos Mesh Helm repo..."
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

echo "==> Installing Chaos Mesh v${CHAOS_MESH_VERSION}..."
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --version "${CHAOS_MESH_VERSION}" \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/k3s/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --wait --timeout=180s

echo "==> Chaos Mesh pods:"
kubectl get pods -n chaos-mesh

echo ""
echo "Chaos Mesh installed. Available CRDs for this demo:"
echo "  NetworkChaos  - latency, packet loss, bandwidth limit"
echo "  PodChaos      - pod kill, container kill"
echo ""
echo "No RBAC token needed (securityMode=false for demo simplicity)."
