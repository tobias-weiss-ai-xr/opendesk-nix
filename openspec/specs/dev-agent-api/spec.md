## Purpose

Defines the HTTP API contract for the openDesk Dev Agent — all endpoints, request/response schemas, Prometheus metrics format, environment variable configuration, and health probe behavior. This contract is the agreement between the dev agent and its consumers (monitoring systems, orchestration platforms, operators).

## ADDED Requirements

### Requirement: Health endpoints respond with JSON status

The dev agent SHALL expose `/healthz` and `/ready` endpoints on the health probe port (default 8081) that return HTTP 200 with a JSON body `{"status": "ok"}` or `{"status": "ready"}` respectively.

#### Scenario: Liveness check

- **WHEN** a GET request is made to `/healthz` on the health port
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL be `{"status": "ok"}`

#### Scenario: Readiness check

- **WHEN** a GET request is made to `/ready` on the health port
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL be `{"status": "ready"}`

### Requirement: Metrics endpoint exposes Prometheus-format gauges

The dev agent SHALL expose `/metrics` on the metrics port (default 8080) returning Prometheus-format text with gauges for pods tracked, predictions count, risk score, and uptime.

#### Scenario: Metrics endpoint format

- **WHEN** a GET request is made to `/metrics` on the metrics port
- **THEN** the response SHALL be HTTP 200
- **AND** the content type SHALL be `text/plain; version=0.0.4; charset=utf-8`
- **AND** the body SHALL contain Prometheus gauges:
  - `opendesk_predictive_agent_pods_tracked` (gauge)
  - `opendesk_predictive_agent_predictions_count` (gauge)
  - `opendesk_predictive_agent_risk_score` (gauge)
  - `opendesk_predictive_agent_uptime_seconds` (gauge)

#### Scenario: Metrics reflect current state

- **WHEN** the dev agent is tracking 5 pods with 2 predictions and a max risk score of 0.75
- **THEN** `opendesk_predictive_agent_pods_tracked` SHALL be 5
- **AND** `opendesk_predictive_agent_predictions_count` SHALL be 2
- **AND** `opendesk_predictive_agent_risk_score` SHALL be 0.75

### Requirement: Status endpoint returns operator metadata

The dev agent SHALL expose `/status` on the metrics port returning JSON with version, operator name, status, pod count, and predictions count.

#### Scenario: Status response

- **WHEN** a GET request is made to `/status` on the metrics port
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL contain JSON with keys: `version`, `operator`, `status`, `pod_count`, `predictions_count`

### Requirement: Predictions endpoint returns risk assessments

The dev agent SHALL expose `/predictions` on the metrics port returning a JSON object with a `predictions` array and `total` count. Each prediction SHALL include: `pod_key`, `risk_score`, `ttf_minutes` (or `ttf` alias), `confidence`, `markov_state`, `memory_trend`, `cpu_trend`, `memory_pct`, `cpu_pct`.

#### Scenario: Predictions response with active predictions

- **WHEN** the dev agent has computed predictions for tracked pods
- **AND** a GET request is made to `/predictions`
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL contain `{"predictions": [...], "total": N}`
- **AND** each prediction SHALL have `pod_key`, `risk_score`, `ttf` (alias for `ttf_minutes`), `confidence`, `markov_state`

#### Scenario: Predictions response with no predictions

- **WHEN** no predictions have been computed
- **AND** a GET request is made to `/predictions`
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL be `{"predictions": [], "total": 0}`

### Requirement: State endpoint returns pod tracking state

The dev agent SHALL expose `/state` on the metrics port returning JSON with the current state model: all tracked pods, their Kalman filter state, Markov chain state, and total pod count.

#### Scenario: State response

- **WHEN** a GET request is made to `/state`
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL contain `pods` (dict of pod keys to pod state), `states` (summary), `markov_chain` (Markov chain data), `total_pods_tracked` (integer)

### Requirement: Reanalyze endpoint triggers a reconcile cycle

The dev agent SHALL expose `/reanalyze` on the metrics port (both GET and POST) that triggers an immediate reconcile cycle and returns the result.

#### Scenario: Reanalyze via GET

- **WHEN** a GET request is made to `/reanalyze`
- **THEN** the dev agent SHALL trigger a reconcile cycle
- **AND** the response SHALL be HTTP 200
- **AND** the body SHALL contain `{"status": "ok", "reanalyze": "triggered"}`

#### Scenario: Reanalyze via POST

- **WHEN** a POST request is made to `/reanalyze`
- **THEN** the behavior SHALL be identical to GET

#### Scenario: Reanalyze with callback result

- **WHEN** a reconcile callback is registered and succeeds
- **THEN** the response SHALL include the reconcile result in the `result` field

#### Scenario: Reanalyze with callback error

- **WHEN** a reconcile callback is registered and raises an exception
- **THEN** the response SHALL be HTTP 503
- **AND** the body SHALL contain `{"status": "error", "error": "<exception message>"}`

### Requirement: Cache endpoint returns LLM analysis cache

The dev agent SHALL expose `/cache` on the metrics port returning the LLM analysis cache as a JSON object with `cache` (dict of cached analyses) and `total` (count).

#### Scenario: Cache response

- **WHEN** a GET request is made to `/cache`
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL contain `{"cache": {...}, "total": N}`

### Requirement: History endpoint returns analysis history

The dev agent SHALL expose `/history` on the metrics port returning the analysis history as a JSON array.

#### Scenario: History response with entries

- **WHEN** LLM analyses have been performed
- **AND** a GET request is made to `/history`
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL be a JSON array of analysis entries

#### Scenario: History response with no entries

- **WHEN** no analyses have been performed
- **AND** a GET request is made to `/history`
- **THEN** the response SHALL be HTTP 200
- **AND** the body SHALL be `[]`

### Requirement: Unknown endpoints return 404

The dev agent SHALL return HTTP 404 with `{"error": "Not Found"}` for any unrecognized path.

#### Scenario: Unknown path

- **WHEN** a GET request is made to `/unknown`
- **THEN** the response SHALL be HTTP 404
- **AND** the body SHALL be `{"error": "Not Found"}`

### Requirement: Environment variable configuration contract

The dev agent SHALL accept configuration via environment variables with documented defaults.

#### Scenario: Core configuration variables

- **WHEN** the dev agent starts
- **THEN** the following environment variables SHALL be read with defaults:
  - `OPERATOR_NAME` (default: `opendesk-dev-agent`)
  - `OPERATOR_NAMESPACE` (default: `opendesk-dev-agent`)
  - `OPERATOR_VERSION` (default: `4.0.0`)
  - `OPERATOR_WATCH_NAMESPACES` (default: `opendesk,opendesk-edu,default,llm`)
  - `RECONCILE_INTERVAL` (default: `60`)
  - `ANALYSIS_TTL` (default: `300`)
  - `ANALYSIS_TTL_MAX` (default: `1200`)
  - `MAX_PODS_PER_CYCLE` (default: `3`)
  - `LOG_VERBOSITY` (default: `info`)
  - `HISTORY_FILE` (default: `/var/lib/opendesk/analysis-history.json`)
  - `HISTORY_MAX` (default: `100`)

#### Scenario: LLM configuration variables

- **WHEN** the dev agent starts
- **THEN** the following LLM environment variables SHALL be read with defaults:
  - `LLM_BACKEND` (default: `ollama`)
  - `OLLAMA_URL` (default: `http://ollama.llm.svc.cluster.local:11434`)
  - `OLLAMA_MODEL` (default: `qwen3-30b-a3b:latest`)
  - `OLLAMA_TIMEOUT` (default: `180`)

#### Scenario: Server configuration variables

- **WHEN** the dev agent starts
- **THEN** the following server environment variables SHALL be read with defaults:
  - `OPERATOR_METRICS_BIND_ADDRESS` (default: `0.0.0.0:8080`)
  - `OPERATOR_HEALTH_PROBE_BIND_ADDRESS` (default: `0.0.0.0:8081`)

### Requirement: Health probe contract for Kubernetes

The dev agent's health endpoints SHALL be usable as Kubernetes liveness and readiness probes with the documented probe configuration.

#### Scenario: Liveness probe

- **WHEN** Kubernetes sends an HTTP GET to `/healthz` on the health port
- **THEN** the response SHALL be HTTP 200 if the process is alive
- **AND** the probe SHALL use `initialDelaySeconds: 45`, `periodSeconds: 30`, `timeoutSeconds: 10`, `failureThreshold: 3`

#### Scenario: Readiness probe

- **WHEN** Kubernetes sends an HTTP GET to `/ready` on the health port
- **THEN** the response SHALL be HTTP 200 if the process is ready to serve traffic
- **AND** the probe SHALL use `initialDelaySeconds: 15`, `periodSeconds: 10`, `timeoutSeconds: 5`, `failureThreshold: 3`

### Requirement: Container healthcheck script

The container SHALL include a healthcheck script that probes both `/healthz` and `/ready` endpoints.

#### Scenario: Healthcheck passes

- **WHEN** both `/healthz` and `/ready` return HTTP 200
- **THEN** the healthcheck script SHALL exit with code 0

#### Scenario: Healthcheck fails

- **WHEN** either `/healthz` or `/ready` does not return HTTP 200
- **THEN** the healthcheck script SHALL exit with code 1
