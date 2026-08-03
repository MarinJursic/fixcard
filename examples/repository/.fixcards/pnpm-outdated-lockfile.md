---
fixcard: 1
id: pnpm-outdated-lockfile
title: Regenerate the lockfile with the pinned pnpm version
match:
  exact: [ERR_PNPM_OUTDATED_LOCKFILE]
  contains: [frozen-lockfile, pnpm-lock.yaml]
  not_contains: [using npm]
applies:
  os: [linux, macos, windows]
  arch: []
  tools:
    node: ">=22 <23"
    pnpm: ">=10 <11"
risk: low
verified:
  command: pnpm install --frozen-lockfile
  exit_code: 0
last_verified: 2026-08-03
authors: [Fixcard synthetic example]
---

## Why this happens

The teaching repository expects a lockfile produced by its pinned pnpm major,
but the committed lockfile was generated with different dependency metadata.

## Do not apply when

The repository is managed by npm or Yarn, or the dependency change itself is
not understood.

## What worked here

Use the package-manager major pinned by the repository, regenerate the lockfile,
and review the dependency diff before committing it.

## Commands to review

```bash
corepack pnpm install
git diff -- pnpm-lock.yaml
pnpm install --frozen-lockfile
```

## Notes

This is synthetic validation evidence for format demonstration only.
