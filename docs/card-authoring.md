# Card authoring guide

A high-quality card records bounded evidence: **what failure it recognizes,
where the resolution was observed, what worked, and when not to use it**.

## Choose stable anchors

Prefer a diagnostic code or distinctive literal emitted by the failing tool:

```yaml
match:
  exact: [ERR_PNPM_OUTDATED_LOCKFILE]
  contains: [frozen-lockfile, pnpm-lock.yaml]
  not_contains: [using npm]
```

- `exact` carries the most weight and respects identifier boundaries.
- `contains` is case-insensitive after safe normalization.
- `not_contains` is a hard contradiction and prevents strong confidence.
- Avoid only `error`, `failed`, timestamps, generated IDs, usernames, absolute
  paths, or a full noisy stack trace.

At least one exact or contains anchor is required.

## Bound applicability

Record only the environment in which the resolution is known to apply:

```yaml
applies:
  os: [linux, macos]
  arch: [arm64, x86_64]
  tools:
    node: ">=22 <23"
    pnpm: ">=10 <11"
```

Tool requirements use semantic-version comparator conjunctions. At lookup,
provide known versions with repeatable `--tool NAME=VERSION` flags. A clear
conflict prevents a strong result; missing environment data remains visible as
unknown rather than being invented.

`fixcard save` records the current OS and architecture by default. Use
`--no-platform` only when the resolution is genuinely platform-independent.

## Write the body for review

`## What worked here` is required and non-empty. Recommended order:

````markdown
## Why this happens

Explain the cause without overstating certainty.

## Do not apply when

State the important counterexample in prose.

## What worked here

Describe the smallest deliberate resolution and what to review.

## Commands to review

```bash
tool subcommand --explicit-option
```

## Notes

Link durable repository context if needed.
````

Commands are never executable metadata. Still treat them as security-sensitive:
declare `risk: high` for destructive, privileged, production, remote-pipe, or
credential-changing operations, and explain safeguards in prose.

## Record validation honestly

```yaml
verified:
  command: pnpm install --frozen-lockfile
  exit_code: 0
  source_commit: 3d84c2a
last_verified: 2026-07-16
```

This means a human observed that command and exit code in the recorded context.
It does not prove causality or guarantee future success. If no validation was
observed, omit `verified`; Fixcard will show an `unverified` note.

## Create non-interactively

Automation may create a draft without executing anything:

```bash
fixcard save --team --yes \
  --id pnpm-outdated-lockfile \
  --title "Regenerate the lockfile with the pinned pnpm version" \
  --exact ERR_PNPM_OUTDATED_LOCKFILE \
  --contains frozen-lockfile \
  --not-contains "using npm" \
  --applies-tool 'pnpm=>=10 <11' \
  --why "The lockfile was produced by another package-manager major." \
  --do-not-apply "The repository is managed by npm or Yarn." \
  --resolution "Use the repository-pinned pnpm major and review the lockfile diff." \
  --validation-command "pnpm install --frozen-lockfile" \
  --validation-exit 0
```

Non-interactive creation requires all required fields plus `--yes`. Shared
creation still previews and lints before the atomic write. `--yes` acknowledges
the preview; it does not bypass blocking safety findings.

## Lifecycle

- update `last_verified` only after a new observation;
- use `superseded_by` and `supersedes` when a replacement has a new ID;
- set `retired: true` with a `retirement_reason` when no replacement exists;
- keep history in Git rather than appending an unbounded audit log to the card;
- treat repeated card use as evidence that the underlying product or build
  should be improved.

The normative field table is in the [stable v1 format](../spec/fixcard-v1.md).
