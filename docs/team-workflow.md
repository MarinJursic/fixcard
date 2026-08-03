# Team workflow

Shared Fixcards are repository-owned documentation. They belong in ordinary
code review. User-global storage is personal scope, not a replacement for
repository review.

Repositories with stricter command boundaries can commit a `.fixcard.toml`
denylist described in the [security and privacy guide](security-and-privacy.md).

## Promote deliberately

1. Prove the resolution in one real incident.
2. Keep the first card private while removing machine-local details.
3. Decide whether recurrence is likely enough to justify maintenance.
4. Add conditions, negative cases, validation, date, and honest risk.
5. Create with `fixcard save --team` or move the generalized file into
   `.fixcards/`.
6. Run `fixcard lint .fixcards` and review the rendered Markdown.
7. Submit it through the repository's normal pull-request process.

## Reviewer checklist

- Does the failure belong specifically to this repository?
- Are anchors distinctive and stripped of volatile/local values?
- Is the underlying cause understood well enough to describe?
- Are platform and tool-version bounds no broader than the evidence?
- Is there a clear “do not apply” condition where misuse is plausible?
- Are commands minimal, inert, correctly fenced, and honestly risk-labeled?
- Is validation an observed fact rather than a certainty claim?
- Could the card contain a secret, customer data, internal hostname, or private
  path even if the scanner did not recognize it?
- Would a permanent code, test, or documentation fix eliminate the need?

## Ownership and change

The repository owns shared cards. `authors` records human-readable provenance,
not authorization. Git review and history supply accountability. When behavior
changes, update or supersede the card in the same change as the relevant code
where practical.

Private cards are clone-local and are not committed automatically. Teams should
not assume they are backed up, synced, or visible to another clone.
