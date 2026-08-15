# RC7 replacement-pilot operating snapshot

> [!IMPORTANT]
> **The protected RC7 activation is installed.** Collection is open only when
> the evidence validator reports `OPEN`. Only post-boundary observations from
> the exact registered build are eligible.
> Opening collection satisfies no gate and does not authorize stable 1.0.

This is the operating snapshot for pilot `fixcard-rc7-2026-08-15`. It applies
to Stage 2 and Stage 3 only after activation. The unchanged study gates,
denominators, privacy rules, and all ten kill criteria remain bound to the
historical protocol through
[`pilot-replacement-registration.json`](../research/pilot-replacement-registration.json).
Milestone 0 and Stage 1 are build-independent but remain closed until an
activation record explicitly names them.

## Exact treatment

- version: `1.0.0-rc.7`
- tag: `v1.0.0-rc.7`
- commit: `165ef5cd4790002516de9c327d634d342842288d`
- pilot ID: `fixcard-rc7-2026-08-15`
- build-manifest canonical JSON SHA-256:
  `f18abc931e870a3a934877b4d33611e8f84190f2e9d765335885dde0d1fa7987`
- registered not-before date: `2026-08-17`

The actual eligible boundary will be the later of that date and the boundary
recorded by the future activation. Pre-boundary, reconstructed, synthetic,
mixed-build, RC4–RC6, untagged, and moving-package-manager observations are
ineligible. Counts start at zero; nothing carries forward from RC4.

## Activation sequence

Opening is a separate protected change, never part of this preregistration:

1. Merge this replacement registration to protected `main` with all required
   checks and reviews.
2. After that merge, a maintainer posts the exact machine-readable opening
   comment in locked issue #5. The authorization binds the live comment and the
   registration pull request's ID, URL, merge commit, and merge timestamp.
3. A later activation pull request adds the authorization record, restores the
   preregistered form byte-for-byte, and applies only the preregistered open
   banners. Its pre-merge check validates the still-open PR and keeps intake
   closed. The candidate boundaries must retain at least 48 hours of Stage 2
   merge lead and three UTC dates of Stage 3 lead; if the merge misses either
   boundary, validation stays closed and a fresh activation is required.
4. Only after that pull request merges does the normal validator re-fetch both
   pull requests, the comment, issue lock, release, formula, exact committed
   records, validator tree, form, and banners. Any mismatch or network failure
   leaves intake closed. `ruby scripts/research_evidence.rb --status` must then
   report `OPEN` before any observation begins.

## Install an exact artifact

Prefer a release archive listed in the
[`build manifest`](../research/pilots/rc7/build-manifest.json). Verify the
downloaded archive SHA-256 against that manifest before extraction. Do not use
a rebuilt binary that merely prints the same version.

A coordinator who uses Homebrew must use the immutable formula blob at commit
`71f00d5574ab8fe6e06c224df0219752ddd44370`, not the moving tap head:

```sh
formula_dir=$(mktemp -d)
curl --fail --location --silent --show-error \
  --output "$formula_dir/fixcard.rb" \
  https://raw.githubusercontent.com/MarinJursic/homebrew-tap/71f00d5574ab8fe6e06c224df0219752ddd44370/Formula/fixcard.rb
brew install --formula "$formula_dir/fixcard.rb"
```

For each participant/repository membership used in Stage 3, retain exactly one
coordinator-controlled, access-controlled distribution receipt. For Stage 2,
retain exactly one such receipt for every observed participant. Each receipt
contains only:

- pilot ID, installation alias, participant alias, and repository alias;
- release asset name and SHA-256, or the exact formula commit and formula blob
  SHA-256;
- outputs of `fixcard --version` and `fix --version`;
- verification timestamp in UTC; and
- verifier alias.

The receipt must be verified after the activation boundary and no later than
the participant's first Stage 2 observation or the repository's first Stage 3
observation date. Keep the same participant/repository membership aliases as
the access-controlled reuse worksheet. Do not publish
receipts, local paths, usernames, hostnames, or repository identities. Every
Stage 2 and Stage 3 row must repeat the pilot ID and build
manifest digest so a same-version rebuild or mixed treatment is rejected.

## Verify behavior before observation

Run:

```sh
fixcard --version
fix --version
fix "$(command -v fixcard)" --version
fixcard status
```

In PowerShell, use the exact resolved binary path without POSIX command
substitution:

```powershell
fixcard --version
fix --version
fix (Get-Command fixcard).Source --version
fixcard status
```

The first three commands in the applicable block must report `1.0.0-rc.7`.
Stop if they do not. Confirm
the intended repository, private, and global storage paths before creating or
looking up cards.

In RC7, bare `fix` starts a one-shot hidden paste flow. With arguments,
`fix PROGRAM [ARGS...]` runs exactly that program without a shell, streams its
output, and performs a lookup only after failure. Piped input performs lookup.
Card text is inert advice and is never executed by Fixcard.

## Collect only after activation

After activation, copy the blank RC7 templates from
[`research/pilots/rc7/templates`](../research/pilots/rc7/templates) into an
access-controlled coordinator location. Never commit completed worksheets.

For Stage 2, record `observed_at` as canonical UTC RFC 3339 and reject any row
before the activation boundary. For Stage 3, use 5–8 active repositories for
four consecutive seven-day periods. Record one repository-week row per week,
one active-user row per participant/repository membership, and one eight-week
row for every card authored in weeks 1–4. Complete the additional four-week
reuse follow-up before classifying kill criterion 5 or making a stable decision.

Validate Stage 2 only with its receipt file:

```sh
ruby scripts/research_evidence.rb --stage-2 \
  --installation-receipts /private/installation-receipts.csv \
  /private/stage-2-observations.csv
```

Validate a complete Stage 3 pilot only with all three cross-file worksheets:

```sh
ruby scripts/research_evidence.rb --complete-pilot \
  --active-user-reuse /private/stage-3-active-user-reuse.csv \
  --eight-week-card-reuse /private/stage-3-eight-week-card-reuse.csv \
  --installation-receipts /private/installation-receipts.csv \
  /private/stage-3-repository-weeks.csv
```

Use real work only. Never fabricate or reconstruct activity, count a synthetic
variant as another real pair, or omit an adverse observation. Capture all fixed
denominators, response counts, attrition, missingness, and the all-recruited or
all-active sensitivity views required by the registration.

## Privacy and public reporting

Keep raw failures, commands, logs, paths, repository names, alias keys,
credentials, customer data, private URLs, receipts, and participant-level rows
outside the public repository and public issues. Public reporting is limited to
coordinator-reviewed, small-cell-suppressed, cross-repository aggregates.

The public intake form stays absent while collection is closed. When activated,
submit only the sanitized aggregate summary through the exact RC7 form. Missing
data remains missing; it is never inferred as zero or a pass.

## Stop rule

If a security fix is required, stop collection immediately and add an
append-only pause event. Do not switch builds within a repository-week or carry
observations into another treatment. A restart requires a new pilot ID, exact
build manifest, protected preregistration, future boundary, and explicit public
opening. Product or usability changes alone do not qualify for the exception.

Stable 1.0 remains prohibited until Milestone 0 and all three stages pass every
predeclared gate and all ten kill criteria have been reviewed.
