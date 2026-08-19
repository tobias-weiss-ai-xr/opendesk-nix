## Why

The current `DEV-AGENT-SPEC.md` describes a Go-based Kubernetes operator (v1.x/v2.x) with CRDs (`HealthPolicy`, `RepairStrategy`), PI Memory integration, and a multi-stage Go build — none of which match the actual implementation. The real dev-agent is a **Python stdlib-only** program (`dev_agent.py` v3.1.0 in `nix/images/`, predictive-agent v4.0.0 in the separate `predictive-agent` repo) that watches pods via `kubectl`, uses Ollama LLM for analysis, and exposes HTTP endpoints (`/healthz`, `/ready`, `/metrics`, `/status`, `/predictions`, `/state`, `/reanalyze`, `/cache`, `/history`).

There is no formal API contract in `opendesk-nix`. However, the `predictive-agent` repo (`~/git/predictive-agent`) already has a complete, passing test suite (105 test functions across 12 test files, including property-based tests with Hypothesis). The Docker/Nix packaging in `opendesk-nix` references stale Go-era artifacts (`docker/dev-agent/Dockerfile`, `dev-agent/flake.nix`). The `dev-agent` repo (`~/git/dev-agent`) has a broken Nix build that references `../dev_agent/*.py` — a directory that does not exist. This creates a gap between specification, implementation, and verification — the spec describes software that doesn't exist, the contract is implicit in code, and the `dev-agent` repo's Nix build is broken.

## What Changes

- **Replace** `specs/technical/DEV-AGENT-SPEC.md` with an accurate specification of the Python-based predictive health monitor (v3.1.0/v4.0.0), covering: reconcile loop, pod health detection, LLM analysis, predictive engine (Kalman/Markov/Bayesian), HTTP API, configuration, and Docker/Nix packaging.
- **Create** an API contract spec (`dev-agent-api`) defining all HTTP endpoints, their request/response schemas, Prometheus metrics format, configuration environment variables, and health check behavior.
- **Document** the existing test pyramid (`dev-agent-tests`) by referencing the 105 tests in `predictive-agent/tests/` — no new tests are created in `opendesk-nix`. The existing tests cover: unit tests (collector, kalman, markov, risk, predictor, state_model, persistence, llm, server, main), property-based tests (Hypothesis invariants), and integration tests (HTTP endpoints with real server).
- **Remove** stale Go-era artifacts that no longer reflect the implementation: `docker/dev-agent/Dockerfile` (Go multi-stage build), `dev-agent/flake.nix` (references non-existent `go-mod2nix` and `opendesk-dev-agent-operator/`).
- **Fix** the broken `dev-agent` repo Nix build (`~/git/dev-agent/nix/dev-agent.nix`) to reference `../predictive_agent/*.py` instead of `../dev_agent/*.py`.
- **Document** that `nix/images/dev-agent.nix` is the v3.1.0 legacy build and `predictive-agent/nix/predictive-agent.nix` is the v4.0.0 canonical build.

## Capabilities

### New Capabilities

- `dev-agent`: Behavioral specification of the Python-based predictive Kubernetes health monitor — reconcile loop, pod health detection, LLM analysis, predictive engine, configuration, and packaging.
- `dev-agent-api`: API contract for all HTTP endpoints (`/healthz`, `/ready`, `/metrics`, `/status`, `/predictions`, `/state`, `/reanalyze`, `/cache`, `/history`), Prometheus metrics format, environment variable configuration, and health probe behavior.
- `dev-agent-tests`: Test pyramid definition — unit tests (Python module level), integration tests (Nix build and image verification), and end-to-end tests (container lifecycle, endpoint contract, metrics format).

### Modified Capabilities

(None — the existing `DEV-AGENT-SPEC.md` is a standalone technical document, not an OpenSpec capability. It will be replaced, not modified.)

## Impact

- **`specs/technical/DEV-AGENT-SPEC.md`**: Replaced entirely with accurate Python-based specification.
- **`nix/images/dev-agent.nix`**: Updated env vars, version, and endpoint documentation to match spec.
- **`nix/images/dev-agent-files/`**: No code changes — `dev_agent.py`, `entrypoint.sh`, `healthcheck.sh` are the source of truth; spec is written to match them.
- **`docker/dev-agent/Dockerfile`**: Removed (Go-era artifact, references non-existent `opendesk-dev-agent-operator/` source directory).
- **`dev-agent/flake.nix`**: Removed (references non-existent `go-mod2nix` and `opendesk-dev-agent-operator/` directory, `kindsys` package doesn't exist in nixpkgs).
- **`tests/dev-agent/README.md`**: New file pointing to `~/git/predictive-agent/tests/` for the actual test suite (document, don't duplicate).
- **`~/git/dev-agent/nix/dev-agent.nix`**: Fixed to reference `../predictive_agent/*.py` instead of `../dev_agent/*.py`.
- **`~/git/dev-agent/nix/dev-agent-files/entrypoint.sh`**: Updated to run `python3 -m predictive_agent.main`.
- **No runtime behavior changes** — this change is specification, contract, and test documentation only. The running dev-agent is unaffected. Tests already exist and pass in the `predictive-agent` repo.
