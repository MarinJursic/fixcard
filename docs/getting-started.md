# Getting started

Fixcard can recall repository, clone-private, and user-global knowledge. It also
works outside Git when user-global cards are available.

## 1. Paste a failure safely

After a command has already failed, run only `fix`:

```console
$ fix
Paste failure text, then press Enter, then Ctrl-D. It is used once and not saved.
ERR_EXAMPLE stable diagnostic fragment
```

On Windows, press Enter, Ctrl-Z, then Enter. Enter commits any unterminated
pasted line before the EOF key, so the documented sequence always completes.
Input is bounded to 1 MiB, used for one local lookup, and not persisted.

A standalone process cannot portably recover earlier terminal output. Fixcard
therefore asks for an explicit paste instead of inspecting clipboard contents,
terminal scrollback, shell history, or arbitrary logs, and it never silently
reruns the previous command.

## 2. Capture an anticipated command safely

The shortest reliable workflow is to let the installed `fix` companion observe
an explicit command:

```console
$ fix pnpm install --frozen-lockfile
```

The companion delegates directly to `fixcard run --` and executes exactly the
program and argv supplied to it, without a shell. It streams both output
channels, keeps only a bounded in-memory tail, and searches after a nonzero
exit. The command's exit code remains the process exit code even when a card
matches.

This mode uses pipes rather than a pseudo-terminal. A program may disable color
or interactive prompts. Run TTY-dependent commands normally and pass their
failure text to `fixcard fix` afterward.

It also accepts existing output and needs no shell activation:

```bash
journalctl -u example --no-pager | fix
```

With piped input and no arguments it performs the same local lookup without an
interactive prompt. The compatibility shell function is documented in the
[installation guide](installation.md#shell-completion-and-compatibility).

## 3. Look up text you already have

Pass stable error fragments as arguments:

```bash
fixcard fix ERR_EXAMPLE "stable diagnostic fragment"
```

Or pipe existing output:

```bash
journalctl -u example --no-pager | fixcard fix
```

Avoid `some-command 2>&1 | fixcard fix` as a command wrapper: an ordinary shell
pipeline can report Fixcard's status instead of the failing command's status.
Use `fixcard run -- some-command` for that case.

## 4. Read the result before acting

A strong result includes the complete resolution in the same invocation. It
also shows the origin, declared risk, applicability, evidence date, and recorded
validation. Commands in cards are inert text.

To inspect a card by ID later:

```bash
fixcard show <card-id>
```

If the same ID exists in multiple scopes, qualify it:

```bash
fixcard show repo:<card-id>
fixcard show private:<card-id>
fixcard show global:<card-id>
```

Use `--explain` to audit deterministic score contributions and `--all` to see
weak candidates:

```bash
fixcard fix --explain --all ERR_EXAMPLE
```

## 5. Save a fix you proved

After deliberately solving and validating a real failure:

```console
$ fixcard save
Short title: Rebuild the generated client
Stable excerpt from the failure: ERR_GENERATED_CLIENT_STALE
What worked here: Run the pinned generator and review the generated diff.
```

The default is clone-private storage:

```text
<git-common-dir>/fixcard/cards/<id>.md
```

All linked worktrees of that clone see it, while another clone does not.

For a personal fix useful across repositories:

```bash
fixcard save --global
```

For repository-owned knowledge that teammates should review with code:

```bash
fixcard save --team
fixcard lint .fixcards
git add .fixcards/<id>.md
git commit
```

Global scope is not a substitute for team scope. Use it for truly portable
personal knowledge; use `.fixcards/` when repository conditions matter.

## 6. Understand provenance labels

- `repository-committed` means the exact parsed file bytes match the blob at
  `HEAD`; it does not claim human review, a trusted author, or a trusted remote.
- `repository-working-copy` means the repository file is new or differs from
  `HEAD`.
- `private` and `user-global` describe storage scope, not authorization.

No label makes commands safe to execute automatically. Read
[Security and privacy](security-and-privacy.md) for the complete contract.
