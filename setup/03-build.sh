#!/bin/bash
# Build the travel-planner Docker image and import it into k3d.
# Source: hybrid-cloud-rca-demo/travel-planner (sibling repo)
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ebpf-travel-demo}"
APP_DIR="$(dirname "$0")/../travel-planner"

echo "==> Building travel-planner image from ${APP_DIR}..."
docker build -t travel-planner:latest "${APP_DIR}"

echo "==> Importing image into k3d cluster '${CLUSTER_NAME}'..."
k3d image import travel-planner:latest -c "${CLUSTER_NAME}"

echo "==> Image ready: travel-planner:latest"
docker images travel-planner
