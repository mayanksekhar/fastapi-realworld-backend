# Threat Model - Conduit API (RealWorld)

**Date:** 2026-07-08
**Author:** Mayank Sekhar / Thinkwerke
**Methodology:** STRIDE
**Scope:** The Conduit backend API (FastAPI), its JWT authentication, and its
container/deployment surface. Frontend clients are out of scope.

## System Overview

Conduit is a Medium-style article platform. The API exposes:

- **Auth:** user registration, login (JWT issuance)
- **Users:** profile read/update, follow/unfollow
- **Articles:** CRUD, favourite/unfavourite, tag listing
- **Comments:** create, list, delete
- **Feed:** personalised article feed for authenticated users

Data lives in PostgreSQL. Authentication is stateless via JWT bearer tokens.
Passwords are hashed with bcrypt (passlib).

## Trust Boundaries

1. **Internet -> API:** unauthenticated and authenticated HTTP traffic.
2. **API -> PostgreSQL:** application to database, inside the cluster/network.
3. **Build -> Registry:** CI produces and signs the image, pushes to GHCR.
4. **Registry -> Runtime:** cluster pulls the image for deployment.

## STRIDE Analysis

### Spoofing (identity)

| Threat | Vector | Mitigation |
|--------|--------|------------|
| Forged JWT to impersonate a user | Weak/legacy JWT library accepting forged tokens | pyjwt upgraded to 2.13.0 (CVE-2026-48526 auth bypass patched). Algorithm pinned; no `none` acceptance. |
| Credential stuffing on login | Reused passwords against /users/login | bcrypt hashing; rate limiting recommended at ingress (follow-up). |
| Algorithm confusion (RS/HS swap) | Attacker changes `alg` header | pyjwt CVE-2026-32597 (crit header handling) and CVE-2026-48523 (algorithm bypass) patched via upgrade. Explicit algorithm allowlist in verification. |

### Tampering (integrity)

| Threat | Vector | Mitigation |
|--------|--------|------------|
| Modified container image in registry | Supply chain interference between build and deploy | Cosign keyless signing; verification gate before deploy. Any post-signing tampering is detectable. |
| SQL injection via article/comment input | Unsanitised query construction | SQLAlchemy ORM with parameterised queries. Semgrep SAST gate scans for raw SQL patterns. |
| Dependency substitution / typosquat | Malicious package in supply chain | Pinned versions in requirements.txt; Grype + Trivy SCA gate; SBOM generated for every build. |

### Repudiation (non-attributability)

| Threat | Vector | Mitigation |
|--------|--------|------------|
| User denies performing an action | No audit trail | structlog structured logging present. Recommend shipping logs to a tamper-evident store in production. |
| Untraceable image provenance | Cannot prove what produced an image | SBOM attestation + Cosign signature tie the image to the exact commit and workflow run (SLSA-aligned provenance). |

### Information Disclosure (confidentiality)

| Threat | Vector | Mitigation |
|--------|--------|------------|
| SSRF via JWKS/URL fetching | pyjwt PyJWKClient fetching attacker URLs | CVE-2026-48522 patched via pyjwt upgrade. |
| SSRF + credential theft via StaticFiles | starlette UNC path handling | CVE-2026-48818 patched via starlette 1.3.1. |
| Secrets leaked in image or repo | Hardcoded credentials, .env committed | Gitleaks gate on every push (0 findings). SECRET_KEY injected at runtime, never baked into the image. |
| Verbose error responses | Stack traces exposed to clients | Ensure debug mode disabled in production config. |
| Host header injection | Malformed Host bypassing restrictions | starlette CVE-2026-48710 patched. |

### Denial of Service (availability)

| Threat | Vector | Mitigation |
|--------|--------|------------|
| Request body DoS | starlette form-limit bypass | CVE-2026-54283 patched via starlette 1.3.1. |
| Detached JWS token DoS | pyjwt processing of crafted tokens | CVE-2026-48525 patched via pyjwt upgrade. |
| Unbounded resource use | No rate limiting on expensive endpoints | Recommend ingress-level rate limiting and pod resource limits (EKS phase). |

### Elevation of Privilege

| Threat | Vector | Mitigation |
|--------|--------|------------|
| Container escape via root process | App running as root in container | Chainguard base runs as nonroot (UID 65532) by default. No shell in runtime image. |
| Privilege escalation via temp dir | pytest insecure temp directory | CVE-2025-71176 patched (test dependency; low runtime relevance but gated regardless). |
| Symlink traversal to read secrets | pydantic-settings following symlinks | GHSA-4xgf-cpjx-pc3j patched via upgrade to 2.14.2. |
| Pod privilege escalation at runtime | Overprivileged pod spec | Planned: Kyverno policies enforcing runAsNonRoot, readOnlyRootFilesystem, dropped capabilities (EKS phase). |

## Attack Surface Summary

The highest-value target is the JWT authentication path. A forged-token
vulnerability there (CVE-2026-48526) would grant full account takeover, which is
why it was the priority fix. The second cluster of risk is SSRF, appearing in
both pyjwt and starlette, addressable through dependency upgrades.

The container hardening (nonroot, no shell, zero OS CVEs) closes the elevation
and lateral-movement paths that would otherwise turn a single app compromise
into host or cluster compromise.

## Coverage by Pipeline Stage

| STRIDE Category | Covering Control |
|-----------------|------------------|
| Spoofing | pyjwt upgrade, algorithm pinning |
| Tampering | Cosign signing, SCA gate, SAST |
| Repudiation | structlog, SBOM attestation |
| Information Disclosure | Gitleaks, dependency patches, runtime secret injection |
| Denial of Service | dependency patches, planned rate limiting |
| Elevation of Privilege | Chainguard nonroot base, planned Kyverno policies |

## Follow-ups (EKS Phase)

- Kyverno admission policies (pod security enforcement)
- Falco runtime detection (anomalous syscalls, secret file reads)
- Ingress rate limiting
- NetworkPolicy to constrain API-to-database traffic
- Cosign verification as an admission gate
