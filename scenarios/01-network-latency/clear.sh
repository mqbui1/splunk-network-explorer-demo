#!/bin/bash
# Remove the hotel-agent latency injection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Removing hotel-agent latency injection..."
kubectl delete -f "${SCRIPT_DIR}/chaos.yaml" --ignore-not-found

echo ""
echo "Fault cleared. Watch Splunk for recovery:"
echo "  network.flow.rtt_ns  should return to baseline within ~30 seconds"
echo "  APM latency should normalize within 1-2 minutes"
