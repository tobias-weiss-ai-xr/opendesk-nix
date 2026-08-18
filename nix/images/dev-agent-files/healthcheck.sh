#!/bin/bash
set -euo pipefail

HEALTH_PORT="${OPERATOR_HEALTH_PROBE_BIND_ADDRESS:-0.0.0.0:8081}"
HEALTH_PORT_NUM="${HEALTH_PORT##*:}"

case "${1:-liveness}" in
  liveness)
    if curl -sf "http://localhost:${HEALTH_PORT_NUM}/healthz" >/dev/null 2>&1; then
      echo "OK: liveness"
      exit 0
    fi
    echo "FAIL: liveness"
    exit 1
    ;;
  readiness)
    if curl -sf "http://localhost:${HEALTH_PORT_NUM}/ready" >/dev/null 2>&1; then
      echo "OK: readiness"
      exit 0
    fi
    echo "FAIL: readiness"
    exit 1
    ;;
  startup)
    if curl -sf "http://localhost:${HEALTH_PORT_NUM}/startup" >/dev/null 2>&1; then
      echo "OK: startup"
      exit 0
    fi
    echo "FAIL: startup"
    exit 1
    ;;
  *)
    echo "Usage: $0 {liveness|readiness|startup}"
    exit 1
    ;;
esac
