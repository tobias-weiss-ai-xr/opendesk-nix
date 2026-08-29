# Zot Registry (pull-through cache)

Zot v2.1.20 built from source (Nix) and shipped as a container image. It runs as
the SCS K3s cluster's local OCI registry on **:5001**, replacing the plain
`registry:2` cache, and serves **on-demand pull-through** for every upstream the
cluster references.

Per the SCS image strategy, images on GHCR are *our own Nix builds* and are
consumed cluster-facing through this local Zot; upstream `docker.io` /
`opencode.de` remain mirror-only until upstreams are paid/withdrawn.

## Why Zot (instead of `registry:2` mirror)

| Capability                    | `registry:2` (old) | Zot v2.1.20 |
|-------------------------------|--------------------|-------------|
| Pull-through on first hit     | ❌ (pre-cache only)| ✅ on-demand |
| Cache locally + serve offline | ⚠️ manual          | ✅           |
| Same registry for 5 upstreams | ❌ one upstream    | ✅ (sync)   |
| Tag/version deletion (GC)     | ❌ (405)           | ✅           |
| Auth (htpasswd/anon pull)     | ✅ basic           | ✅           |
| Metrics (Prometheus)          | ❌                 | ✅ `metrics` |

## Build

```bash
nix build .#zot        # the binary
nix build .#zot-image  # the OCI image tarball
docker load < result
docker tag zot:2.1.20-nix ghcr.io/tobias-weiss-ai-xr/umr/opendesk-edu/opendesk-nix/zot:2.1.20-nix
docker push ghcr.io/tobias-weiss-ai-xr/umr/opendesk-edu/opendesk-nix/zot:2.1.20-nix
```

Build notes:

- zot's in-tree `vendor/` is stale (modules.txt out of sync with go.mod) —
  `postUnpack` strips it and the module graph is re-vendored (hash pinned above).
- Extensions are behind Go build tags; the image enables
  `sync,scrub,metrics,lint,profile,userprefs,imagetrust,events,mgmt`.
  `search` is omitted (drags in trivy → requires `GOEXPERIMENT=jsonv2`);
  `ui` is omitted (embedded frontend).
- CA bundle is baked in (`SSL_CERT_FILE`/`SSL_CERT_DIR`) so upstream TLS
  verification works in the minimal image.

## Config

Baked into the image at `/etc/zot/config.json`. Key points:

- **Sync on-demand** with **`destination: "/"` (identity mapping)** for all five
  upstreams — the local repo path equals the upstream path, matching containerd
  mirror behaviour (host stripped, full repo path kept):
  `ghcr.io`, `registry-1.docker.io`, `registry.opencode.de`,
  `registry.gitlab.opencode.de`, `registry.k8s.io`.
- On-demand tries each registry in order and stops at the first success;
  `not found` / `unauthorized` upstreams are skipped.
- **Secrets are NOT in the image.** GHCR requires auth to read manifests, so a
  credentials file is mounted at `/etc/zot/credentials.json`:

```json
{ "ghcr.io": { "username": "tobias-weiss-ai-xr", "password": "<PAT>" } }
```

## Deploy (clrz14-06, replaces `registry:2` on :5001)

```bash
# on clrz14-06 (as root):
systemctl stop registry-cache 2>/dev/null   # or: docker rm -f registry
mkdir -p /opt/zot/data /opt/zot/secrets
# credentials.json -> /opt/zot/secrets/credentials.json (root:root 0600)
docker run -d --restart=always --name zot \
  -p 5001:5001 \
  -v /opt/zot/data:/var/lib/zot \
  -v /opt/zot/secrets/credentials.json:/etc/zot/credentials.json:ro \
  ghcr.io/tobias-weiss-ai-xr/umr/opendesk-edu/opendesk-nix/zot:2.1.20-nix
```

Nodes already mirror `ghcr.io`, `registry.k8s.io`, `docker.io` and the opencode
registries to `localhost:5001` (clrz14-06) / `172.25.24.36:5001` (clrz14-07/08),
so no `registries.yaml` change is required — the endpoints just start serving
through Zot.

## Verify

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5001/v2/          # 200
docker pull localhost:15001/tobias-weiss-ai-xr/umr/opendesk-edu/opendesk-nix/intercom-service:2.24.0-opendesk.2
# cache lands under /var/lib/zot/<repo>/blobs/sha256/...
```
