//! End-to-end tests for repository discovery, input modes, lookup, and display.

#![allow(
    clippy::expect_used,
    clippy::panic,
    clippy::unwrap_used,
    reason = "integration-test setup should fail immediately with context"
)]

use std::fs;
use std::process::Command;

use assert_cmd::cargo::cargo_bin_cmd;
use predicates::prelude::*;
use tempfile::TempDir;

const CARD: &str = r"---
fixcard: 1
id: known-build
title: Rebuild the generated client
match:
  exact: [E_GENERATED_STALE]
  contains: [generated-client]
risk: low
verified:
  command: cargo test
  exit_code: 0
last_verified: 2026-08-03
---
## What worked here

Run the repository generator and review its diff.
";

fn repository() -> TempDir {
    let temp = TempDir::new().expect("create temp repository");
    let status = Command::new("git")
        .args(["init", "-q"])
        .current_dir(temp.path())
        .status()
        .expect("run git init");
    assert!(status.success());
    let cards = temp.path().join(".fixcards");
    fs::create_dir(&cards).expect("create card directory");
    fs::write(cards.join("known-build.md"), CARD).expect("write card");
    temp
}

#[test]
fn finds_a_strong_direct_query() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["find", "E_GENERATED_STALE", "generated-client"])
        .assert()
        .success()
        .stdout(predicate::str::contains("1 strong repository match"))
        .stdout(predicate::str::contains("known-build"));
}

#[test]
fn reads_failure_from_standard_input() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .arg("find")
        .write_stdin("E_GENERATED_STALE in generated-client")
        .assert()
        .success()
        .stdout(predicate::str::contains("Rebuild the generated client"));
}

#[test]
fn shows_the_evidence_notice() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["show", "known-build"])
        .assert()
        .success()
        .stdout(predicate::str::contains("command: cargo test"))
        .stdout(predicate::str::contains(
            "evidence of a previous resolution, not a guarantee",
        ));
}

#[test]
fn fails_clearly_outside_a_repository() {
    let directory = TempDir::new().expect("create non-repository directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .args(["find", "failure"])
        .assert()
        .code(2)
        .stderr(predicate::str::contains(
            "Fixcard must run inside a Git worktree",
        ));
}
