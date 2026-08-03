---
fixcard: 1
id: docker-postgres-port
title: Stop the stale development database before reusing its host port
match:
  exact: [Bind for 0.0.0.0:5432 failed]
  contains: [port is already allocated]
  not_contains: [address family not supported]
applies:
  os: [linux, macos, windows]
  arch: []
  tools:
    docker: ">=24"
risk: medium
verified:
  command: docker compose ps
  exit_code: 0
last_verified: 2026-08-03
authors: [Fixcard synthetic example]
---

## Why this happens

An older development compose project still owns the host port expected by this
teaching repository.

## Do not apply when

The port belongs to a shared, non-development, or otherwise unrecognized service.

## What worked here

Identify the owning container, verify that it is the stale local development
instance, stop that project deliberately, and then start this repository's
services.

## Commands to review

```bash
docker ps --filter publish=5432
docker compose ps
```

## Notes

Do not stop a container based only on its port number.
