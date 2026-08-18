#!/usr/bin/env python3
"""
openDesk Dev Agent Operator — AI-powered Kubernetes self-healing operator.
Monitors k8s resources and uses Ollama LLM for cluster issue analysis.
Replaces the Go operator binary with a lightweight Python implementation.
"""
import http.server
import json
import os
import subprocess
import threading
import time
import urllib.request
import urllib.error

# Configuration
OPERATOR_NAME = os.environ.get("OPERATOR_NAME", "opendesk-dev-agent")
OPERATOR_NAMESPACE = os.environ.get("OPERATOR_NAMESPACE", "opendesk-dev-agent")
WATCH_NAMESPACES = os.environ.get("OPERATOR_WATCH_NAMESPACES", "opendesk,opendesk-edu,default,llm").split(",")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama.llm.svc.cluster.local:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen3-30b-a3b:latest")
LOG_LEVEL = os.environ.get("OPERATOR_LOG_LEVEL", "info")
HEALTH_PORT = int(os.environ.get("OPERATOR_HEALTH_PROBE_BIND_ADDRESS", "0.0.0.0:8081").split(":")[-1])
METRICS_PORT = int(os.environ.get("OPERATOR_METRICS_BIND_ADDRESS", "0.0.0.0:8080").split(":")[-1])
RECONCILE_INTERVAL = int(os.environ.get("RECONCILE_INTERVAL", "60"))
OLLAMA_TIMEOUT = int(os.environ.get("OLLAMA_TIMEOUT", "180"))

# Unhealthy pod statuses (container statuses that indicate problems)
UNHEALTHY_STATUSES = {
    "CrashLoopBackOff", "Error", "OOMKilled", "ImagePullBackOff", "ErrImagePull",
    "ContainerCreating", "PodInitializing", "CreateContainerError",
    "CreateContainerConfigError", "RunContainerError", "InvalidImageName",
    "RegistryUnavailable", "Evicted", "Pending", "Failed", "Unknown",
}

# State
startup_complete = False
ready = False
last_reconcile = 0
last_error = ""
last_analysis = ""
metrics = {
    "reconcile_total": 0,
    "errors_total": 0,
    "pods_healthy": 0,
    "pods_unhealthy": 0,
    "ai_analysis_total": 0,
    "ai_analysis_errors": 0,
}


def log(level, msg):
    """Log a message with timestamp."""
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"[{ts}] [{level.upper()}] {msg}", flush=True)


def run_cmd(cmd, timeout=30):
    """Run a command and return (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def check_k8s():
    """Check k8s API connectivity."""
    rc, out, err = run_cmd(["kubectl", "get", "pods", "--all-namespaces", "--no-headers"])
    return rc == 0, out, err


def get_all_pods():
    """Get all pods across all namespaces with their status.
    Returns list of dicts: {namespace, name, ready, status, restarts, age}
    """
    rc, out, _ = run_cmd(["kubectl", "get", "pods", "--all-namespaces", "--no-headers"], timeout=30)
    if rc != 0:
        return []
    pods = []
    for line in out.strip().split("\n"):
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        pod = {
            "namespace": parts[0],
            "name": parts[1],
            "ready": parts[2],
            "status": parts[3] if len(parts) > 3 else "Unknown",
            "restarts": parts[4] if len(parts) > 4 else "0",
            "age": parts[5] if len(parts) > 5 else "unknown",
        }
        pods.append(pod)
    return pods


def classify_pods(pods):
    """Classify pods as healthy or unhealthy.
    Healthy: Running (without CrashLoopBackOff), Completed, Succeeded
    Unhealthy: any UNHEALTHY_STATUSES, or non-Running/non-Completed
    """
    healthy = []
    unhealthy = []
    for pod in pods:
        status = pod["status"]
        # Running with CrashLoopBackOff is unhealthy
        if status in UNHEALTHY_STATUSES:
            unhealthy.append(pod)
        elif status in ("Running", "Completed", "Succeeded"):
            healthy.append(pod)
        else:
            # Unknown status — treat as unhealthy
            unhealthy.append(pod)
    return healthy, unhealthy


def get_pod_logs(namespace, name, tail=50):
    """Get recent logs from a pod for LLM context."""
    rc, out, _ = run_cmd(
        ["kubectl", "logs", "-n", namespace, name, f"--tail={tail}", "--previous"],
        timeout=15
    )
    if rc != 0:
        # Try without --previous (pod might not have previous container)
        rc, out, _ = run_cmd(
            ["kubectl", "logs", "-n", namespace, name, f"--tail={tail}"],
            timeout=15
        )
    if rc != 0:
        return f"(unable to fetch logs: {out[:200]})"
    return out[:3000] if out else "(no logs available)"


def get_pod_events(namespace, name):
    """Get recent events for a pod."""
    rc, out, _ = run_cmd(
        ["kubectl", "get", "events", "-n", namespace,
         "--field-selector", f"involvedObject.name={name}",
         "--sort-by=.lastTimestamp", "--no-headers"],
        timeout=15
    )
    if rc != 0 or not out:
        return "(no events)"
    # Take last 10 events
    lines = out.strip().split("\n")
    return "\n".join(lines[-10:])


def get_pod_details(namespace, name):
    """Get detailed pod info for LLM context."""
    rc, out, _ = run_cmd(
        ["kubectl", "get", "pod", "-n", namespace, name, "-o", "json"],
        timeout=15
    )
    if rc != 0:
        return {}
    try:
        data = json.loads(out)
        containers = []
        for c in data.get("spec", {}).get("containers", []):
            containers.append({
                "name": c.get("name"),
                "image": c.get("image"),
                "command": c.get("command", []),
                "args": c.get("args", []),
            })
        statuses = []
        for s in data.get("status", {}).get("containerStatuses", []):
            statuses.append({
                "name": s.get("name"),
                "ready": s.get("ready"),
                "restartCount": s.get("restartCount"),
                "state": s.get("state"),
                "lastState": s.get("lastState"),
            })
        return {
            "phase": data.get("status", {}).get("phase"),
            "containers": containers,
            "containerStatuses": statuses,
            "conditions": data.get("status", {}).get("conditions", []),
        }
    except Exception:
        return {}


def analyze_with_ollama(issue_description, context=""):
    """Use Ollama LLM to analyze a cluster issue and suggest remediation."""
    global metrics, last_analysis
    metrics["ai_analysis_total"] += 1
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
            "options": {"temperature": 0.3, "num_ctx": 8192}
        }).encode()
        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"}
        )
        log("info", f"Sending analysis to Ollama (model={OLLAMA_MODEL}, timeout={OLLAMA_TIMEOUT}s)...")
        with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
            result = json.loads(resp.read().decode())
            response = result.get("response", "")
            eval_count = result.get("eval_count", 0)
            eval_duration = result.get("eval_duration", 0)
            total_duration = result.get("total_duration", 0)
            log("info", f"Ollama response: {eval_count} tokens, eval={eval_duration/1e9:.1f}s, total={total_duration/1e9:.1f}s")
            last_analysis = response[:500]
            return response
    except urllib.error.URLError as e:
        metrics["ai_analysis_errors"] += 1
        log("error", f"Ollama analysis failed (URL error): {e}")
        return ""
    except Exception as e:
        metrics["ai_analysis_errors"] += 1
        log("error", f"Ollama analysis failed: {e}")
        return ""


def reconcile():
    """Main reconciliation loop — check cluster health and analyze issues."""
    global last_reconcile, metrics, ready, last_error
    metrics["reconcile_total"] += 1
    last_reconcile = time.time()

    log("info", f"Reconciling (#{metrics['reconcile_total']})...")

    # Check k8s connectivity
    k8s_ok, _, k8s_err = check_k8s()
    if not k8s_ok:
        last_error = f"k8s API: {k8s_err}"
        metrics["errors_total"] += 1
        log("error", f"k8s API check failed: {k8s_err}")
        ready = False
        return

    # Get all pods and classify
    all_pods = get_all_pods()
    healthy_pods, unhealthy_pods = classify_pods(all_pods)

    metrics["pods_healthy"] = len(healthy_pods)
    metrics["pods_unhealthy"] = len(unhealthy_pods)

    if unhealthy_pods:
        log("info", f"Found {len(unhealthy_pods)} unhealthy pod(s):")
        for pod in unhealthy_pods:
            log("info", f"  → {pod['namespace']}/{pod['name']} status={pod['status']} restarts={pod['restarts']}")

        # Analyze up to 3 unhealthy pods per reconcile cycle
        for pod in unhealthy_pods[:3]:
            ns = pod["namespace"]
            name = pod["name"]
            status = pod["status"]
            restarts = pod["restarts"]

            issue = f"Pod {ns}/{name} status: {status} (restarts: {restarts})"
            log("info", f"Analyzing: {issue}")

            # Gather context for LLM
            logs = get_pod_logs(ns, name)
            events = get_pod_events(ns, name)
            details = get_pod_details(ns, name)

            context_parts = []
            context_parts.append(f"Namespace: {ns}")
            context_parts.append(f"Pod: {name}")
            context_parts.append(f"Status: {status}")
            context_parts.append(f"Restarts: {restarts}")
            if details:
                context_parts.append(f"Phase: {details.get('phase', 'unknown')}")
                for cs in details.get("containerStatuses", []):
                    state = cs.get("state", {})
                    last_state = cs.get("lastState", {})
                    if state:
                        context_parts.append(f"Container {cs['name']} state: {json.dumps(state)}")
                    if last_state:
                        context_parts.append(f"Container {cs['name']} lastState: {json.dumps(last_state)}")
                for c in details.get("containers", []):
                    context_parts.append(f"Container {c['name']}: image={c['image']}, command={c.get('command', [])}")
            context_parts.append(f"\nRecent logs:\n{logs}")
            context_parts.append(f"\nRecent events:\n{events}")

            context = "\n".join(context_parts)

            analysis = analyze_with_ollama(issue, context)
            if analysis:
                log("info", f"AI Analysis for {ns}/{name}:")
                # Log full analysis (not truncated)
                for line in analysis.strip().split("\n"):
                    log("info", f"  {line}")
            else:
                log("error", f"AI Analysis failed for {ns}/{name}")
    else:
        log("info", f"All {len(healthy_pods)} pods healthy")

    ready = True
    log("info", f"Reconcile complete: {len(healthy_pods)} healthy, {len(unhealthy_pods)} unhealthy pods")


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
                "# HELP opendesk_dev_agent_ai_analysis_total Total AI analyses",
                "# TYPE opendesk_dev_agent_ai_analysis_total counter",
                f"opendesk_dev_agent_ai_analysis_total {metrics['ai_analysis_total']}",
                "# HELP opendesk_dev_agent_ai_analysis_errors Total AI analysis errors",
                "# TYPE opendesk_dev_agent_ai_analysis_errors counter",
                f"opendesk_dev_agent_ai_analysis_errors {metrics['ai_analysis_errors']}",
            ]
            self.wfile.write("\n".join(lines).encode())
        elif self.path == "/status":
            body = json.dumps({
                "operator": OPERATOR_NAME,
                "version": "2.2.0",
                "ollama_url": OLLAMA_URL,
                "ollama_model": OLLAMA_MODEL,
                "reconcile_count": metrics["reconcile_total"],
                "pods_healthy": metrics["pods_healthy"],
                "pods_unhealthy": metrics["pods_unhealthy"],
                "ai_analysis_total": metrics["ai_analysis_total"],
                "ai_analysis_errors": metrics["ai_analysis_errors"],
                "errors_total": metrics["errors_total"],
                "last_reconcile": last_reconcile,
                "last_analysis": last_analysis[:200] if last_analysis else "",
                "startup_complete": startup_complete,
                "ready": ready,
            }, indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress access logs


def start_health_server():
    server = http.server.HTTPServer(("0.0.0.0", HEALTH_PORT), HealthHandler)
    server.serve_forever()


def start_metrics_server():
    server = http.server.HTTPServer(("0.0.0.0", METRICS_PORT), HealthHandler)
    server.serve_forever()


def main():
    global startup_complete

    log("info", f"=== {OPERATOR_NAME} v2.2.0 (Python) starting ===")
    log("info", f"Watch namespaces: {WATCH_NAMESPACES}")
    log("info", f"Ollama URL: {OLLAMA_URL}")
    log("info", f"Ollama model: {OLLAMA_MODEL}")
    log("info", f"Ollama timeout: {OLLAMA_TIMEOUT}s")
    log("info", f"Reconcile interval: {RECONCILE_INTERVAL}s")
    log("info", f"Health port: {HEALTH_PORT}")
    log("info", f"Metrics port: {METRICS_PORT}")

    # Start health and metrics servers in background
    threading.Thread(target=start_health_server, daemon=True).start()
    threading.Thread(target=start_metrics_server, daemon=True).start()
    log("info", f"Health server on :{HEALTH_PORT}, metrics on :{METRICS_PORT}")

    # Check Ollama connectivity
    try:
        req = urllib.request.Request(f"{OLLAMA_URL}/api/tags")
        with urllib.request.urlopen(req, timeout=10) as resp:
            tags = json.loads(resp.read().decode())
            models = [m["name"] for m in tags.get("models", [])]
            log("info", f"Connected to Ollama. Available models: {models}")
    except Exception as e:
        log("error", f"Cannot connect to Ollama at {OLLAMA_URL}: {e}")
        log("info", "Continuing without LLM analysis (will retry on reconcile)")

    # Check k8s connectivity
    k8s_ok, _, k8s_err = check_k8s()
    if k8s_ok:
        log("info", "Kubernetes API connectivity: OK")
    else:
        log("error", f"Kubernetes API check failed: {k8s_err}")

    startup_complete = True
    log("info", "Startup complete, starting reconcile loop")

    # Main reconcile loop
    while True:
        try:
            reconcile()
        except Exception as e:
            log("error", f"Reconcile error: {e}")
            metrics["errors_total"] += 1
        time.sleep(RECONCILE_INTERVAL)


if __name__ == "__main__":
    main()
