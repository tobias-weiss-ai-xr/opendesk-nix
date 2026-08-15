# Intercom-Service (ICS) + OIDC Foundation — Execution Plan

**Date:** 2026-08-15 · **Project:** opendesk-nix (SCS K3s cluster) · **Status:** planned

> This plan is the CONTRACT for the taskfleet run. Each section maps 1:1 to a
> task (IC-1 … IC-7). Agents MUST read their section fully and implement exactly
> what it specifies. Cross-cutting conventions live in §0; appendices give the
> reference data (secrets, env vars, cluster facts).

---

## §0 Cross-cutting conventions (ALL tasks)

### Repo layout
- Everything lives in `opendesk-nix`. Source of truth for the SCS cluster.
- Service definitions: `platform/kubernetes/services/<svc>.nix`
- Environment (SCS): `platform/kubernetes/environments/scs/default.nix`
- Aggregator + sealed-secrets machinery: `platform/kubernetes/scs/default.nix`
- Sealed-secrets public cert: `platform/kubernetes/sealed-secrets-pub.pem`
- CI lint: `scripts/ci/check-no-latest-tag.sh` + `scripts/ci/latest-tag-baseline.txt`

### The k8s builder lib (`platform/nix/k8s.nix`)
`lib` passed to every service file is `lib // k8s`. Available builders (check
`platform/nix/k8s.nix` for exact signatures before use):

- `lib.deployment { inherit name image tag port resources labels; env = [...]; volumeMounts = [...]; volumes = [...]; initContainers = [...]; securityContext = {...}; podSecurityContext = {...}; liveness = lib.mkProbe { type = "http"; inherit port; path = "/health"; ... }; readiness = ...; namespace = env.namespaceEdu; strategyType = "Recreate"; }`
- `lib.service { inherit name port labels; namespace = ...; }`
- `lib.ingressWithCert { inherit name port; host = "x.home.opendesk-edu.org"; inherit (env.ingress) className; tlsSecretName = env.tls.secretName; annotations = env.ingress.annotations; namespace = ...; }`
- `lib.secret { name = "..."; namespace = ...; inherit labels; stringData = { "key" = "value"; }; }` — **Secrets with `kind = "Secret"` are automatically converted to SealedSecrets at build time** (see §0 “Sealed secrets”).
- `lib.job { ... }` — check k8s.nix; if absent, build the Job object with `lib.mkDeployment`-style helpers or a raw attrset `{ apiVersion = "batch/v1"; kind = "Job"; metadata = {...}; spec = {...}; }` serialized via `builtins.toJSON` by the aggregator (see §1).
- `lib.mkProbe { type = "http"; inherit port; path = "/health"; initialDelaySeconds; periodSeconds; failureThreshold; }`
- `lib.mkLabels { inherit name; }`

### Sealed secrets (do NOT change the mechanism)
`scs/default.nix` `serialize` turns any `kind = "Secret"` into a `SealedSecret`
using `kubeseal --cert platform/kubernetes/sealed-secrets-pub.pem`. Consequences:
- **Never** put a plaintext `Secret` in the output — only `lib.secret` objects.
- Secret VALUES are `-change-me` style literals in `stringData` (consistent with
  the rest of the repo: e.g. `opencloud-secret-change-me`). They are placeholders,
  rotated via the sealed-secrets flow. Do NOT invent randomness.
- New `lib.secret` entries automatically appear in the sealed-secrets manifest.

### Wiring a new service into `scs/default.nix` (ALL service tasks)
1. In the `let` block, next to the other `import`s:
   ```nix
   redis = import ../services/redis.nix {
     lib = k8sLib;
     inherit env;
   };
   ```
2. Add `++ redis` to `allManifests` (after the existing `++ opencloud` line).
3. Add a manifest emitter block in `manifestDir` (mirror the existing ones):
   ```nix
   # Redis
   ${builtins.concatStringsSep "\n" (
     map (m: ''
       cat >> $out/43-redis.yaml << 'YAMLEOF'
       ---
       ${serialize m}
       YAMLEOF
     '') redis
   )}
   ```
   Use the next free number: 43 = redis, 44 = intercom-service, 21 = keycloak-bootstrap.
4. Add the name to the `inherit` list at the bottom of the `in` block.

### Image pinning (ALL tasks)
**NEVER write `tag = "latest"`.** Every new image must be pinned to an explicit
version tag. The CI lint (`check-no-latest-tag.sh`) fails on any NEW `tag = "latest"`.
Existing project-built images in the baseline are tracked debt — do not add new debt.

### Conventions
- Header comment: SPDX license header (Apache-2.0) + one-line description, like
  every other service file.
- Nix formatting: 2-space indent, `{ }` for empty attrsets, attrsets in the
  existing style. Run `nix fmt -- .` if available; keep it consistent.
- Every env secret that must not be in cleartext uses `valueFrom.secretKeyRef`
  pointing at a sealed `lib.secret`.
- Every service file returns a list of manifests: deployment/service/ingress
  (and secrets) — see `sogo.nix` or `synapse.nix` as the canonical example.

---

## §1 IC-1 — keycloak-bootstrap Job (realm + LDAP federation + OIDC clients)

**Goal:** an idempotent Kubernetes Job that provisions the Keycloak `opendesk`
realm (currently MISSING — only `master` exists; `https://id.home.opendesk-edu.org/realms/opendesk/.well-known/openid-configuration` returns 404), an LDAP
user federation to OpenLDAP, and the OIDC clients the platform needs. This is
the foundation every other task depends on.

### Files
- `platform/kubernetes/services/keycloak-bootstrap.nix` (NEW)
- `platform/kubernetes/environments/scs/default.nix` (extend `keycloak` attr)
- `platform/kubernetes/scs/default.nix` (wire, file `21-keycloak-bootstrap.yaml`)

### Design
- **Image:** `docker.io/keycloak/keycloak:26.0` (matches live keycloak).
- **Manifest kind:** `Job` (batch/v1), `restartPolicy: Never`, `backoffLimit: 4`,
  `ttlSecondsAfterFinished: 86400`. Namespace `opendesk`.
- **Realm model as data:** define the realm/clients declaratively in nix (an
  attrset), then a shell script applies it via `kcadm.sh`. The realm model goes
  in `env.keycloak` (environments/scs/default.nix) so it is data, not code.
- **Secrets (via `lib.secret`):** `keycloak-clients` with keys
  `intercom-client-secret`, `matrix-client-secret`, `sogo-client-secret`
  (values: `<name>-change-me` literals). Mounted at `/mnt/secrets`.
  Admin creds: `keycloak-db` secret (existing, key `admin-password` — value
  `admin` today), mounted read-only.
- **The script** (inline `command` array or a ConfigMap-mounted script with
  `defaultMode = 493` — ConfigMap script is cleaner, mirrors the galera initdb
  pattern; either is acceptable as long as it is idempotent):

```sh
#!/bin/sh
set -eu
KC=/opt/keycloak/bin/kcadm.sh
KCHOST=http://127.0.0.1:8080   # localhost: run `kubectl exec` style via hostNetwork? NO — see below
```

**IMPORTANT:** the Job runs as its own pod; keycloak runs in the same
namespace. Use the service DNS: `http://keycloak.opendesk.svc.cluster.local:8080`.
The script must:
1. Wait for keycloak to be ready (curl loop on
   `http://keycloak.opendesk.svc.cluster.local:8080/realms/master` until 200,
   max ~120s).
2. `kcadm config credentials --server <kc> --realm master --user admin --password "$(cat /mnt/secrets/admin-password)"`.
3. **Realm:** create `opendesk` if missing (idempotent:
   `kcadm get realms/opendesk || kcadm create realms -s realm=opendesk -s enabled=true -s sslRequired=external`).
4. **LDAP federation** (user federation provider):
   ```sh
   kcadm create components -r opendesk -s name=openldap -s providerId=ldap \
     -s providerType=org.keycloak.storage.UserStorageProvider \
     -s parentId=opendesk \
     -s 'config.vendor=["ldap"]' \
     -s 'config.enabled=["true"]' \
     -s 'config.usernameLDAPAttribute=["uid"]' \
     -s 'config.rdnLDAPAttribute=["uid"]' \
     -s 'config.uuidLDAPAttribute=["entryUUID"]' \
     -s 'config.userObjectClasses=["inetOrgPerson, posixAccount"]' \
     -s 'config.connectionUrl=["ldap://openldap.opendesk-edu.svc.cluster.local:389"]' \
     -s 'config.usersDn=["ou=people,dc=opendesk-edu,dc=org"]' \
     -s 'config.bindDn=["cn=admin,dc=opendesk-edu,dc=org"]' \
     -s 'config.bindCredential=["adminpassword"]' \
     -s 'config.authType=["simple"]' \
     -s 'config.searchScope=["1"]' \
     -s 'config.useTruststoreSpi=["ldapsOnly"]' \
     -s 'config.connectionPooling=["false"]' \
     -s 'config.importEnabled=["true"]' \
     -s 'config.syncRegistrations=["false"]' \
     -s 'config.editMode=["READ_ONLY"]' \
     -s 'config.cachePolicy=["DEFAULT"]'
   ```
   (get-or-create by name; do not duplicate if it exists.)
5. **Clients** — for each client below: `kcadm get clients -r opendesk -q clientId=X` → if empty, create with the exact config.

### Client specifications (authoritative — from the openDesk nubus reference, adapted to SCS)

| clientId | type | secret | redirectUris | attributes |
|---|---|---|---|---|
| `opendesk-intercom` | confidential | `intercom-client-secret` | `https://intercom.home.opendesk-edu.org/callback` | `use.refresh.tokens=true`, `backchannel.logout.session.required=true`, `standard.token.exchange.enabled=true`, `standard.token.exchange.enableRefreshRequestedTokenType=SAME_SESSION`, `backchannel.logout.revoke.offline.tokens=true`, `backchannel.logout.url=https://intercom.home.opendesk-edu.org/backchannel-logout` |
| `opendesk-opencloud` | confidential | `opencloud-secret-change-me` (**must match the existing sealed secret** `opendesk-opencloud-db` key `oidc-client-secret`) | `https://cloud.home.opendesk-edu.org/*` | `use.refresh.tokens=true`, `standard.token.exchange.enabled=true` |
| `opendesk-matrix` | confidential | `matrix-client-secret` | `https://matrix.home.opendesk-edu.org/_synapse/client/oidc/callback` | `use.refresh.tokens=true`, `backchannel.logout.session.required=true` |
| `opendesk-sogo` | confidential | `sogo-client-secret` | `https://mail.home.opendesk-edu.org/SOGo/oidc/callback` | `use.refresh.tokens=true` |

All clients: `consentRequired=false`, `frontchannelLogout=false`,
`authorizationServicesEnabled=false`, `publicClient=false`,
`defaultClientScopes=["offline_access"]`.

**Protocol mappers** (add to every client, same for all):
- `opendesk_username` — `oidc-usermodel-attribute-mapper`, `user.attribute=uid`,
  `claim.name=opendesk_username`, id+access+userinfo claims, `jsonType.label=String`.
- `opendesk_useruuid` — `oidc-usermodel-attribute-mapper`, `user.attribute=entryUUID`,
  `claim.name=opendesk_useruuid`, id+access+userinfo claims, `jsonType.label=String`.
- For `opendesk-intercom` additionally: `intercom-audience` —
  `oidc-audience-mapper`, `included.client.audience=opendesk-intercom`,
  `access.token.claim=true`, `id.token.claim=false`.

**Idempotency rule:** every step is get-or-create; running the Job twice must
not fail or duplicate (check existence by name first; on create errors that
indicate “already exists”, treat as success).

### Gate
```sh
nix build .#scs-manifests 2>&1 | tail -3
ls result/21-keycloak-bootstrap.yaml 2>/dev/null
grep -q '"kind":"Job"' result/21-keycloak-bootstrap.yaml
grep -q 'opendesk-intercom' result/21-keycloak-bootstrap.yaml
grep -q 'opendesk-opencloud' result/21-keycloak-bootstrap.yaml
grep -q 'keycloak-clients' result/21-keycloak-bootstrap.yaml
grep -q '"kind":"SealedSecret"' result/21-keycloak-bootstrap.yaml
grep -q 'realm=opendesk\|"realm" : "opendesk"\|opendesk' result/21-keycloak-bootstrap.yaml
```
Also: `grep -n 'tag = "latest"' platform/kubernetes/services/keycloak-bootstrap.nix` must find nothing.

---

## §2 IC-2 — Redis (ICS session store)

**Goal:** a small Redis deployment in `opendesk-edu` for ICS sessions (ephemeral,
NO persistent volume — sessions must survive only as long as the pod; the openDesk
reference uses a shared Redis with no persistence for ICS).

### Files
- `platform/kubernetes/services/redis.nix` (REWORK the existing stub — it is a
  placeholder for the HRZ env with `tag = "latest"` and a StatefulSet+PVC; the
  SCS variant must be a Deployment without PVC)
- `platform/kubernetes/scs/default.nix` (wire, file `43-redis.yaml`)

### Spec
- Image: `docker.io/redis:7.4-alpine` (pinned — the current stub uses
  `ghcr.io/opendesk-edu/redis:latest`; replace with the pinned docker.io image).
- Deployment, 1 replica, `strategyType = "Recreate"` (no PVC → Multi-Attach is
  not a concern, but Recreate is the repo default for stateful-ish services;
  RollingUpdate is fine too — pick one and justify in the header comment).
- Port 6379, service ClusterIP `redis` in `opendesk-edu`.
- **Auth:** env `REDIS_PASSWORD` from sealed secret `redis` (key `password`,
  value `redis-password-change-me`) + args
  `["redis-server", "--requirepass", "$(REDIS_PASSWORD)"]` (kubelet expands
  `$(ENV)` in args). SecurityContext: non-root user 1000 — Redis alpine image
  supports arbitrary uid; `runAsUser=1000, runAsGroup=1000, fsGroup=1000`,
  drop ALL caps, seccomp RuntimeDefault.
- Probes: `lib.mkProbe` tcp on 6379 (liveness initialDelaySeconds 30,
  readiness 5).
- Resources: small (requests 100m/128Mi, limits 500m/512Mi) — see `env.resources`.
- No persistence: no PVC, no `--appendonly`.

### Gate
```sh
nix build .#scs-manifests 2>&1 | tail -3
ls result/43-redis.yaml 2>/dev/null
grep -q 'redis:7.4-alpine' result/43-redis.yaml
grep -q '"kind":"SealedSecret"' result/43-redis.yaml
grep -q 'REDIS_PASSWORD' result/43-redis.yaml
grep -n 'tag = "latest"' platform/kubernetes/services/redis.nix   # must match nothing
grep -q 'persistentVolumeClaim' result/43-redis.yaml && exit 1 || true  # no PVC
```

---

## §3 IC-3 — Intercom-Service (ICS) + fork image source

**Goal:** deploy the intercom-service (browser OIDC broker: silent login,
backchannel logout, file-picker proxy to OpenCloud) configured for the SCS
cluster, plus the source of the forked image (upstream ICS 2.23.11 + `/oc/`
OpenCloud route + `/sogo/` CalDAV/CardDAV route + `/health` endpoint + Node
Alpine base — the openDesk-Edu fork described in
`articles/extending-intercom-service-community-consensus-en.md`).

### Files
- `platform/kubernetes/services/intercom-service.nix` (REWORK the stub)
- `docker/intercom-service/Dockerfile` (NEW — fork image)
- `docker/intercom-service/routes/oc.js` (NEW — OpenCloud proxy route)
- `docker/intercom-service/routes/sogo.js` (NEW — SOGo CalDAV/CardDAV proxy)
- `docker/intercom-service/routes/health.js` (NEW — /health endpoint)
- `docker/intercom-service/config/config.js` (NEW — patched config with OpenCloud)
- `docker/intercom-service/README.md` (NEW — fork rationale + build instructions)
- `platform/kubernetes/scs/default.nix` (wire, file `44-intercom-service.yaml`)

### Fork image (docker/intercom-service/)
Base: the upstream ICS 2.23.11 app (Node.js Express). The `routes/fs.js` proxy
is the template — copy its structure for `oc.js`/`sogo.js` (http-proxy-middleware,
inject `authorization: Bearer <session token>`, `stripIntercomCookies`,
`massageCors`). Implementations:

**`routes/oc.js`** — identical to `fs.js` except: mount at `/oc/`, target
`config.opencloud.url` (env `OC_URL`), session key `oc_access_token` (env
`OC_ENABLED` gates it in `config/config.js`).

**`routes/sogo.js`** — proxy to `config.sogo.url` (env `SOGO_URL`), session key
`sogo_access_token`, mounted at `/sogo/`, pathRewrite `^/sogo` → ``. (The SOGo
backend accepts Bearer tokens for CalDAV/CardDAV when configured; the proxy
itself is backend-agnostic.)

**`config/config.js`** — extend the upstream config with:
```js
opencloud: {
  enabled: JSON.parse((process.env.OC_ENABLED ?? "false").toLowerCase()),
  name: "OpenCloud",
  url: process.env.OC_URL,
  audience: process.env.OC_AUDIENCE,
  session_storage_key: "oc_access_token",
},
sogo: {
  enabled: JSON.parse((process.env.SOGO_ENABLED ?? "false").toLowerCase()),
  name: "SOGo",
  url: process.env.SOGO_URL,
  session_storage_key: "sogo_access_token",
},
```

**`routes/health.js`** — `router.get("/", (req,res)=>res.status(200).json({status:"ok"}))`
mounted at `/health`.

**`routes/index.js`** — mount the new routes: `/oc`, `/sogo`, `/health` alongside
`/fs`, `/silent`, `/backchannel-logout`, `/navigation.json`.

**`Dockerfile`** — Node Alpine base (the fork drops the 2GB UCS base image per
the article):
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --production --frozen-lockfile 2>/dev/null || npm install --omit=dev
COPY . /app
EXPOSE 8080
USER 1000
CMD ["node", "app.js"]
```
Do NOT vendor node_modules into git. The README documents that the upstream
2.23.11 source is the base (see “Upstream source” below) and how to build/push:
`docker build -t ghcr.io/opendesk-edu/intercom-service:2.23.11 docker/intercom-service/`.

> **Upstream source:** the fork source files added here are OVERLAYS on the
> upstream 2.23.11 tree (which lives at
> `gitlab.opencode.de/bmi/opendesk/component-code/crossfunctional/univention/univention_ics`).
> The README must state that the image is built from the upstream tree + these
> overlay files (the orchestrator does the merge at build time, or the overlay
> files are copied over the upstream checkout). Keep the overlay self-contained.

### Deployment spec (intercom-service.nix)
- Image: `ghcr.io/opendesk-edu/intercom-service:2.23.11` (fork — pinned).
- Namespace `opendesk-edu`, port 8080, `strategyType = "Recreate"` (single
  replica, stateless — Recreate is fine).
- **Config env** (all non-secret; from the chart/values reference):
  | env | value |
  |---|---|
  | `ISSUER_BASE_URL` | `https://id.home.opendesk-edu.org/realms/opendesk` |
  | `BASE_URL` | `https://intercom.home.opendesk-edu.org` |
  | `ORIGIN_REGEX` | `^https://.*\\.home\\.opendesk-edu\\.org$` |
  | `ENABLE_SESSION_COOKIE` | `true` |
  | `SESSION_ROLLING_DURATION` | `86400` |
  | `LOG_LEVEL` | `INFO` |
  | `USER_UNIQUE_MAPPER` | `opendesk_useruuid` |
  | `USERNAME_CLAIM` | `opendesk_username` |
  | `CLIENT_ID` | `opendesk-intercom` |
  | `OC_ENABLED` | `true` |
  | `OC_URL` | `https://cloud.home.opendesk-edu.org` |
  | `OC_AUDIENCE` | `opendesk-opencloud` |
  | `SOGO_ENABLED` | `false` (route present, activation is a later phase) |
  | `MATRIX_ENABLED` | `true` |
  | `MATRIX_URL` | `https://matrix.home.opendesk-edu.org` |
  | `MATRIX_SERVER_NAME` | `matrix.home.opendesk-edu.org` |
  | `NC_ENABLED` | `false` (Nextcloud disabled — OpenCloud is our file service) |
  | `REDIS_HOST` | `redis.opendesk-edu.svc.cluster.local` |
  | `REDIS_PORT` | `6379` |
  | `REDIS_USER` | `default` |
  | `PORT` | `8080` |
- **Secret env** (via `valueFrom.secretKeyRef`, sealed secrets):
  | env | secret | key |
  |---|---|---|
  | `SECRET` | `intercom` | `session-secret` (value `intercom-session-secret-change-me-0123456789` — MUST be >=32 chars, express-openid-connect requires it) |
  | `CLIENT_SECRET` | `keycloak-clients` | `intercom-client-secret` |
  | `MATRIX_AS_SECRET` | `intercom` | `matrix-as-token` (value `intercom-matrix-as-token-change-me`) |
  | `REDIS_PASSWORD` | `redis` | `password` |
- **Secrets (`lib.secret`)**: `intercom` (namespace opendesk-edu) with
  `session-secret` + `matrix-as-token`.
- **Probes:** `lib.mkProbe` http on 8080 path `/health` (liveness
  initialDelaySeconds 30, readiness 15, period 10).
- **SecurityContext:** mirror the chart defaults — `runAsUser=1000`,
  `runAsGroup=1000`, `fsGroup=1000`, drop ALL caps, `readOnlyRootFilesystem=true`,
  `runAsNonRoot=true`, seccomp RuntimeDefault. (If the fork image writes nothing
  outside /tmp, RO rootfs works; keep `tempDir`/tmpfs emptyDir for /tmp if needed.)
- **Ingress:** `lib.ingressWithCert` host `intercom.home.opendesk-edu.org`
  (add `intercom = "intercom.home.opendesk-edu.org";` to `env.hosts`).
- **Env additions to `environments/scs/default.nix`:** `hosts.intercom`.

### Gate
```sh
nix build .#scs-manifests 2>&1 | tail -3
ls result/44-intercom-service.yaml 2>/dev/null
grep -q 'intercom.home.opendesk-edu.org' result/44-intercom-service.yaml
grep -q 'opendesk-intercom' result/44-intercom-service.yaml
grep -q 'ISSUER_BASE_URL' result/44-intercom-service.yaml
grep -q 'OC_URL' result/44-intercom-service.yaml
grep -q '"kind":"SealedSecret"' result/44-intercom-service.yaml
grep -q 'intercom:2.23.11' result/44-intercom-service.yaml
grep -n 'tag = "latest"' platform/kubernetes/services/intercom-service.nix   # must match nothing
test -f docker/intercom-service/Dockerfile
test -f docker/intercom-service/routes/oc.js
test -f docker/intercom-service/routes/sogo.js
grep -q 'OC_URL\|oc_access_token' docker/intercom-service/routes/oc.js
grep -q '/health' docker/intercom-service/routes/health.js
grep -q 'node:20-alpine' docker/intercom-service/Dockerfile
```

---

## §4 IC-4 — Element banner (ICS silent login)

**Goal:** point Element at the ICS for silent login + navigation (the openDesk
reference sets `banner.ics_silent_url` + `banner.ics_navigation_json_url`).

### Files
- `platform/kubernetes/services/element.nix` (edit `elementConfig`)

### Spec
Add a `"banner"` object to `elementConfig` (JSON):
```json
"banner": {
  "ics_navigation_json_url": "https://intercom.home.opendesk-edu.org/navigation.json",
  "ics_silent_url": "https://intercom.home.opendesk-edu.org/silent"
}
```
Keep everything else unchanged. Use `env.hosts.intercom` (new host added in
IC-3) for the URL base.

### Gate
```sh
nix build .#scs-manifests 2>&1 | tail -3
grep -q 'ics_silent_url' result/31-element.yaml
grep -q 'intercom.home.opendesk-edu.org/silent' result/31-element.yaml
grep -q 'ics_navigation_json_url' result/31-element.yaml
```

---

## §5 IC-5 — Synapse OIDC (SSO login via Keycloak)

**Goal:** enable OIDC login in synapse against the Keycloak `opendesk` realm
(client `opendesk-matrix`, created in IC-1). Existing password-auth stays
enabled as fallback.

### Files
- `platform/kubernetes/services/synapse.nix` (edit `opencloudConfig`-style
  homeserver.yaml + initContainer sed + new secret)

### Spec
1. In the homeserver.yaml config (`homeserverConfig` string), add:
```yaml
oidc_config:
  enable: true
  discovery_method: "oidc"
  issuer: "https://id.home.opendesk-edu.org/realms/opendesk"
  client_id: "opendesk-matrix"
  client_secret: "__SYNAPSE_OIDC_CLIENT_SECRET__"
  scopes: ["openid", "profile", "email"]
  user_mapping_provider:
    config:
      localpart_template: "{{ user.preferred_username }}"
      display_name_template: "{{ user.preferred_username }}"
```
2. The existing `init-config` initContainer renders the macaroon placeholder
   from `/mnt/secrets/macaroon-secret-key`. Extend it:
   - Add a new `lib.secret` `synapse-oidc` (namespace opendesk) with key
     `oidc-client-secret` = `synapse-oidc-client-secret-change-me`.
   - Mount it read-only at `/mnt/secrets-oidc`.
   - Extend the sed to also replace `__SYNAPSE_OIDC_CLIENT_SECRET__` with
     `$(cat /mnt/secrets-oidc/oidc-client-secret)` (use `sed -e ... -e ...`).
3. Bump `checksum/config` annotation to `synapse-config-v3`.

### Gate
```sh
nix build .#scs-manifests 2>&1 | tail -3
grep -q 'oidc_config' result/30-synapse.yaml
grep -q 'opendesk-matrix' result/30-synapse.yaml
grep -q '__SYNAPSE_OIDC_CLIENT_SECRET__' result/30-synapse.yaml
grep -q 'synapse-config-v3' result/30-synapse.yaml
grep -q '"kind":"SealedSecret"' result/30-synapse.yaml
grep -n 'tag = "latest"' platform/kubernetes/services/synapse.nix   # must match nothing
```

---

## §6 IC-6 — Architecture documentation

**Goal:** document the OIDC + ICS architecture so the deployment is
self-explanatory (the “clean and thorough” requirement).

### Files
- `docs/intercom-oidc.md` (NEW)
- `docs/README.md` if it exists / else `README.md` (add a link/section)

### Content (must cover)
1. What ICS is (browser iframe broker: silent login, backchannel logout,
   file-picker proxy `/oc/` → OpenCloud).
2. The OIDC foundation: realm `opendesk`, LDAP federation (openldap), the
   clients table (from §1) with their purposes.
3. The sealed-secrets flow for the new secrets (keycloak-clients, redis,
   intercom, synapse-oidc) — no cleartext in manifests.
4. Data flow for the attachment use case: app iframe → ICS `/oc/` → OpenCloud
   WebDAV with the user's token; silent login flow; backchannel logout.
5. Operational notes: redeploying the bootstrap Job, rotating a client secret
   (change stringData → `nix build` → apply SealedSecret), the fork image build
   (`docker/intercom-service/README.md`).
6. NetworkPolicy requirements (documented for the scs-infra repo — NOT
   implemented here): kube-system ingress → intercom:80; opendesk-edu →
   opendesk:8008 (ICS→synapse); opendesk → opendesk-edu:80 (keycloak→ICS
   backchannel logout).

### Gate
```sh
test -f docs/intercom-oidc.md
grep -qi 'intercom' docs/intercom-oidc.md
grep -qi 'opendesk' docs/intercom-oidc.md
grep -qi 'realm' docs/intercom-oidc.md
grep -qi '/oc/' docs/intercom-oidc.md
grep -qi 'sealed' docs/intercom-oidc.md
```

---

## §7 IC-7 — CI lint: new images pinned, baseline debt removed

**Goal:** the three services that were tracked `:latest` debt (intercom.nix,
intercom-service.nix, redis.nix) are now pinned — remove them from the baseline
so the lint proves no NEW latest tags and the debt shrinks.

### Files
- `scripts/ci/latest-tag-baseline.txt` (remove lines 14 `intercom.nix`,
  15 `intercom-service.nix`, 31 `redis.nix`)
- (IC-2/IC-3 already pinned the images; only the baseline edit is needed here,
  unless a stray `tag = "latest"` remains — then pin it.)

### Gate
```sh
bash scripts/ci/check-no-latest-tag.sh . 2>&1 | tail -5
grep -q 'OK: no NEW image tag "latest"' <(bash scripts/ci/check-no-latest-tag.sh . 2>&1)
grep -c 'intercom.nix\|intercom-service.nix\|redis.nix' scripts/ci/latest-tag-baseline.txt   # must be 0
nix build .#scs-manifests 2>&1 | tail -2
```

---

## Appendix A — Cluster facts (SCS K3s)

- Cluster: `scs-k3s`, 3 nodes; kubectl from this workstation (`~/.kube/config`).
- Namespaces: `opendesk` (keycloak, synapse, element, galera),
  `opendesk-edu` (sogo, stalwart, opencloud, openldap, postfix, dkimpy-milter).
- Keycloak: `quay.io/keycloak/keycloak:26.0`, internal
  `http://keycloak.opendesk.svc.cluster.local:8080`, public
  `https://id.home.opendesk-edu.org`, admin user `admin` / password in secret
  `keycloak-db` key `admin-password` (= `admin`). Only `master` realm exists.
- OpenLDAP: `openldap.opendesk-edu.svc.cluster.local:389` (no TLS), base
  `dc=opendesk-edu,dc=org`, admin `cn=admin,dc=opendesk-edu,dc=org` /
  `adminpassword`, users `ou=people,dc=opendesk-edu,dc=org`
  (objectClass inetOrgPerson/posixAccount, uid attr, entryUUID).
- OpenCloud: `cloud.home.opendesk-edu.org`, OIDC client `opendesk-opencloud`,
  secret `opencloud-secret-change-me` (sealed secret `opendesk-opencloud-db`).
- Domains: `*.home.opendesk-edu.org`. Ingress: HAProxy, TLS secret
  `opendesk-certificates-tls`.
- Storage: ceph-rbd (RWO), ceph-cephfs (RWX).

## Appendix B — Secret inventory (all via `lib.secret` → SealedSecret)

| Secret | ns | keys | values (placeholders) |
|---|---|---|---|
| `keycloak-clients` | opendesk | `intercom-client-secret`, `matrix-client-secret`, `sogo-client-secret` | `*-change-me` |
| `redis` | opendesk-edu | `password` | `redis-password-change-me` |
| `intercom` | opendesk-edu | `session-secret`, `matrix-as-token` | `intercom-session-secret-change-me-0123456789`, `intercom-matrix-as-token-change-me-0123456789` |
| `synapse-oidc` | opendesk | `oidc-client-secret` | `synapse-oidc-client-secret-change-me` |

## Appendix C — Dependencies & ordering

- IC-1 (foundation) → everything.
- IC-2 (redis) → IC-3 (ICS needs REDIS_HOST).
- IC-3 (ICS) → IC-4 (element banner URL), IC-6 (docs), IC-7 (lint).
- IC-5 (synapse OIDC) needs IC-1 (client) — independent of IC-2..4.
- IC-7 needs IC-2 + IC-3 (pinning) — run last among code tasks.
- IC-6 last (documentation of the final state).
