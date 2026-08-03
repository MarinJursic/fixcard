# Frequently asked questions

## Does Fixcard diagnose new errors?

No. It retrieves a resolution a human already recorded for this repository. No
strong match is a valid and expected result.

## Does it run the suggested command?

Never. Commands and validation evidence are inert text for human review.

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

No. IDs must be unique across private and shared storage. `show` and provenance
need an unambiguous identity.

## Why is a plausible result marked weak?

Fixcard prioritizes precision over recall. Missing exact evidence, a negative
condition, a version/platform conflict, staleness, or lifecycle state can keep a
candidate weak. Use `--explain --all` to inspect why.

## Is the format stable?

The v1 document is an implementation draft. Backward-compatibility guarantees
begin at the first tagged 1.0 specification release. Plain Markdown remains
readable regardless.

## Why not share a global card marketplace?

Repository specificity is the safety boundary and the product value. A global
fix corpus would recreate generic search results with weaker provenance and
more opportunities for malicious instructions.
