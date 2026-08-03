# Validation plan

Fixcard separates engineering verification from product validation.

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

### Stage 1 — diary and interviews

Recruit developers maintaining active repositories. For two weeks, collect only
sanitized metadata about failures that took meaningful time to solve: recurrence,
repository specificity, discoverability, and whether a permanent fix was made.
Do not ask participants to upload raw proprietary logs.

### Stage 2 — concierge capture

For qualifying incidents, draft the card with the participant immediately after
the fix. Measure median authoring time, fields omitted, privacy edits, and whether
the participant judges the card worth keeping. This validates the workflow
before adding integrations.

### Stage 3 — four-week dogfood

Use Fixcard in 5–8 active repositories. Label each shown strong match as relevant
or not, track abstentions, record reuse by author versus teammate, and review all
secret/risk findings. Publish only aggregated, anonymized results and methodology.

## Go/change/stop thresholds

Promote the release candidate to stable 1.0 only if:

- at least 75% of strong rank-one matches are judged relevant, targeting 85%;
- median card creation is at most 20 seconds once the fix is known;
- multiple cards are reused by authors or teammates;
- no serious secret exposure or unsafe-action incident occurs;
- maintenance burden remains acceptable to participating repositories.

Change the capture or matching design if usefulness exists but a threshold
misses. Stop expanding the product if developers consistently decline capture,
reuse is negligible, strong-match relevance stays below 60% after one focused
iteration, or safe sharing requires burdensome process. Do not use card count,
stars, or total searches as substitutes for relevance and reuse.

The strongest question is: **did a developer encounter a real failure, receive
the right repository-owned record at the right moment, and safely resolve the
problem faster than rediscovering it?**
