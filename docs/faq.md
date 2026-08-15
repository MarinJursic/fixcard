# Frequently asked questions

## Does Fixcard diagnose new errors?

No. It retrieves a resolution a human already recorded for the current
repository, clone, or user-global collection. No strong match is a valid and
expected result.

## Does it run the suggested command?

Never. Commands and validation evidence are inert text for human review.

## Can bare `fix` recover the command that just failed?

It cannot recover output printed before it started because shells expose no
portable, privacy-safe API for prior terminal output. Bare `fix` instead opens
a one-shot paste prompt. The supplied text is bounded, searched locally, and
not saved. Fixcard never scrapes scrollback, clipboard contents, or history and
never reruns the previous command silently.

## Why not use shell history?

History remembers what was typed, not why it worked, which repository it was
for, when not to use it, or whether it was reviewed. History tools remain better
for recalling commands.

## Why not put this in the README or runbook?

Do so when readers can find the information by topic. Fixcard is for the moment
when a developer has raw failure text and needs the one repository-specific
record that recognizes it. A card may link to longer documentation.

## Are private cards encrypted or synchronized?

No. They use ordinary filesystem permissions and stay in the clone's Git common
directory. Use operating-system disk encryption and your normal backup policy;
do not put secrets in cards.

## What happens in a linked worktree?

Private cards live in the common Git directory, so linked worktrees in the same
clone share them. Shared cards follow the checked-out branch like other files.

## Can two cards have the same ID?

IDs must be unique within one origin. The same ID may exist in another scope;
use `repo:id`, `private:id`, or `global:id` with `show` when it is ambiguous.

## Why is a plausible result marked weak?

Fixcard prioritizes precision over recall. Missing exact evidence, a negative
condition, an unknown or conflicting tool version, a platform conflict,
scanner-raised or repository-denied command risk, staleness, or lifecycle state
can keep a candidate weak. Use `--explain --all` to inspect why.

## Is the format stable?

Yes. The v1 data model, extension rule, and inert-command semantics are frozen
separately from the CLI release candidate. Incompatible meaning requires a
future schema version. Plain Markdown remains readable regardless.

## Why not share a global card marketplace?

Fixcard supports a local user-global scope for personal knowledge. It does not
provide a network registry or marketplace. A public universal corpus would
recreate generic search results with weaker context and more opportunities for
malicious instructions.
