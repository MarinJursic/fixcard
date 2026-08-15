# Matching and confidence

Fixcard's ranking is deterministic, repository-local, and explainable. It is
designed to abstain instead of turning weak similarity into confident advice.

## Input normalization

Before comparing text, Fixcard safely removes common runtime noise such as ANSI
and bidirectional control bytes, timestamps, UUIDs, volatile hex values, PIDs,
ports, durations, local home/temp paths, repetitive lines, and deep stack-frame
noise. It normalizes Unicode and whitespace while preserving diagnostic codes,
filenames, and useful literals.

Normalization changes only the lookup representation. Fixcard neither stores
nor rewrites the pasted query.

## Evidence

The ranker combines named contributions from:

- exact diagnostic anchors;
- additional literal fragments;
- diagnostic-token and normalized-token overlap;
- OS, architecture, and supplied tool-version compatibility;
- shared/private origin and card age.

Run `fixcard fix --explain ...` to see those contributions. Scores order
candidates; confidence controls whether Fixcard presents one as a strong match.

## Hard caution states

Raw text score cannot override:

- a matching `not_contains` condition;
- a supplied tool version outside `applies.tools`;
- a missing current version for a tool constrained by `applies.tools`;
- an invalid recorded `applies.tools` version range;
- an incompatible OS or architecture;
- retirement or supersession.

Such cards are weak or omitted by default. Use `--all` to inspect weak results
and `--include-retired` for lifecycle history. Supply a current version with
`--tool NAME=VERSION`; otherwise weak output labels the card
`applicability-unknown`. An invalid range is always weak and is labeled
`applicability-invalid`, even when no current version is supplied.

## Result contract

- Default lookup returns at most one strong match.
- Ties and insufficient evidence do not become confident answers.
- `show` always identifies recorded validation as historical evidence.
- A strong result whose recorded validation is stale is labeled before its
  inert instructions.
- Result ordering is stable for the same cards, query, environment, and date.

Numeric thresholds are implementation details until the real-world relevance
study is complete. See [Validation](validation.md) for the acceptance targets.
