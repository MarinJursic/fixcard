# Development guide

## Prerequisites

- Git;
- the Rust toolchain selected by `rust-toolchain.toml`;
- Rust 1.85 when specifically checking the minimum supported version.

## Fast local loop

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo run -p fixcard -- --help
```

Before a pull request, also run:

```bash
cargo +1.85.0 check --workspace --all-targets
cargo audit --deny warnings
cargo deny --all-features check
cargo bench -p fixcard-core --bench search_1000
```

CI performs these checks across Linux, macOS, Windows, the declared MSRV,
coverage, documentation, release mode, dependency policy, and the performance
gate.

## Workspace

- `fixcard-core`: format, parsing, normalization, and ranking;
- `fixcard-git`: repository discovery, storage, and provenance;
- `fixcard-lint`: non-mutating safety and quality diagnostics;
- `fixcard-cli`: input/output and reviewed creation;
- `fixtures`: sanitized test cases;
- `examples`: synthetic user-facing cards;
- `spec`: open format contract.

Keep the dependency direction described in [Architecture](../ARCHITECTURE.md).
Matching behavior needs fixtures that include both the intended result and a
plausible false positive. Never commit real secrets, proprietary logs, customer
identifiers, or internal hostnames.

## Release discipline

Version changes update workspace metadata and `CHANGELOG.md`. A release tag is
built by GitHub Actions into native archives, checksums, a CycloneDX SBOM, and
artifact attestations. Verify the generated release from a fresh download
before marking it stable.
