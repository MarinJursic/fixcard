# Research and positioning

Fixcard emerged from a narrower question than “what developer assistant should
exist?”: what small, repeated cost remains after code generation, search, shell
history, and general documentation are already available?

## Problem framing

Development work includes diagnosis, review, environment repair, dependency
maintenance, CI interpretation, and reconstructing decisions—not only writing
code. More generated change increases the value of trustworthy repository
context and reviewable evidence. The opportunity is therefore not another
source of plausible fixes; it is preserving a fix that a person already proved
and retrieving it at recurrence.

The central behavioral risk is capture friction. A technically excellent index
has no value if a developer will not preserve the result after the incident.
That is why the product has a small command surface, no new service destination, and a
published [kill-criteria-based validation plan](validation.md).

## Adjacent tools and boundaries

| Category | Better choice when… | Fixcard's narrower role |
| --- | --- | --- |
| [Atuin](https://atuin.sh/) and shell history | you need to search commands you typed | preserves cause, conditions, review, and repository provenance after a fix |
| [navi](https://github.com/denisidoro/navi) and cheatsheets | you need an interactive command reference | starts from failure evidence, not a command topic |
| [tldr](https://tldr.sh/) and man pages | you need general tool usage | records a repository-specific resolution |
| README/runbook/wiki | you know the topic or procedure to browse | recognizes pasted failure text at the moment of recurrence |
| search, chat, or coding agents | the failure is new and needs investigation | does not generate; retrieves only prior evidence |

Fixcard borrows the good properties of plain files, local-first tools, and
reviewable knowledge. Its honest novelty claim is the combination of a Git
repository boundary, failure-fingerprint lookup, conditions and hard negatives,
private-first capture, an optional personal global scope, visible trust state, and a deliberately non-executing
format—not the invention of searchable notes.

## Rejected scope

The research rejected shell-history scraping, silent command reruns, command
correction, general runbooks, public fix sharing, CI log warehousing, agent
memory, cloud sync, and automatic execution. Explicit `run --` capture and the
one-shot bare-`fix` paste were kept because they are bounded, local, and honest
about which output was supplied. Command capture also preserves the child
status; after-the-fact paste never pretends it recovered earlier output.

## Evidence discipline

Market and workflow observations motivate the hypothesis; they do not validate
this implementation. Product claims remain bounded by the measurable study in
[Validation](validation.md). Any future editor, shell, or CI integration must be
earned by observed usage of the core rather than used to manufacture adoption.
