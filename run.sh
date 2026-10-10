#!/usr/bin/env bash
# Validated end-to-end against agentevals-cli 0.10.0 and
# otel/opentelemetry-collector-contrib:0.137.0 on 2026-10-10.
set -euo pipefail
cd "$(dirname "$0")"

echo "=== 1. Start the collector (stands in for your real observability backend) ==="
docker compose up -d
trap 'docker compose down' EXIT

echo "=== 2. Install agentevals-cli 0.10.0 into a local venv ==="
python3 -m venv venv
./venv/bin/pip install -q --upgrade pip
./venv/bin/pip install -q agentevals-cli==0.10.0
./venv/bin/agentevals --version

sleep 3 # let the collector finish starting

echo
echo "=== 3. PASS case: the recorded trace called the expected tool ==="
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318 \
  ./venv/bin/agentevals run samples/helm.json \
    --eval-set samples/eval_set_helm.json \
    -m tool_trajectory_avg_score \
    --emit-otel || true

echo
echo "=== 4. FAIL case: a trace from a session that never called the tool ==="
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318 \
  ./venv/bin/agentevals run samples/k8s.json \
    --eval-set samples/eval_set_helm.json \
    -m tool_trajectory_avg_score \
    --emit-otel || true

sleep 2 # let the collector flush its log exporter

echo
echo "=== 5. The round trip: both scores landed in the collector as gen_ai.evaluation.result events ==="
docker compose logs otel-collector | grep -A 9 "EventName: gen_ai.evaluation.result"
