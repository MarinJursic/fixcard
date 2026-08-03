# Security and privacy

Fixcard minimizes what it can expose or act upon by keeping a narrow runtime
data flow.

## What leaves the machine

Nothing through Fixcard. The CLI makes no runtime network requests and has no
telemetry, account, API key, background process, or cloud sync. Normal Git
operations remain outside Fixcard's control; committing and pushing a shared
card can publish its contents according to the repository's remotes.

## What is stored

- Queries are held in memory for the lookup and are not persisted.
- Private cards are plain files under `<git-common-dir>/fixcard/cards/`.
- Shared cards are plain files under `.fixcards/` and become public or private
  according to the Git repository.
- There is no database or cache in v1.

## What Fixcard can execute

Fixcard invokes Git with fixed, non-interactive arguments to discover repository
metadata. It does not invoke a shell and never executes commands from a card.
Code fences and validation commands are inert text.

## Untrusted input controls

- card and query sizes/counts are bounded;
- card-directory symlinks are rejected or ignored;
- IDs cannot traverse paths;
- ambiguous YAML and unsupported schema versions fail closed;
- terminal escape and unsafe control characters are stripped before display;
- semantic-version conflicts and negative conditions lower trust rather than
  being hidden by textual similarity.

## Secret scanning limits

Shared creation scans known credential shapes, high-entropy values, embedded
URL credentials, database URLs, and suspicious assignments. A finding blocks
the write. Scanners have false positives and false negatives; humans must still
review every shared card and the Git diff. Never test the scanner with a real
credential.

Report vulnerabilities privately using GitHub's security advisory interface as
described in the [security policy](../SECURITY.md). The detailed abuse cases and
controls are in the [threat model](threat-model.md).
