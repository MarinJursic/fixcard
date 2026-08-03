# Governance

Fixcard currently uses a maintainer-led governance model. Marin Jursic is the
initial maintainer and release steward. This is a starting point, not a claim of
permanent ownership over the format.

## Decision process

- Routine fixes follow normal pull-request review.
- User-visible behavior needs tests and a real workflow explanation.
- Format and trust-model changes require an ADR, examples, compatibility and
  migration behavior, and public discussion before merge.
- Security incidents may be fixed privately before coordinated disclosure.
- Maintainers may reject scope expansion even when technically sound.

The strongest considerations are user safety, rank-one precision, offline
operation, format durability, and minimal interaction cost. Decisions and
dissent should be documented, not hidden in private chat.

## Becoming a maintainer

Sustained contributors may be invited after demonstrating sound technical
judgment, respectful review, security awareness, and commitment to the narrow
product boundaries. Maintainer access is least-privilege and may be removed for
inactivity or violations after a documented review.

## Releases

Stable releases require green protected-branch checks, an updated changelog,
reviewed dependency changes, reproducible release notes, checksums, an SBOM,
and provenance attestations. No single workflow may both accept untrusted pull-
request code and publish a release.

