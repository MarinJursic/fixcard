# Release-candidate dogfood program

> [!IMPORTANT]
> **The RC4 procedure below is historical and must not be followed.** The RC7
> activation is installed, but collection is open only when the evidence validator
> reports `OPEN`. Collection uses only the exact RC7 operating snapshot and protected
> activation boundaries. RC4–RC6, untagged builds, moving package-manager heads,
> and pre-boundary observations remain ineligible. Opening satisfies no gate.
> See the [current RC7 operating snapshot](dogfood-rc7.md).

Fixcard reaches stable 1.0 only after every stage in
[Validation](validation.md) passes. This program covers the four-week Stage 3
pilot and collects evidence without telemetry or raw development logs. The
Stage 1 and 2 protocols are separate because problem diaries must not begin by
pitching Fixcard.

## Who should participate

Developers maintaining an active repository where failures recur and where at
least one resolution is worth preserving. The study needs 5–8 repositories
covering more than one ecosystem and both personal and team use where possible.

## Start

The only registered Stage 3 build is
[`1.0.0-rc.4`](https://github.com/MarinJursic/fixcard/releases/tag/v1.0.0-rc.4),
at commit `acf0c07944700085d56f50a02b26bbdf2525272d`. Observations made before
2026-08-10 or with another version are ineligible. No evidence from an earlier
or later candidate carries into this treatment.

1. Install the exact `1.0.0-rc.4` release archive from the link above. A
   coordinator who uses Homebrew must install the immutable formula at tap
   commit `c22efbe78064a8c78192b778e270bb936e2cdb4d`; the moving tap head is not
   eligible pilot installation evidence.

   ```sh
   formula_dir=$(mktemp -d)
   curl --fail --location --silent --show-error \
     --output "$formula_dir/fixcard.rb" \
     https://raw.githubusercontent.com/MarinJursic/homebrew-tap/c22efbe78064a8c78192b778e270bb936e2cdb4d/Formula/fixcard.rb
   brew install --formula "$formula_dir/fixcard.rb"
   ```

2. Run both `fixcard --version` and `fix --version`. Each must report its own
   command name followed by `1.0.0-rc.4`; otherwise stop and correct the
   installation before collecting observations.
3. Run `fixcard status` and confirm the expected storage paths.
4. Choose repository, clone-private, or user-global scope deliberately.
5. When anticipating a failure, use `fix PROGRAM [ARGS...]` or its explicit
   `fixcard run -- PROGRAM [ARGS...]` equivalent. For existing output, pipe the
   saved output into `fix`; bare interactive `fix` in RC4 shows status and next
   steps and is not a paste interface.
6. Do not create synthetic successes. Record normal development incidents.

Before the first incident and again at the start of every weekly period, record
a stable random repository alias, the exact outputs of both version commands,
the number of pilot users with repository access, and the report week. Never
use the real repository name as its alias.

Do not switch builds during the four-week period. If a security fix is required,
stop collection, document the interruption, and preregister the replacement and
restart before collecting more observations. Product or usability changes do
not qualify for that exception.

## Access-controlled worksheets

Copy the blank Stage 3 repository-week, active-user, and eight-week card files from
[`research/templates`](../research/templates) to an access-controlled
coordinator location. Do not commit completed files or submit repository-week
rows publicly. Keep the alias key separately and use one globally unique
participant alias across repositories. Record one active-user row per
participant/repository membership so its active and reuser counts reconcile
exactly to each repository's week-four cumulative counts. Record one eight-week
row for every card authored during weeks 1–4, including cards never reused.

For each real lookup, privately record its date, repository alias, whether a
strong result appeared, relevance or correct/incorrect abstention, search
latency, full end-to-end duration, and which tool was used first. For each real
card, record observed creation duration, author or teammate reuse, review
disposition, retirement, and scanner outcome. The repository-week CSV records
the resulting aggregates. Capture one observed timing for every lookup and
every authored card; a missing selected timing blocks completion and is never
reconstructed.

Count a weekly active user in `active_users_with_three_cards` only after that
user authored at least three cards represented in the same repository-week
row. The row's `authored_cards` total must therefore be at least three times
that numerator.

“Relevant” means the first strong result was the correct recorded response for
the actual incident. A plausible but wrong result is irrelevant. No strong
result is often the safe and correct outcome.

Authoring time starts only after the developer already knows the resolution. It
ends when the card is saved. Do not estimate a duration later if it was not
observed.

## Weekly private transfer

Transfer one aggregate row per repository each week to the access-controlled
coordinator CSV. Each period is seven consecutive calendar days and the four
periods must be consecutive and non-overlapping. Differentiation and
maintenance are collected only in week four. Completed rows must not be placed
in GitHub issues, even under aliases: small cells and the reporter's identity
can reveal a private team. Records must not contain:

- raw command output or stack traces;
- credentials, tokens, cookies, or connection strings;
- internal hostnames, customer identifiers, or private paths;
- proprietary source, commands, or repository names.

Report a suspected security problem through
[private vulnerability reporting](../SECURITY.md), not a public validation
issue.

After the pilot and the eight-week reuse follow-up are complete, the
coordinator may submit one
[validation summary](https://github.com/MarinJursic/fixcard/issues/new?template=validation-report.yml)
covering all repositories. Publish only sanitized cross-repository aggregates,
suppress every cell smaller than five, and never publish repository-week rows
or stable repository aliases.

## Decision

After four weeks, maintainers privately aggregate only the submitted counts;
after the week-eight follow-up, the public cross-repository summary includes:

- strong rank-one relevance and its denominator;
- end-to-end lookup duration and whether Fixcard was used before other tools;
- median observed authoring time and sample size;
- weekly active-user capture behavior and its denominator;
- author and teammate reuse rates and counts;
- shared-card acceptance through normal pull-request review;
- scanner catches, false positives, users bypassing scanning because of false
  positives, missed secrets, and safety incidents;
- differentiation responses and maintenance burden;
- repository/ecosystem coverage;
- an explicit go, change, or stop decision.

Missing data is reported as missing. Stars, downloads, total card count, and
synthetic examples do not substitute for relevance or reuse.

Before aggregation, use a full Git clone with Ruby 3.1 or newer and run:

```sh
ruby scripts/research_evidence.rb --complete-pilot \
  --active-user-reuse /private/stage-3-active-user-reuse.csv \
  --eight-week-card-reuse /private/stage-3-eight-week-card-reuse.csv \
  /private/stage-3-repository-weeks.csv
```

The validator rejects blank or mixed versions, pre-eligibility or overlapping
periods, missing gate fields, selective timing samples, impossible counts,
incomplete four-week coverage, and repository counts outside the registered
5–8 range. A successful validation checks completeness and provenance shape;
it does not make adverse evidence pass.

Stable promotion cannot occur at week four. Kill criterion 5 requires an
eight-week teammate-reuse observation, so the exact-build cohort remains under
access-controlled follow-up for four additional weeks before all ten kill
criteria can be classified.
