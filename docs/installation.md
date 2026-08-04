# Installation and verification

Production-v1 builds are currently distributed as release-candidate archives
while the public validation gates are completed.

## Homebrew on macOS or Linux

Install the architecture-specific, checksum-pinned upstream binary:

```bash
brew install MarinJursic/tap/fixcard
fixcard --version
fix --version
```

The fully qualified formula name uses Homebrew's formula-scoped trust flow; it
does not require trusting every future item in the tap. The
[public formula](https://github.com/MarinJursic/homebrew-tap/blob/main/Formula/fixcard.rb)
is tested on Intel and ARM variants of macOS and Linux.

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
version=1.0.0-rc.5
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

Extract the archive, keep `fixcard` and `fix` together, and move both binaries
(`fixcard.exe` and `fix.exe` on Windows) to a directory on `PATH`. Then check
them:

```bash
fixcard --version
fix --version
fixcard --help
fix --help
```

## Install from source

Install Rust 1.85 or newer, then pin the release tag:

```bash
cargo install --git https://github.com/MarinJursic/fixcard \
  --tag v1.0.0-rc.5 --locked fixcard
fixcard --version
fix --version
```

`--locked` uses dependency versions committed by the project. Change the tag
explicitly and add `--force` when upgrading.

To build a checkout:

```bash
git clone https://github.com/MarinJursic/fixcard.git
cd fixcard
cargo build --release --locked
./target/release/fixcard --version
./target/release/fix --version
```

The pinned toolchain in `rust-toolchain.toml` is selected automatically.

## Runtime requirements

- no account, daemon, database, network connection, API key, or model;
- Git on `PATH` for repository and clone-private cards;
- no Git requirement for user-global lookup and authoring outside a repository.

`fixcard run --` directly spawns the requested program. On Windows it refuses
`.bat` and `.cmd` programs because those formats require shell interpretation.

## Shell completion and compatibility

Generate completion definitions without modifying shell configuration:

```bash
fixcard completion zsh
```

The installed `fix` companion already provides one-shot interactive paste,
explicit command capture, and piped lookup in every shell without profile
changes. No activation step is required. Bare `fix` explains how to finish the
paste by entering a line containing only `.`; the input is used once and not
saved. The same terminator works on Unix and Windows.

For compatibility with an older installation, or when a shell function is
specifically preferred, generate an equivalent function. In Bash or Zsh:

```bash
fixcard shell-init
eval "$(fixcard shell-init)"
```

With no argument, Fixcard infers Bash, Zsh, Fish, or PowerShell from the
`SHELL` environment variable. Pass the shell explicitly when detection is
unavailable or the login shell differs from the current shell.

Use the activation syntax for the current shell:

| Shell | Current-session activation |
| --- | --- |
| Bash | `eval "$(fixcard shell-init bash)"` |
| Zsh | `eval "$(fixcard shell-init zsh)"` |
| Fish | `fixcard shell-init fish \| source` |
| PowerShell | `$fixcardInit = & fixcard shell-init powershell; Invoke-Expression $fixcardInit` |

Fixcard never edits profile files. Inspect the generated output before
activation. A function shadows the installed companion for that session, so
opt in only when that is intentional. `power-shell` and `pwsh` remain accepted
as aliases for `powershell`.

## Data directories

- Linux: `${XDG_DATA_HOME:-$HOME/.local/share}/fixcard/cards`;
- macOS: `$HOME/Library/Application Support/fixcard/cards`;
- Windows: `%LOCALAPPDATA%\fixcard\cards`;
- override: `$FIXCARD_DATA_DIR/cards`, where the override must be absolute.

Clone-private cards remain under `<git-common-dir>/fixcard/cards`; repository
cards remain under `.fixcards/`.

## Uninstall

For a Homebrew installation:

```bash
brew uninstall fixcard
```

For a Cargo installation:

```bash
cargo uninstall fixcard
```

For an archive installation, remove the installed `fixcard` and `fix` binaries.
Uninstalling never deletes cards. Inspect and remove each storage directory
separately if desired.
