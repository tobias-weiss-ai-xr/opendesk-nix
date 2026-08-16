# Plan: Matrix Appservice Registration (Intercom-Service share-to-Matrix)

**Date:** 2026-08-16 · **Status:** approved · **Engine:** nix (taskfleet MA-1..MA-3, TDD gates-first)

## Goal

Enable the Intercom-Service (ICS) Matrix integration end-to-end: the ICS fetches a per-user
Matrix access token with the `m.login.application_service` flow, which **requires Synapse to
have the ICS registered as an application service**. Today it is not registered
(`app_service_config_files` absent from `homeserver.yaml`) — the login 403s.

## How the ICS authenticates to Matrix (reference: `docker/intercom-service/utils/matrix.js`)

```
POST https://matrix.home.opendesk-edu.org/_matrix/client/v3/login
Authorization: Bearer <MATRIX_AS_SECRET>        # the appservice as_token
{ "type": "m.login.application_service",
  "identifier": { "type": "m.id.user", "user": "<uid>" } }
```

`uid` = the Keycloak `opendesk_useruuid` claim (LDAP entryUUID) — a **bare localpart** (no `@`,
no server). The ICS already receives `MATRIX_AS_SECRET` (= the appservice `as_token`, from the
sealed `intercom` Secret, key `matrix-as-token`, opendesk-edu ns) and sets `MATRIX_ENABLED=true`.

## Registration contract (Synapse side, namespace `opendesk`)

New sealed Secret **`synapse-appservice`** with keys:
- `matrix-as-token` — the as_token (value provisioned out-of-band = the same token the ICS uses)
- `matrix-hs-token` — a new hs_token (value provisioned out-of-band)

Nix uses `__PLACEHOLDER__` values in `stringData` (sealed at build time); the real values are
applied out-of-band at deploy (established pattern, never commit cleartext).

Templated registration file (in the `synapse-config` ConfigMap, key `appservice/intercom.yaml`),
rendered by the `init-config` initContainer from the mounted Secret:

```yaml
id: intercom
hs_token: "__MATRIX_HS_TOKEN__"
as_token: "__MATRIX_AS_TOKEN__"
sender_localpart: intercom
namespaces:
  users:
    - exclusive: false
      regex: "@.*"
```

Notes:
- `url` omitted — the ICS only performs appservice **login**, never receives pushes.
- The `users` namespace is non-exclusive with a catch-all regex so the AS may log in as any
  user (ghost users are created on demand; real OIDC users still take precedence).
- `homeserver.yaml` gains `app_service_config_files: ["/config/appservice/intercom.yaml"]`.

## Changes

### MA-1 — `platform/kubernetes/services/synapse.nix` (the only source edit)

1. `homeserverConfig`: add `app_service_config_files: ["/config/appservice/intercom.yaml"]`.
2. `synapse-config` ConfigMap: add key `appservice/intercom.yaml` = the registration template above.
3. `init-config` initContainer: extend the sed command to render BOTH files from the mounted
   secrets (copy the existing `__SYNAPSE_MACAROON_SECRET__` pattern; mount the new secret at
   e.g. `/mnt/secrets-appservice`, files `matrix-as-token` + `matrix-hs-token`); render the
   registration template to `/config/appservice/intercom.yaml`.
4. `config-src` volume `items`: add the `appservice/intercom.yaml` key.
5. New `lib.secret` `synapse-appservice` (ns opendesk) with `stringData`:
   `matrix-as-token` = `opendesk-synapse-appservice-as-token-change-me`,
   `matrix-hs-token` = `opendesk-synapse-appservice-hs-token-change-me` (sealed at build).
6. Deployment `volumes`/`volumeMounts`: mount the new `synapse-appservice` Secret (read-only).

### MA-2 — `scripts/e2e-appservice.mjs` (NEW, TDD test artifact)

Reusable Node acceptance test (pattern: the ICS e2e flow script; run inside the intercom pod or
anywhere with `MATRIX_AS_SECRET` + cluster-ca trust):
1. **Manifest assertions** — read `result/30-synapse.yaml` (or path from argv) and assert it
   contains `app_service_config_files`, `intercom.yaml`, `__MATRIX_AS_TOKEN__`,
   `__MATRIX_HS_TOKEN__`, `synapse-appservice`, `sender_localpart`.
2. **Live login assertion** — `m.login.application_service` login against
   `https://matrix.home.opendesk-edu.org/_matrix/client/v3/login` with
   `Authorization: Bearer ${process.env.MATRIX_AS_SECRET}` and user `testuser`
   (env `E2E_MATRIX_USER`, default `testuser`). Assert HTTP 200 + `access_token` present.
3. Exit 0 on success, non-zero with a clear message otherwise. Skip live login (exit 0) when
   `MATRIX_AS_SECRET` is unset (manifest-only mode) — the gate must pass in a bare worktree.

### MA-3 — `scripts/verify-ics.sh` (extend)

Add section 9 "Matrix appservice registration":
- manifest check (result/30-synapse.yaml contains `app_service_config_files` + `intercom.yaml`)
- live check when the cluster is reachable: Secret `synapse-appservice` exists in `opendesk`
  with keys `matrix-as-token` + `matrix-hs-token`.

## Out-of-band deploy sequence (executed by the operator, NOT the agents)

1. Create the real Secret out-of-band (opendesk ns): `matrix-as-token` = existing ICS token,
   `matrix-hs-token` = newly generated.
2. Port the synapse.nix changes to the GitLab ArgoCD source manifests (deploy-synapse.yaml +
   configmaps.yaml) — live secrets FIRST, then sync; validate with `yaml.safe_load_all` +
   `kubectl kustomize`.
3. Rollout-restart synapse; run `node scripts/e2e-appservice.mjs` (manifest + live login) and
   `bash scripts/verify-ics.sh` (section 9).

## Acceptance criteria

- `nix build .#scs-manifests` succeeds; `result/30-synapse.yaml` contains the wiring (MA-1 gate).
- `scripts/e2e-appservice.mjs` passes manifest assertions + (live) the appservice login 200s.
- `scripts/verify-ics.sh` section 9 passes.
- No cleartext secret values in the repo; no `:latest` image tags.
