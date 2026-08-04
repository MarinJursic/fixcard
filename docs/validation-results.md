# Validation results

Last assessed: 2026-08-04.

## Decision

**Insufficient evidence — remain on `1.0.0-rc.2`.** Engineering verification is
green, but no eligible primary-research or dogfood report has been submitted.
Missing evidence is not treated as a zero, a pass, or a reconstructed estimate.

## Evidence ledger

| Stage | Required coverage | Eligible documented evidence | Status |
| --- | --- | --- | --- |
| Evidence corpus | At least 100 sanitized real failure/resolution pairs with permission and second-person review | None submitted | Not started / not documented |
| Problem diary | 24–30 developers across the specified contexts, roles, and platforms for two working weeks | None submitted | Not started / not documented |
| Concierge workflow | Three real cards per participant plus controlled recurrences and maintainer review | None submitted | Not started / not documented |
| Dogfood pilot | One exact build in 5–8 active repositories for four weeks | No report issues; release published 2026-08-03 | Too early / insufficient |

All product thresholds therefore remain unproven, including recurrence
frequency, concierge creation time, seeded retrieval precision, comparative
trust, real rank-one relevance, capture behavior, reuse, team acceptance,
privacy false-positive burden, differentiation, and maintenance burden.

## Verified engineering baseline

Release candidate `1.0.0-rc.2` has repository tests, hosted Linux/macOS/Windows
checks, Rust 1.85 compatibility, dependency and policy audits, performance
gates, native release smoke tests, checksums, a CycloneDX SBOM, GitHub
attestations, and a separately tested Homebrew formula. These results prove the
implementation baseline; they do not prove product behavior.

## Reporting

Follow the [research operations guide](research-operations.md), the
[pre-pilot protocol](research-study.md), and the
[four-week dogfood protocol](dogfood.md). Submit Stage 3 results through the
[sanitized validation form](https://github.com/MarinJursic/fixcard/issues/new?template=validation-report.yml).
The umbrella tracker is
[issue #5](https://github.com/MarinJursic/fixcard/issues/5).
