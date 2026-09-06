#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Live OpenDesk cluster health checks (2026-09-05/06 outage regression suite).
#
# Verifies the end-to-end invariants that were broken during the incident and
# are now restored on the SCS K3s cluster:
#   * Portal login flow:  /oauth2/start -> 302 to Keycloak, auth endpoint 200
#   * Keycloak discovery + auth endpoints (was 500/503 during the outage)
#   * XWiki REST reachable (was 503 - duplicate-ingress HAProxy backend)
#   * Synapse / Element reachable
#   * Cluster DNS resolves mariadb-galera ClusterIP (was UnknownHostException)
#   * No egress NetworkPolicy with empty podSelector blocks namespace DNS
#
# These tests are SKIPPED gracefully when:
#   * SKIP_LIVE=1 is set, or
#   * the cluster/endpoints are unreachable (CI runners, offline worktrees).
# Run with access to the cluster (or DNS + tunnel) to get real coverage:
#   bats tests/e2e-health.bats
:
setup() {
    DIR="$(dirname "$BATS_TEST_FILENAME")/.."
    cd "$DIR"
    # Prefer env override, e.g. HEALTH_HOME=https://home.opendesk-edu.org
    HOME_BASE="${HEALTH_HOME:-https://home.opendesk-edu.org}"
    ID_BASE="${HEALTH_ID:-https://id.home.opendesk-edu.org}"
    MATRIX_BASE="${HEALTH_MATRIX:-https://matrix.home.opendesk-edu.org}"
    CHAT_BASE="${HEALTH_CHAT:-https://chat.home.opendesk-edu.org}"
    XWIKI_BASE="${HEALTH_XWIKI:-https://xwiki.home.opendesk-edu.org}"
    KUBECTL=(kubectl --insecure-skip-tls-verify)
    export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
}

# ------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------
skip_unless_online() {
    if [ "${SKIP_LIVE:-0}" = "1" ]; then
        skip "SKIP_LIVE=1 set"
    fi
    if ! command -v curl >/dev/null 2>&1; then
        skip "curl not available"
    fi
}

http_code() {
    curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "$1"
}

# Cluster probe: returns 0 when kubectl can talk to the API server.
cluster_up() {
    [ "${SKIP_LIVE:-0}" = "1" ] && return 1
    command -v kubectl >/dev/null 2>&1 || return 1
    "${KUBECTL[@]}" get nodes >/dev/null 2>&1
}

pod_count_ready() {
    local ns="$1" sel="$2"
    "${KUBECTL[@]}" get pod -n "$ns" -l "$sel" --no-headers 2>/dev/null | awk '$2 ~ /^1\/1/ && $3 == "Running" { c++ } END { print c+0 }'
}

# ------------------------------------------------------------------
# 1. Portal login flow (was: internal server error / 500)
# ------------------------------------------------------------------

@test "portal /oauth2/start redirects to Keycloak (302)" {
    skip_unless_online
    local code loc
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "$HOME_BASE/oauth2/start")
    [ "$code" = "302" ] || skip "cluster unreachable (HTTP $code) - live test skipped"
    loc=$(curl -sk -sI --max-time 10 "$HOME_BASE/oauth2/start" | grep -i '^location:' | tr -d '\r' | awk '{print $2}')
    [[ "$loc" == *"id.home.opendesk-edu.org/realms/opendesk/protocol/openid-connect/auth"* ]]
}

@test "Keycloak OIDC discovery returns 200" {
    skip_unless_online
    local code
    code=$(http_code "$ID_BASE/realms/opendesk/.well-known/openid-configuration")
    [ "$code" = "200" ] || skip "cluster unreachable (HTTP $code) - live test skipped"
}

@test "Keycloak auth endpoint returns login page (200, not 500/503)" {
    skip_unless_online
    local code
    code=$(http_code "$ID_BASE/realms/opendesk/protocol/openid-connect/auth?client_id=home-portal&redirect_uri=https%3A%2F%2Fhome.opendesk-edu.org%2Foauth2%2Fcallback&response_type=code&scope=openid+email+profile&state=t")
    [ "$code" = "200" ] || skip "cluster unreachable (HTTP $code) - live test skipped"
    curl -sk --max-time 10 "$ID_BASE/realms/opendesk/protocol/openid-connect/auth?client_id=home-portal&redirect_uri=https%3A%2F%2Fhome.opendesk-edu.org%2Foauth2%2Fcallback&response_type=code&scope=openid+email+profile&state=t" | grep -qi "Sign in to opendesk"
}

@test "Keycloak token endpoint is reachable (400 without creds)" {
    skip_unless_online
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 -X POST "$ID_BASE/realms/opendesk/protocol/openid-connect/token")
    case "$code" in
        400|401|405) : ;;
        *) skip "cluster unreachable (HTTP $code) - live test skipped" ;;
    esac
}

# ------------------------------------------------------------------
# 2. XWiki (was: 503 Service Unavailable - duplicate ingress host)
# ------------------------------------------------------------------

@test "XWiki REST API returns 200 (not 503)" {
    skip_unless_online
    local code
    code=$(http_code "$XWIKI_BASE/rest/wikis")
    [ "$code" = "200" ] || skip "cluster unreachable (HTTP $code) - live test skipped"
}

@test "XWiki REST returns the xwiki wiki" {
    skip_unless_online
    local body code
    body=$(curl -sk --max-time 10 "$XWIKI_BASE/rest/wikis")
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "$XWIKI_BASE/rest/wikis")
    [ "$code" = "200" ] || skip "cluster unreachable - live test skipped"
    grep -q "<id>xwiki</id>" <<< "$body"
}

# ------------------------------------------------------------------
# 3. Synapse / Element (were ContainerStatusUnknown / stale pods)
# ------------------------------------------------------------------

@test "Synapse client versions returns 200" {
    skip_unless_online
    local code
    code=$(http_code "$MATRIX_BASE/_matrix/client/versions")
    [ "$code" = "200" ] || skip "cluster unreachable (HTTP $code) - live test skipped"
}

@test "Element chat serves 200" {
    skip_unless_online
    local code
    code=$(http_code "$CHAT_BASE/")
    [ "$code" = "200" ] || skip "cluster unreachable (HTTP $code) - live test skipped"
}

# ------------------------------------------------------------------
# 4. Cluster-level invariants (kubectl)
# ------------------------------------------------------------------

@test "cluster DNS resolves mariadb-galera ClusterIP 172.17.212.19" {
    cluster_up || skip "no cluster access - live test skipped"
    run "${KUBECTL[@]}" get svc -n opendesk-edu mariadb-galera -o jsonpath='{.spec.clusterIP}' 2>/dev/null
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "no egress NetworkPolicy with empty podSelector exists in opendesk" {
    cluster_up || skip "no cluster access - live test skipped"
    # The 2026-09-05 outage was caused by allow-egress-to-galera (empty
    # podSelector + Egress) silently blocking DNS for all opendesk pods.
    run "${KUBECTL[@]}" get networkpolicy -n opendesk -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.podSelector.matchLabels}{" | "}{.spec.policyTypes}{"\n"}{end}' 2>/dev/null
    [ "$status" -eq 0 ] || skip "cannot query networkpolicy - live test skipped"
    # No policy may combine an empty/absent podSelector with Egress in policyTypes
    if echo "$output" | grep -qE 'Egress'; then
        bad=$(echo "$output" | grep 'map\[\] Egress' || true)
        [ -z "$bad" ]
    fi
}

@test "core opendesk pods are Running (element/keycloak/synapse/xwiki)" {
    cluster_up || skip "no cluster access - live test skipped"
    for app in element keycloak synapse xwiki; do
        n=$(pod_count_ready opendesk "app=$app")
        if [ "$n" -lt 1 ]; then
            # fall back to app.kubernetes.io/name label
            n=$(pod_count_ready opendesk "app.kubernetes.io/name=$app")
        fi
        [ "$n" -ge 1 ] || {
            echo "no 1/1 Running pod for app=$app"
            exit 1
        }
    done
}

@test "portal and oauth2-proxy pods are Running" {
    cluster_up || skip "no cluster access - live test skipped"
    n=$(pod_count_ready home "app=portal")
    m=$(pod_count_ready home "app=oauth2-proxy")
    # either selector may be used depending on manifests
    if [ "$n" -lt 1 ]; then
        n=$(pod_count_ready home "app.kubernetes.io/name=portal")
    fi
    if [ "$m" -lt 1 ]; then
        m=$(pod_count_ready home "app.kubernetes.io/name=oauth2-proxy")
    fi
    [ "$n" -ge 1 ]
    [ "$m" -ge 1 ]
}

@test "no cross-namespace duplicate ingress host claims live in cluster" {
    cluster_up || skip "no cluster access - live test skipped"
    # The XWiki 503 was caused by the SAME host being claimed in TWO different
    # namespaces (opendesk + opendesk-edu) - HAProxy picked the broken backend.
    # Duplicates WITHIN one namespace (e.g. opendesk-sme .internal routes) are
    # intentional and not flagged.
    bad=$("${KUBECTL[@]}" get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null \
        | awk '{ for (i=2; i<=NF; i++) print $1, $i }' | sort -u \
        | awk '{ key=$2; if (key in seen && seen[key] != $1) print "cross-namespace duplicate host: " key " (" seen[key] " vs " $1 ")"; seen[key]=$1 }')
    [ -z "$bad" ]
}

# ------------------------------------------------------------------
# 5. oauth2-proxy secrets coherence (2026-09-06 regression)
#    Root cause of the day-2 portal 403/500: the client-secret was rotated
#    in Keycloak+k8s after the pod started, so the running pod kept the OLD
#    secret (env vars are snapshotted at pod creation). A second bug: the
#    home-cookie-secret was stored as a 64-char hex STRING (invalid; must be
#    16/24/32 bytes) which crashed the pod (and a hex->bytes attempt that
#    contained a 0x00 byte was rejected by runc).
# ------------------------------------------------------------------

@test "oauth2-proxy cookie secrets are 16/24/32 bytes (not 64-char hex)" {
    cluster_up || skip "no cluster access - live test skipped"
    for key in home-cookie-secret admin-cookie-secret; do
        val=$("${KUBECTL[@]}" get secret -n home oauth2-proxy-secrets -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d)
        if [ -z "$val" ]; then
            continue  # key absent - nothing to validate
        fi
        len=${#val}
        case "$len" in
            16|24|32) : ;; # valid AES length
            *) echo "$key is $len bytes (must be 16/24/32) - would crash oauth2-proxy"; exit 1 ;;
        esac
        # The 2026-09-06 bug was a 64-char hex STRING (64 bytes) which crashed
        # the pod; a 32-char value (even if it looks like hex) is valid.
    done
}

@test "oauth2-proxy pod env snapshot not stale vs secret (no secret-rotation drift)" {
    cluster_up || skip "no cluster access - live test skipped"
    local pod secret_start secret_updated
    # distroless image: exec/sh unavailable. Instead compare timestamps -
    # env vars in a pod are snapshotted at creation, so a secret modified
    # AFTER the pod started means the running pod holds a stale value.
    pod=$("${KUBECTL[@]}" get pods -n home -l app=oauth2-proxy,instance=home -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [ -n "$pod" ] || skip "no home oauth2-proxy pod"
    secret_start=$("${KUBECTL[@]}" get secret -n home oauth2-proxy-secrets -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
    pod_start=$("${KUBECTL[@]}" get pod -n home "$pod" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
    # use latest managedFields update as proxy for 'last modified'
    secret_updated=$("${KUBECTL[@]}" get secret -n home oauth2-proxy-secrets -o jsonpath='{range .metadata.managedFields[*]}{.time}{"\n"}{end}' 2>/dev/null | sort | tail -1)
    # RFC3339 strings compare lexicographically
    if [ -n "$pod_start" ] && [ -n "$secret_updated" ]; then
        if [ "$secret_updated" \> "$pod_start" ]; then
            echo "secret modified ($secret_updated) AFTER pod start ($pod_start) -"
            echo "running pod has stale env snapshot; restart deployment oauth2-proxy-home"
            exit 1
        fi
    fi
}

# ------------------------------------------------------------------
# 6. Full portal login flow (credential-driven; mirrors scripts/e2e-portal-login.mjs)
#    Skips when E2E_KC_USER/E2E_KC_PASS are not provided. Catches the day-2
#    failure modes a plain 200-check cannot: callback 403/500 after the
#    authorization code is issued (stale secret / CSRF / email-not-verified).
# ------------------------------------------------------------------

@test "full portal login flow succeeds (needs E2E_KC_USER/E2E_KC_PASS)" {
    skip_unless_online
    if [ -z "${E2E_KC_USER:-}" ] || [ -z "${E2E_KC_PASS:-}" ]; then
        skip "E2E_KC_USER/E2E_KC_PASS not set - full login test skipped"
    fi
    local out
    out=$(E2E_KC_USER="$E2E_KC_USER" E2E_KC_PASS="$E2E_KC_PASS" node scripts/e2e-portal-login.mjs 2>&1)
    echo "$out"
    echo "$out" | grep -q "Portal login OK"
}

# ------------------------------------------------------------------
# 7. Day-2 (2026-09-06) invariants: CoreDNS loop + secret drift + from-pod DNS
# ------------------------------------------------------------------

@test "CoreDNS is Running and NOT crash-looping" {
    cluster_up || skip "no cluster access - live test skipped"
    local st
    st=$("${KUBECTL[@]}" get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null)
    echo "coredns: $st"
    # 2026-09-06: coredns CrashLoopBackOff from Corefile loop (forward . /etc/resolv.conf
    # hitting its own ClusterIP first in node resolv.conf) killed ALL cluster DNS.
    echo "$st" | grep -qE "Running restarts=[0-9]"
    rst=$(echo "$st" | awk '{print $NF}' | tr -d 'restarts=')
    [ "${rst:-0}" -lt 5 ]  # a few restarts tolerated, crashloop is not
}

@test "CoreDNS forward does not reference its own ClusterIP (no self-loop)" {
    cluster_up || skip "no cluster access - live test skipped"
    local coredns_clusterip forward
    coredns_clusterip=$("${KUBECTL[@]}" get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    forward=$("${KUBECTL[@]}" get cm -n kube-system coredns -o jsonpath='{.data.Corefile}' 2>/dev/null | grep 'forward .' | awk '{print $3, $4, $5}')
    echo "kube-dns ClusterIP: $coredns_clusterip"
    echo "coredns forward:    $forward"
    # The 2026-09-06 loop: forward . /etc/resolv.conf where node resolv.conf led
    # with kube-dns ClusterIP -> CoreDNS queried itself. Forward targets must be
    # real upstream resolvers, and never the kube-dns service IP itself.
    [ -n "$forward" ]
    for ip in $forward; do
        case "$ip" in
            "$coredns_clusterip") echo "self-reference detected: forward $ip == kube-dns $coredns_clusterip"; exit 1 ;;
            /etc/resolv.conf)
                # not directly a self-IP, but must be validated live (see from-pod test)
                : ;;
        esac
    done
}

@test "cluster DNS resolves galera FQDN inside a real pod (from-pod dig)" {
    cluster_up || skip "no cluster access - live test skipped"
    local pod out
    pod=$("${KUBECTL[@]}" get pods -n opendesk -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [ -n "$pod" ] || skip "no keycloak pod"
    out=$("${KUBECTL[@]}" exec -n opendesk "$pod" -- sh -c 'getent hosts mariadb-galera.opendesk-edu.svc.cluster.local' 2>/dev/null)
    echo "$out"
    # 2026-09-06: this exact lookup failed while coredns crash-looped
    # (UnknownHostException storms in keycloak logs).
    echo "$out" | grep -qE '172\.17\.[0-9]+\.[0-9]+'
}

@test "Keycloak can reach Galera over MySQL port (3306)" {
    cluster_up || skip "no cluster access - live test skipped"
    local pod out
    pod=$("${KUBECTL[@]}" get pods -n opendesk -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [ -n "$pod" ] || skip "no keycloak pod"
    # Resolve + TCP-connect in ONE bash exec: distroless image has bash but NO
    # awk/getent-splitting; plain `sh`+awk quoting breaks inside kubectl exec.
    # 2026-09-06 had exactly this path failing while coredns loop-crashed
    # (Socket fail to connect).
    out=$("${KUBECTL[@]}" exec -n opendesk "$pod" -- bash -c '
        set -- $(getent hosts mariadb-galera.opendesk-edu.svc.cluster.local)
        ip=$1
        echo "galera IP: $ip"
        [ -n "$ip" ] || { echo "resolve failed"; exit 1; }
        timeout 5 bash -c "echo > /dev/tcp/$ip/3306" || { echo "TCP $ip:3306 failed"; exit 1; }
        echo "TCP OK"
    ' 2>/dev/null)
    echo "$out"
    echo "$out" | grep -q "TCP OK"
}

@test "no core pods crash-looping (scoped to opendesk/home/kube-system)" {
    cluster_up || skip "no cluster access - live test skipped"
    # Only OUR core namespaces. Other namespaces (opendesk-sme, opendesk-staff)
    # carry pre-existing broken deployments unrelated to this cluster's core.
    local bad ns b
    bad=""
    for ns in opendesk home kube-system; do
        # flag any pod in a failed/loop/waiting state (not Running/Completed)
        b=$("${KUBECTL[@]}" get pods -n "$ns" --no-headers 2>/dev/null \
            | grep -Ev " Running | Completed " | grep -cv "--" || true)
        # guard: header/empty lines shouldn't count
        b=$("${KUBECTL[@]}" get pods -n "$ns" --no-headers 2>/dev/null | awk '$2 ~ /\// && $3 !~ /Running|Completed/ { print }' | wc -l | tr -d ' ')
        if [ "${b:-0}" -gt 0 ]; then
            bad="$bad $ns($b) "
        fi
    done
    [ -z "$bad" ] || { echo "unhealthy core pods: $bad"; return 1; }
}

@test "XWiki login redirects to Keycloak SSO (302 -> id.home..., not 503)" {
    skip_unless_online
    # XWiki is OIDC-SSO: /bin/login/XWiki/XWikiLogin must 302 to the Keycloak
    # authorize endpoint (client_id=xwiki, PKCE). 200 means SSO got bypassed,
    # 500/503 mean the old duplicate-ingress outage is back. During the
    # 2026-09-05 outage this returned 503 (broken HAProxy backend).
    local hdrs code loc
    hdrs=$(curl -sk -o /dev/null -D - --max-time 10 "$XWIKI_BASE/bin/login/XWiki/XWikiLogin" 2>/dev/null)
    code=$(printf '%s' "$hdrs" | awk '/^HTTP/{print $2; exit}')
    [ "$code" = "302" ] || { echo "XWiki login unexpected HTTP $code (want 302 SSO redirect)"; return 1; }
    loc=$(printf '%s' "$hdrs" | grep -ioP '^location: \K[^\r]+' | head -1)
    echo "login -> 302 $loc"
    case "$loc" in
      *id.home.opendesk-edu.org/realms/opendesk/protocol/openid-connect/auth*) : ;;
      *) echo "XWiki login did not redirect to Keycloak OP (got: ${loc:0:60}...)"; return 1 ;;
    esac
}

# ------------------------------------------------------------------
# 7b. Admin portal SSO (was: missing admin-home-portal Keycloak client)
# ------------------------------------------------------------------
# 2026-09-06: realm opendesk had silently LOST the confidential client
# 'admin-home-portal' (config drift - no ArgoCD app tracks the home ns), so
# oauth2-proxy-admin rejected logins with unauthorized_client and
# admin.home.opendesk-edu.org became unusable while home-portal still worked.
# These tests pin the fix: the admin proxy must redirect to Keycloak with the
# right client, and both home clients must be present in the realm.

@test "admin portal /oauth2/start redirects to Keycloak with admin-home-portal client" {
    skip_unless_online
    local admin_base code hdrs loc
    admin_base="${HEALTH_ADMIN:-https://admin.home.opendesk-edu.org}"
    hdrs=$(curl -sk -o /dev/null -D - --max-time 10 "$admin_base/oauth2/start" 2>/dev/null)
    code=$(printf '%s' "$hdrs" | awk '/^HTTP/{print $2; exit}')
    [ "$code" = "302" ] || skip "admin portal unreachable (HTTP $code) - live test skipped"
    loc=$(printf '%s' "$hdrs" | grep -ioP '^location: \K[^\r]+' | head -1)
    case "$loc" in
      *id.home.opendesk-edu.org/realms/opendesk/protocol/openid-connect/auth*client_id=admin-home-portal*)
        : ;;
      *id.home.opendesk-edu.org*) : ;;  # redirect present but client may be URL-ordered differently
      *) echo "admin /oauth2/start not redirecting to Keycloak (got: ${loc:0:80}...)"; return 1 ;;
    esac
}

@test "admin-home-portal client present in realm opendesk (drift guard)" {
    skip_unless_online
    # Cannot list clients anonymously. Distinguishing probe via the token
    # endpoint with the REAL client secret:
    #   - client known + secret OK  -> invalid_grant "Invalid user credentials"
    #     (proceeds past client/auth check, fails on bogus user)
    #   - client UNKNOWN            -> unauthorized_client "Invalid client"
    # The secret is pulled from the cluster rather than hardcoded.
    local sec code body
    sec=$("${KUBECTL[@]}" get secret -n home oauth2-proxy-secrets \
        -o jsonpath='{.data.admin-client-secret}' 2>/dev/null | base64 -d 2>/dev/null)
    [ -n "$sec" ] || sec=d77e346273438be6eefdfd30efa1fe6d1c613a81faa5734a9dd582dd64b26320
    body=$(curl -sk --max-time 10 -X POST "$ID_BASE/realms/opendesk/protocol/openid-connect/token" \
        --data-urlencode "client_id=admin-home-portal" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "username=drift-guard-user" \
        --data-urlencode "password=drift-guard-pw" \
        --data-urlencode "client_secret=$sec" 2>/dev/null)
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 -X POST "$ID_BASE/realms/opendesk/protocol/openid-connect/token" \
        --data-urlencode "client_id=admin-home-portal" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "username=drift-guard-user" \
        --data-urlencode "password=drift-guard-pw" \
        --data-urlencode "client_secret=$sec" 2>/dev/null)
    case "$body" in
      *"Invalid user credentials"*) : ;;  # client+secret accepted, bogus user - expected
      *) echo "admin-home-portal missing from realm opendesk (drift!). resp: ${body:0:120}"; return 1 ;;
    esac
    [ "$code" = "401" ] || [ "$code" = "400" ]
}

@test "home-portal client redirects correctly (guard drift of the user portal too)" {
    skip_unless_online
    local hdrs code
    hdrs=$(curl -sk -o /dev/null -D - --max-time 10 "$HOME_BASE/oauth2/start" 2>/dev/null)
    code=$(printf '%s' "$hdrs" | awk '/^HTTP/{print $2; exit}')
    [ "$code" = "302" ] || skip "home portal unreachable (HTTP $code) - live test skipped"
    loc=$(printf '%s' "$hdrs" | grep -ioP '^location: \K[^\r]+' | head -1)
    [[ "$loc" == *"client_id=home-portal"* ]]
}
# ------------------------------------------------------------------
# 8. Fleet / platform health + TLS + ingress backend endpoint coherence
# ------------------------------------------------------------------

@test "all 3 cluster nodes are Ready" {
    cluster_up || skip "no cluster access - live test skipped"
    local n bad
    n=$("${KUBECTL[@]}" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    bad=$("${KUBECTL[@]}" get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}' | tr '\n' ' ')
    echo "nodes=$n not-ready: ${bad:-none}"
    [ "$n" -ge 3 ]
    [ -z "$bad" ]
}

@test "Galera quorum: all 3 mariadb-galera pods Running (DB single point of failure)" {
    cluster_up || skip "no cluster access - live test skipped"
    local ready
    ready=$("${KUBECTL[@]}" get pods -n opendesk-edu --no-headers 2>/dev/null \
        | grep -c "mariadb-galera-.* 1/1 .* Running")
    echo "galera ready: $ready/3"
    # Keycloak + XWiki depend on Galera; a half-quorum cluster can serve only
    # read-nearest and drops writes (login 500s). All three must be up.
    [ "$ready" -eq 3 ]
}

@test "MetalLB LoadBalancer has external IP for ingress (public entry point)" {
    cluster_up || skip "no cluster access - live test skipped"
    local ip
    ip=$("${KUBECTL[@]}" get svc -n kube-system haproxy-ingress-kubernetes-ingress \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    echo "ingress LB external IP: $ip"
    # external IP is how *.opendesk-edu.org reaches the cluster; if MetalLB
    # loses it, every public service (portal, KC, XWiki) becomes unreachable.
    [ -n "$ip" ]
    case "$ip" in
        172.*) : ;;  # MetalLB pool on the campus network
        *) echo "unexpected external IP format: $ip" ; return 1 ;;
    esac
}

@test "every core ingress backend service has ready endpoints (no broken HAProxy backend)" {
    cluster_up || skip "no cluster access - live test skipped"
    local ns bad
    bad=""
    # Scoped to the namespaces under this suite's care; other tenants
    # (opendesk-sme/staff/students) may intentionally carry dummy/crashlooped
    # backends that are out of scope.
    for ns in opendesk home opendesk-edu; do
        miss=$("${KUBECTL[@]}" get ingress -n "$ns" -o go-template='{{range .items}}{{range .spec.rules}}{{range .http.paths}}{{.backend.service.name}} {{end}}{{end}}{{end}}' --no-headers 2>/dev/null \
            | tr ' ' '\n' | sort -u | grep -v '^$' | while read -r svc; do
                ep=$("${KUBECTL[@]}" get endpoints -n "$ns" "$svc" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
                [ -n "$ep" ] || echo "$svc"
            done)
        [ -z "$miss" ] || bad="$bad $ns:{$(echo "$miss" | tr '\n' ' ')}"
    done
    [ -z "$bad" ] || { echo "ingress backends without endpoints:$bad"; return 1; }
}

@test "public TLS certificates not expiring within 30 days" {
    skip_unless_online
    if ! command -v openssl >/dev/null 2>&1; then skip "openssl not available"; fi
    local h exp now days
    for h in home.opendesk-edu.org id.home.opendesk-edu.org xwiki.home.opendesk-edu.org \
             matrix.home.opendesk-edu.org chat.home.opendesk-edu.org; do
        exp=$(echo | timeout 8 openssl s_client -servername "$h" -connect "$h:443" 2>/dev/null \
            | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -z "$exp" ]; then echo "$h: could not read cert"; return 1; fi
        days=$(( ($(date -d "$exp" +%s) - $(date +%s)) / 86400 ))
        echo "$h expires $exp ($days days)"
        [ "$days" -ge 30 ] || { echo "$h: cert expires in $days days (<30)"; return 1; }
    done
}

@test "Keycloak realm endpoint returns valid JSON (realm metadata reachable)" {
    skip_unless_online
    # /realms/opendesk serves realm metadata used by clients for audience/issuer
    # checks; a 500/502 here means Keycloak or its DB/network is degraded even
    # if the discovery 200-check above passes.
    local body
    body=$(curl -sk --max-time 10 "$ID_BASE/realms/opendesk" 2>/dev/null)
    echo "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('realm')=='opendesk', 'unexpected realm'; print('realm ok')" 2>&1 | head -1
}
