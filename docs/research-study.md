# Pre-pilot research protocol

Stable 1.0 requires evidence that the problem and workflow are real, not only a
well-tested implementation. This protocol covers the two stages that precede
the four-week [dogfood pilot](dogfood.md).

## Evidence rules

- Recruit outside the Fixcard contributor group where possible.
- Do not pitch Fixcard before the Stage 1 diary is complete.
- Obtain participant consent and explain how aggregate results will be used.
- Keep raw error excerpts, repository names, private paths, commands, and
  company information in participant-controlled local notes.
- Publish only aggregate counts, sanitized quotations, methodology, missing
  data, and sample sizes.
- Do not reconstruct forgotten durations or manufacture synthetic incidents.
- Record recruitment dates, observation dates, participant attrition, and the
  exact Fixcard build used in Stages 2 and 3.

## Stage 1 — problem diary and interviews

Recruit 24–30 developers across at least five product/backend teams, three
platform or infrastructure contexts, three data/ML contexts, and several
open-source maintainers or frequent contributors. Include junior, mid-level,
senior, and staff roles, plus macOS, Linux, and Windows users.

For two working weeks, participants privately log failures that took more than
five minutes to resolve:

| Date | Context category | Resolution minutes | Source searched | Seen before? | Repository-specific? | Recurred? | Resolution saved anywhere? |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| | | | | | | | |

The interviewer may inspect a stable excerpt with the participant, but must not
copy it into public study material. The aggregate report includes participant
coverage, completion and attrition, total qualifying failures, and how many
participants recorded at least two plausible future-use resolutions.

Stage 1 passes only when at least one-third of participants record two or more
such failures.

## Stage 2 — concierge workflow

Ask each participating developer to create three cards from real prior failures.
For every card, prepare controlled recurrence variants that change paths, line
numbers, or versions without changing the underlying cause.

Measure:

- observed creation duration after the resolution is already known;
- correct card ranked first for each controlled recurrence;
- metadata that participants understand, ignore, or misinterpret;
- privacy edits and scanner false positives;
- whether the participant finds the card more trustworthy than a generic
  generated answer;
- whether a repository maintainer would approve the shared card after reviewing
  its actual content.

Stage 2 passes only when median creation is at most 30 seconds, at least 70% of
controlled recurrences return the correct card first, at least 60% of
participants prefer its trustworthiness, and at least five maintainers accept
committed cards after reviewing real examples. An approval that is never
committed does not count toward the maintainer gate.

## Public aggregate report

Publish the recruitment method, participant/context/platform coverage, dates,
sample sizes and denominators, attrition, missing data, each stage metric, and a
pass/change/stop decision. Do not publish a participant-level table when the
combination of role, platform, and context could identify someone.

The current status is maintained in [Validation results](validation-results.md).
The coordinator-ready scripts, consent boundaries, fixed denominators, corpus
procedure, and blank worksheets are in the
[Research operations guide](research-operations.md).
