## Context

The dev-agent has evolved through three generations:

1. **v1.x–v2.x (Go operator)**: A Go-based Kubernetes operator with CRDs (`HealthPolicy`, `RepairStrategy`), PI Memory integration, and a multi-stage Docker build. Described in the now-removed `DEV-AGENT-SPEC.md` (55 KB). The Go source lives in `opendesk-meta/opendesk-dev-agent-operator/`. The `docker/dev-agent/Dockerfile` and `dev-agent/flake.nix` (removed in this change) referenced this era.
2. **v3.x (Python K8s operator)**: A Python stdlib-only operator (`dev_agent.py` v3.1.0) that watches pods via `kubectl`, uses Ollama LLM for analysis, and exposes HTTP endpoints. Packaged in `opendesk-nix/nix/images/dev-agent.nix` as `dev-agent:v7-nix`. Source in `nix/images/dev-agent-files/dev_agent.py`.
3. **v4.0.0 (Predictive agent)**: A refactored Python package (`predictive_agent/`) with Kalman filter, Markov chain, Bayesian risk scoring, and new endpoints (`/predictions`, `/state`, `/reanalyze`). Lives in the separate `predictive-agent` repo (`~/git/predictive-agent`) with its own Nix build (`nix/predictive-agent.nix` → `predictive-agent:v8-nix`) and full test suite (105 tests, all passing).

**Key discovery**: The `predictive-agent` repo already has a complete, passing test suite (11 test files, 105 test functions, including property-based tests with Hypothesis). The `dev-agent` repo (`~/git/dev-agent`) has Nix packaging only, but its `nix/dev-agent.nix` references `../dev_agent/*.py` which does not exist in the repo — the build is broken. The `predictive-agent` repo's `nix/predictive-agent.nix` correctly references `../predictive_agent/*.py` and builds successfully.

This change aligns the `opendesk-nix` spec and contract with the actual v4.0.0 implementation in `predictive-agent`, references the existing test suite, and removes stale Go-era artifacts.

## Goals / Non-Goals

### Goals

- Replace the outdated Go-era spec with an accurate Python-based specification
- Define a formal API contract for all HTTP endpoints
- Document the test pyramid by referencing the existing 105 tests in `predictive-agent/tests/`
- Remove stale Go-era build artifacts (`docker/dev-agent/Dockerfile`, `dev-agent/flake.nix`)
- Document the packaging path: `predictive-agent/nix/predictive-agent.nix` (v8-nix) is the canonical build; `opendesk-nix/nix/images/dev-agent.nix` (v7-nix) is the legacy v3.1.0 build
- Fix the broken `dev-agent` repo Nix build (references non-existent `../dev_agent/`)

### Non-Goals

- Migrating the `predictive-agent` v4.0.0 code into the `opendesk-nix` repo (it stays in its own repo)
- Changing the running dev-agent's behavior (this is spec/contract/test documentation only)
- Building the Docker image via `docker/dev-agent/Dockerfile` (removed — the Nix build is the source of truth)
- Implementing the Go-based CRD operator (it is abandoned)
- Creating new tests in `opendesk-nix` (the tests already exist and pass in `predictive-agent/tests/`)

## Decisions

### D1: Spec replaces, not modifies, the existing DEV-AGENT-SPEC.md

**Decision**: Replace `specs/technical/DEV-AGENT-SPEC.md` entirely rather than patching it.

**Rationale**: The 55 KB spec described CRDs, RBAC, PI Memory, Go build process, and deployment manifests that do not exist in the Python implementation. Patching would leave a confusing mix of Go and Python concepts. A clean replacement is clearer.

**Alternatives considered**:
- Keep the Go spec and add a separate Python spec → Two conflicting specs for the same component is worse than one accurate spec.
- Archive the Go spec and write a new one → Same effect as replacement, but replacement is simpler.

### D2: Three separate spec capabilities (dev-agent, dev-agent-api, dev-agent-tests)

**Decision**: Split into three OpenSpec capabilities rather than one monolithic spec.

**Rationale**:
- `dev-agent`: Behavioral spec (what the agent does — reconcile loop, health detection, LLM analysis, prediction)
- `dev-agent-api`: API contract (what external systems can rely on — endpoints, schemas, env vars)
- `dev-agent-tests`: Test pyramid (how we verify — unit, integration, e2e)

This separation matches the OpenSpec model where each capability gets its own spec file and can evolve independently.

### D3: Reference existing tests in `predictive-agent` repo — do not create new tests in `opendesk-nix`

**Decision**: The test spec documents the existing 105 tests in `predictive-agent/tests/`. No new tests are created in `opendesk-nix`.

**Rationale**: The `predictive-agent` repo already has a comprehensive, passing test suite:
- `test_collector.py` (9 tests): kubectl output parsing, CPU/memory parsing
- `test_kalman.py` (8 tests): 2D Kalman filter state, velocity, prediction, time-to-threshold
- `test_markov.py` (9 tests): Markov chain transitions, matrix, prediction, serialization
- `test_risk.py` (6 tests): Bayesian risk scoring, bounds, signal contributions
- `test_predictor.py` (6 tests): Prediction engine, TTF, confidence, at-risk filtering
- `test_state_model.py` (12 tests): Pod tracking, state classification, Kalman updates, persistence
- `test_persistence.py` (5 tests): StateStore save/load, atomic writes, corruption fallback
- `test_llm.py` (15 tests): LLM analyzer, multi-backend, response parsing, error handling
- `test_server.py` (11 tests): HTTP server, all endpoints, 404, metrics, JSON schemas
- `test_main.py` (6 tests): Reconcile loop, start/stop, output structure
- `test_endpoints.py` (4 tests): Integration tests with real HTTP server
- `test_property.py` (14 tests): Property-based tests with Hypothesis (invariant verification)

All 105 tests pass (`pytest tests/ -v` → 103 passed + 2 collected in 20.79s). Creating duplicate tests in `opendesk-nix` would be reinventing the wheel.

**Alternatives considered**:
- Copy tests into `opendesk-nix/tests/dev-agent/` → Duplicates tests, creates maintenance burden, tests would drift from the code they test.
- Vendor the `predictive_agent/` package into `opendesk-nix` → Adds complexity; the code lives in its own repo with its own CI.

### D4: `predictive-agent/nix/predictive-agent.nix` is the canonical Nix build

**Decision**: The `predictive-agent` repo's `nix/predictive-agent.nix` (builds `predictive-agent:v8-nix`) is the canonical Nix build for v4.0.0. The `opendesk-nix/nix/images/dev-agent.nix` (builds `dev-agent:v7-nix`) is the legacy v3.1.0 build.

**Rationale**: The `predictive-agent` Nix build correctly references `../predictive_agent/*.py` (which exists in the repo) and builds the v4.0.0 package. The `opendesk-nix` Nix build references `dev-agent-files/dev_agent.py` (v3.1.0, single file, no predictive capabilities). The `dev-agent` repo's `nix/dev-agent.nix` references `../dev_agent/*.py` which does not exist — the build is broken.

**Action**: Fix the `dev-agent` repo's Nix build to reference `../predictive_agent/*.py` (co-located with the `predictive-agent` repo) or deprecate it in favor of the `predictive-agent` repo's own Nix build.

### D5: Remove stale Go-era build artifacts

**Decision**: Remove `docker/dev-agent/Dockerfile` and `dev-agent/flake.nix`.

**Rationale**:
- `docker/dev-agent/Dockerfile` was a Go multi-stage build referencing `opendesk-dev-agent-operator/` source that does not exist in this repo. It cannot build.
- `dev-agent/flake.nix` referenced `go-mod2nix` (doesn't exist), `kindsys` (not in nixpkgs), and `opendesk-dev-agent-operator/` directory (doesn't exist). It cannot build.
- `docker/dev-agent/config.yaml`, `docker/dev-agent/entrypoint.sh`, `docker/dev-agent/healthcheck.sh`, `docker/dev-agent/logrotate.conf`, and `docker/dev-agent/limits.d/` are kept as reference files.

### D6: Keep `docker/dev-agent/` config files as reference

**Decision**: Keep `docker/dev-agent/config.yaml`, `docker/dev-agent/entrypoint.sh`, `docker/dev-agent/healthcheck.sh`, `docker/dev-agent/logrotate.conf`, `docker/dev-agent/limits.d/opendesk-operator.conf` as reference documentation.

**Rationale**: These files document the intended configuration and operational setup. The Nix build uses its own entrypoint and healthcheck, but the Docker-era files serve as a configuration reference and are harmless.

## Risks / Trade-offs

- **[Spec-implementation drift]** The spec in `opendesk-nix` describes v4.0.0 behavior, but the `opendesk-nix/nix/images/dev-agent.nix` builds v3.1.0 code. → **Mitigation**: The spec clearly states which version it describes. The `predictive-agent` repo has the v4.0.0 code and its own Nix build. The `opendesk-nix` legacy build is documented as v3.1.0.
- **[Broken dev-agent repo]** The `dev-agent` repo's `nix/dev-agent.nix` references `../dev_agent/*.py` which does not exist. → **Mitigation**: Task 6.1 fixes this by updating the path to `../predictive_agent/*.py` or deprecating the repo.
- **[Test location]** Tests live in `predictive-agent/tests/`, not in `opendesk-nix`. → **Mitigation**: The test spec documents the test location and how to run them. The `opendesk-nix` flake.nix can optionally run the `predictive-agent` tests as a check.

## Migration Plan

1. **Remove stale artifacts**: Delete `docker/dev-agent/Dockerfile` and `dev-agent/flake.nix` (done).
2. **Replace spec**: Replace `specs/technical/DEV-AGENT-SPEC.md` with the new spec (done).
3. **Create API contract**: Create `specs/technical/DEV-AGENT-CONTRACT.md` (done).
4. **Document test pyramid**: Create `openspec/specs/dev-agent-tests/spec.md` referencing the existing 105 tests in `predictive-agent/tests/` (done).
5. **Fix dev-agent repo**: Update `dev-agent/nix/dev-agent.nix` to reference `../predictive_agent/*.py` instead of `../dev_agent/*.py`.
6. **No runtime changes**: The running dev-agent is unaffected.

**Rollback**: Revert the git commit. No data migration, no runtime impact.

## Open Questions

- Should the `opendesk-nix/nix/images/dev-agent.nix` be updated to build from the `predictive-agent` code, or should it be deprecated in favor of the `predictive-agent` repo's own Nix build? (Currently the `opendesk-nix` build uses v3.1.0 code; the `predictive-agent` build uses v4.0.0 code.)
- Should the `dev-agent` repo be deprecated entirely in favor of the `predictive-agent` repo (which has both the code and its own Nix build)?
