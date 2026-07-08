# FastAPI RealWorld - DevSecOps

A demonstration of applying a full DevSecOps pipeline and container hardening to
a real, unsecured open-source application - and proving the pipeline works by
having it find and gate on real vulnerabilities.

Forked from [`borys25ol/fastapi-realworld-backend`](https://github.com/borys25ol/fastapi-realworld-backend),
an implementation of the [RealWorld](https://github.com/gothinkster/realworld)
spec (a Medium clone: JWT auth, articles, comments, profiles, follows, on
PostgreSQL). The upstream app had no security tooling. This fork adds one.

## The Result

| | Before | After |
|-|--------|-------|
| Blocking CVEs | **122** | **0** |
| OS-layer CVEs | 108 (2 CRITICAL) | 0 |
| Dependency CVEs | 14 (4 HIGH) | 0 |
| Image signed | No | Yes (Cosign keyless) |
| SBOM | None | CycloneDX, attested |

This is not a greenfield demo on clean code. It is a documented remediation of
122 findings on an app that shipped with zero security scanning.

## The Pipeline

Five gates run on every push and pull request. Each blocks promotion on findings
at or above its threshold.
secret-scan  ->  sast  ->  sca  ->  build + image-scan  ->  sign + attest
Gitleaks       Bandit     Grype      Trivy (CRITICAL)      Cosign + Syft
Semgrep     Trivy fs

| Stage | Tools | Gate |
|-------|-------|------|
| Secret scanning | Gitleaks | Any committed secret |
| SAST | Bandit, Semgrep | Blocking findings |
| SCA | Grype, Trivy fs | HIGH / CRITICAL dependency CVEs |
| Image scan | Trivy | CRITICAL image CVEs |
| Sign + attest | Cosign, Syft | Keyless signature + CycloneDX SBOM |

## Container Hardening

The runtime image uses [Chainguard's Wolfi-based Python image](https://images.chainguard.dev/directory/image/python/overview),
which ships at zero CVEs, runs as nonroot, and has no shell. The path there is
documented in [ADR-001](docs/adr/ADR-001-hardened-base-image.md):

python:3.12-slim (108 OS CVEs) -> distroless (29, unfixable) -> Chainguard Wolfi (0)

## Verify the Supply Chain

The published image is signed and carries an attested SBOM. Verify with no key:

```bash
cosign verify ghcr.io/mayanksekhar/fastapi-realworld-devsecops:<sha> \
  --certificate-identity-regexp="https://github.com/mayanksekhar" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

## Documentation

| Document | What it covers |
|----------|----------------|
| [AUDIT-REPORT.md](docs/findings/AUDIT-REPORT.md) | Baseline scan - the 122 CVEs found before any pipeline |
| [AFTER-REPORT.md](docs/findings/AFTER-REPORT.md) | Remediation - how each gate was made to pass |
| [THREAT_MODEL.md](docs/THREAT_MODEL.md) | STRIDE analysis of the Conduit API |
| [ADR-001](docs/adr/ADR-001-hardened-base-image.md) | Base image decision record |

## Roadmap

- [x] DevSecOps pipeline (secret, SAST, SCA, image scan, sign, attest)
- [x] Container hardening to zero CVEs
- [x] Threat model (STRIDE)
- [ ] EKS deployment with hardened image
- [ ] Kyverno admission policies (pod security enforcement)
- [ ] Falco runtime detection

## Credits

Application code: [`borys25ol/fastapi-realworld-backend`](https://github.com/borys25ol/fastapi-realworld-backend).
DevSecOps pipeline, hardening, and security documentation: Mayank Sekhar / Thinkwerke.
