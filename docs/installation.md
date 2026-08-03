# Installation and verification

Production-v1 builds are currently distributed as release-candidate archives
while the public validation gates are completed.

## Download a release archive

Choose the archive for the target:

| System | Target |
| --- | --- |
| Linux x86-64, portable static build | `x86_64-unknown-linux-musl` |
| Linux x86-64, glibc | `x86_64-unknown-linux-gnu` |
| Linux ARM64, glibc | `aarch64-unknown-linux-gnu` |
| macOS Intel | `x86_64-apple-darwin` |
| macOS Apple silicon | `aarch64-apple-darwin` |
| Windows x86-64 | `x86_64-pc-windows-msvc` |

The [releases page](https://github.com/MarinJursic/fixcard/releases) contains the
archives, `SHA256SUMS`, a CycloneDX SBOM, and GitHub build attestations.

With the GitHub CLI, download the archive and verification files for a chosen
version:

```bash
version=1.0.0-rc.1
target=aarch64-apple-darwin
gh release download "v${version}" \
  --repo MarinJursic/fixcard \
  --pattern "fixcard-${version}-${target}.tar.gz" \
  --pattern SHA256SUMS \
  --pattern fixcard.cdx.json
```

Verify the selected archive against the published checksum:

```bash
archive="fixcard-${version}-${target}.tar.gz"
grep "  ${archive}$" SHA256SUMS | shasum -a 256 -c -
```

Verify the GitHub-issued build attestation too:

```bash
gh attestation verify "$archive" --repo MarinJursic/fixcard
```

An attestation identifies the GitHub Actions workflow and source revision that
produced an artifact. It is not a behavioral security review.

Extract the archive, move `fixcard` (or `fixcard.exe`) to a directory on `PATH`,
then check it:

```bash
fixcard --version
fixcard --help
```

## Install from source

Install Rust 1.85 or newer, then pin the release tag:

```bash
cargo install --git https://github.com/MarinJursic/fixcard \
  --tag v1.0.0-rc.1 --locked fixcard
fixcard --version
```

`--locked` uses dependency versions committed by the project. Change the tag
explicitly and add `--force` when upgrading.

To build a checkout:

```bash
git clone https://github.com/MarinJursic/fixcard.git
cd fixcard
cargo build --release --locked
./target/release/fixcard --version
```

The pinned toolchain in `rust-toolchain.toml` is selected automatically.

## Runtime requirements

- no account, daemon, database, network connection, API key, or model;
- Git on `PATH` for repository and clone-private cards;
- no Git requirement for user-global lookup and authoring outside a repository.

`fixcard run --` directly spawns the requested program. On Windows it refuses
`.bat` and `.cmd` programs because those formats require shell interpretation.

## Data directories

- Linux: `${XDG_DATA_HOME:-$HOME/.local/share}/fixcard/cards`;
- macOS: `$HOME/Library/Application Support/fixcard/cards`;
- Windows: `%LOCALAPPDATA%\fixcard\cards`;
- override: `$FIXCARD_DATA_DIR/cards`, where the override must be absolute.

Clone-private cards remain under `<git-common-dir>/fixcard/cards`; repository
cards remain under `.fixcards/`.

## Uninstall

For a Cargo installation:

```bash
cargo uninstall fixcard
```

For an archive installation, remove the installed binary. Uninstalling never
deletes cards. Inspect and remove each storage directory separately if desired.
