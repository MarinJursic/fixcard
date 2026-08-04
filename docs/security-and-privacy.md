# Security and privacy

Fixcard minimizes what it can expose or act upon by keeping a narrow runtime
data flow.

## What leaves the machine

Nothing through Fixcard. The CLI makes no runtime network requests and has no
telemetry, account, API key, background process, or cloud sync. Normal Git
operations remain outside Fixcard's control; committing and pushing a shared
card can publish its contents according to the repository's remotes.

## What is stored

- Queries, including bare-`fix` interactive pastes, are bounded to 1 MiB, held
  in memory for one lookup, and not persisted. Oversized terminal pastes are
  discarded through EOF before the error is returned, preventing unread input
  from reaching the caller's shell.
- Private cards are plain files under `<git-common-dir>/fixcard/cards/`.
- Shared cards are plain files under `.fixcards/` and become public or private
  according to the Git repository.
- User-global cards are plain files in the operating system's per-user
  application-data directory.
- `run --` retains at most 512 KiB from each output stream in memory and does
  not persist the captured failure.
- There is no database or cache in v1.

## What Fixcard can execute

Fixcard invokes Git with fixed, non-interactive arguments to discover repository
metadata. `run --` directly executes only the program and argument boundaries
supplied by the user. It does not invoke a shell and never executes commands
from a card. Code fences, `verified.command`, and extension data are inert text.
Windows `.bat` and `.cmd` programs are refused because Windows interprets them
through a command shell.

## Untrusted input controls

- per-card, aggregate-source, card-count, directory-entry, query, anchor,
  extension-depth, extension-node, and diagnostic work are bounded;
- card-directory symlinks are rejected and symlinked card files are ignored;
- IDs cannot traverse paths;
- ambiguous YAML and unsupported schema versions fail closed;
- terminal escape and unsafe control characters are stripped before display;
- semantic-version conflicts and negative conditions lower trust rather than
  being hidden by textual similarity.
- interactive paste reads only explicit terminal input; it never reads the
  clipboard, terminal scrollback, shell history, or arbitrary logs.
- malformed cards are quarantined during lookup with prominent bounded
  diagnostics; strict `lint` still fails.

## Provenance is descriptive, not authorization

`repository-committed` means the exact bytes parsed and displayed equal the
card blob at `HEAD`. It does not prove human review, a trusted Git author, a
trusted branch, or a trusted remote. `repository-working-copy`, `private`, and
`user-global` likewise describe source state only. No provenance label, author,
risk field, or validation field authorizes execution.

Duplicate IDs across scopes are independent and can be addressed with `repo:`,
`private:`, and `global:` prefixes. A repository card cannot suppress a
user-global card merely by declaring the same ID.

On Unix, clone-private and user-global directories are forced to mode `0700`
and card files to `0600`. On Windows, files inherit the ACL of the user's Git or
Local AppData directory; Fixcard does not attempt to replace Windows ACLs.

## Secret scanning limits

Shared creation scans known credential shapes, high-entropy values, embedded
URL credentials, database URLs, and suspicious assignments. A finding blocks
the write. Scanners have false positives and false negatives; humans must still
review every shared card and the Git diff. Never test the scanner with a real
credential.

## Repository policy

A repository may forbid command classes even on cards declared `risk: high` by
committing a bounded `.fixcard.toml` file:

```toml
[lint]
deny-command-classes = [
  "privileged-command",
  "recursive-deletion",
  "force-push",
  "remote-pipe-to-shell",
  "database-migration",
  "production-target",
  "credential-change",
]
```

Unknown fields or class names fail closed. The policy affects `lint` and card
creation; it cannot enable execution or weaken built-in diagnostics. The file
must be a regular UTF-8 file no larger than 64 KiB.

Report vulnerabilities privately using GitHub's security advisory interface as
described in the [security policy](../SECURITY.md). The detailed abuse cases and
controls are in the [threat model](threat-model.md).
