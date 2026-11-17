#!/bin/bash
# Block all traffic to currency-agent via NetworkPolicy (simulates firewall/routing failure).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Blocking all ingress to currency-agent (NetworkPolicy DENY)..."
kubectl apply -f "${SCRIPT_DIR}/policy.yaml"

echo ""
echo "Policy active immediately. Check Splunk:"
echo "  APM  -> orchestrator spans: currency-agent calls will timeout (~5s)"
echo "       -> 'currency-agent: HTTPSConnectionPool read timed out' errors"
echo "  IM   -> Network Explorer -> filter dst.service = currency-agent"
echo "          Metric: tcp.new_sockets drops to zero"
echo "          new TCP connections show SYN_SENT but no SYN_ACK — connection blocked"
echo ""
echo "Demo talking point:"
echo "  'Currency lookups are failing — the orchestrator times out every request.'"
echo "  'eBPF shows active TCP connections to currency-agent have gone to zero.'"
echo "  'This is a network-level block — firewall rule or NetworkPolicy change.'"
echo "  'Without eBPF, we would have blamed the app. The kernel knows the truth.'"
echo ""
echo "Run ./clear.sh to restore connectivity."
