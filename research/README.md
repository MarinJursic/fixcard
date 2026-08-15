# Research operations kit

> [!IMPORTANT]
> **The protected RC7 activation is installed. Collection is open only when the
> evidence validator reports `OPEN`.** Use only post-boundary observations and the exact
> registered templates. Opening collection satisfies no gate and does not
> authorize stable 1.0.

This directory contains blank, privacy-minimizing templates for Fixcard's
pre-pilot research and release-candidate pilot. When collection is explicitly
open, copy the templates into a participant-controlled or access-controlled
location before entering data. Do not commit completed worksheets to this
repository.

The templates deliberately collect aliases, counts, timings, and decisions—not
raw errors, commands, paths, repository names, or failure descriptions. Follow
the complete [study operations guide](../docs/research-operations.md) before
recruiting participants or collecting observations.

## Templates

The historical root templates remain bound to the interrupted RC4 protocol.
The exact RC7 Stage 2 and Stage 3 templates are frozen separately under
[`pilots/rc7/templates`](pilots/rc7/templates); they add a pilot ID, build
manifest digest, a Stage 2 observation timestamp, and a coordinator-controlled
installation-receipt schema. Neither set authorizes collection while intake is
closed.

- [`stage-1-participants.csv`](templates/stage-1-participants.csv) records one
  aggregate row per recruited participant.
- [`stage-2-observations.csv`](templates/stage-2-observations.csv) records one
  aggregate row per real card evaluated in the concierge study.
- [`stage-3-repository-weeks.csv`](templates/stage-3-repository-weeks.csv)
  records one aggregate row per anonymous repository and pilot week.
- [`stage-3-active-user-reuse.csv`](templates/stage-3-active-user-reuse.csv)
  records reconciled participant/repository memberships so the global
  active-user reuse denominator can be deduplicated without publishing
  identities.
- [`stage-3-eight-week-card-reuse.csv`](templates/stage-3-eight-week-card-reuse.csv)
  freezes the card-level denominator for kill criterion 5.
- [`aggregate-report.md`](templates/aggregate-report.md) is the public report
  outline and decision record.

Run `ruby scripts/check_research_kit.rb` from a full Git clone with Ruby 3.1 or
newer to verify that the distributed templates retain their expected
privacy-minimizing schemas and match the frozen protocol commit.
