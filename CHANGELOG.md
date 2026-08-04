# Changelog

All notable changes are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses semantic
versioning. The v1 format is stable; the CLI remains a release
candidate until the documented product-validation gates pass.

## [Unreleased]

## [1.0.0-rc.5] - 2026-08-04

### Interactive lookup changes

- Make bare `fix` a bounded one-shot paste flow so an ordinary failure can be
  looked up without anticipating it, supplying command syntax, activating a
  shell function, or granting clipboard, history, or scrollback access.
- Align generated Bash, Zsh, Fish, and PowerShell compatibility functions with
  the installed companion's interactive paste behavior.

### Safety changes

- Keep interactive failure text in memory only, enforce the existing 1 MiB
  query limit, and reject empty input. A raw terminal reader with a random,
  per-invocation completion token treats pasted control bytes as data and
  discards oversized input until the safe frame closes, preventing unread
  paste tails from reaching the caller's shell. Ctrl-C arms a separate random
  cancellation token, preserving a safe escape path while raw mode is active;
  catchable Unix termination signals restore terminal mode before re-raising,
  including signals received during raw-mode activation. Hidden or split
  prompt terminals are rejected before raw mode begins.

## [1.0.0-rc.4] - 2026-08-04

### Usability additions

- Install a real cross-platform `fix` companion beside `fixcard`, so explicit
  command capture, piped lookup, and interactive status work in every shell
  without per-session activation or profile edits.

### Distribution changes

- Package and smoke-test both executables in every native release archive.
- Keep `shell-init` as a compatibility function rather than the primary path to
  the literal command.

## [1.0.0-rc.3] - 2026-08-04

### Validation additions

- Coordinator-ready research operations guide, privacy-safe blank study
  templates, fixed denominators, full kill criteria, and CI schema validation.
- Milestone 0 evidence gate requiring at least 100 permissioned, sanitized real
  failure/resolution pairs before stable promotion.

### Usability changes

- `shell-init` now infers common shells when its argument is omitted and
  generates one `fix` function for explicit command capture, piped lookup, and
  interactive status.
- Interactive status now shows a two-command quick start and the detected
  current-session activation command.
- Unmatched lookups now suggest the appropriate private or user-global capture
  command after the failure is solved.

## [1.0.0-rc.2] - 2026-08-03

### Adoption additions

- Opt-in `shell-init` output for a literal `fix PROGRAM [ARGS...]` wrapper around
  the safe, explicit `fixcard run --` workflow.
- Native completion generation for Bash, Zsh, Fish, PowerShell, and Elvish.
- A privacy-preserving four-week dogfood protocol and structured, sanitized
  validation-report issue form.

### Adoption changes

- Expanded command-line integration tests to execute the generated Bash wrapper
  and prove that shell metacharacters remain literal arguments.
- Routed completion output through Fixcard's clean broken-pipe handling.

## [1.0.0-rc.1] - 2026-08-03

### Release candidate additions

- One-invocation `fix` output that includes the complete strongest resolution.
- Explicit `run -- PROGRAM [ARGS...]` capture with direct argv execution,
  bounded in-memory tails, streamed output, and child-status preservation.
- User-global cards in standard OS application-data directories, including use
  outside Git repositories.
- Minimal three-prompt `save` flow and scoped `show` references.
- Resilient lookup that quarantines malformed cards with bounded diagnostics.
- Resource limits for directories, aggregate source, anchors, YAML extension
  depth/nodes, lint input, captured output, and diagnostics.
- Linux x86-64 musl release artifact and post-extraction artifact smoke tests.

### Changed

- Renamed the unsupported `repo-reviewed` claim to byte-verified
  `repository-committed`; dirty or untracked cards are
  `repository-working-copy`.
- Stabilized the v1 format with explicit `x-` extension and permanently inert
  command semantics.
- Pinned every third-party GitHub Action to a full commit SHA.

### Release candidate security

- Reject symlinked card directories and restrict private Unix directory/file
  modes to `0700`/`0600`.
- Never persist captured command output and never execute card-derived text.
- Refuse Windows batch programs in `run --` because they require a shell.

## [0.1.0-alpha.2] - 2026-08-03

### Fixed

- Treat a downstream stdout consumer closing early as a clean exit instead of
  panicking with a broken-pipe error.

## [0.1.0-alpha.1] - 2026-08-03

### Added

- Open Fixcard v1 draft specification and modular Rust workspace.
- Deterministic repository-local `find` and provenance-aware `show`.
- Private-by-default and explicitly shared card creation with preview.
- Schema, secret, risk, staleness, lifecycle, and certainty-language linting.
- Worktree-safe Git common-directory storage and symlink defenses.
- Cross-platform, security, dependency-review, coverage, and performance CI.
- Complete installation, authoring, matching, team, privacy, validation,
  performance, development, and release documentation.
- Five-platform release automation with checksums, CycloneDX SBOM, and GitHub
  provenance/SBOM attestations.
- Optional repository policy for forbidden command classes.

### Security

- Private-by-default atomic storage and symlink/path defenses.
- Secret-like values are blocked from team saves and redacted from previews and
  display.
- YAML aliases/custom tags fail closed; terminal control bytes are neutralized.

[Unreleased]: https://github.com/MarinJursic/fixcard/compare/v1.0.0-rc.5...HEAD
[1.0.0-rc.5]: https://github.com/MarinJursic/fixcard/compare/v1.0.0-rc.4...v1.0.0-rc.5
[1.0.0-rc.4]: https://github.com/MarinJursic/fixcard/compare/v1.0.0-rc.3...v1.0.0-rc.4
[1.0.0-rc.3]: https://github.com/MarinJursic/fixcard/compare/v1.0.0-rc.2...v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/MarinJursic/fixcard/compare/v1.0.0-rc.1...v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/MarinJursic/fixcard/compare/v0.1.0-alpha.2...v1.0.0-rc.1
[0.1.0-alpha.2]: https://github.com/MarinJursic/fixcard/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/MarinJursic/fixcard/compare/7685c83...v0.1.0-alpha.1
