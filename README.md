# Travel Planner eBPF Network Monitoring Demo

Demonstrates **Splunk Network Explorer** (eBPF-based network monitoring) using a travel planner
microservices app. Shows how kernel-level network telemetry surfaces the root cause of issues
that look like app errors but are actually network faults — without any code changes.

## Architecture

```
                        ┌─────────────────────────────────┐
                        │     travel-planner namespace      │
  load-gen ──HTTP──▶  orchestrator
                          │── flight-agent   (scenario 2: packet loss)
                          │── hotel-agent    (scenario 1: network latency)
                          │── activity-agent (scenario 4: connection drop)
                          │── currency-agent (scenario 3: connection drop)
                          └── synthesizer
                        └─────────────────────────────────┘

Splunk OTel Collector — Chart 1 (DaemonSet agent + Gateway + clusterReceiver)
  ├── APM traces   ─▶ Splunk APM
  └── Metrics      ─▶ Splunk IM

OTel eBPF — Chart 2 (upstream open-telemetry/opentelemetry-ebpf)
  ├── kernel-collector  ← eBPF DaemonSet, reads TCP/UDP/DNS/HTTP from kernel
  ├── reducer           ← aggregates kernel data into MTS (1 pod)
  └── k8s-collector     ← enriches flows with pod/service/namespace labels
  └── OTLP gRPC ──▶ Chart 1 Gateway ──▶ Splunk IM (tcp.* / http.* / dns.* metrics)

> Two-chart architecture required since splunk-otel-collector-chart v0.88.
> networkExplorer.enabled is deprecated — do NOT use it.
```

## Infrastructure Requirements

| Item | Requirement |
|------|-------------|
| OS | Linux only (kernel 4.4+, ideally 5.15+ for CO-RE eBPF) |
| Recommended | Ubuntu 22.04 EC2 c5.2xlarge or similar |
| K8s | k3d >= 5.6 (k3s in Docker) |
| Helm | >= 3.12 |
| Docker | >= 24 |

> **macOS limitation**: k3d on Docker Desktop uses a Linux 5.15 VM. Network Explorer
> will deploy but eBPF probes operate inside the VM. Works for demos but RTT numbers
> reflect the VM's loopback, not real host network. For realistic data, run on Linux.

## Setup (one-time)

```bash
export ACCESS_TOKEN=<splunk-ingest-token>
export REALM=us1
export INSTANCE=vinod-ebpf-demo      # unique cluster name

# 1. Create k3d cluster
./setup/01-cluster.sh

# 2. Install Splunk OTel Collector with eBPF Network Explorer
./setup/02-collector.sh

# 3. Build and load app image
./setup/03-build.sh

# 4. Deploy travel planner app
./setup/04-deploy.sh

# 5. Install Chaos Mesh (failure injection tool)
./setup/05-chaos.sh

# 6. Start load generator
./setup/06-load.sh
```

## Failure Scenarios

Each scenario has `inject.sh` and `clear.sh`. Run them in sequence during the demo.

| # | Scenario | Target | Method | Key eBPF Signal |
|---|----------|--------|--------|-----------------|
| 1 | Network Latency | hotel-agent | Chaos Mesh tc netem | `tcp.rtt.average` spike |
| 2 | Packet Loss / Retransmits | flight-agent | Chaos Mesh tc netem | `tcp.retrans` spike |
| 3 | Connection Drop | currency-agent | Kubernetes NetworkPolicy | `tcp.new_sockets` drops to zero |
| 4 | Bandwidth Throttle | synthesizer | Chaos Mesh bandwidth | `tcp.bytes` throughput collapse |

```bash
# Example: inject latency then clear it
./scenarios/01-network-latency/inject.sh
# ... demo in Splunk ...
./scenarios/01-network-latency/clear.sh
```

## Demo Script

### Opening (60 sec)
> "TripWise Corp runs a travel booking platform. Their SRE team just got paged: users are
> reporting slow hotel search results and intermittent flight booking failures. Let's show
> how Splunk Observability Cloud helps the team go from alert to root cause in minutes —
> and how eBPF gives them network-layer visibility they never had before."

### Act 1: Healthy Baseline
1. Open Splunk APM → Service Map (filter env: `ebpf-travel-demo`)
2. Show all 6 services, all green, normal latency
3. Navigate to IM → Infrastructure → Network Explorer
4. Show the network flow map — connections between services, healthy RTT, zero retransmits

### Act 2: Scenario 1 — Network Latency (Hotel Agent)

```bash
./scenarios/01-network-latency/inject.sh
```

**Wait 60 seconds**, then:
1. APM → Service Map: `hotel-agent` lights up amber/red — latency spike
2. Click `hotel-agent` → show P99 latency jumped to ~2s+
3. Click the `orchestrator → hotel-agent` edge → show span timeline
4. **Pivot**: IM → Network Explorer → filter `dst.service = hotel-agent`
5. Show: `tcp.rtt.average` has a sharp step-up at the exact same timestamp
6. **Key message**: "APM told us *where* the slowness is. eBPF tells us *why* — it's
   network-level RTT, not slow app code or database queries."

```bash
./scenarios/01-network-latency/clear.sh   # show recovery
```

### Act 3: Scenario 2 — Packet Loss (Flight Agent)

```bash
./scenarios/02-packet-loss/inject.sh
```

**Wait 60 seconds**, then:
1. APM → flight-agent: intermittent errors, elevated P95/P99
2. IM → Network Explorer → filter `dst.service = flight-agent`
3. Show: `tcp.retrans` (TCP retransmit count) spiking — classic packet-loss signature
4. **Key message**: "Intermittent errors in the app — the classic 'works sometimes' problem.
   eBPF shows TCP retransmits pointing to packet loss in the overlay network, not a code bug."

```bash
./scenarios/02-packet-loss/clear.sh
```

### Act 4: Scenario 3 — Connection Drop (Currency Agent)

```bash
./scenarios/03-connection-drop/inject.sh
```

**Wait 30 seconds**, then:
1. APM → orchestrator: currency-agent calls failing with connection errors, timing out
2. IM → Network Explorer → show zero active connections to `currency-agent`
3. eBPF shows TCP SYN packets with no response (connection_failed metric)
4. **Key message**: "No network path at all — firewall rule change or network policy
   misconfiguration. eBPF sees it immediately without touching a single firewall log."

```bash
./scenarios/03-connection-drop/clear.sh
```

### Closing (30 sec)
> "In all three scenarios the application symptoms looked identical in traditional APM:
> slow or failed calls. eBPF gave us the network-layer evidence — RTT, retransmits,
> dropped connections — without touching any application code, without installing agents
> on the app teams' side, and without waiting for a network team handoff.
> That's the power of Splunk Network Explorer."

## Key eBPF Metrics to Show in Splunk

Network Explorer emits these metric names (confirmed from Splunk docs):

| Metric | Navigator | What It Shows |
|--------|-----------|---------------|
| `tcp.rtt.average` | Network Explorer | Per-connection TCP RTT (µs) — reveals network latency between pods |
| `tcp.retrans` | Network Explorer | TCP retransmit count — packet loss signal |
| `tcp.bytes` | Network Explorer | Throughput per flow (bytes sent/received) |
| `tcp.active` | Network Explorer | Active TCP connections |
| `tcp.new_sockets` | Network Explorer | New TCP connections opened — drops to 0 when blocked |
| `tcp.resets` | Network Explorer | TCP RST count — abrupt connection drops |
| `http.client.duration.average` | Network Explorer | HTTP request duration (ms) at kernel level |
| `http.status_code` | Network Explorer | HTTP response code distribution |
| `dns.client.duration.average` | Network Explorer | DNS query latency |

> **OBI vs Network Explorer**: This demo uses **Network Explorer** (GA) which produces IM
> metrics from eBPF. Splunk also offers **OBI (OpenTelemetry-based Instrumentation)** (Beta)
> which generates APM *traces* from eBPF — no code changes required. OBI and Network Explorer
> serve different use cases; both can run simultaneously. OBI requires Linux kernel 5.8+.

## SignalFlow for Custom Dashboard

```
# TCP RTT by destination service (travel-planner namespace)
data('tcp.rtt.average',
     filter=filter('dst.namespace', 'travel-planner'),
     rollup='average').mean(by=['dst.service']).publish()

# TCP retransmits by destination service
data('tcp.retrans',
     filter=filter('dst.namespace', 'travel-planner'),
     rollup='sum').sum(by=['dst.service']).publish()

# Throughput per service (bytes received)
data('tcp.bytes',
     filter=filter('dst.namespace', 'travel-planner'),
     rollup='sum').sum(by=['dst.service']).publish()

# HTTP request duration at kernel level
data('http.client.duration.average',
     filter=filter('dst.namespace', 'travel-planner'),
     rollup='average').mean(by=['dst.service']).publish()
```

## Resetting the Demo Environment

```bash
# Remove all scenarios at once
kubectl delete networkchaos --all -n travel-planner 2>/dev/null || true
kubectl delete networkpolicy --all -n travel-planner 2>/dev/null || true

# Full reset (delete + redeploy app)
kubectl delete namespace travel-planner
./setup/04-deploy.sh
```

## Troubleshooting

**eBPF pods not starting:**
```bash
# Chart 2 pods (kernel-collector DaemonSet + reducer Deployment)
kubectl get pods -n splunk-monitoring | grep otel-ebpf
kubectl describe pod -n splunk-monitoring <otel-ebpf-kernel-collector-xxx>
```
Common cause: Kernel lacks BPF support. Check: `ls /sys/kernel/debug/tracing`

On macOS (Docker Desktop): kernel-collector DaemonSet stays `Pending` — this is expected.
eBPF programs require the host Linux kernel, not the macOS hypervisor. APM traces still work.

**Gateway service not found during 02-collector.sh:**
```bash
kubectl get svc -n splunk-monitoring
# Look for a service with 'gateway' in the name
# Re-run with explicit override:
GATEWAY_SVC=<name> ./setup/02-collector.sh   # (not supported — edit GATEWAY_SVC manually)
```

**Chaos Mesh webhook not injecting:**
```bash
kubectl get mutatingwebhookconfigurations | grep chaos
# If missing, reinstall:
helm upgrade chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --reuse-values
```

**No network metrics in Splunk IM:**
```bash
# Check reducer logs (Chart 2)
kubectl logs -n splunk-monitoring -l app.kubernetes.io/component=reducer
# Check gateway is receiving OTLP from reducer
kubectl logs -n splunk-monitoring -l app.kubernetes.io/component=otel-collector-gateway | grep -i ebpf
```
Common cause: `endpoint.address` in ebpf-values.yaml points to wrong gateway service name.
Check: `kubectl get svc -n splunk-monitoring | grep gateway`
