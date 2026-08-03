# Fixcard format v1

Status: stable. The v1 data model and inert-command semantics are frozen
independently of the CLI release-candidate version. Additive data requires an
`x-` extension; incompatible meaning requires a future schema version.

## File and location

A shared card is UTF-8 Markdown at `.fixcards/<id>.md`. A private card uses the
same format under `<git-common-dir>/fixcard/cards/<id>.md`. Files larger than the
implementation's documented safety limit may be rejected. Symlinks are not
followed while discovering cards.

A user-global card uses the same format in the operating system's per-user
application-data directory. Storage location determines scope; scope is not a
field inside the document.

## Document shape

The file starts with YAML front matter between exact `---` lines, followed by a
Markdown body. YAML aliases and custom tags are not part of v1. The body must
contain non-empty `## What worked here` content; `## Why this happens`,
`## Commands to review`, `## Do not apply when`, and `## Notes` are optional.

```markdown
---
fixcard: 1
id: pnpm-outdated-lockfile
title: Regenerate the lockfile with the repository-pinned pnpm version
match:
  exact: [ERR_PNPM_OUTDATED_LOCKFILE]
  contains: [frozen-lockfile, pnpm-lock.yaml]
applies:
  os: [macos, linux]
  arch: [arm64, x86_64]
  tools:
    node: ">=22 <23"
    pnpm: ">=10 <11"
risk: low
verified:
  command: pnpm install --frozen-lockfile
  exit_code: 0
  source_commit: 3d84c2a
last_verified: 2026-07-16
authors: ["@developer"]
---

## What worked here

Use the package-manager major pinned by this repository and regenerate the
lockfile. Review its diff before committing it.
```

## Fields

| Field | Required | Semantics |
| --- | --- | --- |
| `fixcard` | yes | Integer schema version; exactly `1` for this specification. |
| `id` | yes | Lowercase ASCII slug: `[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?`. Must match the filename and be unique within one storage origin. The same ID may exist independently in another scope. |
| `title` | yes | Plain-text summary, 1–120 Unicode scalar values. |
| `match.exact` | conditional | Stable, literal diagnostic anchor. At least one exact or contains anchor is required. |
| `match.contains` | conditional | Literal fragment expected after case-folding and whitespace normalization. |
| `match.not_contains` | no | Hard negative fragment. A match suppresses strong confidence. |
| `applies.os` | no | `macos`, `linux`, `windows`, or another lowercase extension value. |
| `applies.arch` | no | Normalized architecture such as `arm64`, `x86_64`, or another lowercase extension value. |
| `applies.tools` | no | Tool name to npm-style comparator conjunction understood by the implementation. |
| `risk` | yes | `low`, `medium`, or `high`; scanners may raise the effective displayed risk. |
| `verified.command` | no | Inert command text that was used for validation. |
| `verified.exit_code` | no | Observed signed process exit status; requires `verified.command`. |
| `verified.source_commit` | no | Git object prefix or full hexadecimal object ID. |
| `last_verified` | conditional | ISO `YYYY-MM-DD`; at least this or `created` is required. |
| `created` | conditional | ISO `YYYY-MM-DD`; at least this or `last_verified` is required. |
| `authors` | no | Human-readable identities, not authorization claims. |
| `supersedes` | no | IDs replaced by this card. |
| `superseded_by` | no | ID replacing this card. |
| `retired` | no | Boolean; retired cards do not appear in default search. |
| `retirement_reason` | conditional | Required when `retired` is true. |

Unknown top-level fields are invalid unless their key begins with `x-`.
Implementations must ignore `x-` fields for matching and behavior and preserve
them if they rewrite a card. Unknown nested fields in v1-defined structures are
invalid. Duplicate YAML mapping keys are invalid. YAML aliases and custom tags
are invalid.

No v1 field has action semantics. In particular, `verified.command`, Markdown
code fences, `## Commands to review`, and `x-` values are always inert. A future
implementation must not reinterpret those fields as executable; typed actions,
if ever standardized, require a new schema version and threat model.

## Matching

Matching is local, deterministic, and explainable. An implementation normalizes
input noise, evaluates literal anchors and diagnostic tokens, applies platform
and semantic-version compatibility, then assigns a confidence class. Negative
conditions, retirement, and clear version mismatches take precedence over raw
text score. A default lookup returns at most one strong card.

Implementations may differ in numeric ranking, but must expose the evidence for
a result and must not represent weak similarity as a verified answer.

## Safety

All prose and commands are untrusted text. The format does not define execution.
Implementations must neutralize terminal control sequences and clearly identify
high-risk operations. Team-oriented authors should scan for secrets, machine-
local paths, internal names, and embedded URL credentials before commit.

Implementations may impose documented limits on file bytes, aggregate corpus
bytes, card count, directory entries, anchor count and length, YAML extension
depth and nodes, and emitted diagnostics. A rejected or malformed card should
not prevent independent valid cards from being searched; strict validation may
still fail the corpus.

## Lifecycle

Retired cards remain readable and addressable by ID but are excluded from
default lookup. Supersession references do not delete history. Verification
history normally belongs in Git history rather than an ever-growing YAML list.
