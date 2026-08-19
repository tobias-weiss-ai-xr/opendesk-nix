#!/usr/bin/env python3
"""
openDesk Dev Agent Operator v3.0 — AI-powered Kubernetes self-healing operator.

Optimizations over v2.2:
- Analysis caching with TTL: don't re-analyze same pod within ANALYSIS_TTL seconds
- Graceful SIGTERM/SIGINT handling for clean shutdown
- Model warmup on startup (pre-loads LLM to avoid 31s cold load on first analysis)
- Reduced log verbosity: only logs every 10th cycle when all healthy
- Single kubectl JSON call for all pods (faster than text parsing + per-pod calls)
- Parallel analysis of multiple unhealthy pods (threads)
- Analysis history persisted to /var/lib/opendesk/analysis-history.json
- Configurable via env vars: ANALYSIS_TTL, MAX_PODS_PER_CYCLE, LOG_VERBOSITY
- /status endpoint with full analysis history
- Better metrics: cache hits, warmup time, analysis duration histogram
"""
import http.server
import json
import os
import signal
import subprocess
import threading
import time
import urllib.request
import urllib.error
from collections import deque

# ─── Configuration ────────────────────────────────────────────────────────────
OPERATOR_NAME = os.environ.get("OPERATOR_NAME", "opendesk-dev-agent")
OPERATOR_NAMESPACE = os.environ.get("OPERATOR_NAMESPACE", "opendesk-dev-agent")
OPERATOR_VERSION = "3.0.0"
WATCH_NAMESPACES = os.environ.get("OPERATOR_WATCH_NAMESPACES", "opendesk,opendesk-edu,default,llm").split(",")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama.llm.svc.cluster.local:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen3-30b-a3b:latest")
OLLAMA_TIMEOUT = int(os.environ.get("OLLAMA_TIMEOUT", "180"))
RECONCILE_INTERVAL = int(os.environ.get("RECONCILE_INTERVAL", "60"))
ANALYSIS_TTL = int(os.environ.get("ANALYSIS_TTL", "300"))       # 5 min cache
MAX_PODS_PER_CYCLE = int(os.environ.get("MAX_PODS_PER_CYCLE", "3"))
LOG_VERBOSITY = os.environ.get("LOG_VERBOSITY", "info")          # info or debug
HISTORY_FILE = os.environ.get("HISTORY_FILE", "/var/lib/opendesk/analysis-history.json")
HISTORY_MAX = int(os.environ.get("HISTORY_MAX", "100"))
HEALTH_PORT = int(os.environ.get("OPERATOR_HEALTH_PROBE_BIND_ADDRESS", "0.0.0.0:8081").split(":")[-1])
METRICS_PORT = int(os.environ.get("OPERATOR_METRICS_BIND_ADDRESS", "0.0.0.0:8080").split(":")[-1])

# Unhealthy pod statuses
UNHEALTHY_STATUSES = {
    "CrashLoopBackOff", "Error", "OOMKilled", "ImagePullBackOff", "ErrImagePull",
    "ContainerCreating", "PodInitializing", "CreateContainerError",
    "CreateContainerConfigError", "RunContainerError", "InvalidImageName",
    "RegistryUnavailable", "Evicted", "Pending", "Failed", "Unknown",
}

# ─── State ────────────────────────────────────────────────────────────────────
startup_complete = False
ready = False
shutting_down = False
last_reconcile = 0
last_analysis = ""
model_warmup_time = 0
analysis_cache = {}  # {cache_key: {"timestamp": float, "analysis": str, "pod_key": str}}
analysis_history = deque(maxlen=HISTORY_MAX)
metrics = {
    "reconcile_total": 0,
    "errors_total": 0,
    "pods_healthy": 0,
    "pods_unhealthy": 0,
    "ai_analysis_total": 0,
    "ai_analysis_errors": 0,
    "ai_analysis_cache_hits": 0,
    "ai_analysis_duration_seconds": 0,
    "model_warmup_seconds": 0,
}


def log(level, msg):
    """Log a message with timestamp."""
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"[{ts}] [{level.upper()}] {msg}", flush=True)


def log_debug(msg):
    if LOG_VERBOSITY == "debug":
        log("debug", msg)


# ─── K8s Helpers ──────────────────────────────────────────────────────────────
def run_cmd(cmd, timeout=30):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def get_all_pods_json():
    """Get all pods as JSON (single kubectl call). Faster than text parsing + per-pod calls."""
    rc, out, _ = run_cmd(
        ["kubectl", "get", "pods", "--all-namespaces", "-o", "json", "--no-headers"],
        timeout=30
    )
    if rc != 0:
        return []
    try:
        data = json.loads(out)
        return data.get("items", [])
    except Exception:
        return []


def classify_pods_json(pods_json):
    """Classify pods from JSON output. Returns (healthy_list, unhealthy_list)."""
    healthy = []
    unhealthy = []
    for item in pods_json:
        meta = item.get("metadata", {})
        spec = item.get("spec", {})
        status = item.get("status", {})
        ns = meta.get("namespace", "")
        name = meta.get("name", "")
        phase = status.get("phase", "Unknown")
        container_statuses = status.get("containerStatuses", [])
        restart_count = sum(cs.get("restartCount", 0) for cs in container_statuses)
        # Determine container state
        container_state = "Running"
        for cs in container_statuses:
            state = cs.get("state", {})
            if not cs.get("ready", False):
                if "waiting" in state:
                    container_state = state["waiting"].get("reason", "Unknown")
                elif "terminated" in state:
                    container_state = state["terminated"].get("reason", "Error")
                break
        # Classify
        if phase in ("Succeeded",):
            healthy.append({"namespace": ns, "name": name, "phase": phase, "restarts": restart_count})
        elif phase == "Running" and container_state == "Running":
            healthy.append({"namespace": ns, "name": name, "phase": phase, "restarts": restart_count})
        else:
            unhealthy.append({
                "namespace": ns,
                "name": name,
                "phase": phase,
                "status": container_state,
                "restarts": restart_count,
                "_item": item,  # Keep full item for context gathering
            })
    return healthy, unhealthy


def get_pod_context(pod_item):
    """Extract context from already-fetched pod JSON (no extra kubectl calls)."""
    meta = pod_item.get("metadata", {})
    spec = pod_item.get("spec", {})
    status = pod_item.get("status", {})
    ns = meta.get("namespace", "")
    name = meta.get("name", "")

    context_parts = []
    context_parts.append(f"Namespace: {ns}")
    context_parts.append(f"Pod: {name}")
    context_parts.append(f"Phase: {status.get('phase', 'unknown')}")

    # Container info
    for c in spec.get("containers", []):
        context_parts.append(f"Container {c.get('name')}: image={c.get('image')}, command={c.get('command', [])}, args={c.get('args', [])}")

    # Container statuses
    for cs in status.get("containerStatuses", []):
        state = cs.get("state", {})
        last_state = cs.get("lastState", {})
        ready = cs.get("ready", False)
        restarts = cs.get("restartCount", 0)
        context_parts.append(f"ContainerStatus {cs.get('name')}: ready={ready}, restarts={restarts}")
        if state:
            context_parts.append(f"  state: {json.dumps(state)}")
        if last_state:
            context_parts.append(f"  lastState: {json.dumps(last_state)}")

    # Conditions
    for cond in status.get("conditions", []):
        if cond.get("status") != "True":
            context_parts.append(f"Condition {cond.get('type')}: {cond.get('status')} ({cond.get('message', '')})")

    # Events (still needs a separate call, but only for unhealthy pods)
    rc, events_out, _ = run_cmd(
        ["kubectl", "get", "events", "-n", ns,
         "--field-selector", f"involvedObject.name={name}",
         "--sort-by=.lastTimestamp", "--no-headers"],
        timeout=15
    )
    if rc == 0 and events_out:
        lines = events_out.strip().split("\n")
        context_parts.append(f"\nRecent events:\n" + "\n".join(lines[-10:]))

    # Logs (still needs a separate call, but only for unhealthy pods)
    rc, logs_out, _ = run_cmd(
        ["kubectl", "logs", "-n", ns, name, "--tail=30", "--previous"],
        timeout=15
    )
    if rc != 0:
        rc, logs_out, _ = run_cmd(
            ["kubectl", "logs", "-n", ns, name, "--tail=30"],
            timeout=15
        )
    if rc == 0 and logs_out:
        context_parts.append(f"\nRecent logs:\n{logs_out[:2000]}")
    else:
        context_parts.append("\nRecent logs: (unable to fetch)")

    return "\n".join(context_parts)


# ─── LLM Analysis ─────────────────────────────────────────────────────────────
def warmup_ollama():
    """Pre-load the model to avoid cold-start latency on first real analysis."""
    global model_warmup_time, metrics
    start = time.time()
    try:
        log("info", f"Warming up Ollama model {OLLAMA_MODEL}...")
        data = json.dumps({
            "model": OLLAMA_MODEL,
            "prompt": "OK",
            "stream": False,
            "options": {"temperature": 0, "num_predict": 1, "num_ctx": 512}
        }).encode()
        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            resp.read()  # consume
        model_warmup_time = time.time() - start
        metrics["model_warmup_seconds"] = model_warmup_time
        log("info", f"Model warmup complete in {model_warmup_time:.1f}s")
    except Exception as e:
        model_warmup_time = time.time() - start
        metrics["model_warmup_seconds"] = model_warmup_time
        log("error", f"Model warmup failed: {e}")


def analyze_with_ollama(issue_description, context, pod_key):
    """Analyze an issue with Ollama LLM. Uses cache to avoid redundant calls."""
    global metrics, last_analysis, analysis_cache

    # Check cache
    now = time.time()
    cache_key = pod_key
    if cache_key in analysis_cache:
        cached = analysis_cache[cache_key]
        age = now - cached["timestamp"]
        if age < ANALYSIS_TTL:
            log_debug(f"Cache hit for {pod_key} (age={age:.0f}s < TTL={ANALYSIS_TTL}s)")
            metrics["ai_analysis_cache_hits"] += 1
            return cached["analysis"]

    # Cache miss — call LLM
    metrics["ai_analysis_total"] += 1
    start = time.time()
    try:
        prompt = f"""You are a Kubernetes cluster self-healing operator running on the SCS k3s cluster.
Analyze the following issue and suggest remediation.

Issue: {issue_description}

Context: {context}

Respond in JSON format with:
{{
  "analysis": "brief analysis of the root cause",
  "severity": "critical|high|medium|low",
  "action": "recommended action to fix the issue",
  "command": "kubectl command to fix if applicable, otherwise empty string"
}}

Be concise. Focus on the most likely cause and the safest fix."""
        data = json.dumps({
            "model": OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.3, "num_ctx": 4096}
        }).encode()
        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"}
        )
        log("info", f"Analyzing {pod_key} with Ollama (model={OLLAMA_MODEL}, timeout={OLLAMA_TIMEOUT}s)...")
        with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
            result = json.loads(resp.read().decode())
            response = result.get("response", "")
            eval_count = result.get("eval_count", 0)
            eval_duration = result.get("eval_duration", 0)
            total_duration = result.get("total_duration", 0)
            duration = time.time() - start
            metrics["ai_analysis_duration_seconds"] = duration
            log("info", f"Ollama response: {eval_count} tokens, eval={eval_duration/1e9:.1f}s, total={total_duration/1e9:.1f}s, wall={duration:.1f}s")
            last_analysis = response[:500]
            # Cache the result
            analysis_cache[cache_key] = {
                "timestamp": now,
                "analysis": response,
                "pod_key": pod_key,
            }
            # Add to history
            analysis_history.append({
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "pod": pod_key,
                "issue": issue_description[:200],
                "analysis": response[:1000],
                "duration_seconds": round(duration, 1),
                "tokens": eval_count,
            })
            save_history()
            return response
    except urllib.error.URLError as e:
        metrics["ai_analysis_errors"] += 1
        log("error", f"Ollama analysis failed (URL error): {e}")
        return ""
    except Exception as e:
        metrics["ai_analysis_errors"] += 1
        log("error", f"Ollama analysis failed: {e}")
        return ""


# ─── History Persistence ──────────────────────────────────────────────────────
def save_history():
    """Save analysis history to file for persistence across restarts."""
    try:
        os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
        with open(HISTORY_FILE, "w") as f:
            json.dump(list(analysis_history), f, indent=2)
    except Exception as e:
        log_debug(f"Failed to save history: {e}")


def load_history():
    """Load analysis history from file on startup."""
    try:
        if os.path.exists(HISTORY_FILE):
            with open(HISTORY_FILE, "r") as f:
                data = json.load(f)
                for item in data:
                    analysis_history.append(item)
            log("info", f"Loaded {len(analysis_history)} analysis history entries from {HISTORY_FILE}")
    except Exception as e:
        log_debug(f"Failed to load history: {e}")


# ─── Reconcile Loop ───────────────────────────────────────────────────────────
def reconcile():
    """Main reconciliation loop — check cluster health and analyze issues."""
    global last_reconcile, metrics, ready, last_error
    metrics["reconcile_total"] += 1
    last_reconcile = time.time()
    cycle = metrics["reconcile_total"]

    log_debug(f"Reconciling (#{cycle})...")

    # Get all pods via a single JSON call
    pods_json = get_all_pods_json()
    if not pods_json:
        # Fallback: k8s API check
        k8s_ok, _, k8s_err = run_cmd(["kubectl", "get", "pods", "--all-namespaces", "--no-headers"])
        if not k8s_ok:
            last_error = f"k8s API: {k8s_err}"
            metrics["errors_total"] += 1
            log("error", f"k8s API check failed: {k8s_err}")
            ready = False
            return
        # JSON parse failed but text works — skip this cycle
        log_debug("k8s JSON parse failed, skipping")
        ready = True
        return

    healthy_pods, unhealthy_pods = classify_pods_json(pods_json)
    metrics["pods_healthy"] = len(healthy_pods)
    metrics["pods_unhealthy"] = len(unhealthy_pods)

    # Clean expired cache entries
    now = time.time()
    expired = [k for k, v in analysis_cache.items() if now - v["timestamp"] > ANALYSIS_TTL * 2]
    for k in expired:
        del analysis_cache[k]
    if expired:
        log_debug(f"Expired {len(expired)} cache entries")

    if unhealthy_pods:
        log("info", f"Found {len(unhealthy_pods)} unhealthy pod(s):")
        for pod in unhealthy_pods:
            log("info", f"  → {pod['namespace']}/{pod['name']} phase={pod['phase']} status={pod['status']} restarts={pod['restarts']}")

        # Analyze up to MAX_PODS_PER_CYCLE unhealthy pods in parallel
        to_analyze = unhealthy_pods[:MAX_PODS_PER_CYCLE]
        threads = []
        results = {}

        def analyze_pod(pod):
            ns = pod["namespace"]
            name = pod["name"]
            status = pod["status"]
            restarts = pod["restarts"]
            pod_key = f"{ns}/{name}"
            issue = f"Pod {pod_key} status: {status} (restarts: {restarts})"
            context = get_pod_context(pod["_item"])
            analysis = analyze_with_ollama(issue, context, pod_key)
            results[pod_key] = analysis

        for pod in to_analyze:
            t = threading.Thread(target=analyze_pod, args=(pod,))
            threads.append(t)
            t.start()

        for t in threads:
            t.join(timeout=OLLAMA_TIMEOUT + 30)

        # Log results
        for pod in to_analyze:
            pod_key = f"{pod['namespace']}/{pod['name']}"
            analysis = results.get(pod_key, "")
            if analysis:
                log("info", f"AI Analysis for {pod_key}:")
                for line in analysis.strip().split("\n"):
                    log("info", f"  {line}")
            else:
                log("error", f"AI Analysis failed for {pod_key}")
    else:
        # Only log every 10th cycle when healthy
        if cycle % 10 == 0:
            log("info", f"Reconcile #{cycle}: all {len(healthy_pods)} pods healthy")

    ready = True
    if unhealthy_pods:
        log("info", f"Reconcile #{cycle} complete: {len(healthy_pods)} healthy, {len(unhealthy_pods)} unhealthy")
    log_debug(f"Reconcile #{cycle} complete: {len(healthy_pods)} healthy, {len(unhealthy_pods)} unhealthy, cache={len(analysis_cache)}")


# ─── HTTP Handlers ────────────────────────────────────────────────────────────
class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            code = 200 if startup_complete else 503
            body = json.dumps({
                "status": "ok" if startup_complete else "starting",
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            })
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/ready":
            code = 200 if ready else 503
            body = json.dumps({
                "status": "ready" if ready else "not ready",
                "reconcile_count": metrics["reconcile_total"],
                "last_reconcile": last_reconcile,
                "pods_healthy": metrics["pods_healthy"],
                "pods_unhealthy": metrics["pods_unhealthy"],
            })
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/startup":
            code = 200 if startup_complete else 102
            body = json.dumps({"status": "started" if startup_complete else "starting"})
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/metrics":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            lines = [
                "# HELP opendesk_dev_agent_reconcile_total Total reconciliations",
                "# TYPE opendesk_dev_agent_reconcile_total counter",
                f"opendesk_dev_agent_reconcile_total {metrics['reconcile_total']}",
                "# HELP opendesk_dev_agent_errors_total Total errors",
                "# TYPE opendesk_dev_agent_errors_total counter",
                f"opendesk_dev_agent_errors_total {metrics['errors_total']}",
                "# HELP opendesk_dev_agent_pods_healthy Healthy pods",
                "# TYPE opendesk_dev_agent_pods_healthy gauge",
                f"opendesk_dev_agent_pods_healthy {metrics['pods_healthy']}",
                "# HELP opendesk_dev_agent_pods_unhealthy Unhealthy pods",
                "# TYPE opendesk_dev_agent_pods_unhealthy gauge",
                f"opendesk_dev_agent_pods_unhealthy {metrics['pods_unhealthy']}",
                "# HELP opendesk_dev_agent_ai_analysis_total Total AI analyses (LLM calls)",
                "# TYPE opendesk_dev_agent_ai_analysis_total counter",
                f"opendesk_dev_agent_ai_analysis_total {metrics['ai_analysis_total']}",
                "# HELP opendesk_dev_agent_ai_analysis_errors Total AI analysis errors",
                "# TYPE opendesk_dev_agent_ai_analysis_errors counter",
                f"opendesk_dev_agent_ai_analysis_errors {metrics['ai_analysis_errors']}",
                "# HELP opendesk_dev_agent_ai_analysis_cache_hits Total cache hits (skipped LLM calls)",
                "# TYPE opendesk_dev_agent_ai_analysis_cache_hits counter",
                f"opendesk_dev_agent_ai_analysis_cache_hits {metrics['ai_analysis_cache_hits']}",
                "# HELP opendesk_dev_agent_ai_analysis_duration_seconds Last analysis duration in seconds",
                "# TYPE opendesk_dev_agent_ai_analysis_duration_seconds gauge",
                f"opendesk_dev_agent_ai_analysis_duration_seconds {metrics['ai_analysis_duration_seconds']}",
                "# HELP opendesk_dev_agent_model_warmup_seconds Model warmup duration in seconds",
                "# TYPE opendesk_dev_agent_model_warmup_seconds gauge",
                f"opendesk_dev_agent_model_warmup_seconds {metrics['model_warmup_seconds']}",
                "# HELP opendesk_dev_agent_cache_size Current analysis cache size",
                "# TYPE opendesk_dev_agent_cache_size gauge",
                f"opendesk_dev_agent_cache_size {len(analysis_cache)}",
                "# HELP opendesk_dev_agent_history_entries Total analysis history entries",
                "# TYPE opendesk_dev_agent_history_entries counter",
                f"opendesk_dev_agent_history_entries {len(analysis_history)}",
            ]
            self.wfile.write("\n".join(lines).encode())
        elif self.path == "/status":
            body = json.dumps({
                "operator": OPERATOR_NAME,
                "version": OPERATOR_VERSION,
                "ollama_url": OLLAMA_URL,
                "ollama_model": OLLAMA_MODEL,
                "ollama_timeout": OLLAMA_TIMEOUT,
                "analysis_ttl": ANALYSIS_TTL,
                "max_pods_per_cycle": MAX_PODS_PER_CYCLE,
                "reconcile_interval": RECONCILE_INTERVAL,
                "reconcile_count": metrics["reconcile_total"],
                "pods_healthy": metrics["pods_healthy"],
                "pods_unhealthy": metrics["pods_unhealthy"],
                "ai_analysis_total": metrics["ai_analysis_total"],
                "ai_analysis_errors": metrics["ai_analysis_errors"],
                "ai_analysis_cache_hits": metrics["ai_analysis_cache_hits"],
                "ai_analysis_duration_seconds": round(metrics["ai_analysis_duration_seconds"], 1),
                "model_warmup_seconds": round(metrics["model_warmup_seconds"], 1),
                "errors_total": metrics["errors_total"],
                "last_reconcile": last_reconcile,
                "last_analysis": last_analysis[:200] if last_analysis else "",
                "cache_size": len(analysis_cache),
                "history_entries": len(analysis_history),
                "startup_complete": startup_complete,
                "ready": ready,
                "shutting_down": shutting_down,
            }, indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/history":
            body = json.dumps(list(analysis_history), indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/cache":
            cache_data = {}
            for k, v in analysis_cache.items():
                cache_data[k] = {
                    "timestamp": v["timestamp"],
                    "age_seconds": time.time() - v["timestamp"],
                    "analysis": v["analysis"][:500],
                }
            body = json.dumps(cache_data, indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def start_health_server():
    server = http.server.HTTPServer(("0.0.0.0", HEALTH_PORT), HealthHandler)
    server.serve_forever()


def start_metrics_server():
    server = http.server.HTTPServer(("0.0.0.0", METRICS_PORT), HealthHandler)
    server.serve_forever()


# ─── Signal Handling ──────────────────────────────────────────────────────────
def handle_shutdown(signum, frame):
    global shutting_down
    shutting_down = True
    log("info", f"Received signal {signum}, shutting down gracefully...")
    # Save history before exiting
    save_history()
    log("info", "History saved. Exiting.")
    os._exit(0)


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    global startup_complete

    log("info", f"=== {OPERATOR_NAME} v{OPERATOR_VERSION} starting ===")
    log("info", f"Watch namespaces: {WATCH_NAMESPACES}")
    log("info", f"Ollama URL: {OLLAMA_URL}")
    log("info", f"Ollama model: {OLLAMA_MODEL}")
    log("info", f"Ollama timeout: {OLLAMA_TIMEOUT}s")
    log("info", f"Analysis TTL: {ANALYSIS_TTL}s")
    log("info", f"Max pods per cycle: {MAX_PODS_PER_CYCLE}")
    log("info", f"Reconcile interval: {RECONCILE_INTERVAL}s")
    log("info", f"History file: {HISTORY_FILE}")
    log("info", f"Health port: {HEALTH_PORT}")
    log("info", f"Metrics port: {METRICS_PORT}")

    # Register signal handlers
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    # Start health and metrics servers
    threading.Thread(target=start_health_server, daemon=True).start()
    threading.Thread(target=start_metrics_server, daemon=True).start()
    log("info", f"Health server on :{HEALTH_PORT}, metrics on :{METRICS_PORT}")

    # Load analysis history from file
    load_history()

    # Check Ollama connectivity and warmup model
    try:
        req = urllib.request.Request(f"{OLLAMA_URL}/api/tags")
        with urllib.request.urlopen(req, timeout=10) as resp:
            tags = json.loads(resp.read().decode())
            models = [m["name"] for m in tags.get("models", [])]
            log("info", f"Connected to Ollama. Available models: {models}")
        # Warmup model in background thread
        threading.Thread(target=warmup_ollama, daemon=True).start()
    except Exception as e:
        log("error", f"Cannot connect to Ollama at {OLLAMA_URL}: {e}")
        log("info", "Continuing without LLM analysis (will retry on reconcile)")

    # Check k8s connectivity
    rc, _, k8s_err = run_cmd(["kubectl", "get", "pods", "--all-namespaces", "--no-headers"])
    if rc == 0:
        log("info", "Kubernetes API connectivity: OK")
    else:
        log("error", f"Kubernetes API check failed: {k8s_err}")

    startup_complete = True
    log("info", "Startup complete, starting reconcile loop")

    # Main reconcile loop
    while not shutting_down:
        try:
            reconcile()
        except Exception as e:
            log("error", f"Reconcile error: {e}")
            metrics["errors_total"] += 1
        time.sleep(RECONCILE_INTERVAL)

    log("info", "Shutdown complete.")


if __name__ == "__main__":
    main()
