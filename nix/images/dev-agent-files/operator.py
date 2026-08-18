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
import sys

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

# State
startup_complete = False
ready = False
last_reconcile = 0
last_error = ""
metrics = {
    "reconcile_total": 0,
    "errors_total": 0,
    "pods_healthy": 0,
    "pods_unhealthy": 0,
    "ai_analysis_total": 0,
    "ai_analysis_errors": 0,
}

def log(level, msg):
    if level == "error" or (level == "info" and LOG_LEVEL in ("info", "debug")) or LOG_LEVEL == "debug":
        ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        print(f"[{ts}] [{level.upper()}] {msg}", flush=True)

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return 1, "", str(e)

def check_k8s():
    rc, out, err = run_cmd(["kubectl", "get", "pods", "--all-namespaces", "--no-headers"])
    return rc == 0, out, err

def get_unhealthy_pods():
    rc, out, err = run_cmd([
        "kubectl", "get", "pods", "--all-namespaces",
        "--field-selector=status.phase!=Running,status.phase!=Succeeded",
        "--no-headers"
    ])
    if rc != 0:
        return []
    pods = []
    for line in out.strip().split("\n"):
        if line.strip():
            parts = line.split()
            if len(parts) >= 3:
                pods.append({"namespace": parts[0], "name": parts[1], "ready": parts[2], "status": parts[3] if len(parts) > 3 else "Unknown"})
    return pods

def get_crashloop_pods():
    rc, out, err = run_cmd([
        "kubectl", "get", "pods", "--all-namespaces",
        "--no-headers"
    ])
    if rc != 0:
        return []
    pods = []
    for line in out.strip().split("\n"):
        if line.strip() and "CrashLoopBackOff" in line:
            parts = line.split()
            if len(parts) >= 4:
                pods.append({"namespace": parts[0], "name": parts[1], "ready": parts[2], "status": parts[3]})
    return pods

def analyze_with_ollama(issue_description, context=""):
    """Use Ollama LLM to analyze a cluster issue and suggest remediation."""
    global metrics
    metrics["ai_analysis_total"] += 1
    try:
        prompt = f"""You are a Kubernetes cluster self-healing operator. Analyze the following issue and suggest remediation.

Issue: {issue_description}

Context: {context}

Respond in JSON format with:
{{"analysis": "brief analysis", "severity": "critical|high|medium|low", "action": "recommended action", "command": "kubectl command to fix if applicable"}}
"""
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
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read().decode())
            return result.get("response", "")
    except Exception as e:
        metrics["ai_analysis_errors"] += 1
        log("error", f"Ollama analysis failed: {e}")
        return ""

def reconcile():
    """Main reconciliation loop - check cluster health and analyze issues."""
    global last_reconcile, metrics, ready
    metrics["reconcile_total"] += 1
    last_reconcile = time.time()
    
    log("info", f"Reconciling (#{metrics['reconcile_total']})...")
    
    # Check k8s connectivity
    k8s_ok, _, k8s_err = check_k8s()
    if not k8s_ok:
        global last_error
        last_error = f"k8s API: {k8s_err}"
        metrics["errors_total"] += 1
        log("error", f"k8s API check failed: {k8s_err}")
        ready = False
        return
    
    # Get unhealthy pods
    unhealthy = get_unhealthy_pods()
    crashloop = get_crashloop_pods()
    
    total_pods = 0
    healthy_pods = 0
    unhealthy_pods = 0
    
    rc, out, _ = run_cmd(["kubectl", "get", "pods", "--all-namespaces", "--no-headers"])
    if rc == 0:
        for line in out.strip().split("\n"):
            if line.strip():
                total_pods += 1
                if "Running" in line and "CrashLoopBackOff" not in line:
                    healthy_pods += 1
                else:
                    unhealthy_pods += 1
    
    metrics["pods_healthy"] = healthy_pods
    metrics["pods_unhealthy"] = unhealthy_pods
    
    if unhealthy:
        log("info", f"Found {len(unhealthy)} unhealthy pods")
        for pod in unhealthy[:5]:  # Limit to 5 per reconcile
            issue = f"Pod {pod['namespace']}/{pod['name']} status: {pod['status']}"
            log("info", f"Analyzing: {issue}")
            analysis = analyze_with_ollama(issue, f"Namespace: {pod['namespace']}, Pod: {pod['name']}, Status: {pod['status']}")
            if analysis:
                log("info", f"AI Analysis: {analysis[:200]}")
    
    if crashloop:
        log("info", f"Found {len(crashloop)} CrashLoopBackOff pods")
        for pod in crashloop[:3]:
            issue = f"Pod {pod['namespace']}/{pod['name']} in CrashLoopBackOff"
            log("info", f"Analyzing: {issue}")
            # Get pod logs for context
            rc, logs, _ = run_cmd(["kubectl", "logs", "-n", pod["namespace"], pod["name"], "--tail=20"])
            analysis = analyze_with_ollama(issue, f"Recent logs:\n{logs[:2000]}")
            if analysis:
                log("info", f"AI Analysis: {analysis[:200]}")
    
    ready = True
    log("info", f"Reconcile complete: {healthy_pods} healthy, {unhealthy_pods} unhealthy pods")

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            code = 200 if startup_complete else 503
            body = json.dumps({"status": "ok" if startup_complete else "starting", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/ready":
            code = 200 if ready else 503
            body = json.dumps({"status": "ready" if ready else "not ready", "reconcile_count": metrics["reconcile_total"], "last_reconcile": last_reconcile})
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
                f"# HELP opendesk_dev_agent_reconcile_total Total reconciliations",
                f"# TYPE opendesk_dev_agent_reconcile_total counter",
                f"opendesk_dev_agent_reconcile_total {metrics['reconcile_total']}",
                f"# HELP opendesk_dev_agent_errors_total Total errors",
                f"# TYPE opendesk_dev_agent_errors_total counter",
                f"opendesk_dev_agent_errors_total {metrics['errors_total']}",
                f"# HELP opendesk_dev_agent_pods_healthy Healthy pods",
                f"# TYPE opendesk_dev_agent_pods_healthy gauge",
                f"opendesk_dev_agent_pods_healthy {metrics['pods_healthy']}",
                f"# HELP opendesk_dev_agent_pods_unhealthy Unhealthy pods",
                f"# TYPE opendesk_dev_agent_pods_unhealthy gauge",
                f"opendesk_dev_agent_pods_unhealthy {metrics['pods_unhealthy']}",
                f"# HELP opendesk_dev_agent_ai_analysis_total Total AI analyses",
                f"# TYPE opendesk_dev_agent_ai_analysis_total counter",
                f"opendesk_dev_agent_ai_analysis_total {metrics['ai_analysis_total']}",
                f"# HELP opendesk_dev_agent_ai_analysis_errors Total AI analysis errors",
                f"# TYPE opendesk_dev_agent_ai_analysis_errors counter",
                f"opendesk_dev_agent_ai_analysis_errors {metrics['ai_analysis_errors']}",
            ]
            self.wfile.write("\n".join(lines).encode())
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
    
    log("info", f"=== {OPERATOR_NAME} v2.1.0 (Python) starting ===")
    log("info", f"Watch namespaces: {WATCH_NAMESPACES}")
    log("info", f"Ollama URL: {OLLAMA_URL}")
    log("info", f"Ollama model: {OLLAMA_MODEL}")
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
