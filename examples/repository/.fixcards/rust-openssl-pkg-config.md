---
fixcard: 1
id: rust-openssl-pkg-config
title: Point the build at the repository's documented OpenSSL toolchain
match:
  exact: [Could not find directory of OpenSSL installation]
  contains: [openssl-sys, pkg-config]
  not_contains: [feature vendored]
applies:
  os: [linux]
  arch: [x86_64, arm64]
  tools:
    rust: ">=1.85"
risk: medium
verified:
  command: cargo check --locked
  exit_code: 0
last_verified: 2026-08-03
authors: [Fixcard synthetic example]
---

## Why this happens

The native dependency discovery path does not match the OpenSSL setup documented
for this teaching repository.

## Do not apply when

The crate intentionally enables a vendored TLS backend or the target is not a
Linux host build.

## What worked here

Install or select the development package described by the repository's setup
guide, confirm that `pkg-config` resolves it, then rebuild without changing the
application's TLS policy.

## Commands to review

```bash
pkg-config --modversion openssl
cargo check --locked
```

## Notes

This example deliberately avoids a distro-specific privileged install command.
