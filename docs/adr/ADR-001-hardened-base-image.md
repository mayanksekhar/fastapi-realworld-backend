That's a clean scan. Zero HIGH, zero CRITICAL. No findings table printed because there's nothing to report.
Let me put this in perspective — what you just did:
StageBeforeAfterOS layer CVEs108 (2 CRITICAL)0Python dep CVEs14 (4 HIGH)0Base imagepython:3.12-slim (Debian)Chainguard WolfiTotal blocking122 CVEs0
Now let's lock it in. Commit the working Dockerfile and push so the pipeline runs green end-to-end.
bashcd ~/fastapi-realworld-backend

# Update the ADR to reflect Chainguard (not distroless)
cat > docs/adr/ADR-001-hardened-base-image.md << 'EOF'
# ADR-001: Hardened Base Image — Chainguard Wolfi

**Date:** 2026-07-08
**Status:** Accepted
**Author:** Mayank Sekhar / Thinkwerke

## Context

Trivy image scan of the original `python:3.12-slim` (Debian 13) runtime found
**122 CVEs** including 2 CRITICAL in perl-base. Switching to
`distroless/python3-debian12` reduced this but still carried 29 OS CVEs
(5 CRITICAL) from the bundled Debian 12 layer — zlib, sqlite, expat, cpython —
most marked will_not_fix or fix_deferred by Debian.

## Decision

Use Chainguard's Wolfi-based Python images:
- Builder: `cgr.dev/chainguard/python:latest-dev` (has pip, venv, shell)
- Runtime: `cgr.dev/chainguard/python:latest` (no shell, no package manager)

Wolfi is a continuously-patched rolling "undistro" purpose-built for low-to-zero
CVE container images. Application dependencies are installed into a venv in the
builder and copied to the minimal runtime.

## Consequences

**Positive:**
- OS-layer CVEs reduced from 108 (2 CRITICAL) to 0
- No shell in runtime = no RCE-via-shell attack surface
- Runs as nonroot (UID 65532) by default
- Continuously rebuilt — new CVEs patched upstream without base image swap
- Passes Trivy CRITICAL/HIGH gate cleanly

**Negative:**
- No shell for debugging — use ephemeral debug containers in k8s
- venv must be built in a writable path (/home/nonroot) since UID 65532 is default
- Tied to Chainguard's :latest (Python 3.14) — pin to digest for reproducible builds

## Alternatives Considered

- python:3.12-slim — 108 OS CVEs, rejected
- distroless/python3-debian12 — 29 OS CVEs (5 CRITICAL unfixable), rejected
- Chainguard Wolfi — 0 OS CVEs, accepted
