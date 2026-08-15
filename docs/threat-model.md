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
| Malicious card suggests destructive action | all card fields remain inert; lookup independently raises effective displayed risk, blocks strong confidence for underdeclared or policy-denied command classes, and shows descriptive provenance |
| Terminal escape injection or split-token scanner bypass | strip C0/C1, ANSI, OSC, and unsafe bidi/control characters before risk classification, secret redaction, and output so every stage sees the same canonical text |
| Wrong fix for another version | semantic version constraints, visible mismatch, hard negative conditions |
| Stale fix presented as current | `last_verified`, configurable staleness warning, retired/superseded lifecycle |
| Symlink or path traversal | stable ID validation, reject card-directory symlinks, ignore symlinked card files, no path construction from an unvalidated ID |
| Resource exhaustion | bounded Git output and diagnostics, committed-object counts and sizes before allocation, working entries, cards, aggregate and per-card bytes, anchors, extensions, queries, output tails, and diagnostics; Git children are terminated and reaped on bound failures; linear-time regexes only |
| Accidental collection of prior terminal context | bare `fix` reads only an explicit bounded paste through a raw, per-invocation random-token frame; no clipboard, scrollback, history, arbitrary-log, or background capture |
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
- Author-declared risk is never authoritative. Lookup reclassifies the title,
  rendered body, and recorded validation command with the built-in scanner;
  detected dangerous or repository-denied command classes cannot be a strong
  result, and the displayed risk cannot be lower than that effective result.
- Committed-card provenance reads reject excessive Git tree metadata, object
  counts, individual blob sizes, and aggregate source bytes before allocating
  blob bodies. Bounded Git diagnostics are drained concurrently, and children
  are terminated and reaped after an early failure.
- `run --` executes only user-supplied argv and preserves a failing child status.
- Interactive paste reads only standard input through a raw terminal frame with
  a cryptographically random completion token, is bounded to 1 MiB, and is not
  persisted. Control bytes remain query data, and oversized input is discarded
  until the frame closes so no tail returns to the shell. Ctrl-C arms a separate
  random cancellation frame instead of exiting with unread input. Catchable
  Unix termination signals restore terminal mode before being re-raised. A
  synchronization gate covers the transition into raw mode.
  Redirected prompts and, on Unix, split input/prompt terminals are rejected
  before raw mode so the random completion and cancellation tokens stay visible.
  The Unix `fix` companion replaces its process with `fixcard`, preventing a
  wrapper-only termination signal from orphaning the raw-mode owner.
- No runtime network request is made.
- Team files are not written without explicit `--team` intent and preview.
- A finding that resembles a secret blocks team-save by default.
- Unsafe terminal bytes never reach the renderer unchanged.
