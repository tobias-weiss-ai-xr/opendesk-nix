# Security Review for Public Release

**Date:** 2026-08-07  
**Status:** ⚠️ Requires Cleanup Before Public Release  
**Review Type:** Internal Infrastructure Exposure Assessment

---

## Executive Summary

This document identifies sensitive information that must be removed or redacted before making the `opendesk-nix` repository public on GitHub.

### Overall Assessment: ✅ SAFE WITH MINOR CHANGES

The repository is **mostly safe** for public release. Only **3 files** contain internal infrastructure references that need to be replaced with generic placeholders.

---

## Sensitive Information Found

### 🔴 High Priority - Must Remove

#### Internal IP Addresses

| File | Line | Content | Risk |
|------|------|---------|------|
| `lib/registry.nix` | 103 | `172.17.209.143:5000` | Internal registry IP |
| `lib/integrated-devguard.nix` | 756 | `172.17.209.143:5000` | Internal registry IP |
| `lib/ci-cd/container-gov-de.nix` | 20 | `172.17.209.143:5000` | Internal registry IP |

**Impact:** Reveals internal network topology and registry infrastructure

**Remediation:** Replace with generic placeholder

---

### 🟡 Medium Priority - Review Required

#### HRZ Public Hostnames

| File Pattern | Count | Example | Risk |
|--------------|-------|---------|------|
| `*.nix` | 20+ | `opendesk.hrz.uni-marburg.de` | Low - Public-facing URL |

**Impact:** Minimal - These are public-facing URLs already visible in production

**Recommendation:** Keep as-is (these are public deployment targets)

---

### 🟢 Low Priority - Informational

#### Placeholder Passwords

| File | Content | Risk |
|------|---------|------|
| `templates/container-gov-de/nixos-config.nix` | `ChangeMe123` | None - Clearly placeholder |

**Impact:** None - These are clearly placeholder values in templates

**Recommendation:** Keep as-is (documented as "Change Me")

---

## Cleanup Actions Required

### 1. Replace Internal Registry IP

**Files to modify:**
- `lib/registry.nix` (line 103)
- `lib/integrated-devguard.nix` (line 756)
- `lib/ci-cd/container-gov-de.nix` (line 20)

**Change from:**
```nix
fallback = "172.17.209.143:5000";
```

**Change to:**
```nix
fallback = "registry.example.com:5000";  # Replace with your registry
```

Or use environment variable:
```nix
fallback = builtins.getEnv "REGISTRY_FALLBACK" or "registry.example.com:5000";
```

---

### 2. Update Health Check Script

**File:** `lib/integrated-devguard.nix` (line 756)

**Current:**
```bash
REGISTRIES=("ghcr.io" "registry.gitlab.com" "172.17.209.143:5000")
```

**Change to:**
```bash
REGISTRIES=("ghcr.io" "registry.gitlab.com" "registry.example.com:5000")
```

---

## Public Release Checklist

- [ ] Replace `172.17.209.143:5000` with placeholder in `lib/registry.nix`
- [ ] Replace `172.17.209.143:5000` with placeholder in `lib/integrated-devguard.nix`
- [ ] Replace `172.17.209.143:5000` with placeholder in `lib/ci-cd/container-gov-de.nix`
- [ ] Verify no secrets in `.env` files (already in `.gitignore`)
- [ ] Verify no credentials in CI/CD configs
- [ ] Add `SECURITY-REVIEW.md` to repository root
- [ ] Document registry configuration in README

---

## Safe to Publish Information

### ✅ Public-Facing URLs (Safe)
- `opendesk.hrz.uni-marburg.de` - Public deployment target
- `registry.opencode.de` - Public GitLab registry
- `ghcr.io/tobias-weiss-ai-xr` - Public GitHub registry

### ✅ Configuration Templates (Safe)
- Placeholder passwords (`ChangeMe123`)
- Example configurations
- Documentation with public URLs

### ✅ Security Policies (Safe)
- Kyverno policies
- Compliance checks
- Security scanning configurations

---

## Recommendation

**Status:** ✅ **SAFE TO PUBLISH AFTER CLEANUP**

The repository contains **minimal sensitive information** that is easily remediated:

1. **3 internal IP references** - Replace with generic placeholders
2. **Public HRZ URLs** - Safe to keep (public deployment targets)
3. **Placeholder credentials** - Safe to keep (clearly marked)

**Estimated cleanup time:** 5 minutes

**Risk after cleanup:** 🟢 **LOW**

---

## Post-Publication Notes

### What's Safe to Share Publicly

- ✅ Nix build configurations
- ✅ Container definitions
- ✅ Security policies (Kyverno)
- ✅ Compliance frameworks (ZKI-IT-Grundschutz)
- ✅ CI/CD pipeline templates
- ✅ Documentation and examples

### What Should Remain Private

- 🔒 Actual registry credentials (use environment variables)
- 🔒 Internal network topology (already removed)
- 🔒 Production secrets (use Vault/Sealed Secrets)
- 🔒 Private SSH keys (use keyless signing)

---

## Contact

For security concerns, contact:
- **Security Team:** security@opendesk-edu.org
- **DPO:** datenschutz@hrz.uni-marburg.de

---

**Last Updated:** 2026-08-07  
**Next Review:** Before each major release
