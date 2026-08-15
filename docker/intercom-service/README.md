# Intercom-Service (ICS) — openDesk Edu fork image overlay

This directory is the **overlay** for the openDesk Edu fork of the
intercom-service image (upstream: Univention ICS 2.23.11).

## Why a fork

Upstream ICS 2.23.11 ships only a Nextcloud proxy (`/fs/`) and lacks a health
endpoint. openDesk Edu runs **OpenCloud** as its file service, so we add:

| File | Change |
|---|---|
| `routes/oc.js` | `/oc/` proxy → OpenCloud (Keycloak token exchange to the `opendesk-opencloud` audience) |
| `routes/sogo.js` | `/sogo/` CalDAV/CardDAV proxy → SOGo (route present; enabled via `SOGO_ENABLED`) |
| `routes/health.js` | `/health` Kubernetes probe endpoint |
| `config/config.js` | `opencloud` + `sogo` config blocks (`OC_ENABLED`/`OC_URL`/`OC_AUDIENCE`, `SOGO_ENABLED`/`SOGO_URL`) |
| `routes/fs.js`, `wiki.js`, `nob.js`, `navigation.js` | proxy creation guarded on backend `enabled`/`url` (upstream creates proxies unconditionally and crashes when a backend URL is unset) |
| `routes/index.js`, `app.js` | register + mount the new routes |
| `Dockerfile` | Node 20 Alpine base instead of the 2GB UCS base image (per the community-consensus article) |

## How the image is built

1. Check out the upstream tree:
   `git clone https://gitlab.opencode.de/bmi/opendesk/component-code/crossfunctional/univention/univention_ics`
   (the upstream source lives at `intercom/` inside that repo).
2. Copy the upstream `intercom/` tree here **minus** `node_modules`, then
   overlay the files from this directory.
3. Build + push:
   ```sh
   docker build -t ghcr.io/opendesk-edu/intercom-service:2.23.11 .
   # SCS air-gap push (registry on the control-plane node):
   docker save ghcr.io/opendesk-edu/intercom-service:2.23.11 | ssh scs@172.25.24.36 "docker load"
   ssh scs@172.25.24.36 "docker tag ghcr.io/opendesk-edu/intercom-service:2.23.11 172.17.0.6:5001/ghcr.io/opendesk-edu/intercom-service:2.23.11 && docker push 172.17.0.6:5001/ghcr.io/opendesk-edu/intercom-service:2.23.11"
   ```
   The cluster's containerd mirrors `ghcr.io/*` to `http://172.17.0.6:5001`, so
   pods reference the image by its original name `ghcr.io/opendesk-edu/intercom-service:2.23.11`.

## Config env (fork additions)

| env | default | purpose |
|---|---|---|
| `OC_ENABLED` | `false` | enable the `/oc/` OpenCloud proxy |
| `OC_URL` | — | OpenCloud base URL (e.g. `https://cloud.home.opendesk-edu.org`) |
| `OC_AUDIENCE` | — | Keycloak audience for token exchange (e.g. `opendesk-opencloud`) |
| `SOGO_ENABLED` | `false` | enable the `/sogo/` CalDAV/CardDAV proxy |
| `SOGO_URL` | — | SOGo base URL |

See `platform/kubernetes/services/intercom-service.nix` for the deployed values.
