# Architecture decision records

Use an architecture decision record (ADR) for a material change to the Fixcard
format, trust model, execution boundary, compatibility contract, or storage
model. ADRs explain why a durable decision exists; user-facing behavior still
belongs in the normal documentation and tests.

## Numbering and status

1. Copy [`template.md`](template.md).
2. Use the next four-digit number and a short kebab-case title.
3. Start with `Proposed`; change it to `Accepted` only when the implementing
   pull request is accepted.
4. Never rewrite an accepted decision to hide a change. Add a new ADR and mark
   the earlier record `Superseded by ADR-NNNN`.

## Records

- [ADR-0001: Recompute trust-critical classifications at lookup](0001-runtime-trust-reclassification.md)
