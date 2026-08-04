# Validation results

Last assessed: 2026-08-04.

## Decision

**Insufficient evidence — remain on `1.0.0-rc.4`.** Engineering verification is
green, but no eligible primary-research or dogfood report has been submitted.
Missing evidence is not treated as a zero, a pass, or a reconstructed estimate.

## Evidence ledger

| Stage | Required coverage | Eligible documented evidence | Status |
| --- | --- | --- | --- |
| Evidence corpus | At least 100 sanitized real failure/resolution pairs with permission and second-person review | None submitted | Not started / not documented |
| Problem diary | 24–30 developers across the specified contexts, roles, and platforms for two working weeks | None submitted | Not started / not documented |
| Concierge workflow | Three real cards per participant plus controlled recurrences and maintainer review | None submitted | Not started / not documented |
| Dogfood pilot | One exact build in 5–8 active repositories for four weeks | Exact pilot build `1.0.0-rc.4` published 2026-08-04; no eligible report issues submitted | Not started / insufficient |

All product thresholds therefore remain unproven, including recurrence
frequency, concierge creation time, seeded retrieval precision, comparative
trust, real rank-one relevance, capture behavior, reuse, team acceptance,
privacy false-positive burden, differentiation, and maintenance burden.

## Verified engineering baseline

Release candidate `1.0.0-rc.4` at commit
[`acf0c079`](https://github.com/MarinJursic/fixcard/commit/acf0c07944700085d56f50a02b26bbdf2525272d)
passes 75 repository tests, hosted Linux/macOS/Windows checks, Rust 1.85
compatibility, dependency and policy audits, documentation and research-form
validation, and performance gates.

The [release workflow](https://github.com/MarinJursic/fixcard/actions/runs/30926021852)
produced six native archives. Every archive contains the `fix` and `fixcard`
binaries and passed a post-packaging sibling-delegation smoke test. The
[prerelease](https://github.com/MarinJursic/fixcard/releases/tag/v1.0.0-rc.4)
also includes SHA-256 checksums, a CycloneDX SBOM, SLSA build-provenance
attestations, and SBOM attestations.

The Apple Silicon archive was independently downloaded and verified with the
published checksum (`9b9d28e7bc637ac6beb7f5c86175888ecc826b64aac1cd4de9116ef98306f0a0`).
Both packaged binaries reported `1.0.0-rc.4`, `fix` successfully delegated to
its packaged sibling, and `gh attestation verify` resolved the archive to the
tagged commit and release workflow.

The Homebrew formula at commit
[`c22efbe`](https://github.com/MarinJursic/homebrew-tap/commit/c22efbe78064a8c78192b778e270bb936e2cdb4d)
passed audit, install, formula tests, and both-binary sibling smoke checks on
x86_64/ARM Linux and Intel/Apple Silicon macOS. A clean installation from the
public tap was then repeated on Apple Silicon. These results prove the
implementation and distribution baseline; they do not prove product behavior.

## Reporting

Follow the [research operations guide](research-operations.md), the
[pre-pilot protocol](research-study.md), and the
[four-week dogfood protocol](dogfood.md). Submit Stage 3 results through the
[sanitized validation form](https://github.com/MarinJursic/fixcard/issues/new?template=validation-report.yml).
The umbrella tracker is
[issue #5](https://github.com/MarinJursic/fixcard/issues/5).
