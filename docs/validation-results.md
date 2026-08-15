# Validation results

Last assessed: 2026-08-15.

## Decision

**Insufficient evidence — keep stable 1.0 unreleased.** Stage 3 RC4 collection
is paused under the documented security-fix restart rule. A defensive review
found a committed-card resource-exhaustion path and a runtime risk-labeling
defect in RC4. No eligible primary-research or dogfood report was submitted
before the interruption, so eligible evidence remains zero and nothing carries
forward. Missing evidence is not treated as a zero, a pass, or a reconstructed
estimate.

The interruption was recorded publicly in
[issue #5](https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5302005971).
RC4, RC5, RC6, untagged fixes, and moving package-manager heads are ineligible
while collection is paused. A replacement can become the one exact Stage 3
treatment only after its security fixes merge, release artifacts and digests
are verified, a protected preregistration freezes them with a new eligible
start boundary, and issue #5 explicitly reopens collection.

The existing machine-readable
[`pilot-registration.json`](../research/pilot-registration.json) is a pre-data
registration that freezes `1.0.0-rc.4`, commit
`acf0c07944700085d56f50a02b26bbdf2525272d`, six archive digests, an eligible
start date of 2026-08-10, all fixed gates, and all ten kill criteria. It records
zero eligible evidence at registration and carries nothing across builds. It
remains the immutable record of the interrupted treatment; it does not authorize
new RC4 collection after the pause.

## Evidence ledger

| Stage | Required coverage | Eligible documented evidence | Status |
| --- | --- | --- | --- |
| Evidence corpus | At least 100 sanitized real failure/resolution pairs with permission and second-person review | None submitted | Not started / not documented |
| Problem diary | 24–30 developers across the specified contexts, roles, and platforms for two working weeks | None submitted | Not started / not documented |
| Concierge workflow | Three real cards per participant plus controlled recurrences and maintainer review | None submitted | Not started / not documented |
| Dogfood pilot | One exact build in 5–8 active repositories for four weeks | RC4 collection interrupted by the security-fix rule with zero eligible report issues; replacement not yet frozen | Paused / restart required |

All product thresholds therefore remain unproven, including recurrence
frequency, concierge creation time, seeded retrieval precision, comparative
trust, real rank-one relevance, capture behavior, reuse, team acceptance,
privacy false-positive burden, differentiation, and maintenance burden.

## Verified engineering baseline

The latest engineering candidate, `1.0.0-rc.6` at commit
[`6a10e055`](https://github.com/MarinJursic/fixcard/commit/6a10e0556576a80e481a2ca362544f81bd05977f)
passes 84 repository tests, hosted Linux/macOS/Windows checks, Rust 1.85
compatibility, dependency and policy audits, documentation and performance
gates. It is not eligible RC4 pilot evidence. The exact post-merge commit passed
[CI](https://github.com/MarinJursic/fixcard/actions/runs/30984540106) and
[security](https://github.com/MarinJursic/fixcard/actions/runs/30984540104).

The [release workflow](https://github.com/MarinJursic/fixcard/actions/runs/30984877313)
produced six native archives. Every archive contains the `fix` and `fixcard`
binaries and passed a post-packaging sibling-delegation smoke test. The
[prerelease](https://github.com/MarinJursic/fixcard/releases/tag/v1.0.0-rc.6)
also includes SHA-256 checksums, a CycloneDX SBOM, SLSA build-provenance
attestations, and SBOM attestations.

The Apple Silicon archive was independently downloaded and verified with the
published checksum (`faec6a30e09b03bed3912085f0279a5162f7c72e2f2fdc3984ee59f402506133`).
Both packaged binaries reported `1.0.0-rc.6`, `fix` successfully delegated to
its packaged sibling, and `gh attestation verify` resolved the archive to the
tagged commit and release workflow for both SLSA provenance and CycloneDX SBOM
predicates.

Bare installed `fix` now enters a one-shot hidden paste flow on a terminal,
while piped input remains a lookup and arguments remain direct argv capture.
Random completion and cancellation frames prevent pasted control bytes or
oversized tails from reaching the shell. POSIX pseudo-terminal regressions
exercise redirected and split prompts, 20 startup-signal timings, active-input
SIGTERM restoration, and installed-`fix` process replacement.

The Homebrew formula at commit
[`4540692`](https://github.com/MarinJursic/homebrew-tap/commit/4540692a35180a8efa353c2cd8cadc46fc019750)
passed [post-merge audit, install, formula tests, and both-binary sibling smoke
checks](https://github.com/MarinJursic/homebrew-tap/actions/runs/30985670860)
on x86_64/ARM Linux and Intel/Apple Silicon macOS. A clean installation from
the public tap was then repeated on Apple Silicon. These results prove the
implementation and distribution baseline; they do not prove product behavior.

The research-kit checker accepts exact RC4 Stage 2 and Stage 3 rows and
deliberately mutates them to prove that RC3 and blank versions are rejected.
The standalone validator also rejects malformed input, observations before the
eligible date, missing complete-pilot fields, selective timing samples,
impossible partial totals, duplicate repository-weeks, decreasing cumulative
active-user or reuse counts, incomplete four-week coverage, and repository
counts outside 5–8. These controls prevent evidence mixing; they do not turn
adverse observations into a pass.

## Reporting

The public validation intake form is disabled while collection is paused. Do
not submit RC4 or replacement-build evidence until a protected replacement
preregistration merges and issue #5 explicitly reopens collection.

Follow the [research operations guide](research-operations.md), the
[pre-pilot protocol](research-study.md), and the
[four-week dogfood protocol](dogfood.md). After an eligible replacement pilot
is completed, its protected protocol will restore the sanitized intake form.
Repository-week and participant-level records remain access-controlled; only
small-cell-suppressed aggregate results may be submitted publicly.
The umbrella tracker is
[issue #5](https://github.com/MarinJursic/fixcard/issues/5).
