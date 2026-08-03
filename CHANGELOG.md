# Changelog

All notable changes are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and will use semantic
versioning after the first stable format release.

## [Unreleased]

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

[Unreleased]: https://github.com/MarinJursic/fixcard/commits/main
[0.1.0-alpha.1]: https://github.com/MarinJursic/fixcard/compare/7685c83...v0.1.0-alpha.1
