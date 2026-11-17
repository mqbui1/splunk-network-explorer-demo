#!/bin/bash
# Throttle synthesizer ingress bandwidth to 100 Kbps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Throttling synthesizer bandwidth to 100 Kbps..."
kubectl apply -f "${SCRIPT_DIR}/chaos.yaml"

echo ""
echo "Throttle active. Wait 60-90 seconds (bandwidth saturation is gradual)."
echo "Check Splunk:"
echo "  APM  -> synthesizer: P99 latency climbs gradually as requests queue"
echo "       -> overall /plan endpoint response time degrades"
echo "  IM   -> Network Explorer -> filter dst.service = synthesizer"
echo "          Metric: network.flow.bytes_recv drops sharply (throughput starvation)"
echo "          network.flow.rtt_ns may increase as buffers fill (secondary effect)"
echo ""
echo "Demo talking point:"
echo "  'The booking summary is slow. Synthesizer looks like the culprit in APM.'"
echo "  'eBPF shows bytes received by synthesizer has collapsed — not slow code,'"
echo "  'it is starved for bandwidth. Noisy-neighbor or misconfigured rate limit.'"
echo ""
echo "Run ./clear.sh to remove the throttle."
