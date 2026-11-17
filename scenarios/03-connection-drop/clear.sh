#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Restoring currency-agent connectivity (deleting NetworkPolicy)..."
kubectl delete -f "${SCRIPT_DIR}/policy.yaml" --ignore-not-found
echo "Policy removed. Active connections to currency-agent should resume within ~10 seconds."
