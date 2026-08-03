# Fixcard

[![CI](https://github.com/MarinJursic/fixcard/actions/workflows/ci.yml/badge.svg)](https://github.com/MarinJursic/fixcard/actions/workflows/ci.yml)
[![Security](https://github.com/MarinJursic/fixcard/actions/workflows/security.yml/badge.svg)](https://github.com/MarinJursic/fixcard/actions/workflows/security.yml)
[![MSRV: 1.85](https://img.shields.io/badge/MSRV-1.85-DEA584.svg)](https://www.rust-lang.org/)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**Paste an error; get the fix this repository already proved.**

Fixcard is a local, Git-aware command-line tool and an open Markdown format for
repository-specific troubleshooting knowledge. It finds human-recorded fixes,
shows exactly why one matched, and keeps the conditions, risk, validation, and
provenance beside the resolution.

Fixcard does not generate advice, capture shell history, upload logs, call a
model, run a daemon, or execute a card's commands.

> [!WARNING]
> Fixcard is an **alpha**. Its safety and deterministic behavior are tested, but
> real-world adoption and retrieval quality have not yet passed the published
> [validation plan](docs/validation.md). A previous resolution is evidence, not
> a guarantee.

## A two-minute example

From anywhere inside a Git worktree:

```console
$ fixcard find ERR_PNPM_OUTDATED_LOCKFILE frozen-lockfile
1 strong repository match

pnpm-outdated-lockfile — Regenerate the lockfile with the pinned pnpm version
confidence: strong · origin: shared · risk: low

Run: fixcard show pnpm-outdated-lockfile
```

Inspect the complete, inert card:

```console
$ fixcard show pnpm-outdated-lockfile
```

After deliberately solving a new failure, preserve it privately:

```console
$ fixcard new
```

When the card is general enough for teammates, create or move it to
`.fixcards/`, lint it, and review it like code:

```console
$ fixcard new --team
$ fixcard lint
```

See [Getting started](docs/getting-started.md) for a complete walkthrough and
[`examples/repository`](examples/repository) for a small teaching repository.

## Install

The current alpha can be built directly from the public repository:

```bash
cargo install --git https://github.com/MarinJursic/fixcard --locked fixcard
```

Rust 1.85 or newer is supported. Tagged prereleases will also provide
cross-platform binaries, checksums, an SBOM, and GitHub artifact attestations.
See [Installation and verification](docs/installation.md) for source builds,
upgrades, and artifact verification.

## Commands

| Command | Purpose |
| --- | --- |
| `fixcard find [query]` | Search shared and private cards. Reads stdin when no query is supplied. |
| `fixcard show <id>` | Show one complete card, provenance, and evidence notice. |
| `fixcard new [--team]` | Create a reviewed private card, or explicitly create a shared card. |
| `fixcard lint [path]` | Check schema, anchors, versions, secrets, risk, lifecycle, and staleness. |

Useful lookup switches include `--explain`, `--all`,
`--tool node=22.18.0`, and `--include-retired`. Run any command with `--help`
for its exact interface.

## Why a repository boundary?

A fix can be correct for one codebase and harmful in another. Fixcard only
loads cards belonging to the current Git repository:

- shared cards: `<worktree>/.fixcards/*.md`, reviewed and versioned with code;
- private cards: `<git-common-dir>/fixcard/cards/*.md`, local to the clone and
  shared safely across linked worktrees.

There is no global corpus and no network lookup. The Markdown remains readable
and useful if the binary disappears.

## Trust model

- Matching is deterministic and can explain every scoring contribution.
- A negative condition or clear version mismatch prevents a strong result.
- Default lookup shows at most one strong match; weak candidates require
  `--all`.
- Commands are rendered as untrusted text and are never executed.
- Terminal control bytes are neutralized before display.
- Shared-card creation is explicit, previewed, and blocked on secret-like
  findings; scanning remains defense in depth, not proof of safety.
- Retired and superseded cards stay addressable but leave default search.

Read the [security and privacy guide](docs/security-and-privacy.md), the formal
[threat model](docs/threat-model.md), and the draft
[v1 format specification](spec/fixcard-v1.md).

## When Fixcard is—and is not—the right tool

Use Fixcard when a recurring failure has a repository-specific resolution worth
preserving with its conditions. Use shell-history tools for recalling commands,
cheatsheets for general command discovery, runbooks for multi-step operations,
and ordinary docs or a permanent code fix when the knowledge is broadly
applicable. Repeated use of the same card is a signal to remove the underlying
failure.

The narrower product rationale and competitor boundaries are documented in
[Research and positioning](docs/research-and-positioning.md).

## Documentation

- [Documentation index](docs/README.md)
- [Getting started](docs/getting-started.md)
- [Card authoring guide](docs/card-authoring.md)
- [Matching and confidence](docs/matching.md)
- [Team workflow](docs/team-workflow.md)
- [Examples](docs/examples.md)
- [FAQ](docs/faq.md)
- [Architecture](ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Roadmap](ROADMAP.md)

## Project status and name

The four-command MVP is implemented and tested on Linux, macOS, Windows, and
Rust 1.85. Performance gates cover a 1,000-card repository. Those engineering
facts do not prove product adoption; the project will not claim otherwise.

“Fixcard” remains a working name. A preliminary collision search found an
unrelated aviation-recruiting service and no same-purpose developer tool, but
this is not legal or trademark clearance. See [Name due diligence](docs/naming.md).

## License

The implementation and specification are licensed under Apache-2.0. Cards
created in another repository remain subject to that repository's licensing,
privacy, and contribution rules.
