# Validation results

Protocol baseline assessed: 2026-08-15.

## Decision

**Insufficient evidence — keep stable 1.0 unreleased.** RC7 is published and
engineering-verified, and the protected activation is installed. Collection is
open only when the evidence validator reports `OPEN`. Every eligible count began
at zero; opening
collection satisfies no gate, carries nothing forward, and does not authorize
stable 1.0. Missing evidence is never treated as zero, a pass, or an estimate.

RC4–RC6, untagged fixes, same-version rebuilds, moving package-manager heads,
and every pre-boundary observation remain ineligible. Stage 2 and Stage 3 use
only the exact RC7 treatment after their protected activation boundaries.
Retrospective observations are forbidden.

The existing machine-readable
[`pilot-registration.json`](../research/pilot-registration.json) is a pre-data
registration that freezes `1.0.0-rc.4`, commit
`acf0c07944700085d56f50a02b26bbdf2525272d`, six archive digests, an eligible
start date of 2026-08-10, all fixed gates, and all ten kill criteria. It records
zero eligible evidence at registration and carries nothing across builds. It
remains the immutable record of the interrupted treatment; it does not authorize
new RC4 collection after the pause.

The separate machine-readable
[`pilot-replacement-registration.json`](../research/pilot-replacement-registration.json)
and [`RC7 build manifest`](../research/pilots/rc7/build-manifest.json) freeze the
replacement candidate as a closed preregistration. Current intake authority is
derived only from the protected activation record. The
[`RC7 operating snapshot`](dogfood-rc7.md) reflects RC7's one-shot paste flow
and exact installation receipts; the RC4 dogfood body remains historical.

## Evidence ledger

| Stage | Required coverage | Eligible documented evidence | Status |
| --- | --- | --- | --- |
| Evidence corpus | At least 100 sanitized real failure/resolution pairs with permission and second-person review | None submitted | Not started / not documented |
| Problem diary | 24–30 developers across the specified contexts, roles, and platforms for two working weeks | None submitted | Not started / not documented |
| Concierge workflow | Three real cards per participant plus controlled recurrences and maintainer review | None submitted | Not started / not documented |
| Dogfood pilot | One exact build in 5–8 active repositories for four weeks | RC4 interrupted with zero eligible reports; RC7 begins from zero only after protected activation | No eligible result documented |

All product thresholds therefore remain unproven, including recurrence
frequency, concierge creation time, seeded retrieval precision, comparative
trust, real rank-one relevance, capture behavior, reuse, team acceptance,
privacy false-positive burden, differentiation, and maintenance burden.

## Verified engineering baseline

The engineering-verified prerelease is `1.0.0-rc.7` at commit
[`165ef5c`](https://github.com/MarinJursic/fixcard/commit/165ef5cd4790002516de9c327d634d342842288d).
It passes 103 repository tests, hosted Linux/macOS/Windows checks, Rust 1.85
compatibility, dependency and policy audits, documentation, security, and
performance gates. The security-hardening merge passed
[post-merge CI](https://github.com/MarinJursic/fixcard/actions/runs/31889606058)
and [security](https://github.com/MarinJursic/fixcard/actions/runs/31889606068);
the release-metadata merge also passed
[post-merge CI](https://github.com/MarinJursic/fixcard/actions/runs/31890076986).

The [release workflow](https://github.com/MarinJursic/fixcard/actions/runs/31890187276)
produced six native archives. Every archive contains the `fix` and `fixcard`
binaries and passed a post-packaging sibling-delegation smoke test. The
[prerelease](https://github.com/MarinJursic/fixcard/releases/tag/v1.0.0-rc.7)
also includes SHA-256 checksums, a CycloneDX SBOM, SLSA build-provenance
attestations, and SBOM attestations.

The Apple Silicon archive was independently downloaded and verified with the
published checksum (`c56714ac4ef563d56d1b5e12c78b2df5567a4f3006907f9ff1ff8c37f8478756`).
All six archive checksums passed. Both Apple Silicon binaries reported
`1.0.0-rc.7`, `fix` successfully delegated to
its packaged sibling, and `gh attestation verify` resolved the archive to the
tagged commit and release workflow for both SLSA provenance and CycloneDX SBOM
predicates. The published SBOM parsed successfully.

Bare installed `fix` now enters a one-shot hidden paste flow on a terminal,
while piped input remains a lookup and arguments remain direct argv capture.
Random completion and cancellation frames prevent pasted control bytes or
oversized tails from reaching the shell. POSIX pseudo-terminal regressions
exercise redirected and split prompts, 20 startup-signal timings, active-input
SIGTERM restoration, and installed-`fix` process replacement.

The Homebrew formula at commit
[`71f00d5`](https://github.com/MarinJursic/homebrew-tap/commit/71f00d5574ab8fe6e06c224df0219752ddd44370)
passed [post-merge audit, install, formula tests, and both-binary sibling smoke
checks](https://github.com/MarinJursic/homebrew-tap/actions/runs/31890675255)
on x86_64/ARM Linux and Intel/Apple Silicon macOS. A public-tap upgrade, both
binaries, sibling delegation, and `brew test` were then repeated on Apple
Silicon. These results prove the
implementation and distribution baseline; they do not prove product behavior.

The historical checker preserves exact RC4 records while the replacement
registration binds RC7's pilot ID and build-manifest digest. The RC7 templates
add those fields to every Stage 2 and Stage 3 row and add a canonical UTC
observation timestamp to Stage 2.
The standalone validator also rejects malformed input, observations before the
eligible date, missing complete-pilot fields, selective timing samples,
impossible partial totals, duplicate repository-weeks, decreasing cumulative
active-user or reuse counts, incomplete four-week coverage, and repository
counts outside 5–8. These controls prevent evidence mixing; they do not turn
adverse observations into a pass.

## Reporting

The public validation form is authoritative only when it is installed
byte-identically with an effective protected activation record. When it is
absent, do not submit evidence. RC4 and every pre-boundary or other-build
observation remain ineligible in every state.

Follow the [research operations guide](research-operations.md), the
[pre-pilot protocol](research-study.md), the
[historical dogfood protocol](dogfood.md), and the
[RC7 operating snapshot](dogfood-rc7.md). After an eligible replacement pilot
is completed, its protected protocol uses the sanitized intake form.
Repository-week and participant-level records remain access-controlled; only
small-cell-suppressed aggregate results may be submitted publicly.
The umbrella tracker is
[issue #5](https://github.com/MarinJursic/fixcard/issues/5).
