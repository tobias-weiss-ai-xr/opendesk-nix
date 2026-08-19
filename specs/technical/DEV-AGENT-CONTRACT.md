# Dev Agent — API Contract

**Version**: 4.0.0
**Implementation**: Python 3 (stdlib only)

> This contract is the agreement between the dev agent and its consumers
> (monitoring systems, orchestration platforms, operators).
> The behavioral spec is at `specs/technical/DEV-AGENT-SPEC.md`.
> The test pyramid is at `openspec/specs/dev-agent-tests/spec.md`.

---

## 1. HTTP Endpoints

### 1.1 Health Endpoints (port 8081)

#### `GET /healthz`

Liveness probe. Returns HTTP 200 if the process is alive.

**Response**:
```json
{"status": "ok"}
```

**Content-Type**: `application/json`

#### `GET /ready`

Readiness probe. Returns HTTP 200 if the process is ready to serve traffic.

**Response**:
```json
{"status": "ready"}
```

**Content-Type**: `application/json`

---

### 1.2 Metrics & API Endpoints (port 8080)

#### `GET /metrics`

Prometheus-format metrics.

**Response**:
- **Content-Type**: `text/plain; version=0.0.4; charset=utf-8`
- **Body**: Prometheus gauges

**Metrics**:

| Metric | Type | Description |
|--------|------|-------------|
| `opendesk_predictive_agent_pods_tracked` | gauge | Number of pods currently tracked |
| `opendesk_predictive_agent_predictions_count` | gauge | Number of active predictions |
| `opendesk_predictive_agent_risk_score` | gauge | Highest current risk score (0–1) |
| `opendesk_predictive_agent_uptime_seconds` | gauge | Uptime in seconds |
| `opendesk_dev_agent_pods_tracked` | gauge | Alias for `opendesk_predictive_agent_pods_tracked` |
| `opendesk_dev_agent_predictions_count` | gauge | Alias for `opendesk_predictive_agent_predictions_count` |
| `opendesk_dev_agent_risk_score` | gauge | Alias for `opendesk_predictive_agent_risk_score` |

**Example**:
```
# HELP opendesk_predictive_agent_pods_tracked Number of pods currently tracked
# TYPE opendesk_predictive_agent_pods_tracked gauge
opendesk_predictive_agent_pods_tracked 5
# HELP opendesk_predictive_agent_predictions_count Number of active predictions
# TYPE opendesk_predictive_agent_predictions_count gauge
opendesk_predictive_agent_predictions_count 2
# HELP opendesk_predictive_agent_risk_score Highest current risk score (0-1)
# TYPE opendesk_predictive_agent_risk_score gauge
opendesk_predictive_agent_risk_score 0.75
# HELP opendesk_predictive_agent_uptime_seconds Uptime in seconds
# TYPE opendesk_predictive_agent_uptime_seconds gauge
opendesk_predictive_agent_uptime_seconds 3600
```

---

#### `GET /status`

Operator metadata.

**Response**:
```json
{
  "version": "4.0.0",
  "operator": "opendesk-dev-agent",
  "status": "running",
  "pod_count": 5,
  "predictions_count": 2
}
```

---

#### `GET /predictions`

Risk predictions for all tracked pods.

**Response**:
```json
{
  "predictions": [
    {
      "pod_key": "opendesk/nextcloud-abc123",
      "risk_score": 0.75,
      "ttf_minutes": 15,
      "ttf": 15,
      "confidence": 0.85,
      "markov_state": "STRESSED",
      "memory_trend": 2.5,
      "cpu_trend": 0.0,
      "memory_pct": 82.5,
      "cpu_pct": 45.0
    }
  ],
  "total": 1
}
```

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `pod_key` | string | `namespace/pod-name` |
| `risk_score` | float | Bayesian risk score (0.0–0.99) |
| `ttf_minutes` | int\|null | Time-to-failure in minutes (null if not approaching threshold) |
| `ttf` | int\|null | Alias for `ttf_minutes` |
| `confidence` | float | Prediction confidence (0.0–1.0) |
| `markov_state` | string | Current Markov state (HEALTHY/DEGRADED/STRESSED/CRITICAL/FAILED/RECOVERED) |
| `memory_trend` | float | Memory trend (MiB/min) |
| `cpu_trend` | float | CPU trend (millicores/min) |
| `memory_pct` | float | Memory usage percentage |
| `cpu_pct` | float | CPU usage percentage |

---

#### `GET /state`

Pod state model with Kalman filter state and Markov chain.

**Response**:
```json
{
  "pods": {
    "opendesk/nextcloud-abc123": {
      "namespace": "opendesk",
      "name": "nextcloud-abc123",
      "state": "STRESSED",
      "kalman_memory": { ... },
      "kalman_cpu": { ... },
      "memory_pct": 82.5,
      "cpu_pct": 45.0,
      "memory_mib": 825,
      "memory_limit_mib": 1000,
      "cpu_m": 450,
      "restart_count": 3,
      "log_errors": 5,
      "node_pressure": false
    }
  },
  "states": "stable",
  "markov_chain": {
    "counts": [[95,4,1,0,0,0], ...],
    "total_transitions": 42,
    "last_updated": 1711234567.89
  },
  "total_pods_tracked": 1
}
```

---

#### `GET /reanalyze` / `POST /reanalyze`

Trigger an immediate reconcile cycle.

**Response (success)**:
```json
{
  "status": "ok",
  "reanalyze": "triggered"
}
```

**Response (with callback result)**:
```json
{
  "status": "ok",
  "reanalyze": "triggered",
  "result": { ... }
}
```

**Response (callback error)**:
- **Status**: 503
```json
{
  "status": "error",
  "error": "<exception message>"
}
```

---

#### `GET /cache`

LLM analysis cache.

**Response**:
```json
{
  "cache": {
    "opendesk/nextcloud-abc123": {
      "analysis": "Pod is in CrashLoopBackOff due to...",
      "severity": "high",
      "action": "Check database connectivity",
      "command": "kubectl logs ...",
      "timestamp": 1711234567.89,
      "ttl": 300
    }
  },
  "total": 1
}
```

---

#### `GET /history`

Analysis history (most recent first, max `HISTORY_MAX` entries).

**Response**:
```json
[
  {
    "pod_key": "opendesk/nextcloud-abc123",
    "analysis": "Pod is in CrashLoopBackOff due to...",
    "severity": "high",
    "action": "Check database connectivity",
    "command": "kubectl logs ...",
    "timestamp": 1711234567.89
  }
]
```

---

### 1.3 Error Responses

#### Unknown path

**Response**:
- **Status**: 404
```json
{"error": "Not Found"}
```

---

## 2. Environment Variables

### 2.1 Core Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPERATOR_NAME` | `opendesk-dev-agent` | Operator name (used in metrics, logs) |
| `OPERATOR_NAMESPACE` | `opendesk-dev-agent` | Operator namespace (skipped in analysis) |
| `OPERATOR_VERSION` | `4.0.0` | Version string (reported in `/status`) |
| `OPERATOR_WATCH_NAMESPACES` | `opendesk,opendesk-edu,default,llm` | Comma-separated namespaces to watch |
| `RECONCILE_INTERVAL` | `60` | Reconcile loop interval (seconds) |
| `MAX_PODS_PER_CYCLE` | `3` | Max unhealthy pods to analyze per cycle |
| `LOG_VERBOSITY` | `info` | Log level (`info` or `debug`) |

### 2.2 LLM Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_BACKEND` | `ollama` | LLM backend (`ollama`, `saia`, `tud`, `openai`) |
| `OLLAMA_URL` | `http://ollama.llm.svc.cluster.local:11434` | LLM API URL |
| `OLLAMA_MODEL` | `qwen3-30b-a3b:latest` | LLM model name |
| `OLLAMA_TIMEOUT` | `180` | LLM request timeout (seconds) |

### 2.3 Analysis Cache

| Variable | Default | Description |
|----------|---------|-------------|
| `ANALYSIS_TTL` | `300` | Initial analysis cache TTL (seconds) |
| `ANALYSIS_TTL_MAX` | `1200` | Maximum analysis cache TTL (seconds) |
| `HISTORY_FILE` | `/var/lib/opendesk/analysis-history.json` | Analysis history file path |
| `HISTORY_MAX` | `100` | Maximum history entries |

### 2.4 Server Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPERATOR_METRICS_BIND_ADDRESS` | `0.0.0.0:8080` | Metrics/API server bind address |
| `OPERATOR_HEALTH_PROBE_BIND_ADDRESS` | `0.0.0.0:8081` | Health probe server bind address |

### 2.5 Persistence (v4.0.0)

| Variable | Default | Description |
|----------|---------|-------------|
| `PREDICTIONS_FILE` | `/var/lib/opendesk/predictions.json` | Predictions file path |
| `STATE_MODEL_FILE` | `/var/lib/opendesk/state-model.json` | State model file path |

---

## 3. Health Probes

### 3.1 Kubernetes Probes

| Probe | Path | Port | Initial Delay | Period | Timeout | Failure Threshold |
|-------|------|------|----------------|--------|---------|-------------------|
| Liveness | `/healthz` | 8081 | 45s | 30s | 10s | 3 |
| Readiness | `/ready` | 8081 | 15s | 10s | 5s | 3 |

### 3.2 Container Healthcheck

The container includes a healthcheck script (`/opt/dev-agent/healthcheck.sh`) that probes both `/healthz` and `/ready`:

```bash
HEALTH_ADDR="${OPERATOR_HEALTH_PROBE_BIND_ADDRESS:-0.0.0.0:8081}"
HEALTH_PORT="${HEALTH_ADDR##*:}"

# Liveness: GET /healthz → expect HTTP 200
# Readiness: GET /ready → expect HTTP 200
# Exit 0 if both pass, exit 1 if either fails
```

---

## 4. Ports

| Port | Protocol | Description | Internal/External |
|------|----------|-------------|-------------------|
| 8080 | TCP | Metrics/API server | Internal |
| 8081 | TCP | Health probe server | Internal |

---

## 5. Resource Requirements

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 100m | 500m |
| Memory | 128Mi | 512Mi |
| Ephemeral Storage | 100Mi | 500Mi |
