---
fixcard: 1
id: pnpm-outdated-lockfile
title: Regenerate the lockfile with the repository-pinned pnpm version
match:
  exact:
    - ERR_PNPM_OUTDATED_LOCKFILE
  contains:
    - frozen-lockfile
    - pnpm-lock.yaml
  not_contains:
    - EACCES
applies:
  os: [macos, linux]
  arch: [arm64, x86_64]
  tools:
    node: ">=22 <23"
    pnpm: ">=10 <11"
risk: low
verified:
  command: pnpm install --frozen-lockfile
  exit_code: 0
  source_commit: 3d84c2a
last_verified: 2026-07-16
authors: ["@developer"]
---

## Why this happens

`package.json` changed while the lockfile was generated with an incompatible
package-manager version.

## What worked here

1. Confirm the package-manager version pinned by the repository.
2. Enable Corepack.
3. Run `pnpm install`.
4. Review and commit the lockfile diff.

## Commands to review

```bash
corepack enable
pnpm install
```

## Notes

Do not delete `pnpm-lock.yaml`; CI requires the committed lockfile.

