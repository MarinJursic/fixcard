# Support

Use [GitHub Discussions](https://github.com/MarinJursic/fixcard/discussions) for
sanitized usage questions and card-authoring help. Use the issue forms for
reproducible bugs or evidence-backed workflow proposals.

This community project has no guaranteed response time or commercial support.
Security reports belong in private vulnerability reporting as described in
[`SECURITY.md`](SECURITY.md).

## Supported platforms

Release artifacts and CI cover:

- Linux x86-64 (glibc 2.35+ or static musl) and ARM64 (glibc 2.39+);
- macOS 10.12+ on Intel and macOS 11+ on Apple silicon;
- Windows 10+ / Server x86-64 using MSVC;
- source builds with Rust 1.85 or newer.

Other Rust-supported targets may work but are community-supported until added
to the release matrix. `run --` uses pipe capture rather than PTY emulation;
TTY-dependent programs should be invoked directly. Windows batch programs are
not accepted by `run --`.

The project aims to keep the stable v1 card format readable indefinitely.
Deprecated CLI behavior will be documented for at least one minor release before
removal when security does not require an immediate change.

Never paste real credentials, internal hostnames, customer identifiers,
proprietary logs, or private repository content into a public question.
