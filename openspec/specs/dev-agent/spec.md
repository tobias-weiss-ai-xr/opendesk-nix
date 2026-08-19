## Purpose

Defines the behavioral contract for the openDesk Dev Agent — a Python stdlib-only predictive Kubernetes health monitor that watches pods via kubectl, detects unhealthy states, uses an LLM (Ollama) for root-cause analysis, and predicts pod failures using Kalman trends, Markov state transitions, and Bayesian risk scoring.

## ADDED Requirements

### Requirement: Reconcile loop monitors pod health periodically

The dev agent SHALL run a reconcile loop at a configurable interval (default 60 seconds) that fetches all pods across watched namespaces via `kubectl get pods`, classifies each pod as healthy or unhealthy, and triggers LLM analysis for unhealthy pods.

#### Scenario: Reconcile loop runs at configured interval

- **WHEN** the dev agent is running with `RECONCILE_INTERVAL=60`
- **THEN** the reconcile loop SHALL execute approximately every 60 seconds
- **AND** each cycle SHALL fetch pod status across all watched namespaces

#### Scenario: Reconcile loop skips self-namespace

- **WHEN** the dev agent is running in namespace `opendesk-dev-agent`
- **THEN** the reconcile loop SHALL skip pods in the `opendesk-dev-agent` namespace to prevent self-analysis loops

#### Scenario: Reconcile loop handles kubectl failures gracefully

- **WHEN** `kubectl get pods` fails or returns non-zero exit code
- **THEN** the dev agent SHALL log the error
- **AND** SHALL continue the loop without crashing
- **AND** SHALL increment an error counter in metrics

### Requirement: Pod health detection identifies unhealthy states

The dev agent SHALL classify pods as unhealthy when their status or container state matches any of: `CrashLoopBackOff`, `Error`, `OOMKilled`, `ImagePullBackOff`, `ErrImagePull`, `ContainerCreating`, `PodInitializing`, `CreateContainerError`, `CreateContainerConfigError`, `RunContainerError`, `InvalidImageName`, `RegistryUnavailable`, `Evicted`, `Pending`, `Failed`, `Unknown`.

#### Scenario: CrashLoopBackOff pod is detected as unhealthy

- **WHEN** a pod has container status `CrashLoopBackOff`
- **THEN** the dev agent SHALL classify the pod as unhealthy
- **AND** SHALL trigger LLM analysis for that pod

#### Scenario: Healthy pod is not analyzed

- **WHEN** a pod has status `Running` with all containers ready
- **THEN** the dev agent SHALL classify the pod as healthy
- **AND** SHALL NOT trigger LLM analysis for that pod

#### Scenario: Maximum pods per cycle limits analysis

- **WHEN** more than `MAX_PODS_PER_CYCLE` (default 3) unhealthy pods are detected in a single reconcile cycle
- **THEN** the dev agent SHALL analyze only the first `MAX_PODS_PER_CYCLE` pods
- **AND** SHALL log that remaining pods are deferred to the next cycle

### Requirement: LLM analysis provides root-cause assessment

The dev agent SHALL send unhealthy pod context (name, namespace, status, events, logs) to an Ollama LLM endpoint and parse the JSON response for `analysis`, `severity`, `action`, and `command` fields.

#### Scenario: Successful LLM analysis

- **WHEN** an unhealthy pod is detected and `OLLAMA_URL` is reachable
- **THEN** the dev agent SHALL send a prompt to `{OLLAMA_URL}/api/chat` with `stream: false` and `temperature: 0`
- **AND** SHALL parse the JSON response containing `analysis`, `severity`, `action`, `command`
- **AND** SHALL store the result in analysis history

#### Scenario: LLM analysis caching with adaptive TTL

- **WHEN** a pod's status has not changed since the last analysis
- **THEN** the dev agent SHALL skip re-analysis and use the cached result
- **AND** the cache TTL SHALL increase adaptively: 300s → 600s → 1200s (up to `ANALYSIS_TTL_MAX`)

#### Scenario: LLM timeout or error

- **WHEN** the LLM request times out (default 180 seconds) or fails
- **THEN** the dev agent SHALL log the error
- **AND** SHALL continue the reconcile loop without crashing
- **AND** SHALL NOT store a result for that pod

### Requirement: Predictive engine estimates time-to-failure

The dev agent SHALL use a 2D Kalman filter to estimate memory and CPU trends, a first-order Markov chain to model state transitions (HEALTHY → DEGRADED → STRESSED → CRITICAL → FAILED → RECOVERED), and Bayesian risk scoring to produce a risk score (0.0 to 0.99) and optional time-to-failure estimate (in minutes).

#### Scenario: Memory trend prediction

- **WHEN** a pod has memory usage data over multiple reconcile cycles
- **THEN** the Kalman filter SHALL estimate the memory growth rate (MiB/min)
- **AND** SHALL predict time-to-failure when memory growth is positive and approaching the limit

#### Scenario: Markov state classification

- **WHEN** a pod has memory percentage, CPU percentage, restart count, log errors, and node pressure data
- **THEN** the state classifier SHALL assign one of: `HEALTHY`, `DEGRADED`, `STRESSED`, `CRITICAL`
- **AND** the Markov chain SHALL record the state transition

#### Scenario: Bayesian risk scoring

- **WHEN** pod metrics and Markov state are available
- **THEN** the risk scorer SHALL combine memory percentage, memory trend, CPU percentage, restart rate, log error rate, node pressure, and Markov transition probabilities into a risk score between 0.0 and 0.99

### Requirement: State persistence survives restarts

The dev agent SHALL persist the Markov chain state and prediction history to JSON files on disk, and SHALL load them on startup to restore state across container restarts.

#### Scenario: State persistence on shutdown

- **WHEN** the dev agent receives SIGTERM or SIGINT
- **THEN** the dev agent SHALL save the Markov chain state to the state model file
- **AND** SHALL save prediction history to the predictions file
- **AND** SHALL shut down gracefully

#### Scenario: State restoration on startup

- **WHEN** the dev agent starts and a valid state model file exists
- **THEN** the dev agent SHALL load the Markov chain from the file
- **AND** SHALL resume state tracking with the loaded transition counts

#### Scenario: Corrupted state file fallback

- **WHEN** the state model file is corrupted or unreadable
- **THEN** the dev agent SHALL fall back to a fresh Markov chain with default prior counts
- **AND** SHALL NOT crash

### Requirement: Model warmup on startup

The dev agent SHALL pre-load the LLM model on startup to avoid cold-start latency on the first analysis.

#### Scenario: Model warmup

- **WHEN** the dev agent starts and `OLLAMA_URL` is configured
- **THEN** the dev agent SHALL send a warmup request to the LLM
- **AND** SHALL log the warmup duration

### Requirement: Configuration via environment variables

The dev agent SHALL be configurable via environment variables with sensible defaults.

#### Scenario: Default configuration

- **WHEN** no environment variables are set
- **THEN** the dev agent SHALL use defaults: `RECONCILE_INTERVAL=60`, `ANALYSIS_TTL=300`, `MAX_PODS_PER_CYCLE=3`, `LOG_VERBOSITY=info`, `METRICS_PORT=8080`, `HEALTH_PORT=8081`

#### Scenario: Custom configuration

- **WHEN** environment variables are set (e.g., `RECONCILE_INTERVAL=30`, `OLLAMA_MODEL=qwen3-30b-a3b:latest`)
- **THEN** the dev agent SHALL use the provided values
- **AND** SHALL log the configuration at startup

### Requirement: Container packaging as Nix Docker image

The dev agent SHALL be packaged as a Nix-built Docker image containing Python 3, kubectl, curl, bash, and the dev_agent Python package. The image SHALL expose ports 8080 (metrics) and 8081 (health) and run as a non-root user where possible.

#### Scenario: Nix image build

- **WHEN** `nix build .#dev-agent-image` (or equivalent) is executed
- **THEN** a Docker image SHALL be produced with the dev_agent Python package, entrypoint, and healthcheck
- **AND** the image SHALL contain kubectl, curl, bash, and Python 3

#### Scenario: Container startup

- **WHEN** the container starts
- **THEN** the entrypoint SHALL create required directories (`/var/lib/opendesk`, `/var/log/opendesk`, `/var/cache/opendesk`)
- **AND** SHALL set `PYTHONPATH` to include the dev_agent package
- **AND** SHALL start the Python reconcile loop via `python3 -m dev_agent` or `python3 -m predictive_agent`

### Requirement: Graceful shutdown

The dev agent SHALL handle SIGTERM and SIGINT signals to shut down gracefully, saving state and stopping HTTP servers.

#### Scenario: SIGTERM handling

- **WHEN** the container receives SIGTERM
- **THEN** the dev agent SHALL stop the reconcile loop
- **AND** SHALL save state to disk
- **AND** SHALL shut down HTTP servers
- **AND** SHALL exit with code 0

### Requirement: Analysis history persistence

The dev agent SHALL maintain a history of LLM analyses (up to `HISTORY_MAX` entries, default 100) persisted to a JSON file.

#### Scenario: History storage

- **WHEN** an LLM analysis completes
- **THEN** the result SHALL be appended to the history list
- **AND** the list SHALL be truncated to `HISTORY_MAX` entries
- **AND** the list SHALL be persisted to `HISTORY_FILE` (default `/var/lib/opendesk/analysis-history.json`)

#### Scenario: History retrieval via API

- **WHEN** a GET request is made to `/history`
- **THEN** the dev agent SHALL return the analysis history as a JSON array
