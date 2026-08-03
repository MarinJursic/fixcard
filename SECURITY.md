# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability or accidental
secret exposure. Use GitHub's private vulnerability reporting for this
repository. Include the affected version, reproduction, impact, and any known
mitigation. You should receive an acknowledgement within three working days.

Do not include real credentials in a report. Revoke any exposed credential at
its provider before reporting the scanner miss.

## Supported versions

Until the first stable release, only the latest tagged pre-release and current
`main` receive security fixes. A stable support table will be published with
version 1.0.

## Security posture

Fixcard treats repository cards and pasted logs as untrusted. It never executes
card commands and makes no runtime network requests. Secret detection is defense
in depth and cannot certify that text is safe to publish. See
[`docs/threat-model.md`](docs/threat-model.md) for the complete model.

