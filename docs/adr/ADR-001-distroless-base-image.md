# ADR-001: Switch Runtime Base Image to Distroless

**Date:** 2026-07-08  
**Status:** Accepted  
**Author:** Mayank Sekhar / Thinkwerke

## Context

Trivy image scan of `python:3.12-slim` runtime stage found **108 OS-layer CVEs**
including 2 CRITICAL in `perl-base` (CVE-2026-42496, CVE-2026-8376).
These packages (perl, curl, gzip, ncurses) are not required at runtime.
The CI pipeline gate blocks on CRITICAL, preventing deployment.

## Decision

Replace the runtime stage base image with
`gcr.io/distroless/python3-debian12:nonroot`.

Distroless images contain only the application and its runtime dependencies —
no shell, no package manager, no unnecessary OS utilities.

## Consequences

**Positive:**
- Eliminates all 108 Debian OS-layer CVEs
- No shell = reduced attack surface (no RCE via shell injection)
- `nonroot` tag enforces UID 65532 — no root at runtime
- Smaller image surface area
- Trivy CRITICAL gate will pass

**Negative:**
- No shell for debugging — use `kubectl exec` with ephemeral debug containers
- Entrypoint must be explicit binary path, not shell script
- docker-entrypoint.sh removed — replaced with direct uvicorn invocation

## Alternatives Considered

- `python:3.12-alpine` — smaller than slim but still has OS packages and CVEs
- `scratch` — too minimal, Python runtime not available
- Accepted tradeoff: lose shell convenience, gain security posture
