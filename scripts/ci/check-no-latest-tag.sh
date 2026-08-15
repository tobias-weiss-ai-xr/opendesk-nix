#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# CI gate: forbid pinning container images to the non-reproducible "latest" tag.
#
# Rationale: ":latest" causes non-reproducible deploys and image drift, which
# was the root cause of the OpenCloud Bleve/BoltDB corruption incident
# (2026-08-15). Every service MUST pin an explicit, immutable version tag so a
# redeploy cannot silently pull a different image (and corrupt stateful data).
#
# This check FAILS (exit 1) if any Kubernetes service in the scanned tree pins
# `tag = "latest"`.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
echo "Scanning ${ROOT} for image tag = \"latest\" ..."

# Match explicit `tag = "latest"`. The lib default `tag ? "latest"` (note the
# `?`) is intentionally NOT matched - it is a parameter default, not a pin.
mapfile -t bad < <(grep -rEn 'tag[[:space:]]*=[[:space:]]*"latest"' "$ROOT" 2>/dev/null || true)

if [ "${#bad[@]}" -gt 0 ]; then
  echo "ERROR: ${#bad[@]} location(s) pin image tag \"latest\" (non-reproducible, drift risk):" >&2
  printf '  %s\n' "${bad[@]}" >&2
  echo "Pin to an explicit version tag, e.g. tag = \"v1.2.3\"." >&2
  exit 1
fi

echo "OK: no service pins image tag \"latest\"."
