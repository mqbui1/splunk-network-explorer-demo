#!/bin/bash
# Interactive demo runner — walks through all 4 Network Explorer eBPF scenarios.
#
# Usage:
#   ./demo.sh
#
# Each scenario prompts before injecting and before clearing, so you can
# narrate in Splunk between steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pause() {
  echo ""
  echo -e "${YELLOW}Press ENTER to continue...${RESET}"
  read -r
}

header() {
  echo ""
  echo -e "${BOLD}${CYAN}========================================${RESET}"
  echo -e "${BOLD}${CYAN}  $1${RESET}"
  echo -e "${BOLD}${CYAN}========================================${RESET}"
  echo ""
}

# ----------------------------------------------------------------
# Preflight checks
# ----------------------------------------------------------------
header "Preflight Check"

echo "Checking cluster access..."
kubectl get nodes --no-headers 2>/dev/null || {
  echo "ERROR: kubectl cannot reach the cluster. Run ./setup/01-cluster.sh first."
  exit 1
}

echo "Checking travel-planner pods..."
kubectl get pods -n travel-planner --no-headers 2>/dev/null | grep -v Terminating || {
  echo "ERROR: travel-planner namespace not found. Run ./setup/04-deploy.sh first."
  exit 1
}

echo ""
echo -e "${GREEN}Cluster OK. Load generator should be running (./setup/06-load.sh).${RESET}"
echo ""
echo "Open in Splunk before starting:"
echo "  1. APM -> Service Map (filter: environment = \${INSTANCE}-demo)"
echo "  2. Infrastructure -> Network Explorer (filter: namespace = travel-planner)"
pause

# ----------------------------------------------------------------
# Act 0: Healthy Baseline
# ----------------------------------------------------------------
header "Act 0 — Healthy Baseline (show this BEFORE any fault)"
echo "Walk through what 'good' looks like so the audience has a reference point."
echo ""
echo "APM — Service Map:"
echo "  - All 6 services green: orchestrator, flight-agent, hotel-agent,"
echo "    activity-agent, currency-agent, synthesizer"
echo "  - P50 latency < 100ms on all edges, error rate ~0%"
echo "  - Service map shows the full call chain: orchestrator fans out to all agents"
echo ""
echo "Infrastructure — Network Explorer (filter: namespace = travel-planner):"
echo "  KEY METRICS TO SHOW:"
echo "  +---------------------------+----------------------------------+"
echo "  | Metric                    | Healthy value                    |"
echo "  +---------------------------+----------------------------------+"
echo "  | tcp.rtt.average           | < 1ms between pods (loopback)    |"
echo "  | tcp.retrans               | Near zero (0-1 per minute)       |"
echo "  | tcp.bytes                 | Steady throughput, no drops      |"
echo "  | tcp.new_sockets           | Consistent rate matching RPS     |"
echo "  | tcp.active                | Stable active connection count   |"
echo "  | http.client.duration.avg  | < 100ms, matches APM latency     |"
echo "  +---------------------------+----------------------------------+"
echo ""
echo "  - Network flow map shows connections between all services"
echo "  - No red/amber indicators on any flow"
echo "  - http.client.duration.average in Network Explorer MATCHES APM"
echo "    span latency — this cross-validation is a key trust signal"
echo ""
echo "TALKING POINT:"
echo "  'This is our travel booking platform in a healthy state. APM shows"
echo "   the application call graph. Network Explorer shows the same topology"
echo "   from the kernel — before any code runs. RTT under 1ms, zero retransmits,"
echo "   steady throughput. This is our baseline. Now let us break things.'"
pause

# ----------------------------------------------------------------
# Scenario 1: Network Latency
# ----------------------------------------------------------------
header "Scenario 1 of 4 — Network Latency (hotel-agent)"
echo "FAULT:   Chaos Mesh tc netem — 2000ms delay on hotel-agent inbound traffic"
echo "APM:     hotel-agent P99 latency spikes to 2s+"
echo "eBPF:    tcp.rtt.average for hotel-agent flows jumps from <1ms to 2000ms"
echo ""
echo "TALKING POINT:"
echo "  'APM tells us WHERE it's slow. eBPF tells us WHY — it's the network"
echo "   layer, not slow app code or a database query.'"
pause

echo -e "${YELLOW}Injecting fault...${RESET}"
"${SCRIPT_DIR}/scenarios/01-network-latency/inject.sh"

echo ""
echo -e "${YELLOW}Wait 30-60 seconds, then show Splunk. Come back when ready to clear.${RESET}"
pause

echo -e "${YELLOW}Clearing fault...${RESET}"
"${SCRIPT_DIR}/scenarios/01-network-latency/clear.sh"
echo -e "${GREEN}Scenario 1 cleared. Wait ~30s for metrics to recover.${RESET}"
pause

# ----------------------------------------------------------------
# Scenario 2: Packet Loss
# ----------------------------------------------------------------
header "Scenario 2 of 4 — Packet Loss (flight-agent)"
echo "FAULT:   Chaos Mesh tc netem — 25% random packet loss on flight-agent"
echo "APM:     Intermittent errors + elevated P95/P99 on flight-agent"
echo "eBPF:    tcp.retrans spikes — TCP retransmitting to compensate for drops"
echo ""
echo "TALKING POINT:"
echo "  'Intermittent failures — the classic works-sometimes problem."
echo "   eBPF retransmit signature proves it's packet loss in the overlay"
echo "   network, not a code bug or flaky dependency.'"
pause

echo -e "${YELLOW}Injecting fault...${RESET}"
"${SCRIPT_DIR}/scenarios/02-packet-loss/inject.sh"

echo ""
echo -e "${YELLOW}Wait 60 seconds for retransmits to accumulate, then show Splunk.${RESET}"
pause

echo -e "${YELLOW}Clearing fault...${RESET}"
"${SCRIPT_DIR}/scenarios/02-packet-loss/clear.sh"
echo -e "${GREEN}Scenario 2 cleared.${RESET}"
pause

# ----------------------------------------------------------------
# Scenario 3: Connection Drop
# ----------------------------------------------------------------
header "Scenario 3 of 4 — Connection Drop (currency-agent)"
echo "FAULT:   Kubernetes NetworkPolicy — deny all ingress to currency-agent"
echo "APM:     All currency-agent calls time out (~5s) with connection errors"
echo "eBPF:    tcp.new_sockets drops to zero — no TCP sessions established"
echo ""
echo "TALKING POINT:"
echo "  'No network path at all — firewall rule or policy change. eBPF sees"
echo "   it immediately without touching a firewall log. The app team"
echo "   gets cleared instantly.'"
pause

echo -e "${YELLOW}Injecting fault...${RESET}"
"${SCRIPT_DIR}/scenarios/03-connection-drop/inject.sh"

echo ""
echo -e "${YELLOW}Active immediately. Show Splunk now — no wait needed.${RESET}"
pause

echo -e "${YELLOW}Clearing fault...${RESET}"
"${SCRIPT_DIR}/scenarios/03-connection-drop/clear.sh"
echo -e "${GREEN}Scenario 3 cleared.${RESET}"
pause

# ----------------------------------------------------------------
# Scenario 4: Bandwidth Throttle
# ----------------------------------------------------------------
header "Scenario 4 of 4 — Bandwidth Throttle (synthesizer)"
echo "FAULT:   Chaos Mesh bandwidth — 100 Kbps cap on synthesizer"
echo "APM:     All /plan calls slow (synthesizer aggregates everything)"
echo "eBPF:    tcp.bytes collapses — normal RTT, no retransmits, just starved bandwidth"
echo ""
echo "TALKING POINT:"
echo "  'Throughput collapse without RTT increase or retransmits — that is a"
echo "   rate limit or noisy-neighbor QoS policy, not an app bottleneck."
echo "   Three different network failure patterns, one consistent workflow.'"
pause

echo -e "${YELLOW}Injecting fault...${RESET}"
"${SCRIPT_DIR}/scenarios/04-bandwidth-throttle/inject.sh"

echo ""
echo -e "${YELLOW}Wait 60-90 seconds (bandwidth saturation is gradual), then show Splunk.${RESET}"
pause

echo -e "${YELLOW}Clearing fault...${RESET}"
"${SCRIPT_DIR}/scenarios/04-bandwidth-throttle/clear.sh"
echo -e "${GREEN}Scenario 4 cleared.${RESET}"

# ----------------------------------------------------------------
# Closing
# ----------------------------------------------------------------
header "Demo Complete"
echo -e "${GREEN}All 4 scenarios complete.${RESET}"
echo ""
echo "CLOSING TALKING POINT:"
echo "  'In all 4 scenarios APM symptoms looked the same — slow or failed calls."
echo "   Network Explorer gave us the evidence layer: RTT, retransmits, blocked"
echo "   connections, starved bandwidth — zero code changes, kernel-level telemetry,"
echo "   no network team handoff. That is the power of eBPF in Splunk O11y.'"
echo ""
echo "To reset everything:"
echo "  kubectl delete networkchaos --all -n travel-planner 2>/dev/null || true"
echo "  kubectl delete networkpolicy --all -n travel-planner 2>/dev/null || true"
echo ""
