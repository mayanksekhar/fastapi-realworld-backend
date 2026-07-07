# Security Audit Report — Baseline (Before DevSecOps Pipeline)

**Date:** 2026-07-08  
**Target:** `borys25ol/fastapi-realworld-backend` (forked, unmodified)  
**Auditor:** Mayank Sekhar / Thinkwerke  
**Branch:** `audit/initial-security-scan`

## Summary

No security pipeline existed in the upstream repository. This report documents
findings from five scanners run against the unmodified codebase and container image.

| Scanner | Tool | Findings |
|---------|------|----------|
| SAST | Bandit 1.9.4 | 116 Low |
| SAST | Semgrep OSS | 2 Blocking |
| SCA | Grype 0.115.0 | 14 CVEs (5H, 7M, 2L) |
| Secret Scan | Gitleaks 8.30.0 | 0 |
| Filesystem Scan | Trivy 0.69.3 | 11 CVEs (4H, 7M) |
| Image Scan (OS) | Trivy 0.69.3 | 108 CVEs (2C, 29H, 77M) |
| Image Scan (Python) | Trivy 0.69.3 | 14 CVEs (4H, 10M) |

**Total unique CVEs across all scans: 122**

---

## Critical Findings

### CRIT-001 — JWT Authentication Bypass (CVE-2026-48526)
- **Package:** pyjwt 2.10.1
- **Severity:** HIGH
- **Impact:** Forged JSON Web Tokens can bypass authentication — directly exploitable
  against this app's `/api/users/login` and protected routes.
- **Fix:** Upgrade to pyjwt >= 2.13.0

### CRIT-002 — Starlette SSRF via StaticFiles (CVE-2026-48818)
- **Package:** starlette 0.50.0
- **Severity:** HIGH
- **Impact:** SSRF and NTLM credential theft via UNC paths in StaticFiles handler.
- **Fix:** Upgrade to starlette >= 1.1.0 (via fastapi upgrade)

### CRIT-003 — OS Layer Bloat: 108 Debian CVEs
- **Base Image:** python:3.12-slim (Debian 13.5)
- **Severity:** 2 CRITICAL, 29 HIGH
- **Root Cause:** curl, perl, ncurses, glibc included in slim image but not required
  at runtime.
- **Fix:** Switch to distroless/python3 base — eliminates OS-layer CVEs entirely.

### CRIT-004 — PyJWT crit Header Bypass (CVE-2026-32597)
- **Package:** pyjwt 2.10.1
- **Severity:** HIGH
- **Impact:** Accepts unknown `crit` header extensions in violation of RFC 7515,
  enabling token manipulation.
- **Fix:** Upgrade to pyjwt >= 2.12.0

---

## Container Hardening Gaps

| Check | Status |
|-------|--------|
| Non-root user | ✅ Runs as `app` |
| Read-only filesystem | ❌ Not enforced |
| Dropped Linux capabilities | ❌ Not configured |
| Distroless / minimal base | ❌ Debian slim (108 OS CVEs) |
| Multi-stage build | ✅ Present |
| SBOM generated | ❌ None |
| Image signed (Cosign) | ❌ None |
| No build tools in runtime layer | ✅ Wheels copied, builder discarded |

---

## Remediation Plan

This baseline is the "before" state. The DevSecOps pipeline built in subsequent
commits will address all findings above through:

1. Automated SCA gating (Grype) — blocks merge on HIGH/CRITICAL CVEs
2. SAST in CI (Bandit + Semgrep) — blocks on blocking findings  
3. Dependency pinning with fixed versions in requirements.txt
4. Hardened Dockerfile (distroless base, read-only FS, dropped caps)
5. Image signing (Cosign keyless) + SBOM (Syft/CycloneDX)
6. EKS deployment with Kyverno policies enforcing pod security

