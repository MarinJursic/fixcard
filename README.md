# Fixcard

[![CI](https://github.com/MarinJursic/fixcard/actions/workflows/ci.yml/badge.svg)](https://github.com/MarinJursic/fixcard/actions/workflows/ci.yml)
[![Security](https://github.com/MarinJursic/fixcard/actions/workflows/security.yml/badge.svg)](https://github.com/MarinJursic/fixcard/actions/workflows/security.yml)
[![MSRV: 1.85](https://img.shields.io/badge/MSRV-1.85-DEA584.svg)](https://www.rust-lang.org/)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**A command failed? Type `fix`, paste the failure, and get the complete fix
your team already proved.**

Fixcard is a local command-line tool and open Markdown format for recurring
development failures. It matches literal evidence, shows the whole recorded
resolution immediately, and keeps applicability, risk, validation, and source
provenance beside it.

It never generates advice, uploads logs, runs a daemon, or executes text from a
card. A match is a suggested resolution, not an automatic fix.

> [!IMPORTANT]
> The production-v1 implementation is being validated as a release candidate.
> Engineering checks are automated, but the published real-user validation
> gates are not complete. See [Validation](docs/validation.md).

## The shortest path

After an ordinary command fails, type only `fix` and paste the failure:

```console
$ fix
Paste failure text, press Enter, type `END-7K4M2P9QX6R3A`, then press Enter. Input is hidden, used once, and not saved.
```

Paste the failure, press Enter, then type the displayed completion token on its
own line and press Enter. The random token changes on every invocation and the
same flow works on Windows. Fixcard reads in raw terminal mode, so pasted
control characters cannot end input and reach the shell. Input is hidden,
bounded to 1 MiB, searched locally, and not persisted; oversized text is
discarded until the token arrives. A standalone process cannot
portably recover output printed before it started, so this explicit paste is
the shortest honest after-the-fact workflow: no scrollback, clipboard, or
history scraping and no silent rerun.

When a failure is anticipated, let `fix` observe the command directly:

```console
$ fix pnpm install --frozen-lockfile
...the command's normal output...
ERR_PNPM_OUTDATED_LOCKFILE

1 strong Fixcard match
Matched: exact anchor `ERR_PNPM_OUTDATED_LOCKFILE`

Regenerate the lockfile with the pinned pnpm version

Card: pnpm-outdated-lockfile
Trust
  origin: repository-committed
  risk: low risk

## What worked here

Use the repository's pinned pnpm version, regenerate the lockfile, and review
the diff.

This is evidence of a previous resolution, not a guarantee. Review commands
before running them.
```

This delegates to `fixcard run --`, which executes only the supplied program
and argv without a shell. It streams the child's stdout and stderr, retains a
bounded in-memory tail, performs lookup after a failure, and returns the
child's original exit code. Fixcard's result is written to stderr so the
child's stdout stays pipeline-safe. Captured output is not persisted.

Already have the error? One invocation is enough:

```console
fixcard fix ERR_PNPM_OUTDATED_LOCKFILE frozen-lockfile
journalctl -u my-service --no-pager | fixcard fix
```

Supported installs include the literal `fix` companion command:

```bash
fix
fix pnpm install --frozen-lockfile
journalctl -u my-service --no-pager | fix
```

Bare `fix` prompts for the one-shot paste. With arguments, it runs the command
you provide and looks up a known resolution if that command fails. With piped
input and no arguments, it uses Fixcard's direct lookup flow. It locates the
sibling `fixcard` executable and directly preserves argv, standard streams,
and the child exit status without invoking a shell. It does not execute card
text or pretend it can recover an earlier failure. No shell profile or
current-session activation is required. The compatibility `shell-init`
function remains documented in the
[installation guide](docs/installation.md#shell-completion-and-compatibility).

## Save what worked

The default interactive flow asks only for a title, stable failure excerpt, and
resolution, then shows a preview:

```console
fixcard save                       # private to this clone
fixcard save --team                # .fixcards/, for repository review
fixcard save --global              # reusable in all repositories for this user
```

`fixcard new` remains an alias-compatible authoring command. Optional flags add
negative conditions, tool ranges, explanation, validation evidence, or inert
commands for humans to review.

## Card scopes and precedence

| Scope | Storage | Displayed origin |
| --- | --- | --- |
| Repository | `<worktree>/.fixcards/*.md` | `repository-committed` only when the parsed bytes exactly match `HEAD`; otherwise `repository-working-copy` |
| Clone-private | `<git-common-dir>/fixcard/cards/*.md` | `private` |
| User-global | OS application-data directory | `user-global` |

Repository cards win deterministic tie-breaks over private and global cards.
Duplicate IDs across scopes remain independent; address them as `repo:id`,
`private:id`, or `global:id` with `fixcard show`.

User-global cards are local files, not a public registry. They work outside Git
repositories. On Linux Fixcard follows the XDG data-directory convention; on
macOS it uses Application Support; on Windows it uses Local AppData. Set the
absolute `FIXCARD_DATA_DIR` path to override the base directory.

## Install

On macOS or Linux, install the checksum-pinned release binary from the
[Fixcard Homebrew formula](https://github.com/MarinJursic/homebrew-tap/blob/main/Formula/fixcard.rb):

```bash
brew install MarinJursic/tap/fixcard
```

Release archives contain the `fixcard` and `fix` binaries, license, changelog,
and README for:

- Linux x86-64 glibc and static musl;
- Linux ARM64 glibc;
- macOS Intel and Apple silicon;
- Windows x86-64 MSVC.

Each GitHub release includes SHA-256 checksums, a CycloneDX SBOM, and GitHub
artifact attestations. See [Installation and verification](docs/installation.md)
for exact download and verification steps. A source install requires Rust 1.85
or newer:

```bash
cargo install --git https://github.com/MarinJursic/fixcard \
  --tag v1.0.0-rc.5 --locked fixcard
```

## Commands

| Command | Purpose |
| --- | --- |
| `fix` / `fix PROGRAM [ARGS...]` / `output \| fix` | Paste a failure, explicitly capture one command, or look up piped output. |
| `fixcard` / `fixcard fix [text]` | Show the complete strongest known resolution; reads piped stdin when text is omitted. Use `--paste` for terminal input. |
| `fixcard run -- PROGRAM [ARGS...]` | Run explicit argv, stream output, and look up a card after failure while preserving status. |
| `fixcard save [--team\|--global]` | Record a resolution with a minimal reviewed preview. |
| `fixcard show [scope:]id` | Display one complete inert card and available provenance. |
| `fixcard list` | List available cards using stable scoped references. |
| `fixcard status` | Show storage paths, repository detection, and card counts. |
| `fixcard shell-init [shell]` | Print a compatibility `fix` function when a shell function is specifically preferred. |
| `fixcard completion <shell>` | Generate shell completion definitions. |
| `fixcard lint [path]` | Strictly validate schema, anchors, versions, secrets, risk, lifecycle, and staleness. |
| `fixcard find [text]` | Compatibility name for direct lookup. |
| `fixcard new [...]` | Compatibility name for authoring. |

Lookup quarantines malformed cards with bounded diagnostics so one bad file
cannot hide valid knowledge. `lint` remains strict and fails on bad input.

## Safety contract

- Card content, code fences, recorded validation commands, and extension fields
  are always inert text.
- Matching is local, deterministic, bounded, and explainable with `--explain`.
- A negative condition or clear tool-version mismatch prevents a strong result.
- Weak candidates are hidden unless `--all` is requested.
- Terminal controls are neutralized and secret-like output is redacted before
  display; redaction is defense in depth, not a promise that a log is harmless.
- Card files, directory entries, aggregate bytes, anchors, YAML extensions, and
  diagnostics have explicit resource limits.
- Symlinked card directories and card files are not followed. Private Unix
  directories are mode `0700` and files are mode `0600`.
- `run --` is deliberately non-PTY capture. Programs may disable color or
  prompts when stdout/stderr are pipes; invoke them directly when a TTY is
  required.
- Interactive paste is bounded to 1 MiB, held only for the lookup, and never
  reads the clipboard, scrollback, history, or arbitrary logs.

Read [Security and privacy](docs/security-and-privacy.md) and the formal
[Threat model](docs/threat-model.md) before using cards from an untrusted
checkout.

## Open format, open project

Fixcards are ordinary Markdown with YAML front matter. They remain readable in
code review and useful without this binary. The implementation and format are
Apache-2.0 licensed; cards in another repository remain subject to that
repository's license and contribution rules.

- [Getting started](docs/getting-started.md)
- [Card authoring](docs/card-authoring.md)
- [Matching and confidence](docs/matching.md)
- [Pre-pilot research protocol](docs/research-study.md)
- [Research operations guide and templates](docs/research-operations.md)
- [Release-candidate dogfood program](docs/dogfood.md)
- [Current validation results](docs/validation-results.md)
- [Examples](docs/examples.md)
- [Architecture](ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)

Fixcard is intentionally a small, supportable tool: no cloud service, telemetry,
public corpus, shell hook, PTY emulator, AI dependency, or automatic action
runner. Repeated use of one card is a signal to remove the underlying failure.
