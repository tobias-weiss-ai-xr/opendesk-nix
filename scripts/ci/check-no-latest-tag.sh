#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# CI gate: forbid introducing NEW container images pinned to the
# non-reproducible "latest" tag.
#
# Rationale: ":latest" causes non-reproducible deploys and image drift, which
# was the root cause of the OpenCloud Bleve/BoltDB corruption incident
# (2026-08-15). Every service SHOULD pin an explicit, immutable version tag.
#
# Policy (forbid-new / track-existing):
#   * Any `tag = "latest"` in a file NOT listed in the baseline FAILS the check
#     (a NEW :latest was introduced - exactly the regression we want to block).
#   * Files listed in scripts/ci/latest-tag-baseline.txt are KNOWN :latest
#     services (debt). They are permitted so CI stays green, but should be
#     pinned over time. Remove a file from the baseline as soon as it is pinned.
#
# NOTE: most remaining :latest services are project-built images
# (ghcr.io/opendesk-edu/*) whose version tags are not published/verifiable from
# this environment. Pinning them requires the image pipeline to publish version
# tags. Until then they live in the baseline as tracked debt.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE="${2:-${BASELINE_FILE:-$SCRIPT_DIR/latest-tag-baseline.txt}}"

echo "Scanning ${ROOT} for image tag = \"latest\" ..."

# Match explicit `tag = "latest"`. The lib default `tag ? "latest"` (note the
# `?`) is intentionally NOT matched - it is a parameter default, not a pin.
mapfile -t bad < <(grep -rEn 'tag[[:space:]]*=[[:space:]]*"latest"' "$ROOT" 2>/dev/null || true)

# Load baseline (files permitted to use :latest) - tracked debt.
declare -A allowed
if [ -f "$BASELINE" ]; then
  while IFS= read -r f; do
    f="${f%$''}"  # strip CR (baseline file is checked out with CRLF)
    [ -n "$f" ] && allowed["$f"]=1
  done < "$BASELINE"
fi

# Classify matches: new (not in baseline) => FAIL; baseline => tracked (warn).
new_bad=()
for entry in "${bad[@]:-}"; do
  [ -z "$entry" ] && continue
  f="${entry%%:*}"
  # Normalise to a path relative to the scanned root. The root is a Nix
  # store path when invoked from flake.nix (${./platform/kubernetes/services}
  # is copied to /nix/store/<hash>-services), so the literal
  # 'platform/kubernetes/services/' prefix never appears there and the
  # baseline could never match — every tracked :latest file was reported
  # as new. Strip the actual root prefix instead; fall back to the bare
  # filename for store-path copies.
  rel="${f#*"$ROOT/"}"
  if [ -z "$rel" ] || [ "$rel" = "$f" ]; then
    rel="${f##*/}"
  fi
  if [ -z "${allowed[$rel]:-}" ]; then
    new_bad+=("$entry")
  fi
done

if [ "${#new_bad[@]}" -gt 0 ]; then
  echo "ERROR: ${#new_bad[@]} NEW location(s) pin image tag \"latest\" (not in baseline):" >&2
  printf '  %s\n' "${new_bad[@]}" >&2
  echo "Pin to an explicit version tag, e.g. tag = \"v1.2.3\"." >&2
  echo "If this is a pre-existing project-built image, add it to scripts/ci/latest-tag-baseline.txt (tracked debt)." >&2
  exit 1
fi

echo "OK: no NEW image tag \"latest\". (${#bad[@]} pre-existing location(s) tracked in baseline as debt to be pinned.)"
