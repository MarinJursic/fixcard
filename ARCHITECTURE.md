# Architecture

## Goals

Fixcard must be fast enough to feel like a shell primitive, safe with untrusted
repository content, useful without a database or service, and replaceable
without losing repository knowledge.

## Workspace boundaries

- `fixcard-core`: versioned card model, front-matter parsing, normalization,
  environment compatibility, deterministic ranking, and result explanations.
- `fixcard-git`: repository/worktree discovery, private/shared/global loading,
  exact committed-blob comparison, quarantine reporting, and provenance. Git is
  invoked with bounded, non-interactive calls.
- `fixcard-lint`: schema, lifecycle, secret, local-data, certainty-language,
  and risky-command diagnostics. It does not mutate cards.
- `fixcard-cli`: arguments, direct command capture, input modes, terminal-safe
  rendering, OS data-directory selection, and reviewed creation workflow.

Dependencies point inward: the CLI may depend on every library, lint and Git
may depend on core, and core never depends on terminal or Git behavior.

## Data flow

1. Optionally discover the nearest Git worktree and Git common directory.
2. Load repository, clone-private, and user-global Markdown card origins.
3. Parse bounded UTF-8 input into a versioned model; quarantine malformed cards
   for lookup while strict lint fails them.
4. Sanitize terminal control sequences before displaying any repository text.
5. Normalize the supplied failure and calculate deterministic evidence for each
   eligible card.
6. Apply hard exclusions and compatibility penalties before confidence labels.
7. Display at most one strong result by default; weak results require `--all`.

## Matching contract

Ranking is deliberately explainable. Exact anchors, required substrings,
diagnostic tokens, normalized token overlap, environment compatibility,
committed/source provenance, and staleness each produce named evidence. Version
or negative-condition conflicts cannot be hidden by a high text score.

Thresholds are constants with fixture-backed precision tests. They are not
marketed as calibrated until tested on representative real failures.

## Storage and cache

V1 requires no database. Cards are parsed on demand. An index cache may be
added only after measured workloads justify it; if added, it belongs under the
Git common directory, is content-addressed, contains no card body, and can be
deleted without losing information.

## Compatibility

Unknown top-level front-matter fields require an `x-` prefix, are preserved at
the data-model boundary, and are ignored by matching and behavior. Unknown
fields inside v1-defined structures and unknown schema versions fail closed.
All v1 command-shaped content remains inert. The Markdown body remains useful
without the binary.

## Decision records

Material format or trust changes require an ADR under `docs/decisions/`, an
example, migration behavior, and tests. Features outside the documented command
surface require evidence from real workflows and an explicit scope review.
