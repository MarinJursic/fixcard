//! Repeatable performance gate for the documented 1,000-card search target.

#![allow(
    clippy::panic,
    reason = "a benchmark gate must fail when the documented target regresses"
)]

use std::hint::black_box;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use fixcard_core::{CardOrigin, Environment, LoadedCard, SearchOptions, parse_card, search};

fn main() {
    let cards = corpus();
    let query = "E_PACKAGE_0731 dependency resolver failed for package-0731.toml";
    for _ in 0..5 {
        black_box(search(
            black_box(query),
            black_box(&cards),
            &Environment::default(),
            &SearchOptions::default(),
        ));
    }

    let mut samples = Vec::with_capacity(30);
    for _ in 0..30 {
        let started = Instant::now();
        let results = search(
            black_box(query),
            black_box(&cards),
            &Environment::default(),
            &SearchOptions::default(),
        );
        black_box(results);
        samples.push(started.elapsed());
    }
    samples.sort_unstable();
    let median = samples[samples.len() / 2];
    let p95 = samples[samples.len() * 95 / 100];
    println!("search_1000 median={median:?} p95={p95:?}");
    assert!(
        p95 < Duration::from_millis(100),
        "1,000-card p95 search {p95:?} exceeded the 100 ms target"
    );
}

fn corpus() -> Vec<LoadedCard> {
    (0..1_000)
        .map(|index| {
            let id = format!("package-{index:04}");
            let source = format!(
                "---\nfixcard: 1\nid: {id}\ntitle: Repair dependency package {index:04}\nmatch:\n  exact: [E_PACKAGE_{index:04}]\n  contains: [package-{index:04}.toml, dependency resolver]\nrisk: low\nlast_verified: 2026-08-01\n---\n## What worked here\n\nRegenerate package-{index:04}.toml with the repository-pinned resolver and review the diff.\n"
            );
            let document = parse_card(&source)
                .unwrap_or_else(|error| unreachable!("benchmark fixture must parse: {error}"));
            LoadedCard {
                document,
                path: PathBuf::from(format!("{id}.md")),
                origin: CardOrigin::Shared,
            }
        })
        .collect()
}
