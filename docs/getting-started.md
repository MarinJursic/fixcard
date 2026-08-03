# Getting started

This walkthrough uses a disposable or existing Git repository. Fixcard refuses
to run outside a worktree because repository context is part of its safety
boundary.

## 1. Confirm the repository has no cards

```console
$ fixcard find "an error from this repository"
No Fixcards exist in this repository yet.
```

## 2. Solve a real failure deliberately

Fixcard does not diagnose the first occurrence. Debug normally, understand what
changed, and validate the outcome yourself. Preserve only the smallest durable
explanation after you know what worked.

## 3. Create a private card

```console
$ fixcard new
```

The interactive flow asks for a title, a stable error excerpt, an explanation,
the resolution, optional inert commands, and optional validation evidence. It
renders the complete file, runs lint, and asks before writing it.

Private is the default. The resulting file lives at:

```text
<git-common-dir>/fixcard/cards/<id>.md
```

Git's common directory means all linked worktrees of the same clone see the
private card, while another clone does not.

## 4. Find it again

Pass text as arguments:

```bash
fixcard find "ERR_EXAMPLE" "stable diagnostic fragment"
```

Or pipe/paste the original failure:

```bash
some-command 2>&1 | fixcard find
```

Fixcard reads only the supplied text. It does not intercept the shell command,
store the query, or make a network request.

Use `--explain` to audit scoring and `--all` to inspect weak candidates:

```bash
fixcard find --explain --all "ERR_EXAMPLE"
```

## 5. Inspect before acting

```bash
fixcard show <card-id>
```

Compare the recorded platform, tool versions, negative conditions, date, risk,
and provenance with the current situation. Commands are text for review and
copying; Fixcard never runs them.

## 6. Share only when justified

Create a shared card explicitly:

```bash
fixcard new --team
```

Or manually generalize a private card into `.fixcards/<id>.md`. Remove local
paths, internal identifiers, credentials, and details that are not stable. Then:

```bash
fixcard lint .fixcards
git add .fixcards/<id>.md
git commit
```

The card should receive the same review as a script or operational document.
See [Team workflow](team-workflow.md).
