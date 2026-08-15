# ADR-0001: Recompute trust-critical classifications at lookup

- Status: Accepted
- Date: 2026-08-15

## Context

A Fixcard is untrusted input, including its author-declared `risk` value and its
applicability constraints. Previously, lookup could display `risk: low` and a
strong result for a card whose inert resolution contained a dangerous command.
It could also treat a tool-constrained card as strong when no current version
for that tool was supplied. Running `lint` separately was not a safe runtime
boundary because lookup did not require it.

Committed-card provenance also read Git tree and blob output before all public
per-card, aggregate-byte, and count limits had been enforced. An untrusted
repository could therefore consume resources outside the documented bounds.

## Decision

Lookup independently recomputes the effective command risk from the title,
Markdown body, and recorded validation command using the same built-in classes
as lint. Repository policy may deny additional detected classes but may never
lower effective risk. A scanner-raised or policy-denied card is weak and its
effective risk is displayed before its inert instructions.
Terminal controls are removed before both classification and secret redaction,
so the scanner and renderer operate on the same canonical text.

A tool-constrained card is weak when the current version is unknown. Callers
must supply `--tool NAME=VERSION` to establish that applicability input.

The Git adapter bounds tree output, stored diagnostics, object count,
individual committed blob size, and aggregate committed source bytes before
allocating blob bodies. Metadata and allowed content are requested sequentially
so neither side can fill a pipe while waiting for the other. The adapter
terminates and reaps the child when a limit or protocol check fails.

## Consequences

- Authors cannot create strong low-risk results merely by declaring low risk.
- A conservative classifier may produce weak false positives; users may still
  inspect them explicitly with `--all`, and maintainers can improve the shared
  deterministic classifier rather than bypass it per card.
- Existing constrained cards can move from strong to weak until the caller
  supplies a tool version.
- Oversized or unusually broad repositories fail with a bounded diagnostic
  instead of partially establishing committed provenance.
- Card content remains inert. This decision does not authorize automatic
  command execution or imply that high-risk classification detects every
  dangerous instruction.

## Compatibility and migration

The v1 card schema and on-disk files do not change. Existing cards need no
migration. Their runtime confidence or displayed effective risk can become more
conservative. Older binaries retain their prior behavior, so security-fixed
pilot evidence must use one exact replacement build and cannot mix with RC4.

## Verification

- CLI regressions prove an underdeclared destructive card is not strong and is
  never rendered with a low effective-risk label.
- Lint unit tests prove card and repository policy cannot lower built-in risk.
- Matching unit tests prove unknown constrained tool versions force weakness.
- Git adapter tests prove oversized working and committed cards are rejected
  before body loading.
- The threat model, security guide, matching guide, and changelog document the
  visible behavior and remaining limits.
