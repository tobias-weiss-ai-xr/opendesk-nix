#!/bin/bash
set -euo pipefail

echo "[INFO] === openDesk Dev Agent Operator (Python) starting ==="
echo "[INFO] Version: 2.1.0-python"
echo "[INFO] Ollama URL: ${OLLAMA_URL:-http://ollama.llm.svc.cluster.local:11434}"
echo "[INFO] Watch namespaces: ${OPERATOR_WATCH_NAMESPACES:-opendesk,opendesk-edu,default,llm}"

# Create directories
mkdir -p /var/log/opendesk /var/lib/opendesk /var/cache/opendesk /run/opendesk /tmp /home/opendesk/.kube

# Execute the Python operator (python3 is in PATH from nix image Env)
exec python3 /opt/dev-agent/dev_agent.py "$@"
