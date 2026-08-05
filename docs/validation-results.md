# Validation results

Last assessed: 2026-08-05.

## Decision

**Insufficient evidence — do not promote stable 1.0.** The current engineering
candidate is `1.0.0-rc.5`, but the exact preregistered Stage 3 build remains
`1.0.0-rc.4`. Engineering verification is green, but no eligible
primary-research or dogfood report has been submitted. Missing evidence is not
treated as a zero, a pass, or a reconstructed estimate.

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

## Stage 3 build freeze

The exact Stage 3 build is `1.0.0-rc.4` at commit
[`acf0c079`](https://github.com/MarinJursic/fixcard/commit/acf0c07944700085d56f50a02b26bbdf2525272d).
The later `1.0.0-rc.5` engineering candidate does not replace it for pilot
evidence: no security-fix interruption and restart was documented under the
[research operations rule](research-operations.md#6-run-stage-3-on-one-exact-build).

Eligible evidence carried between builds is therefore zero. Reports from RC5
must remain separate and cannot contribute to RC4 denominators. If a future
security fix requires a replacement build, the coordinator must stop,
document the interruption, preregister the replacement and restart treatment,
and update this ledger through the protected pull-request workflow before any
new observation period is counted.

RC4 predates RC5's bare-`fix` paste workflow. Even a complete RC4 pilot cannot
be used to claim that the RC5-only workflow passed product validation or to
promote RC5 as the exact validated build. Stable promotion of the current
feature-complete product therefore requires an authorized build change and a
fresh, unmixed observation period on that exact replacement.

## Verified engineering baseline

Release candidate `1.0.0-rc.5` at commit
[`c0b3bc2b`](https://github.com/MarinJursic/fixcard/commit/c0b3bc2bcf594ab78d35356f88a0e9348923f522)
passes 83 repository tests, hosted Linux/macOS/Windows checks, Rust 1.85
compatibility, dependency and policy audits, documentation and research-form
validation, and performance gates.

The [release workflow](https://github.com/MarinJursic/fixcard/actions/runs/30936161557)
produced six native archives. Every archive contains the `fix` and `fixcard`
binaries and passed a post-packaging sibling-delegation smoke test. The
[prerelease](https://github.com/MarinJursic/fixcard/releases/tag/v1.0.0-rc.5)
also includes SHA-256 checksums, a CycloneDX SBOM, SLSA build-provenance
attestations, and SBOM attestations.

The Apple Silicon archive was independently downloaded and verified with the
published checksum (`6e8a4147def87a8bad34d7e276dd5926b58366767e73314c2da89d2a38fbdcaa`).
Both packaged binaries reported `1.0.0-rc.5`, `fix` successfully delegated to
its packaged sibling, and `gh attestation verify` resolved the archive to the
tagged commit and release workflow.

Bare installed `fix` now enters a one-shot hidden paste flow on a terminal,
while piped input remains a lookup and arguments remain direct argv capture.
Random completion and cancellation frames prevent pasted control bytes or
oversized tails from reaching the shell. POSIX pseudo-terminal regressions
exercise redirected and split prompts, 20 startup-signal timings, active-input
SIGTERM restoration, and installed-`fix` process replacement.

The Homebrew formula at commit
[`b85b699`](https://github.com/MarinJursic/homebrew-tap/commit/b85b6991941e6fa24f36db192a9e9e10c3aa3991)
passed [post-merge audit, install, formula tests, and both-binary sibling smoke
checks](https://github.com/MarinJursic/homebrew-tap/actions/runs/30937327259)
on x86_64/ARM Linux and Intel/Apple Silicon macOS. A clean installation from
the public tap was then repeated on Apple Silicon. These results prove the
implementation and distribution baseline; they do not prove product behavior.

## Reporting

Follow the [research operations guide](research-operations.md), the
[pre-pilot protocol](research-study.md), and the
[four-week dogfood protocol](dogfood.md). Submit Stage 3 results through the
[sanitized validation form](https://github.com/MarinJursic/fixcard/issues/new?template=validation-report.yml).
The umbrella tracker is
[issue #5](https://github.com/MarinJursic/fixcard/issues/5).
