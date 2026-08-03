# Threat model

## Assets

- secrets and private identifiers in pasted logs;
- repository integrity and developer machines;
- user trust in card provenance and validation;
- terminal integrity when displaying untrusted Markdown;
- shared repository history.

## Trust boundaries

The current repository, every card in every scope, pasted input, environment
metadata, Git configuration, requested program, and subprocess output are
untrusted. The local operating system and installed Fixcard binary are trusted.
Network services are outside the runtime data flow.

## Primary threats and controls

| Threat | Control |
| --- | --- |
| Secret committed in a card | private-by-default storage, preview, conservative scanner, team-save cancellation on findings |
| Malicious card suggests destructive action | all card fields remain inert, visible high-risk state, command-class diagnostics, descriptive provenance |
| Terminal escape injection | strip C0/C1, ANSI, OSC, and unsafe bidi/control characters before output |
| Wrong fix for another version | semantic version constraints, visible mismatch, hard negative conditions |
| Stale fix presented as current | `last_verified`, configurable staleness warning, retired/superseded lifecycle |
| Symlink or path traversal | stable ID validation, reject card-directory symlinks, ignore symlinked card files, no path construction from an unvalidated ID |
| Resource exhaustion | bounded entries, cards, aggregate and per-card bytes, anchors, extensions, queries, output tails, and diagnostics; linear-time regexes only |
| Git option or command injection | fixed Git argv, `--` before paths, no shell invocation, non-interactive environment |
| Shell injection through `run --` | direct argv spawn without a shell; refuse Windows batch formats; card text never becomes argv |
| One malformed or colliding card hides valid cards | per-card quarantine during lookup, scoped duplicate addressing, strict lint remains separate |
| Certainty laundering | lint claims such as “always fixes”; render an evidence-not-guarantee notice |
| Supply-chain compromise | locked dependencies, commit-pinned CI actions, checksums, artifact attestations, SBOM, dependency review |

## Non-promises

Secret scanning is defense in depth, not proof that a card is safe to publish.
Exact equality with a `HEAD` blob is provenance, not human review or an
endorsement. A recorded validation proves only the reported command and exit
status under recorded conditions.

## Security invariants

- No card content is executed.
- `run --` executes only user-supplied argv and preserves a failing child status.
- No runtime network request is made.
- Team files are not written without explicit `--team` intent and preview.
- A finding that resembles a secret blocks team-save by default.
- Unsafe terminal bytes never reach the renderer unchanged.
