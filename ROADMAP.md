# Roadmap

## 0.1 — trustworthy MVP

- [x] v1 Markdown/YAML parser and open draft specification
- [x] worktree-safe private and shared card discovery
- [x] deterministic `find` and provenance-aware `show`
- [x] reviewed private/team `new` workflow
- [x] secret, risk, lifecycle, and quality `lint`
- [x] 1,000-card performance gate
- [x] cross-platform CI and security automation proven green
- [x] complete user and authoring documentation
- [x] provenance-attested prerelease artifacts with checksums and SBOM

## Validation before 1.0

The security-hardened production-v1 implementation is prepared as
`1.0.0-rc.7`. Stable release
promotion remains intentionally blocked on evidence rather than code volume:

- assemble at least 100 permissioned, sanitized real failure/resolution pairs;
- conduct the diary study and concierge test described in the research memo;
- dogfood in 5–8 active repositories for four weeks;
- achieve at least 80% judged relevance for strong rank-one matches, targeting
  85%, with every predeclared kill criterion overriding an otherwise passing
  gate;
- demonstrate median creation at or below 20 seconds after a fix is known;
- demonstrate real reuse by authors or teammates without a serious safety event;
- publish anonymized methodology and a go/change/stop decision.

## Explicitly not planned

Automatic shell-history capture, generated fixes, model calls, cloud accounts,
workflow replay, command execution, a public universal fix corpus, a dashboard,
or an incident-response platform. Evidence may justify editor selection helpers
or CI lookup later, but integrations are not a substitute for a useful core.
