#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Post-restore / acceptance verification for the ICS + OIDC foundation
# (plan/2026-08-15-intercom-oidc-plan.md).
#
# Checks, in order:
#   1. cluster reachability (kubectl)
#   2. all workloads Ready (opendesk + opendesk-edu)
#   3. ArgoCD applications Synced
#   4. Keycloak realm `opendesk` OIDC discovery 200
#   5. ICS /health + /oc/ OIDC redirect (PKCE params)
#   6. Element banner config served
#   7. Synapse OIDC config present in the rendered homeserver.yaml
#   8. Redis auth (AUTH round-trip via the ICS env or direct PING w/ password)
#
# Usage: bash scripts/verify-ics.sh   (kubectl context scs-k3s via tunnel)

set -euo pipefail

PASS=0
FAIL=0
step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }

step "1. Cluster reachability"
if kubectl get ns opendesk >/dev/null 2>&1; then
  ok "kubectl reachable ($(kubectl version -o json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])' 2>/dev/null || echo unknown))"
else
  bad "kubectl cannot reach the cluster — is the tunnel up? (systemctl --user start scs-k3s-tunnel.service)"
  exit 1
fi

step "2. Workloads Ready"
NOTREADY=$(kubectl get pods -A 2>/dev/null | awk 'NR>1 && $3 != "Running" && $3 != "Completed" && $3 != "Succeeded" && $4 != "1/1" && $4 != "0/0" && $4 !~ /^[0-9]+\/[0-9]+$/ {print} ' | head -10)
# simpler: rely on Ready column
NOTREADY=$(kubectl get pods -n opendesk -n opendesk-edu -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].ready}{"\n"}{end}' 2>/dev/null | grep -v 'true' | head -5 || true)
if [ -z "$NOTREADY" ]; then
  ok "all containers ready"
else
  bad "not-ready pods:"
  echo "$NOTREADY" | sed 's/^/    /'
fi

step "3. ArgoCD applications"
kubectl get app -n argocd -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null | while read -r app sync health; do
  [ "$app" = "APP" ] && continue
  if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
    ok "$app: $sync/$health"
  else
    bad "$app: $sync/$health"
  fi
done

step "4. Keycloak realm opendesk OIDC discovery"
KC_POD=$(kubectl get pods -n opendesk -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$KC_POD" ]; then
  code=$(kubectl exec -n opendesk "$KC_POD" -- sh -c 'exec 3<>/dev/tcp/127.0.0.1/8080; printf "GET /realms/opendesk/.well-known/openid-configuration HTTP/1.0\r\nHost: x\r\nConnection: close\r\n\r\n" >&3; head -1 <&3' 2>/dev/null | awk '{print $2}' || true)
  if [ "$code" = "200" ]; then ok "realm discovery 200 (in-cluster)"; else bad "realm discovery: $code (expected 200)"; fi
else
  bad "keycloak pod not found"
fi

step "5. Intercom-Service endpoints"
ICS=$(kubectl get pods -n opendesk-edu -l app=intercom-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$ICS" ]; then
  h=$(kubectl exec -n opendesk-edu "$ICS" -- wget -qO- http://127.0.0.1:8080/health 2>/dev/null || true)
  case "$h" in *'"status":"ok"'*) ok "/health -> $h";; *) bad "/health -> $h";; esac
  loc=$(kubectl exec -n opendesk-edu "$ICS" -- wget -qS -O /dev/null http://127.0.0.1:8080/oc/ 2>&1 | grep -i '^Location:' | head -1 || true)
  case "$loc" in
    *"client_id=opendesk-intercom"*"code_challenge_method=S256"*) ok "/oc/ -> OIDC auth redirect (PKCE)";;
    *) bad "/oc/ -> $loc";;
  esac
else
  bad "intercom-service pod not found"
fi

step "6. Element banner"
ELEM=$(kubectl get pods -n opendesk -l app=element -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$ELEM" ]; then
  b=$(kubectl exec -n opendesk "$ELEM" -- grep -o 'ics_silent_url[^,]*' /app/config.json 2>/dev/null | head -1 || true)
  case "$b" in *intercom.home.opendesk-edu.org/silent*) ok "banner: $b";; *) bad "banner: $b";; esac
else
  bad "element pod not found"
fi

step "7. Synapse OIDC"
SYN=$(kubectl get pods -n opendesk -l app=synapse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$SYN" ]; then
  o=$(kubectl exec -n opendesk "$SYN" -- grep -A3 'oidc_config' /config/homeserver.yaml 2>/dev/null | head -4 || true)
  if [ -n "$o" ]; then ok "oidc_config present"; else bad "no oidc_config in homeserver.yaml"; fi
else
  bad "synapse pod not found"
fi

step "8. Redis AUTH"
REDIS_PW=$(kubectl get secret redis -n opendesk-edu -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -n "$REDIS_PW" ]; then
  r=$(kubectl exec -n opendesk-edu deploy/redis -- redis-cli -a "$REDIS_PW" PING 2>/dev/null | tail -1 || true)
  case "$r" in PONG) ok "redis AUTH PING -> PONG";; *) bad "redis PING -> $r";; esac
else
  bad "redis secret not readable"
fi

printf '\n\033[1mResult: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
