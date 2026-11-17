#!/bin/bash
# Inject 2-second TCP latency on hotel-agent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Injecting network latency on hotel-agent (2000ms +/- 200ms)..."
kubectl apply -f "${SCRIPT_DIR}/chaos.yaml"

echo ""
echo "Chaos active. Wait 30-60 seconds, then check Splunk:"
echo "  APM  -> Service Map -> hotel-agent (latency will spike)"
echo "  IM   -> Network Explorer -> filter dst.service = hotel-agent"
echo "          Metric: network.flow.rtt_ns  (should show sharp step-up)"
echo ""
echo "Demo talking point:"
echo "  'APM shows hotel-agent is slow. But is it the app or the network?'"
echo "  'eBPF shows TCP RTT jumped from <1ms to 2000ms — it is a network issue.'"
echo "  'No code change, no log trawling, no waiting for the network team.'"
echo ""
echo "Run ./clear.sh to remove the fault."
