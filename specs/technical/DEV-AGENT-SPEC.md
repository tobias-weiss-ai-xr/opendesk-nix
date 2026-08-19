# Dev Agent — Predictive Kubernetes Health Monitor

**Version**: 4.0.0
**Implementation**: Python 3 (stdlib only)
**Packaging**: Nix `buildLayeredImage`
**Source code**: `~/git/predictive-agent/` (v4.0.0 with Kalman/Markov/Bayesian, 189+ tests)
**Legacy build**: `nix/images/dev-agent.nix` (v3.1.0, no predictive capabilities)
**Canonical build**: `~/git/predictive-agent/nix/predictive-agent.nix` (v4.0.0, image: `predictive-agent:v8-nix`)
**Alternative build**: `~/git/dev-agent/nix/dev-agent.nix` (v4.0.0, image: `dev-agent:v8-nix`)
**Source**: `nix/images/dev-agent-files/dev_agent.py` (v3.1.0), `predictive-agent` repo (v4.0.0)

> This specification is the canonical behavioral spec for the openDesk Dev Agent.
> It is maintained as an OpenSpec capability at `openspec/specs/dev-agent/spec.md`.
> The API contract is at `specs/technical/DEV-AGENT-CONTRACT.md`.
> The test pyramid is defined at `openspec/specs/dev-agent-tests/spec.md`.

---

## 1. Overview

The Dev Agent is a Python stdlib-only predictive Kubernetes health monitor that:

1. **Watches pods** via `kubectl get pods` across configurable namespaces
2. **Detects unhealthy pods** by container status (CrashLoopBackOff, Error, OOMKilled, etc.)
3. **Analyzes** unhealthy pods using an Ollama LLM for root-cause assessment
4. **Predicts** pod failures using Kalman filter trends, Markov state transitions, and Bayesian risk scoring (v4.0.0)
5. **Exposes** HTTP endpoints for health, metrics, predictions, state, and history
6. **Persists** Markov chain state and analysis history to disk for restart resilience

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Dev Agent Process                           │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │  Reconcile    │   │  Predictive  │   │  HTTP Server │        │
│  │  Loop         │──▶│  Engine      │──▶│  (8080/8081) │        │
│  │  (60s default)│   │              │   │              │        │
│  └──────┬───────┘   └──────┬───────┘   └──────────────┘        │
│         │                  │                                    │
│         ▼                  ▼                                    │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │  Collector    │   │  LLM         │   │  State       │        │
│  │  (kubectl)    │   │  Analyzer    │   │  Persistence │        │
│  └──────────────┘   │  (Ollama)    │   │  (JSON files)│        │
│                     └──────────────┘   └──────────────┘        │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │  Kalman      │   │  Markov      │   │  Bayesian    │        │
│  │  Filter      │   │  Chain       │   │  Risk Score  │        │
│  │  (2D)        │   │  (6 states)  │   │  (0.0–0.99)  │        │
│  └──────────────┘   └──────────────┘   └──────────────┘        │
│                                                                 │
│  Ports: 8080 (metrics/API), 8081 (health)                      │
│  Config: Environment variables (see API contract)              │
│  Persistence: /var/lib/opendesk/ (state, history, cache)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Reconcile Loop

The reconcile loop is the core monitoring cycle:

| Parameter | Default | Env Var |
|-----------|---------|---------|
| Interval | 60s | `RECONCILE_INTERVAL` |
| Max pods per cycle | 3 | `MAX_PODS_PER_CYCLE` |
| Analysis TTL | 300s (adaptive: 300→600→1200) | `ANALYSIS_TTL` / `ANALYSIS_TTL_MAX` |
| Log verbosity | info | `LOG_VERBOSITY` |
| Watch namespaces | opendesk,opendesk-edu,default,llm | `OPERATOR_WATCH_NAMESPACES` |

**Cycle steps**:
1. Fetch all pods via `kubectl get pods --all-namespaces -o json`
2. Classify each pod as healthy or unhealthy
3. Skip self-namespace (`opendesk-dev-agent`) to prevent self-analysis loops
4. For unhealthy pods (up to `MAX_PODS_PER_CYCLE`):
   - Check analysis cache (skip if within TTL and status unchanged)
   - Fetch pod events and logs (skip for `ImagePullBackOff`/`ContainerCreating` — empty anyway)
   - Send context to Ollama LLM (`/api/chat`, `stream: false`, `temperature: 0`)
   - Parse JSON response (`analysis`, `severity`, `action`, `command`)
   - Store result in history and cache
5. Update Markov chain state transitions
6. Update Kalman filter trends (memory, CPU)
7. Compute Bayesian risk scores
8. Persist state to disk
9. Log summary (every 10th cycle when all healthy, every cycle when unhealthy)

---

## 4. Pod Health Detection

A pod is classified as unhealthy when its status or container state matches:

| Status | Condition |
|--------|-----------|
| `CrashLoopBackOff` | Container restarting repeatedly |
| `Error` | Pod failed |
| `OOMKilled` | Container killed by OOM |
| `ImagePullBackOff` | Cannot pull image |
| `ErrImagePull` | Image pull error |
| `ContainerCreating` | Container still creating |
| `PodInitializing` | Pod initializing |
| `CreateContainerError` | Container creation failed |
| `CreateContainerConfigError` | Container config error |
| `RunContainerError` | Container runtime error |
| `InvalidImageName` | Invalid image name |
| `RegistryUnavailable` | Registry unavailable |
| `Evicted` | Pod evicted |
| `Pending` | Pod pending |
| `Failed` | Pod failed |
| `Unknown` | Pod status unknown |

---

## 5. Predictive Engine (v4.0.0)

### 5.1 Kalman Filter (2D)

State vector: `[level, velocity]`. Observation: `[level]`.

| Property | Description |
|----------|-------------|
| `level` | Current estimated value (e.g., memory in MiB) |
| `velocity` | Current trend (e.g., MiB per cycle) |
| `level_uncertainty` | Standard deviation of level estimate |
| `velocity_uncertainty` | Standard deviation of velocity estimate |
| `predict(steps)` | Predict level at future step |
| `time_to_threshold(threshold)` | Estimate steps to reach threshold |

### 5.2 Markov Chain (6 states)

States: `HEALTHY → DEGRADED → STRESSED → CRITICAL → FAILED → RECOVERED`

Prior transition counts are hand-tuned. The chain records transitions and normalizes to probabilities. Multi-step prediction uses matrix exponentiation.

### 5.3 Bayesian Risk Scoring

Combines multiple signals into a risk score (0.0 to 0.99):

| Signal | Weight (likelihood ratio multiplier) |
|--------|--------------------------------------|
| Memory > 95% | ×10 |
| Memory > 85% | ×5 |
| Memory > 70% | ×2 |
| Memory trend + TTF < 5 min | ×8 |
| Memory trend + TTF < 10 min | ×4 |
| CPU > 95% | ×3 |
| CPU > 80% | ×1.5 |
| Restart rate > 5/hr | ×10 |
| Restart rate > 3/hr | ×4 |
| Restart rate > 1/hr | ×2 |
| Log errors > 10/min | ×3 |
| Log errors > 5/min | ×2 |
| Node memory pressure | ×4 |
| Node disk pressure | ×6 |
| Markov state CRITICAL | ×20 |
| Markov state STRESSED | ×3 |
| Markov state DEGRADED | ×1.5 |
| Markov P(critical) | ×(1 + 5×P) |
| Markov P(failed) | ×(1 + 10×P) |

Posterior: `P(risk) = (prior × LR) / (prior × LR + (1 - prior))` with prior = 0.01.

### 5.4 State Classification

| Score | State |
|-------|-------|
| ≥ 10 | CRITICAL |
| ≥ 6 | STRESSED |
| ≥ 3 | DEGRADED |
| < 3 | HEALTHY |

Score components: memory %, CPU %, restart rate, log errors, node pressure, Markov state.

---

## 6. LLM Analysis

The dev agent sends unhealthy pod context to an Ollama LLM for root-cause analysis.

### 6.1 Request

```
POST {OLLAMA_URL}/api/chat
Content-Type: application/json

{
  "model": "{OLLAMA_MODEL}",
  "messages": [{"role": "user", "content": "<prompt>"}],
  "stream": false,
  "temperature": 0,
  "num_predict": 256
}
```

### 6.2 Response (expected JSON)

```json
{
  "analysis": "Brief analysis of the root cause",
  "severity": "high|medium|low",
  "action": "Recommended action",
  "command": "kubectl command to execute (if applicable)"
}
```

### 6.3 Caching

- Analysis results are cached per pod with adaptive TTL: 300s → 600s → 1200s
- Cache is skipped when pod status changes
- Cache key: `{namespace}/{pod_name}`

### 6.4 Multi-backend support (v4.0.0)

| Backend | Endpoint | Auth |
|---------|----------|------|
| Ollama | `{OLLAMA_URL}/api/chat` | None |
| SAIA | `{OLLAMA_URL}/chat/completions` | Bearer token |
| TUD | `{OLLAMA_URL}/chat/completions` | Bearer token |
| OpenAI | `{OLLAMA_URL}/chat/completions` | Bearer token |

---

## 7. HTTP API

See `specs/technical/DEV-AGENT-CONTRACT.md` for the full API contract.

### Endpoints

| Endpoint | Port | Method | Description |
|----------|------|--------|-------------|
| `/healthz` | 8081 | GET | Liveness probe |
| `/ready` | 8081 | GET | Readiness probe |
| `/metrics` | 8080 | GET | Prometheus metrics |
| `/status` | 8080 | GET | Operator metadata |
| `/predictions` | 8080 | GET | Risk predictions |
| `/state` | 8080 | GET | Pod state model |
| `/reanalyze` | 8080 | GET/POST | Trigger reconcile |
| `/cache` | 8080 | GET | LLM analysis cache |
| `/history` | 8080 | GET | Analysis history |

### Prometheus Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `opendesk_predictive_agent_pods_tracked` | gauge | Number of pods tracked |
| `opendesk_predictive_agent_predictions_count` | gauge | Number of active predictions |
| `opendesk_predictive_agent_risk_score` | gauge | Highest current risk score (0–1) |
| `opendesk_predictive_agent_uptime_seconds` | gauge | Uptime in seconds |

---

## 8. State Persistence

| File | Default Path | Content |
|------|-------------|---------|
| State model | `/var/lib/opendesk/state-model.json` | Markov chain state |
| Predictions | `/var/lib/opendesk/predictions.json` | Prediction history |
| Analysis history | `/var/lib/opendesk/analysis-history.json` | LLM analysis results (max `HISTORY_MAX` entries) |

**Atomic writes**: State is written to a `.tmp` file then `os.replace()`'d to prevent corruption on crash/pod eviction.

**Fallback**: Missing or corrupted files fall back to fresh defaults (empty Markov chain, empty predictions, empty history).

---

## 9. Configuration

All configuration is via environment variables. See `specs/technical/DEV-AGENT-CONTRACT.md` for the full table.

### Core

| Variable | Default | Description |
|----------|---------|-------------|
| `OPERATOR_NAME` | `opendesk-dev-agent` | Operator name |
| `OPERATOR_NAMESPACE` | `opendesk-dev-agent` | Operator namespace |
| `OPERATOR_VERSION` | `4.0.0` | Version string |
| `OPERATOR_WATCH_NAMESPACES` | `opendesk,opendesk-edu,default,llm` | Comma-separated namespaces |
| `RECONCILE_INTERVAL` | `60` | Reconcile loop interval (seconds) |
| `MAX_PODS_PER_CYCLE` | `3` | Max unhealthy pods to analyze per cycle |
| `LOG_VERBOSITY` | `info` | Log level (info or debug) |

### LLM

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_BACKEND` | `ollama` | LLM backend (ollama, saia, tud, openai) |
| `OLLAMA_URL` | `http://ollama.llm.svc.cluster.local:11434` | LLM API URL |
| `OLLAMA_MODEL` | `qwen3-30b-a3b:latest` | LLM model name |
| `OLLAMA_TIMEOUT` | `180` | LLM request timeout (seconds) |

### Analysis Cache

| Variable | Default | Description |
|----------|---------|-------------|
| `ANALYSIS_TTL` | `300` | Initial cache TTL (seconds) |
| `ANALYSIS_TTL_MAX` | `1200` | Maximum cache TTL (seconds) |
| `HISTORY_FILE` | `/var/lib/opendesk/analysis-history.json` | History file path |
| `HISTORY_MAX` | `100` | Max history entries |

### Server

| Variable | Default | Description |
|----------|---------|-------------|
| `OPERATOR_METRICS_BIND_ADDRESS` | `0.0.0.0:8080` | Metrics/API server bind address |
| `OPERATOR_HEALTH_PROBE_BIND_ADDRESS` | `0.0.0.0:8081` | Health probe server bind address |

---

## 10. Packaging

### Nix Docker Image

**Build**: `nix build .#dev-agent-image` (from `nix/images/dev-agent.nix`)

**Contents**: Python 3, kubectl, curl, bash, coreutils, gnugrep, gnused, procps, cacert, dev_agent package

**Entrypoint**: `/opt/dev-agent/entrypoint.sh` → `python3 -m dev_agent` (v3.1.0) or `python3 -m predictive_agent` (v4.0.0)

**Healthcheck**: `/opt/dev-agent/healthcheck.sh` probes `/healthz` and `/ready` on the health port

**Ports**: 8080 (metrics/API), 8081 (health)

**User**: `0:0` (root — required for kubectl access in K8s)

### v3.1.0 vs v4.0.0

| Feature | v3.1.0 (`nix/images/`) | v4.0.0 (`predictive-agent` repo) |
|---------|------------------------|-----------------------------------|
| Reconcile loop | ✓ | ✓ |
| Pod health detection | ✓ | ✓ |
| LLM analysis (Ollama) | ✓ | ✓ (multi-backend) |
| Analysis caching | ✓ (adaptive TTL) | ✓ (adaptive TTL) |
| Model warmup | ✓ | ✓ |
| Graceful shutdown | ✓ | ✓ |
| HTTP endpoints | /healthz, /ready, /metrics, /status, /history, /cache | + /predictions, /state, /reanalyze |
| Kalman filter | ✗ | ✓ (2D) |
| Markov chain | ✗ | ✓ (6 states) |
| Bayesian risk | ✗ | ✓ (0.0–0.99) |
| State persistence | Analysis history only | + Markov chain + predictions |
| Multi-backend LLM | Ollama only | Ollama, SAIA, TUD, OpenAI |

---

## 11. Graceful Shutdown

On SIGTERM or SIGINT:
1. Stop the reconcile loop
2. Save Markov chain state to state model file
3. Save prediction history to predictions file
4. Shut down HTTP servers (metrics + health)
5. Exit with code 0

---

## 12. Test Pyramid

See `openspec/specs/dev-agent-tests/spec.md` for the full test specification.

| Layer | What | How | Speed |
|-------|------|-----|-------|
| Unit | Python modules (collector, kalman, markov, risk, predictor, state_model, persistence, llm, server, main) | `pytest tests/dev-agent/unit/` | < 30s |
| Integration | Nix build, image contents, entrypoint, healthcheck | `nix flake check` | Medium |
| E2E | Container lifecycle, endpoint contract, metrics format, reanalyze | `pytest tests/dev-agent/e2e/` (requires Docker) | Slow |
