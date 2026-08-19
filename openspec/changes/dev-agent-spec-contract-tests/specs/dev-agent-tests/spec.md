## Purpose

Documents the test pyramid for the openDesk Dev Agent. The tests live in the `predictive-agent` repository (`~/git/predictive-agent/tests/`) and are NOT recreated in `opendesk-nix`. This spec maps each test file to the requirements it verifies.

## ADDED Requirements

### Requirement: Unit tests verify individual Python modules

The `predictive-agent` repo SHALL include unit tests for each Python module. All tests run without external dependencies (no kubectl, no Ollama server, no network access). External calls are mocked or stubbed.

**Existing tests** (105 test functions, all passing):

#### `tests/test_collector.py` (9 tests)

- **WHEN** unit tests for `collector` are run
- **THEN** tests SHALL verify: `parse_cpu` (millicores and cores), `parse_memory` (MiB, GiB, KiB, TiB, bytes), `collect_top_metrics` (kubectl output parsing), `collect_top_nodes` (node metrics parsing), `count_log_errors` (error pattern matching)

#### `tests/test_kalman.py` (8 tests)

- **WHEN** unit tests for `kalman` are run
- **THEN** tests SHALL verify: initial state estimation, trend velocity calculation, prediction at future steps, time-to-threshold estimation, uncertainty propagation, convergence with repeated measurements

#### `tests/test_markov.py` (9 tests)

- **WHEN** unit tests for `markov` are run
- **THEN** tests SHALL verify: state transition recording, transition matrix normalization, multi-step prediction, most-likely-next-state, serialization (to_dict/from_dict round-trip), default prior counts

#### `tests/test_risk.py` (6 tests)

- **WHEN** unit tests for `risk` are run
- **THEN** tests SHALL verify: Bayesian risk calculation with various inputs, risk score bounds (0.0 to 0.99), influence of memory percentage, memory trend, CPU, restart rate, log errors, node pressure, and Markov state on risk score

#### `tests/test_predictor.py` (6 tests)

- **WHEN** unit tests for `predictor` are run
- **THEN** tests SHALL verify: prediction result fields (pod_key, risk_score, ttf_minutes, confidence, markov_state, memory_trend, cpu_trend), time-to-failure calculation, confidence calculation, at-risk prediction filtering

#### `tests/test_state_model.py` (12 tests)

- **WHEN** unit tests for `state_model` are run
- **THEN** tests SHALL verify: pod tracking, Kalman filter updates, state classification (HEALTHY/DEGRADED/STRESSED/CRITICAL), time-to-failure estimation, serialization (to_dict/from_dict round-trip), Markov chain integration, persistence

#### `tests/test_persistence.py` (5 tests)

- **WHEN** unit tests for `persistence` are run
- **THEN** tests SHALL verify: Markov chain save/load round-trip, predictions save/load round-trip, atomic writes (no corrupted files on crash), missing file fallback (fresh chain/empty list), corrupted file fallback

#### `tests/test_llm.py` (15 tests)

- **WHEN** unit tests for `llm` are run
- **THEN** tests SHALL verify: prompt building with and without prediction data, Ollama backend analysis, OpenAI-compatible backend analysis, response parsing (valid JSON, invalid JSON fallback), error handling (timeout, connection refused), multi-backend support (OLLAMA, SAIA, TUD, OPENAI)

#### `tests/test_server.py` (11 tests)

- **WHEN** unit tests for `server` are run
- **THEN** tests SHALL verify: all endpoints (`/healthz`, `/ready`, `/metrics`, `/status`, `/predictions`, `/state`, `/history`, `/cache`, `/reanalyze`), 404 for unknown paths, Prometheus metrics format, JSON response schemas, server start/stop, shared server context

#### `tests/test_main.py` (6 tests)

- **WHEN** unit tests for `main` are run
- **THEN** tests SHALL verify: reconcile loop start/stop, reconcile function output structure, thread lifecycle

### Requirement: Property-based tests verify invariants

The `predictive-agent` repo SHALL include property-based tests using Hypothesis that generate random inputs to discover edge cases.

#### `tests/test_property.py` (14 tests)

- **WHEN** property-based tests are run
- **THEN** tests SHALL verify invariants: risk score always bounded (0.0–0.99), risk monotonically increases with Markov severity, Markov transition matrix rows sum to 1, Markov predict returns valid distribution, Markov total transitions match, parse_cpu handles millicores, parse_memory handles MiB, classify_state always returns valid state, classify_state with low metrics returns HEALTHY, predictor confidence is bounded (0.0–1.0)

### Requirement: Integration tests verify HTTP endpoints with real server

The `predictive-agent` repo SHALL include integration tests that start a real HTTP server and verify endpoint responses.

#### `tests/test_endpoints.py` (4 tests)

- **WHEN** integration tests are run
- **THEN** tests SHALL verify: server starts and responds on configured port, `/healthz` returns 200 with `{"status": "ok"}`, `/ready` returns 200 with `{"status": "ready"}`, `/metrics` returns 200 with Prometheus-format text

### Requirement: Unit tests run without external dependencies

Unit tests SHALL NOT require kubectl, a Kubernetes cluster, an Ollama server, or network access. All external calls SHALL be mocked or stubbed.

#### Scenario: No kubectl required

- **WHEN** unit tests are run in an environment without kubectl
- **THEN** all tests SHALL pass by mocking subprocess calls

#### Scenario: No LLM server required

- **WHEN** unit tests are run without an Ollama server
- **THEN** LLM tests SHALL use mock HTTP responses or test the prompt-building and response-parsing logic without making real HTTP calls

### Requirement: Tests are runnable via pytest

The `predictive-agent` repo SHALL include a `pyproject.toml` with pytest configuration. Tests SHALL be runnable via `pytest tests/ -v`.

#### Scenario: Run all tests

- **WHEN** `pytest tests/ -v` is executed in the `predictive-agent` repo root
- **THEN** all 105 tests SHALL pass
- **AND** execution time SHALL be under 30 seconds

#### Scenario: Run a specific test module

- **WHEN** `pytest tests/test_kalman.py -v` is executed
- **THEN** all tests in that module SHALL pass

### Requirement: Nix build produces a valid Docker image

The `predictive-agent` repo SHALL include a Nix build (`nix/predictive-agent.nix`) that produces a Docker image with the correct contents, entrypoint, and healthcheck.

#### Scenario: Nix image builds successfully

- **WHEN** `nix build .#predictive-agent-image` (or equivalent) is executed in the `predictive-agent` repo
- **THEN** the build SHALL complete without errors
- **AND** SHALL produce a Docker image artifact tagged `predictive-agent:v8-nix`

#### Scenario: Image contains required tools

- **WHEN** the built image is inspected
- **THEN** it SHALL contain: `python3`, `kubectl`, `curl`, `bash`, `coreutils`, `gnugrep`, `gnused`, `procps`, `cacert`
- **AND** the `predictive_agent` Python package SHALL be importable via `PYTHONPATH=/opt/predictive-agent`

#### Scenario: Entrypoint is executable

- **WHEN** the image is run
- **THEN** the entrypoint SHALL be executable
- **AND** SHALL set `PYTHONPATH=/opt/predictive-agent`
- **AND** SHALL create required directories (`/var/lib/opendesk`, `/var/log/opendesk`, `/var/cache/opendesk`)
- **AND** SHALL exec `python3 -m predictive_agent.main`

### Requirement: End-to-end tests verify container lifecycle and endpoint contract

End-to-end tests SHALL start the container and verify all HTTP endpoints respond according to the API contract.

#### Scenario: Container starts and becomes healthy

- **WHEN** the container is started
- **THEN** the health endpoint `/healthz` SHALL return HTTP 200
- **AND** the readiness endpoint `/ready` SHALL return HTTP 200

#### Scenario: All API endpoints respond

- **WHEN** the container is healthy
- **THEN** GET `/healthz` SHALL return 200 with `{"status": "ok"}`
- **AND** GET `/ready` SHALL return 200 with `{"status": "ready"}`
- **AND** GET `/metrics` SHALL return 200 with Prometheus-format text
- **AND** GET `/status` SHALL return 200 with JSON containing `version`, `operator`, `status`, `pod_count`, `predictions_count`
- **AND** GET `/predictions` SHALL return 200 with JSON containing `predictions` array and `total`
- **AND** GET `/state` SHALL return 200 with JSON containing `pods`, `states`, `markov_chain`, `total_pods_tracked`
- **AND** GET `/history` SHALL return 200 with a JSON array
- **AND** GET `/cache` SHALL return 200 with JSON containing `cache` and `total`
- **AND** GET `/reanalyze` SHALL return 200 with `{"status": "ok", "reanalyze": "triggered"}`
- **AND** GET `/unknown` SHALL return 404 with `{"error": "Not Found"}`

### Requirement: Test coverage for critical paths

The test suite SHALL achieve coverage of critical code paths: Kalman filter convergence, Markov state transitions, Bayesian risk scoring, LLM response parsing, HTTP endpoint responses, state persistence, and graceful shutdown.

#### Scenario: Critical path coverage

- **WHEN** test coverage is measured
- **THEN** the following modules SHALL have tests: `collector`, `kalman`, `markov`, `risk`, `predictor`, `state_model`, `persistence`, `llm`, `server`, `main`
- **AND** property-based tests SHALL verify invariants (risk bounds, Markov matrix, state classification)
- **AND** integration tests SHALL verify the HTTP server responds correctly
