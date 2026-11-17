#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Removing synthesizer bandwidth throttle..."
kubectl delete -f "${SCRIPT_DIR}/chaos.yaml" --ignore-not-found
echo "Throttle removed. bytes_recv should recover to normal within ~30 seconds."
