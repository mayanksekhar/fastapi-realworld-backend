# Security Remediation Report - After DevSecOps Pipeline

**Date:** 2026-07-08
**Target:** `mayanksekhar/fastapi-realworld-devsecops` (forked from `borys25ol/fastapi-realworld-backend`)
**Author:** Mayank Sekhar / Thinkwerke
**Companion to:** `AUDIT-REPORT.md` (baseline / before state)

## Summary

The baseline audit found 122 CVEs across the container image and Python
dependencies, with no security pipeline present upstream. This report documents
the remediation: a five-stage DevSecOps pipeline that gates on findings, and the
fixes applied to pass those gates.

The headline result: **122 blocking CVEs reduced to 0** (HIGH/CRITICAL), with a
signed image and SBOM attestation proving supply chain integrity.

## Before vs After

| Layer | Before | After |
|-------|--------|-------|
| OS-layer CVEs (container) | 108 (2 CRITICAL, 29 HIGH) | 0 |
| Python dependency CVEs | 14 (4 HIGH) | 0 |
| Base image | python:3.12-slim (Debian 13.5) | cgr.dev/chainguard/python (Wolfi) |
| Image signed | No | Yes (Cosign keyless) |
| SBOM | None | CycloneDX, attested to image |
| Pipeline gates | None | 5 stages, blocking on HIGH/CRITICAL |
| **Total blocking CVEs** | **122** | **0** |

## The Pipeline

Five stages run on every push and pull request. Each gate blocks promotion when
it finds issues at or above its severity threshold.
secret-scan  ->  sast  ->  sca  ->  build + image-scan  ->  sign + attest
Gitleaks       Bandit     Grype      Trivy (CRITICAL)      Cosign + Syft
Semgrep     Trivy fs
## How the Gates Proved Themselves

The pipeline was not tuned to pass on the first run. It was run against the
unmodified app first, and it correctly blocked. The remediation below was driven
by real gate failures, visible in the Actions history.

### Gate 1: SCA (Grype + Trivy filesystem)

The SCA stage failed on the first run with 14 dependency CVEs. Remediation:

| Package | Before | After | CVEs Resolved |
|---------|--------|-------|---------------|
| pyjwt | 2.10.1 | 2.13.0 | CVE-2026-48526 (JWT auth bypass), CVE-2026-32597, CVE-2026-48522 (SSRF), CVE-2026-48523, CVE-2026-48525 |
| starlette | 0.50.0 | 1.3.1 | CVE-2026-48818 (SSRF + NTLM theft), CVE-2026-54283 (DoS), CVE-2026-48710, CVE-2026-48817 |
| pydantic-settings | 2.12.0 | 2.14.2 | GHSA-4xgf-cpjx-pc3j (symlink traversal) |
| pytest | 9.0.2 | 9.0.3 | CVE-2025-71176 (privilege escalation) |
| black | 26.1.0 | 26.3.1 | GHSA-3936-cmfr-pm3m |

The starlette fix required a transitive dependency resolution. `fastapi==0.131.0`
capped starlette below the patched version, so fastapi was upgraded to 0.136.1
and starlette pinned explicitly to 1.3.1. Pinning the transitive dependency
directly follows the FastAPI maintainers' guidance that securing the resolved
dependency set is the application developer's responsibility.

### Gate 2: Image Scan (Trivy)

After the dependency fixes, the image scan still blocked on 122 CVEs from the
Debian base image, including 2 CRITICAL in `perl-base` (CVE-2026-42496 path
traversal, CVE-2026-8376 heap overflow). These OS packages (perl, curl, gzip,
ncurses, glibc) are not required at runtime.

The base image was hardened in two documented steps (see
`docs/adr/ADR-001-hardened-base-image.md`):

| Base image | OS CVEs | Verdict |
|------------|---------|---------|
| python:3.12-slim (Debian 13.5) | 108 (2 CRITICAL) | Rejected |
| distroless/python3-debian12 | 29 (5 CRITICAL) | Rejected - CRITICAL CVEs marked will_not_fix / fix_deferred by Debian |
| cgr.dev/chainguard/python (Wolfi) | 0 | Accepted |

The distroless step is worth noting: it reduced the package count from 109 to 34
but still carried unfixable CVEs in the bundled Debian 12 layer (zlib
CVE-2023-45853, sqlite CVE-2025-7458, cpython stdlib). Debian will not ship
fixes for these, so no amount of patching the layer would clear the gate.
Chainguard's Wolfi is continuously rebuilt and shipped at zero CVEs, which is
what allowed the gate to pass.

### Gates That Passed Clean

- **Secret scan (Gitleaks):** 0 findings. No credentials committed upstream.
- **SAST (Bandit):** 116 low-severity findings, none blocking. These are
  informational (assert usage in tests, standard library calls) and do not meet
  the gate threshold.
- **SAST (Semgrep):** 2 findings reviewed, non-blocking after triage.

## Supply Chain Integrity

The final image is signed and carries an attested SBOM. Both artifacts are
published to GHCR alongside the image and are publicly verifiable.

Published artifacts:
- `latest` / `<sha>` - the signed application image
- `sha256-<digest>.sig` - Cosign signature (keyless, Sigstore)
- `sha256-<digest>.att` - CycloneDX SBOM attestation

Verification (no key required, uses GitHub Actions OIDC identity):

```bash
cosign verify ghcr.io/mayanksekhar/fastapi-realworld-devsecops:<sha> \
  --certificate-identity-regexp="https://github.com/mayanksekhar" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

This establishes SLSA-aligned provenance: the image can be traced to the exact
workflow run and commit that produced it, and any tampering after signing is
detectable.

## Residual Risk

- **Bandit low-severity findings (116):** accepted. Reviewed as informational;
  no action required. Documented here rather than suppressed silently.
- **Base image pinned to :latest:** Chainguard's :latest currently ships Python
  3.14. For fully reproducible builds, pin to a digest and update via automation.
  Tracked as a follow-up.
- **Runtime security:** static and supply chain layers are covered. Runtime
  detection (Falco) and admission control (Kyverno) are planned for the EKS
  deployment phase.

## Conclusion

The pipeline does what a DevSecOps pipeline is supposed to do: it caught real,
exploitable vulnerabilities in a real application and blocked them from shipping
until they were fixed. The before/after is not a demo on clean code - it is a
documented remediation of 122 findings on an app that had zero security tooling.
