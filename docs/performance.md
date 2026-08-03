# Performance methodology

Fixcard publishes two engineering targets from the original product brief:

- release-binary process startup p95 below 75 ms;
- deterministic search p95 below 100 ms for 1,000 parsed cards.

## Automated gates

`scripts/check_startup.py` starts a new optimized `fixcard --version` process 30
times, reports median and p95 wall time, and fails at 75 ms. This measures
process and CLI initialization under ordinary filesystem caching; it is not a
claim about a literal power-on disk cache.

`crates/fixcard-core/benches/search_1000.rs` builds a deterministic synthetic
corpus, warms five searches, measures 30 complete ranking calls, and fails at a
100 ms p95. It intentionally excludes file parsing so a regression in the
ranker is attributable. End-to-end lookup remains covered by CLI tests.

Both gates run in CI. The corpus and query are public, so the measurement is
repeatable and cannot contain proprietary failure data.

## Local reference measurement

On 2026-08-03, an Apple M2 Pro (arm64, macOS 14.6.1) release build measured:

| Measurement | Median | p95 |
| --- | ---: | ---: |
| `fixcard --version`, 100 fresh processes | 1.74 ms | 2.57 ms |
| full no-match lookup, 100 fresh processes | 18.17 ms | 18.99 ms |
| in-memory search across 1,000 cards, 30 samples | 16.98 ms | 17.25 ms |

These numbers describe one machine and are not universal performance claims.
CI enforces the budgets rather than the exact reference values. Real-world
relevance and human lookup time remain part of the separate
[validation plan](validation.md).
