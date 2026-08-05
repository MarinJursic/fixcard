# Research operations guide

This guide turns the [pre-pilot protocol](research-study.md) and
[release-candidate pilot](dogfood.md) into a coordinator-ready procedure. It
does not replace local ethics, employment, privacy, or legal review. Completed
worksheets stay outside the public repository.

## 1. Register before collecting data

Before recruitment, copy the blank files from [`research/templates`](../research/templates)
to an access-controlled location and record:

- the protocol commit, dates, coordinator, conflicts, and exact denominator
  rules;
- recruitment quotas and the treatment of attrition and missing observations;
- the exact Fixcard build reserved for Stages 2 and 3;
- the pass, change, stop, and kill criteria without weakening them later;
- who may inspect participant-controlled raw notes and when they are destroyed.

The current Stage 3 registration is machine-readable in
[`research/pilot-registration.json`](../research/pilot-registration.json). It
freezes the exact tag, commit, archive digests, eligible start date, denominators,
thresholds, and all ten kill criteria before observations begin. A prose issue
or release announcement cannot override that file.

Participant aliases use `P001`, `P002`, and so on. Repository aliases use
`R001`, `R002`, and so on. Context aliases such as `PB01` describe a team or
working context without naming it. Keep the alias key separate from study data.

## 2. Recruit without pitching the product

Recruit 24–30 developers using the coverage quotas in
[Pre-pilot research](research-study.md). A neutral invitation is:

> We are studying how developers recover from failures that take more than five
> minutes to resolve. For two working weeks, you will keep brief private notes
> about qualifying incidents. We are evaluating the problem before presenting
> a proposed tool.

Before participation, explain the observation period, time burden, voluntary
nature, withdrawal process, access to notes, aggregate publication, and limits
on confidentiality. Obtain the form of consent required by the coordinator's
organization. Do not imply that this repository supplies legal or ethics
approval.

## 3. Run the non-leading Stage 1 diary

Give participants only the private diary fields in
[Pre-pilot research](research-study.md). Do not mention cards, matching, Fixcard,
or a desired recurrence rate. A reminder may restate the five-minute threshold
and privacy rules but must not ask participants to find a reusable failure.

At the end of two working weeks, the coordinator transfers only one aggregate
row per recruited participant into `stage-1-participants.csv`:

- `recruitment_context`: `product_backend`, `platform_infrastructure`,
  `data_ml`, or `open_source`;
- `role_band`: `junior`, `mid`, `senior`, or `staff`, never a uniquely
  identifying job title;
- `platform`: `macos`, `linux`, `windows`, or preregistered `mixed`;
- `qualifying_failures`: failures observed above the five-minute threshold;
- `reusable_failures`: qualifying resolutions judged plausibly useful later;
- `recurrent_failures`, `repository_specific_failures`, and
  `previously_saved_failures`: aggregate incident counts, each no greater than
  `qualifying_failures`.

The Stage 1 denominator is everyone recruited, not only completers. Report
attrition separately. Stage 1 passes only when at least one third of recruited
participants record two or more plausible reusable failures and the required
coverage was actually recruited.

For coverage, count distinct `context_alias` values and require at least five
`product_backend`, three `platform_infrastructure`, and three `data_ml`
contexts, plus at least three `open_source` participants. Recruit at least one
participant in every role band and at least one macOS, Linux, and Windows user;
`mixed` does not substitute for a missing named platform.

## 4. Create the Milestone 0 evidence corpus

Before using real incidents as matching evidence, obtain explicit permission
for each retained pair. Collect at least 100 real failure/resolution pairs;
synthetic examples and multiple formatting variants of one incident do not
increase the pair count.

Sanitization removes or replaces repository names, people, organizations,
customer identifiers, hostnames, private paths, credentials, tokens, internal
URLs, source excerpts, and commands that reveal infrastructure. A second person
reviews every retained pair. Preserve the stable diagnostic structure needed
for matching, record its broad ecosystem/category, and assign a corpus alias.

The public report states the pair count, consent/access model, categories,
sampling limitations, and review method. Publish pair contents only when the
participant and repository owner explicitly permit it. Otherwise keep the
corpus access-controlled and publish aggregate benchmark results.

## 5. Run Stage 2 consistently

Only after the diary closes, explain Fixcard and ask each participant to create
three cards from real prior failures. Time creation after the resolution is
already known. Prepare controlled recurrence variants by changing incidental
paths, line numbers, or versions without changing the cause.

Record one row per real card in `stage-2-observations.csv`. Use a stable
non-identifying `maintainer_alias` such as `M001` for the reviewer; leave it
blank only when the card was not reviewed. The
`correct_rank_one` value is a count no greater than `controlled_variants`.
Semicolon-separated timing samples compare Fixcard with the participant's
normal search route. Record whether metadata caused confusion, plus only counts
of privacy edits and scanner false positives—never the removed text.
Use `fixcard`, `normal_search`, or `no_preference` for one consistent
`trust_preferred` response per participant; leave it blank when unanswered. Use
`accepted`, `changes_requested`, `rejected`, or `not_reviewed` for
`maintainer_decision`.

Report the median across observed card-creation durations, rank-one precision
as correct variants divided by all controlled variants, comparative trust once
per responding participant, and the number of distinct maintainers with at
least one accepted committed card after normal review. Stage 2 needs at least
five such maintainers. Missing timings or responses stay missing.

## 6. Run Stage 3 on one exact build

Freeze one release-candidate version for 5–8 active repositories and four
working weeks. Follow the [dogfood protocol](dogfood.md). Enter one aggregate
row per anonymous repository and week in `stage-3-repository-weeks.csv`.

Timing sample fields contain semicolon-separated observed numeric durations,
not estimates. `full_lookups_under_ten_seconds`, `fixcard_used_first`, and
`other_tool_used_first` are counts no greater than `lookup_attempts`.
`correct_abstentions` and `incorrect_abstentions` describe lookups without a
strong result. `cumulative_unique_active_reusers` is the deduplicated number
through that week; use the week-four value and never sum it across weeks.
Record differentiation responses and maintenance burden in the final week
unless the protocol preregisters more frequent collection. A serious trust
incident, unsafe-certainty incident, or missed real secret is reported
immediately and cannot be averaged away by more activity.

`users_bypassing_scanner_due_false_positives` is a deduplicated weekly user
count. Any nonzero count fails the privacy gate; a frustrating false positive
must not be hidden merely because it did not expose a secret.

Do not switch builds mid-pilot. If a security fix requires a new build, stop,
document the interruption, and preregister whether the affected observation
period must restart.

Before aggregation, validate the access-controlled Stage 3 CSV with:

```sh
ruby scripts/research_evidence.rb --complete-pilot /path/to/stage-3.csv
```

The command is intentionally fail-closed for blank or nonregistered versions,
duplicate repository-weeks, impossible count relationships, incomplete weeks,
and repository coverage outside 5–8. Do not edit the validator or registration
after seeing results to make a report pass.

In the CSV, encode maintenance burden as `acceptable`, `unacceptable`, or
`too_early_to_judge`. Semicolon-delimited timing samples must be the observed
non-negative values; their counts cannot exceed the corresponding lookup or
authored-card counts.

## 7. Use fixed denominators

Calculate and publish:

| Metric | Numerator | Denominator |
| --- | --- | --- |
| Stage 1 recurrence | Recruited participants with two or more reusable failures | All recruited participants |
| Stage 2 precision | Correct rank-one controlled variants | All observed controlled variants |
| Stage 2 trust | Participants preferring Fixcard's trustworthiness | Participants answering the comparison once |
| Stage 3 relevance | Relevant strong rank-one matches | All displayed strong rank-one matches |
| Stage 3 full-flow speed | Observed end-to-end lookups below 10 seconds | All observed end-to-end lookup timings |
| Stage 3 capture behavior | Weekly active users creating at least three cards | Weekly active users for the same repository-weeks |
| Stage 3 reuse | Unique active users who reused a card or had a teammate reuse one | Unique active pilot users over four weeks |
| Differentiation | Pilot users who distinguish Fixcard from alternatives | Pilot users answering the differentiation question |
| Maintenance | Repositories reporting acceptable burden in week four | Repositories answering the week-four maintenance question |

For creation and capture medians, publish the number of observed durations.
For lookup performance, report tool-search measurements separately from the
human end-to-end flow. Never replace a missing denominator with downloads,
stars, total cards, synthetic runs, or engineering tests.

## 8. Review every stop condition

Stop or radically change the project when any condition persists after one
focused iteration:

1. More than 80% of relevant developers create no card after onboarding.
2. Median creation remains above 30 seconds.
3. Strong-match false positives exceed 20%.
4. Most users prefer ordinary history, Atuin, Recall, or equivalent search.
5. Fewer than 10% of cards are reused by another person over eight weeks in
   active teams.
6. Teams refuse committed cards as clutter or liability.
7. Secret redaction is not reliable enough for shared cards.
8. Cards become stale faster than they are used.
9. The product needs automatic terminal capture to feel valuable.
10. Adoption depends on AI generation, cloud sync, or workflow replay.

Do not reinterpret a triggered criterion as success. Record a `change` or
`stop` decision and the focused iteration, if any, before collecting more data.

## 9. Publish an auditable aggregate report

Use [`aggregate-report.md`](../research/templates/aggregate-report.md). Publish
coverage, dates, exact build, denominators, missing data, deviations, all
thresholds, every kill criterion, and one `go`, `change`, or `stop` decision.
Small cells that could identify a participant are combined or suppressed.

Stable 1.0 is eligible only after all evidence gates pass. A technically green
release candidate with missing participant evidence remains a prerelease.

Submit the Stage 1 and 2 aggregate report as a pull request that updates
[Validation results](validation-results.md) and links its public methodology.
Submit Stage 3 repository-week aggregates through the
[validation report form](https://github.com/MarinJursic/fixcard/issues/new?template=validation-report.yml),
then use the same protected pull-request path for the final decision.
