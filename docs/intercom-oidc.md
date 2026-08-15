# Intercom-Service (ICS) + OIDC foundation

This document describes the OIDC/SSO layer and the Intercom-Service (ICS)
broker deployed on the SCS K3s cluster. It is the companion to the execution
plan (`plan/2026-08-15-intercom-oidc-plan.md`) and the fork image source
(`docker/intercom-service/`).

## 1. What the Intercom-Service is

The ICS is a lightweight browser-embedded broker. Apps embed it as an iframe;
it communicates via `postMessage`. It provides:

- **Silent login** — passes OIDC tokens between apps without user interaction
  (`/silent`). Element uses this via `banner.ics_silent_url`.
- **Backchannel logout** — coordinated SSO session termination (Keycloak →
  ICS `/backchannel-logout` → apps).
- **File-picker proxy `/oc/` → OpenCloud** — the "attachments" use case: an
  app requests a file from OpenCloud through the ICS; the ICS performs a
  Keycloak **token exchange** (`urn:ietf:params:oauth:grant-type:token-exchange`)
  to the `opendesk-opencloud` audience and proxies the request with the user's
  token as a Bearer header.
- **`/sogo/` CalDAV/CardDAV proxy** — calendar/contact data access across apps
  (route present in the fork; enabled via `SOGO_ENABLED` in a later phase).

## 2. The OIDC foundation

The SCS Keycloak deployment only contained the `master` realm. The
`keycloak-bootstrap` Job (see `platform/kubernetes/services/keycloak-bootstrap.nix`)
provisions, idempotently:

- **Realm `opendesk`** (`https://id.home.opendesk-edu.org/realms/opendesk`).
- **LDAP user federation** → OpenLDAP
  (`ldap://openldap.opendesk-edu.svc.cluster.local:389`, users
  `ou=people,dc=opendesk-edu,dc=org`, `uid`/`entryUUID` attributes).
- **Clients** (all confidential, `offline_access` scope, claim mappers
  `opendesk_username` = `uid` and `opendesk_useruuid` = `entryUUID`):

| client | purpose | redirect |
|---|---|---|
| `opendesk-intercom` | ICS OIDC (token exchange + backchannel logout to ICS) | `https://intercom.home.opendesk-edu.org/callback` |
| `opendesk-opencloud` | OpenCloud OIDC (audience for ICS token exchange) | `https://cloud.home.opendesk-edu.org/*` |
| `opendesk-matrix` | Synapse OIDC login | `https://matrix.home.opendesk-edu.org/_synapse/client/oidc/callback` |
| `opendesk-sogo` | SOGo OIDC (future) | `https://mail.home.opendesk-edu.org/SOGo/oidc/callback` |

Client secrets live in the sealed `keycloak-clients` Secret (rotatable via the
sealed-secrets flow); the opencloud value matches the existing
`opendesk-opencloud-db`/`oidc-client-secret`.

## 3. Data flows

### File picker / attachments (app → ICS → OpenCloud)

```
Browser app iframe ──postMessage──▶ ICS (intercom.home.opendesk-edu.org)
                                        │ 1. silent login (OIDC, client opendesk-intercom)
                                        │ 2. GET /oc/remote.php/dav/files/…
                                        │    token exchange → aud=opendesk-opencloud
                                        ▼
                                   OpenCloud (cloud.home.opendesk-edu.org)
```

### Silent login (Element)

Element's `config.json` banner sets `ics_silent_url` + `ics_navigation_json_url`.
The ICS `/silent` endpoint reports session status via `window.postMessage`, so
the app logs the user in without a redirect.

## 4. Components

| component | location | notes |
|---|---|---|
| Keycloak bootstrap Job | `platform/kubernetes/services/keycloak-bootstrap.nix` | idempotent, image `quay.io/keycloak/keycloak:26.0`, kcadm script in a ConfigMap |
| Redis session store | `platform/kubernetes/services/redis.nix` | `docker.io/redis:7.4-alpine`, ephemeral (no PVC), password auth |
| Intercom-Service | `platform/kubernetes/services/intercom-service.nix` | fork image `ghcr.io/opendesk-edu/intercom-service:2.23.11` (mirrored to the cluster registry) |
| Fork image source | `docker/intercom-service/` | Node 20 Alpine base + `/oc/` + `/sogo/` + `/health` |
| Element banner | `platform/kubernetes/services/element.nix` | `ics_silent_url` + `ics_navigation_json_url` |
| Synapse OIDC | `platform/kubernetes/services/synapse.nix` | `oidc_config` → realm `opendesk`, client `opendesk-matrix`; secret rendered by the `init-config` initContainer |

## 5. Secrets (all sealed at build time)

| Secret | namespace | keys |
|---|---|---|
| `keycloak-clients` | opendesk | `intercom-client-secret`, `matrix-client-secret`, `sogo-client-secret`, `opencloud-client-secret` |
| `redis` | opendesk-edu | `password` |
| `intercom` | opendesk-edu | `session-secret` (≥32 chars), `matrix-as-token` |
| `synapse-oidc` | opendesk | `oidc-client-secret` |

No secret value appears in cleartext in any committed manifest — every Secret
becomes a `SealedSecret` at build time (`scs/default.nix` `serialize`) and the
in-cluster controller decrypts it on apply.

## 6. Operational notes

- **Re-running the bootstrap Job** is safe (get-or-create semantics). To force
  reconciliation: `kubectl -n opendesk delete job keycloak-bootstrap && kubectl
  apply -f <manifests>`.
- **Rotating a client secret**: change the value in the service's `lib.secret`
  `stringData`, `nix build .#scs-manifests`, apply the SealedSecret, then
  update the consumer (ICS env, synapse secret mount).
- **The fork image** is built from the upstream 2.23.11 tree + the overlay in
  `docker/intercom-service/` (see its README for the build/push steps and the
  air-gap push to the cluster registry at `172.17.0.6:5001`).

## 7. NetworkPolicy requirements (scs-infra repo — not part of opendesk-nix)

Applied in `hrz/kubernetes/scs.git` (`k8s/network-policies/`):

- `opendesk` ns: allow `opendesk-edu` → `app: synapse` :8008 (ICS Matrix API)
- `opendesk-edu` ns: allow `opendesk` → `app: intercom-service` :8080
  (Keycloak backchannel logout)

Ingress to ICS (kube-system → :8080) is covered by the existing
`allow-haproxy-ingress` policy in `opendesk-edu`; ICS → OpenCloud/Redis/SOGo
(same namespace) is covered by `allow-same-namespace`.
