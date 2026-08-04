# Validation plan

Fixcard separates engineering verification from product validation.

Participants use the privacy-preserving [dogfood program](dogfood.md) and submit
aggregated reports without raw logs or proprietary repository content.
The non-leading diary and concierge protocols are in
[Pre-pilot research](research-study.md). Current evidence and missing gates are
published in [Validation results](validation-results.md).

The [Research operations guide](research-operations.md) supplies neutral
recruitment language, consent boundaries, fixed denominators, privacy-safe blank
worksheets, and the public aggregate-report structure.

## Verified in the repository

- the parser rejects malformed, ambiguous, oversized, and unsupported cards;
- repository discovery works from nested directories and linked worktrees;
- user-global cards work inside or outside Git using standard OS data paths;
- matching is deterministic, explainable, and honors hard conflicts;
- `fix` renders the complete resolution in one invocation;
- `run --` preserves argv boundaries, streams child output, keeps bounded
  in-memory tails, places its recommendation on stderr, and preserves status;
- shared creation is explicit, previewed, linted, and atomic;
- lookup quarantines malformed cards while strict lint still fails;
- exact parsed bytes, rather than Git authorship, determine the
  `repository-committed` label;
- card content is not executed, symlinked card directories are rejected,
  private Unix modes are restricted, and terminal controls are neutralized;
- Linux, macOS, Windows, and Rust 1.85 builds are exercised in CI;
- a 1,000-card benchmark is gated below the 100 ms p95 lookup target on the CI
  reference runner;
- optimized process startup is gated below the 75 ms p95 target;
- a pseudo-terminal regression test stresses SIGTERM during startup and verifies
  that interactive paste terminal state is restored before exit;
- dependencies are locked, audited, policy-checked, and reviewed;
- third-party CI actions are commit-pinned and release archives are extracted
  and smoke-tested before publication.

These are testable implementation claims. They do **not** establish that people
will create cards or that strong matches are relevant in diverse repositories.

## Unverified product hypotheses

1. After an expensive failure is solved, a developer will spend about 20
   seconds preserving the result.
2. Repository-specific anchors produce sufficiently precise rank-one retrieval
   on real logs.
3. Authors or teammates reuse cards often enough to repay capture and review.
4. Teams can share cards without a serious privacy or unsafe-command incident.
5. The useful niche remains distinct from shell history, docs, and runbooks.

## Staged study

### Milestone 0 — evidence corpus

Retain at least 100 sanitized real failure/resolution pairs with explicit
permission, a second-person sanitization review, broad category metadata, and a
documented access model. Synthetic examples and multiple variants of one real
incident do not increase the count. Pair contents remain access-controlled
unless both the participant and repository owner permit publication.

This corpus supports representative matching evaluation; the synthetic
1,000-card benchmark proves performance only.

### Stage 1 — diary and interviews

Recruit 24–30 developers spanning product/backend, platform/infrastructure,
data/ML, and open-source contexts; junior through staff roles; and macOS,
Linux, and Windows. Do not pitch Fixcard before the diary. For two working
weeks, record failures taking more than five minutes, recurrence, repository
specificity, discoverability, and whether a permanent fix was made. Raw excerpts
stay with the participant and are never submitted publicly.

Pass only when at least one-third of participants record two or more meaningful
failures whose resolution could plausibly help a future repository user.

### Stage 2 — concierge capture

Each participant creates three cards from real prior failures. Test controlled
variants with changed paths, line numbers, and versions. Measure creation time,
correct first retrieval, metadata comprehension, privacy edits, comparative
trust, and whether maintainers would accept shared cards.

Pass only when median concierge creation is at most 30 seconds, at least 70% of
seeded recurrences return the correct card first, at least 60% of participants
prefer its trustworthiness to a generic generated answer, and at least five
repository maintainers accept committed cards after reviewing real examples.

### Stage 3 — four-week dogfood

Use one exact Fixcard build in 5–8 active repositories for four weeks. Label each
shown strong match as relevant or not, track abstentions and end-to-end lookup
time, record capture and reuse by author versus teammate, track normal pull-request
review of shared cards, and review every secret/risk finding. Publish only
aggregated, anonymized results and methodology.

## Go/change/stop thresholds

Promote the exact tested release candidate to stable 1.0 only if every stage
passes and the four-week pilot meets all core thresholds:

| Metric | Required signal |
| --- | --- |
| Match precision | At least 75% of strong rank-one matches judged relevant; target 85% before broad promotion |
| Lookup latency | Search below 100 ms and the full human lookup flow usually below 10 seconds |
| Creation friction | Median at or below 20 seconds after the resolution is known |
| Capture behavior | At least 50% of weekly active pilot users create three or more cards |
| Reuse | At least 30% of active users consume a prior card within four weeks, or a teammate consumes one |
| Team acceptance | At least five shared cards accepted through normal pull-request review across multiple repositories |
| Trust | No serious incident caused by misleading certainty or automatic execution |
| Privacy | No undetected real secret in the pilot corpus and false-positive burden low enough that scanning is not bypassed |
| Differentiation | A majority of pilot users can explain why Fixcard is not simply history, Atuin, Recall, Navi, or a README |
| Maintenance | Burden remains acceptable to participating repositories |

Change the capture or matching design if usefulness exists but a threshold
misses. Stop expanding the product if developers consistently decline capture,
reuse is negligible, strong-match relevance stays below 60% after one focused
iteration, or safe sharing requires burdensome process. Evidence from synthetic
incidents, stars, downloads, total card count, or same-day engineering tests
cannot substitute for these behavioral gates.

The complete ten-item kill-criteria review and fixed denominator definitions are
in [Research operations](research-operations.md). Every published decision must
report each criterion rather than silently omitting adverse evidence.

The strongest question is: **did a developer encounter a real failure, receive
the right repository-owned record at the right moment, and safely resolve the
problem faster than rediscovering it?**
