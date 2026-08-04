# Contributing

Thank you for helping preserve trustworthy troubleshooting knowledge without
turning Fixcard into a general assistant.

## Before proposing work

- Search existing issues and the public roadmap.
- For behavior changes, describe a real repository workflow and why existing
  focused tools or documentation do not solve it.
- Discuss format changes before implementation. They require examples,
  migration behavior, and an ADR.
- Keep the explicit non-goals in the README and design principles intact.

## Development

Install the pinned Rust toolchain, then run:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

Behavior changes require tests. Matching claims require sanitized fixtures and
a stated methodology. Never commit a real secret, internal log, customer name,
or proprietary failure to the fixture corpus.

Validation evidence follows the [research operations guide](docs/research-operations.md).
Do not commit completed participant worksheets or alias keys. Submit only the
public aggregate report, methodology, denominators, missing data, and the
corresponding update to [validation results](docs/validation-results.md).

## Contribution accountability

Contributors must be able to explain and maintain submitted changes. Assisted
or generated code is welcome only after the contributor has reviewed it,
understands it, verifies it, and follows any disclosure requested by maintainers.
The standard is accountability, not how the first draft was produced.

By contributing, you agree that your contribution is licensed under
Apache-2.0 and that you have the right to submit it.
