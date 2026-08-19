# Dev Agent Tests

The dev agent test suite lives in the **predictive-agent** repository, not in `opendesk-nix`.

## Location

```
~/git/predictive-agent/tests/
```

## Running Tests

```bash
cd ~/git/predictive-agent
pytest tests/ -v
```

## Test Files (189 passing, 14 TDD red-phase)

| File | Tests | Description |
|------|-------|-------------|
| `test_collector.py` | 9 | kubectl output parsing, CPU/memory parsing, log error counting |
| `test_kalman.py` | 8 | 2D Kalman filter: state, velocity, prediction, time-to-threshold |
| `test_markov.py` | 9 | Markov chain: transitions, matrix, prediction, serialization |
| `test_risk.py` | 6 | Bayesian risk scoring: signals, bounds, posterior |
| `test_predictor.py` | 6 | Prediction engine: TTF, confidence, at-risk filtering |
| `test_state_model.py` | 12 | Pod tracking, state classification, Kalman updates, persistence |
| `test_persistence.py` | 5 | StateStore: save/load, atomic writes, corruption fallback |
| `test_llm.py` | 15 | LLM analyzer: prompt building, backends, response parsing, errors |
| `test_server.py` | 11 | HTTP server: all endpoints, 404, metrics, JSON schemas |
| `test_main.py` | 6 | Reconcile loop: start/stop, output structure, thread lifecycle |
| `test_endpoints.py` | 4 | Integration: HTTP server with real data |
| `test_property.py` | 14 | Property-based: Hypothesis invariants (risk bounds, Markov matrix) |
| `test_boundary.py` | 48 | Boundary value analysis (9 TDD red-phase failures) |
| `test_concurrency.py` | — | Concurrency: concurrent save/load (2 TDD red-phase failures) |
| `test_integration.py` | 13 | Full reconcile cycle, HTTP server with real state, persistence |
| `test_performance.py` | — | Performance: 1000 predicts, 1000 healthz, 10000 log lines (timing) |

## Test Pyramid

| Layer | What | How | Speed |
|-------|------|-----|-------|
| Unit | Python modules | `pytest tests/test_*.py` | < 30s |
| Property | Invariants | `pytest tests/test_property.py` (Hypothesis) | < 10s |
| Boundary | Edge cases | `pytest tests/test_boundary.py` | < 5s |
| Integration | Full pipeline | `pytest tests/test_integration.py` | < 5s |
| Performance | Throughput | `pytest tests/test_performance.py` | < 120s |

## Nix Build

The v4.0.0 Nix build lives in the predictive-agent repo:

```bash
cd ~/git/predictive-agent
nix build .#predictive-agent-image
```

The legacy v3.1.0 Nix build lives in opendesk-nix:

```bash
cd ~/git/opendesk-nix
nix build .#dev-agent-image
```

## See Also

- `specs/technical/DEV-AGENT-SPEC.md` — Behavioral specification
- `specs/technical/DEV-AGENT-CONTRACT.md` — API contract
- `openspec/specs/dev-agent-tests/spec.md` — Test pyramid specification
