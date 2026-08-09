# Research operations kit

This directory contains blank, privacy-minimizing templates for Fixcard's
pre-pilot research and release-candidate pilot. Copy the templates into a
participant-controlled or access-controlled location before entering data. Do
not commit completed worksheets to this repository.

The templates deliberately collect aliases, counts, timings, and decisions—not
raw errors, commands, paths, repository names, or failure descriptions. Follow
the complete [study operations guide](../docs/research-operations.md) before
recruiting participants or collecting observations.

## Templates

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
