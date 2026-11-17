#!/bin/bash
# Install Splunk OTel Collector (gateway mode) + upstream OTel eBPF chart for Network Explorer.
#
# Two-chart architecture (required since splunk-otel-collector-chart v0.88):
#   Chart 1: splunk-otel-collector — DaemonSet agent + Gateway + clusterReceiver
#   Chart 2: open-telemetry/opentelemetry-ebpf — kernel-collector DaemonSet + reducer
#            Points endpoint.address to the Chart 1 gateway service.
#
# Required env vars:
#   ACCESS_TOKEN  - Splunk Observability ingest token
#   REALM         - e.g. us1
#   INSTANCE      - unique name, e.g. vinod-ebpf-demo
set -euo pipefail

: "${ACCESS_TOKEN:?Set ACCESS_TOKEN}"
: "${REALM:?Set REALM}"
: "${INSTANCE:?Set INSTANCE}"

OTEL_CHART_VERSION="${OTEL_CHART_VERSION:-0.136.0}"
EBPF_CHART_VERSION="${EBPF_CHART_VERSION:-0.9.0}"
NAMESPACE="splunk-monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Adding Helm repos..."
helm repo add splunk-otel-collector-chart https://signalfx.github.io/splunk-otel-collector-chart
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update splunk-otel-collector-chart open-telemetry

# ----------------------------------------------------------------
# Chart 1: Splunk OTel Collector with Gateway mode
# The gateway receives network flow OTLP data from the eBPF chart
# and forwards it to Splunk IM via the SignalFx exporter.
# ----------------------------------------------------------------
echo "==> Installing Splunk OTel Collector v${OTEL_CHART_VERSION} (gateway mode)..."
helm upgrade --install splunk-otel-collector \
  splunk-otel-collector-chart/splunk-otel-collector \
  --version "${OTEL_CHART_VERSION}" \
  --create-namespace \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/../collector/values.yaml" \
  --set="splunkObservability.accessToken=${ACCESS_TOKEN}" \
  --set="splunkObservability.realm=${REALM}" \
  --set="clusterName=${INSTANCE}-cluster" \
  --set="environment=${INSTANCE}-demo"

echo "==> Waiting for collector agent DaemonSet..."
kubectl rollout status daemonset/splunk-otel-collector-agent \
  -n "${NAMESPACE}" --timeout=180s

echo "==> Waiting for collector gateway Deployment..."
kubectl rollout status deployment/splunk-otel-collector-gateway \
  -n "${NAMESPACE}" --timeout=180s

# ----------------------------------------------------------------
# Chart 2: upstream OTel eBPF — kernel-collector + reducer
# Discover the gateway ClusterIP service name and point eBPF at it.
# ----------------------------------------------------------------
GATEWAY_SVC=$(kubectl get svc -n "${NAMESPACE}" \
  --selector='app.kubernetes.io/component=otel-collector-gateway' \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "${GATEWAY_SVC}" ]]; then
  # Fallback: grep for 'gateway' in service list
  GATEWAY_SVC=$(kubectl get svc -n "${NAMESPACE}" \
    -o custom-columns='NAME:.metadata.name' --no-headers \
    | grep gateway | head -1)
fi

if [[ -z "${GATEWAY_SVC}" ]]; then
  echo "ERROR: Could not find gateway service in ${NAMESPACE}."
  echo "Check: kubectl get svc -n ${NAMESPACE}"
  exit 1
fi

GATEWAY_ADDR="${GATEWAY_SVC}.${NAMESPACE}.svc.cluster.local"
echo "==> Gateway service: ${GATEWAY_ADDR}"

echo "==> Installing OTel eBPF chart v${EBPF_CHART_VERSION} (kernel-collector + reducer)..."
helm upgrade --install otel-ebpf \
  open-telemetry/opentelemetry-ebpf \
  --version "${EBPF_CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/../collector/ebpf-values.yaml" \
  --set="endpoint.address=${GATEWAY_ADDR}"

echo "==> Waiting for eBPF reducer Deployment..."
kubectl rollout status deployment/otel-ebpf-reducer \
  -n "${NAMESPACE}" --timeout=180s || {
  echo ""
  echo "WARN: eBPF reducer rollout timed out."
  echo "Check: kubectl get pods -n ${NAMESPACE} | grep otel-ebpf"
  echo "On macOS/Docker Desktop the kernel-collector DaemonSet may stay Pending"
  echo "(eBPF requires Linux kernel). APM data still works; network metrics limited."
}

echo ""
echo "==> All pods in ${NAMESPACE}:"
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Network Explorer is active. First tcp.* / http.* / dns.* metrics appear in"
echo "Splunk IM → Infrastructure → Network Explorer within ~2 minutes."
