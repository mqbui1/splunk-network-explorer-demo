#!/bin/bash
# Inject 25% packet loss on flight-agent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Injecting 25% packet loss on flight-agent..."
kubectl apply -f "${SCRIPT_DIR}/chaos.yaml"

echo ""
echo "Chaos active. Wait 60 seconds, then check Splunk:"
echo "  APM  -> Service Map -> flight-agent"
echo "       -> Error rate increases (intermittent request failures)"
echo "       -> P99 latency spikes (TCP retransmit backoff adds latency)"
echo "  IM   -> Network Explorer -> filter dst.service = flight-agent"
echo "          Metric: tcp.retrans  (should spike significantly)"
echo ""
echo "Demo talking point:"
echo "  'Flight search is failing intermittently — classic overlay network packet loss.'"
echo "  'eBPF shows TCP retransmits spiking. That is the kernel telling us packets'"
echo "  'are being dropped in the container network fabric — not an app bug.'"
echo ""
echo "Run ./clear.sh to remove the fault."
