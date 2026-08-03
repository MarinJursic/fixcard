# Release guide

Releases are tag-driven and must originate from a reviewed commit on `main`.

## Prepare

1. Choose a semantic version. Alpha versions use `X.Y.Z-alpha.N`.
2. Update the workspace version and exact internal dependency versions.
3. Move relevant changelog entries from `Unreleased` to the version and date.
4. Run the complete local checks from [Development](development.md).
5. Merge the release-preparation pull request and confirm required CI.

## Tag

Create an annotated tag whose version exactly matches Cargo metadata:

```bash
git switch main
git pull --ff-only
git tag -a vX.Y.Z-alpha.N -m "Fixcard vX.Y.Z-alpha.N"
git push origin vX.Y.Z-alpha.N
```

The release workflow builds five native archives:

- Linux x86_64 and arm64;
- macOS x86_64 and arm64;
- Windows x86_64.

It then generates SHA-256 checksums and a CycloneDX 1.5 SBOM, creates Sigstore-
backed GitHub provenance and SBOM attestations, and publishes a prerelease when
the version contains a prerelease suffix.

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
attestation verification output. Confirm that the release page has five
archives, `SHA256SUMS`, and `fixcard.cdx.json` before announcing it.

## Failure handling

Do not move or reuse a published tag. If the workflow fails before a GitHub
release exists, fix the workflow on `main`, bump the prerelease number, and tag
again. If assets were published incorrectly, document the problem and issue a
new patch/prerelease; do not silently replace provenance-bound artifacts.
