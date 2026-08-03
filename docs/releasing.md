# Release guide

Releases are tag-driven and must originate from a reviewed commit on `main`.

## Prepare

1. Choose a semantic version. Release candidates use `X.Y.Z-rc.N`.
2. Update the workspace version and exact internal dependency versions.
3. Move relevant changelog entries from `Unreleased` to the version and date.
4. Run the complete local checks from [Development](development.md).
5. Merge the release-preparation pull request and confirm required CI.

## Tag

Create an annotated tag whose version exactly matches Cargo metadata:

```bash
git switch main
git pull --ff-only
git tag -a vX.Y.Z-rc.N -m "Fixcard vX.Y.Z-rc.N"
git push origin vX.Y.Z-rc.N
```

The release workflow builds six native archives in the protected `release`
environment:

- Linux x86_64 glibc, x86_64 static musl, and ARM64 glibc;
- macOS x86_64 and arm64;
- Windows x86_64.

It then generates SHA-256 checksums and a CycloneDX 1.5 SBOM, creates Sigstore-
backed GitHub provenance and SBOM attestations, and publishes a prerelease when
the version contains a prerelease suffix.

Every third-party action is pinned to a full commit SHA. The workflow extracts
and smoke-tests each final archive before upload. Stable and release-candidate
tags must be covered by the repository's tag-protection rules and are never
moved or reused.

Builds are not currently claimed to be bit-for-bit reproducible across runners:
native toolchains and archive timestamps can differ. Published checksums and
attestations identify the exact artifacts produced by the protected workflow.

## Verify independently

Download an archive from the published release on a machine that did not build
it, then:

```bash
shasum -a 256 -c SHA256SUMS
gh attestation verify <archive> --repo MarinJursic/fixcard
```

Extract the archive and exercise:

```bash
fixcard --version
fixcard --help
```

For an SBOM attestation, supply the CycloneDX predicate URI shown by GitHub's
attestation verification output. Confirm that the release page has six
archives, `SHA256SUMS`, and `fixcard.cdx.json` before announcing it.

## Failure handling

Do not move or reuse a published tag. If the workflow fails before a GitHub
release exists, fix the workflow on `main`, bump the prerelease number, and tag
again. If assets were published incorrectly, document the problem and issue a
new patch/prerelease; do not silently replace provenance-bound artifacts.
