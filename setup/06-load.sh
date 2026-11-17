#!/bin/bash
# Start the continuous load generator.
# Sends /plan requests to the orchestrator NodePort (localhost:8080).
set -euo pipefail

LOAD_GEN_DIR="$(dirname "$0")/../load-gen"

echo "==> Installing load-gen dependencies..."
cd "${LOAD_GEN_DIR}"
pip3 install -q -r requirements.txt

echo ""
echo "Starting load generator — 1 request/sec, rotating destinations..."
echo "Press Ctrl+C to stop."
echo ""

python3 load_gen.py --url http://localhost:8080/plan --rps 1
