# Threat model

## Assets

- secrets and private identifiers in pasted logs;
- repository integrity and developer machines;
- user trust in card provenance and validation;
- terminal integrity when displaying untrusted Markdown;
- shared repository history.

## Trust boundaries

The current repository, every card, pasted input, environment metadata, Git
configuration, and subprocess output are untrusted. The local operating system
and the installed Fixcard binary are trusted for the MVP. Network services are
outside the runtime data flow.

## Primary threats and controls

| Threat | Control |
| --- | --- |
| Secret committed in a card | private-by-default storage, preview, conservative scanner, team-save cancellation on findings |
| Malicious card suggests destructive action | inert rendering, visible high-risk state, command-class diagnostics, provenance |
| Terminal escape injection | strip C0/C1, ANSI, OSC, and unsafe bidi/control characters before output |
| Wrong fix for another version | semantic version constraints, visible mismatch, hard negative conditions |
| Stale fix presented as current | `last_verified`, configurable staleness warning, retired/superseded lifecycle |
| Symlink or path traversal | stable ID validation, canonical containment checks, no following card-directory symlinks |
| Resource exhaustion | bounded input/card sizes and counts; linear-time regexes only |
| Git option or command injection | fixed Git argv, `--` before paths, no shell invocation, non-interactive environment |
| Certainty laundering | lint claims such as “always fixes”; render an evidence-not-guarantee notice |
| Supply-chain compromise | locked dependencies, least-privilege CI, checksums, signatures, SBOM, dependency review |

## Non-promises

Secret scanning is defense in depth, not proof that a card is safe to publish.
Git history is provenance, not an endorsement. A recorded validation proves only
the observed command and exit status under recorded conditions.

## Security invariants

- No card content is executed.
- No runtime network request is made.
- Team files are not written without explicit `--team` intent and preview.
- A finding that resembles a secret blocks team-save by default.
- Unsafe terminal bytes never reach the renderer unchanged.

