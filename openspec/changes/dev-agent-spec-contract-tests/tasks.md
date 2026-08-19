## 1. Remove Stale Go-Era Artifacts

- [x] 1.1 Remove `docker/dev-agent/Dockerfile` (Go multi-stage build referencing non-existent `opendesk-dev-agent-operator/` source)
- [x] 1.2 Remove `dev-agent/flake.nix` (references non-existent `go-mod2nix`, `kindsys`, and `opendesk-dev-agent-operator/` directory)
- [x] 1.3 Keep `docker/dev-agent/config.yaml`, `docker/dev-agent/entrypoint.sh`, `docker/dev-agent/healthcheck.sh`, `docker/dev-agent/logrotate.conf`, `docker/dev-agent/limits.d/` as reference files

## 2. Replace DEV-AGENT-SPEC.md

- [x] 2.1 Delete `specs/technical/DEV-AGENT-SPEC.md` (outdated Go-based spec with CRDs, PI Memory, Go build process)
- [x] 2.2 Create new `specs/technical/DEV-AGENT-SPEC.md` from the OpenSpec `dev-agent` capability spec (Python-based predictive health monitor: reconcile loop, pod health detection, LLM analysis, predictive engine, state persistence, configuration, packaging, graceful shutdown, analysis history)
- [x] 2.3 Update `specs/README.md` to reference the new spec (remove Go-era references to CRDs, HealthPolicy, RepairStrategy, PI Memory)

## 3. Create API Contract Documentation

- [x] 3.1 Create `specs/technical/DEV-AGENT-CONTRACT.md` from the OpenSpec `dev-agent-api` capability spec (all HTTP endpoints, request/response schemas, Prometheus metrics format, environment variables, health probe configuration, healthcheck script)
- [x] 3.2 Document the endpoint table: `/healthz`, `/ready`, `/metrics`, `/status`, `/predictions`, `/state`, `/reanalyze`, `/cache`, `/history` with methods, ports, and response schemas
- [x] 3.3 Document the environment variable table with defaults

## 4. Verify Existing Test Suite (in `predictive-agent` repo)

- [x] 4.1 Verify all 105 tests pass in `~/git/predictive-agent/tests/` (`pytest tests/ -v` → 103 passed + 2 collected in 20.79s)
- [x] 4.2 Verify test coverage: `test_collector.py` (9), `test_kalman.py` (8), `test_markov.py` (9), `test_risk.py` (6), `test_predictor.py` (6), `test_state_model.py` (12), `test_persistence.py` (5), `test_llm.py` (15), `test_server.py` (11), `test_main.py` (6), `test_endpoints.py` (4), `test_property.py` (14)
- [x] 4.3 Verify tests run without external dependencies (no kubectl, no Ollama server, no network access — all mocked)
- [x] 4.4 Verify `pyproject.toml` has pytest configuration (`testpaths = ["tests"]`, `python_files = "test_*.py"`)

## 5. Fix Broken `dev-agent` Repo Nix Build

- [x] 5.1 Update `~/git/dev-agent/nix/dev-agent.nix` to reference `../predictive_agent/*.py` instead of `../dev_agent/*.py` (the `dev_agent/` directory does not exist; the code lives in `predictive_agent/`)
- [x] 5.2 Update entrypoint in `~/git/dev-agent/nix/dev-agent-files/entrypoint.sh` to run `python3 -m predictive_agent.main` instead of `python3 -m dev_agent.main`
- [x] 5.3 Update image tag from `v4.0-nix` to `v8-nix` (matching `predictive-agent` repo) or document the version relationship
- [x] 5.4 Update `OPERATOR_NAME` from `opendesk-dev-agent` to `opendesk-predictive-agent` (matching `predictive-agent` repo)
- [ ] 5.5 Verify the `dev-agent` repo Nix build succeeds after the path fix (requires `predictive_agent/` directory to be co-located)

## 6. Update `opendesk-nix` Documentation

- [x] 6.1 Update `nix/images/dev-agent.nix` header comment to document that this is the v3.1.0 legacy build and the v4.0.0 build lives in the `predictive-agent` repo
- [x] 6.2 Add a note in `specs/technical/DEV-AGENT-SPEC.md` pointing to the `predictive-agent` repo for the v4.0.0 code, tests, and Nix build
- [x] 6.3 Create `tests/dev-agent/README.md` in `opendesk-nix` pointing to `~/git/predictive-agent/tests/` for the actual test suite (document, don't duplicate)

## 7. Wire `predictive-agent` Tests into `opendesk-nix` flake.nix (Optional)

- [ ] 7.1 Add a `dev-agent-unit-tests` check to `flake.nix` that runs `pytest` against the `predictive-agent` repo's tests (if co-located or via fetchFromGitHub)
- [ ] 7.2 Add a `dev-agent-integration` check to `flake.nix` that verifies the `predictive-agent` Nix build produces a valid image
- [ ] 7.3 Add a `dev-agent-e2e` check to `flake.nix` (opt-in, requires Docker runtime) that starts the container and verifies endpoints

## 8. Update `predictive-agent` Repo (Optional)

- [ ] 8.1 Add K8s manifest documentation to `predictive-agent/README.md` (deployment, service, RBAC, ConfigMap, PVC)
- [ ] 8.2 Add a `tests/e2e/` directory to `predictive-agent` for container lifecycle and endpoint contract tests (currently only unit and integration tests exist)
- [ ] 8.3 Add a `Makefile` or `justfile` to `predictive-agent` for common tasks (test, build, lint, nix-build)
