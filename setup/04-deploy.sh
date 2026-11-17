#!/bin/bash
# Deploy travel-planner app manifests to K8s.
#
# Required env vars:
#   INSTANCE - demo instance name (used as the OTel deployment.environment)
set -euo pipefail

: "${INSTANCE:?Set INSTANCE}"

MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo "==> Applying namespace..."
kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"

echo "==> Creating demo-secret (deployment environment tag)..."
kubectl create secret generic demo-secret \
  --from-literal=env="${INSTANCE}-demo" \
  --namespace travel-planner \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploying travel-planner services..."
for svc in orchestrator flight-agent hotel-agent activity-agent currency-agent synthesizer; do
  kubectl apply -f "${MANIFESTS_DIR}/${svc}.yaml"
done

echo "==> Waiting for all deployments to be ready..."
for svc in orchestrator flight-agent hotel-agent activity-agent currency-agent synthesizer; do
  kubectl rollout status deployment/${svc} -n travel-planner --timeout=120s
done

echo ""
echo "==> Pod status:"
kubectl get pods -n travel-planner

echo ""
echo "==> Services:"
kubectl get svc -n travel-planner

echo ""
echo "App deployed. Test with:"
echo "  curl -s -X POST http://localhost:8080/plan -H 'Content-Type: application/json' \\"
echo "       -d '{\"origin\":\"Seattle\",\"destination\":\"Paris\",\"travellers\":2}' | python3 -m json.tool"
