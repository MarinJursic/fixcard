# Fixcard

**Paste an error; get the fix this repository already proved.**

Fixcard is a local, Git-aware command-line tool and an open Markdown format for
repository-specific, human-confirmed troubleshooting knowledge. It searches
cards in the current repository, explains why a card matched, and displays the
recorded resolution with its conditions, validation, provenance, staleness,
and risk.

> [!IMPORTANT]
> Fixcard is under active development. The `fixcard` name is a working project
> name; a preliminary search found unrelated uses, so it should not be treated
> as a trademark-clearance conclusion.

## What makes it different

Other tools remember commands or generate suggestions. Fixcard remembers what
this repository proved. It deliberately does not capture shell history, call an
LLM, upload logs, run a daemon, or execute a card's commands.

```text
failure -> deliberate human resolution -> small Markdown card -> Git review
   ^                                                        |
   +---------------- conservative local lookup <------------+
```

## Planned CLI surface

```console
fixcard find [query]   # search shared and private cards in the current repo
fixcard show <id>      # render one complete card and its provenance
fixcard new [--team]   # create a private card, or explicitly create a team card
fixcard lint [path]    # validate format, safety, secrets, and staleness
```

The public format is being specified in
[`spec/fixcard-v1.md`](spec/fixcard-v1.md). Architecture and security decisions
live in [`ARCHITECTURE.md`](ARCHITECTURE.md) and
[`docs/threat-model.md`](docs/threat-model.md).

## Product boundaries

- local and offline by default;
- private cards by default, stored in Git's common directory;
- shared cards are ordinary `.fixcards/*.md` files;
- deterministic, explainable ranking; precision before recall;
- commands are always inert text;
- no telemetry, accounts, cloud service, AI, or automatic capture;
- no claim that a prior fix is a guarantee.

## Project status

The implementation is being built in auditable milestones. The key unresolved
product risk cannot be eliminated by code: after solving an expensive failure,
will developers spend about 20 seconds preserving the resolution? The project
will keep the validation and kill criteria in the original research visible
rather than presenting adoption as proven.

## License

The implementation and specification are licensed under Apache-2.0. Fixcards
created in another repository remain subject to that repository's licensing and
contribution rules.

