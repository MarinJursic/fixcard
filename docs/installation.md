# Installation and verification

Fixcard is currently an alpha. Install Rust 1.85 or newer, then choose one of
the following approaches.

## Install from Git

```bash
cargo install --git https://github.com/MarinJursic/fixcard --locked fixcard
fixcard --version
```

`--locked` uses the dependency versions committed by the project. Upgrade by
running the same command with `--force`.

To install a reproducible tag, add `--tag vX.Y.Z` after the repository URL.

## Build a checkout

```bash
git clone https://github.com/MarinJursic/fixcard.git
cd fixcard
cargo build --release --locked
./target/release/fixcard --version
```

The pinned toolchain is selected automatically by `rust-toolchain.toml`.

## Tagged binaries

Tagged prereleases attach native archives and a `SHA256SUMS` file to the GitHub
release. Check the digest before installing:

```bash
shasum -a 256 -c SHA256SUMS
```

On systems with the GitHub CLI, verify the GitHub-issued build attestation too:

```bash
gh attestation verify <archive> --repo MarinJursic/fixcard
```

An attestation proves which GitHub Actions workflow produced an artifact; it is
not a review of the artifact's behavior. Release assets also include a
CycloneDX software bill of materials (SBOM).

## Runtime requirements

- a Git executable available on `PATH`;
- a Git worktree (Fixcard deliberately does not search outside one);
- no account, daemon, database, network connection, or API key.

## Uninstall

```bash
cargo uninstall fixcard
```

Uninstalling the binary does not delete cards. Shared cards remain in
`.fixcards/`; private cards remain in `<git-common-dir>/fixcard/cards/` and can
be removed manually after inspection.
