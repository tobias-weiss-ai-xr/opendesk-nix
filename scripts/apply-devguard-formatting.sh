#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# Script to apply DevGuard PR #2843 formatting patterns

set -euo pipefail

echo "Applying DevGuard PR #2843 formatting patterns..."
echo "=================================================="
echo ""

# Check if we're in the right directory
if [ ! -f "flake.nix" ]; then
    echo "ERROR: Please run this script from the repository root"
    exit 1
fi

# Check for nix
if ! command -v nix &> /dev/null; then
    echo "ERROR: Nix is not installed"
    exit 1
fi

echo "[1/4] Running treefmt (nixfmt, statix, deadnix)..."
if nix run .#formatter -- --stdin-check 2>/dev/null; then
    # If formatter is available, use it
    find . -name "*.nix" -type f | xargs nix run .#formatter -- 2>/dev/null || true
else
    # Fallback to direct treefmt if available
    if command -v treefmt &> /dev/null; then
        treefmt
    else
        echo "  WARNING: treefmt not available, skipping"
    fi
fi
echo "  ✓ treefmt complete"
echo ""

echo "[2/4] Running statix (Nix linter)..."
if command -v statix &> /dev/null; then
    find . -name "*.nix" -type f | xargs statix check 2>/dev/null || echo "  WARNING: statix found issues"
else
    echo "  WARNING: statix not available"
fi
echo ""

echo "[3/4] Running deadnix (dead code detector)..."
if command -v deadnix &> /dev/null; then
    # deadnix in check mode first
    find . -name "*.nix" -type f | xargs deadnix 2>/dev/null || echo "  WARNING: deadnix found dead code"
    # Then fix mode
    find . -name "*.nix" -type f | xargs deadnix --edit 2>/dev/null || true
else
    echo "  WARNING: deadnix not available"
fi
echo ""

echo "[4/4] Running nixfmt (Nix formatter)..."
if command -v nixfmt &> /dev/null; then
    find . -name "*.nix" -type f | xargs nixfmt 2>/dev/null || true
else
    echo "  WARNING: nixfmt not available"
fi
echo ""

echo "=================================================="
echo "Formatting application complete!"
echo ""
echo "Recommended next steps:"
echo "  1. Review changes with: git diff"
echo "  2. Test with: nix flake check"
echo "  3. Run formatting check: nix run .#formatter -- --stdin-check"
echo "  4. Commit changes"
