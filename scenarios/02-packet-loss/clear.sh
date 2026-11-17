#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Removing flight-agent packet-loss injection..."
kubectl delete -f "${SCRIPT_DIR}/chaos.yaml" --ignore-not-found
echo "Fault cleared. tcp.retrans should return to near-zero within ~60 seconds."
