//! End-to-end tests for repository discovery, input modes, lookup, and display.

#![allow(
    clippy::expect_used,
    clippy::panic,
    clippy::unwrap_used,
    reason = "integration-test setup should fail immediately with context"
)]

use std::fs;
use std::path::Path;
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
    git(temp.path(), &["config", "user.name", "Fixcard Test"]);
    git(
        temp.path(),
        &["config", "user.email", "fixcard@example.invalid"],
    );
    let cards = temp.path().join(".fixcards");
    fs::create_dir(&cards).expect("create card directory");
    fs::write(cards.join("known-build.md"), CARD).expect("write card");
    temp
}

fn empty_repository() -> TempDir {
    let temp = TempDir::new().expect("create temp repository");
    git(temp.path(), &["init", "-q"]);
    git(temp.path(), &["config", "user.name", "Fixcard Test"]);
    git(
        temp.path(),
        &["config", "user.email", "fixcard@example.invalid"],
    );
    temp
}

fn git(directory: &Path, args: &[&str]) {
    let status = Command::new("git")
        .args(args)
        .current_dir(directory)
        .status()
        .expect("run Git");
    assert!(status.success(), "Git command failed: {args:?}");
}

fn creation_args() -> [&'static str; 15] {
    [
        "new",
        "--id",
        "generated-stale",
        "--title",
        "Rebuild the generated client",
        "--exact",
        "E_GENERATED_STALE",
        "--resolution",
        "Run the generator and review its diff.",
        "--validation-command",
        "cargo test",
        "--validation-exit",
        "0",
        "--yes",
        "--team",
    ]
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
fn redacts_secret_like_values_when_showing_an_existing_card() {
    let repository = repository();
    let secret = "ghp_1234567890abcdefghijklmnopqrst";
    let source = CARD.replace(
        "Run the repository generator and review its diff.",
        &format!("Remove the accidentally recorded token {secret}."),
    );
    fs::write(repository.path().join(".fixcards/known-build.md"), source)
        .expect("write card containing test-shaped secret");
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["show", "known-build"])
        .assert()
        .success()
        .stdout(predicate::str::contains(secret).not())
        .stdout(predicate::str::contains("[REDACTED]"));
}

#[test]
fn lint_reports_an_id_filename_mismatch() {
    let repository = repository();
    let original = repository.path().join(".fixcards/known-build.md");
    let renamed = repository.path().join(".fixcards/wrong-name.md");
    fs::rename(original, &renamed).expect("rename fixture card");
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["lint", renamed.to_str().expect("UTF-8 path")])
        .assert()
        .code(1)
        .stdout(predicate::str::contains("id-filename-mismatch"));
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

#[test]
fn creates_and_lints_a_team_card_non_interactively() {
    let repository = empty_repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(creation_args())
        .assert()
        .success()
        .stdout(predicate::str::contains("Saved team card"));

    let card = repository.path().join(".fixcards/generated-stale.md");
    let source = fs::read_to_string(&card).expect("read created team card");
    assert!(source.contains("last_verified:"));
    assert!(source.contains("authors:\n- Fixcard Test"));
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["lint", card.to_str().expect("UTF-8 path")])
        .assert()
        .success()
        .stdout(predicate::str::contains("0 error(s)"));
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["show", "generated-stale"])
        .assert()
        .success()
        .stdout(predicate::str::contains("recorded authors: Fixcard Test"));
}

#[test]
fn creation_records_negative_and_tool_applicability_conditions() {
    let repository = empty_repository();
    let mut args = creation_args().to_vec();
    args.extend([
        "--not-contains",
        "using npm",
        "--applies-tool",
        "node=>=22 <23",
        "--do-not-apply",
        "Do not use this when the repository is managed by npm.",
        "--no-platform",
        "--no-author",
    ]);
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(args)
        .assert()
        .success();

    let source = fs::read_to_string(repository.path().join(".fixcards/generated-stale.md"))
        .expect("read created team card");
    assert!(source.contains("not_contains:\n  - using npm"));
    assert!(source.contains("node: '>=22 <23'"));
    assert!(source.contains("os: []\n  arch: []"));
    assert!(source.contains("authors: []"));
    assert!(source.contains("## Do not apply when"));
}

#[test]
fn rejects_an_invalid_tool_range_before_saving() {
    let repository = empty_repository();
    let mut args = creation_args().to_vec();
    args.extend(["--applies-tool", "node=not-a-range"]);
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(args)
        .assert()
        .code(2)
        .stderr(predicate::str::contains("invalid semantic version range"));
    assert!(
        !repository
            .path()
            .join(".fixcards/generated-stale.md")
            .exists()
    );
}

#[test]
fn private_creation_uses_the_git_common_directory() {
    let repository = empty_repository();
    let mut args = creation_args().to_vec();
    args.retain(|argument| *argument != "--team");
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(args)
        .assert()
        .success()
        .stdout(predicate::str::contains("Saved private card"));
    assert!(
        repository
            .path()
            .join(".git/fixcard/cards/generated-stale.md")
            .is_file()
    );
    assert!(!repository.path().join(".fixcards").exists());
}

#[test]
fn refuses_to_overwrite_an_existing_card() {
    let repository = empty_repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(creation_args())
        .assert()
        .success();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(creation_args())
        .assert()
        .code(2)
        .stderr(predicate::str::contains("refusing to overwrite"));
}

#[test]
fn blocks_a_secret_from_a_team_card() {
    let repository = empty_repository();
    let mut args = creation_args().to_vec();
    args.extend([
        "--command",
        "export TOKEN=ghp_1234567890abcdefghijklmnopqrst",
    ]);
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(args)
        .assert()
        .code(2)
        .stdout(predicate::str::contains("ghp_1234567890abcdefghijklmnopqrst").not())
        .stderr(predicate::str::contains("blocking errors"));
    assert!(
        !repository
            .path()
            .join(".fixcards/generated-stale.md")
            .exists()
    );
}

#[test]
fn blocks_understated_dangerous_commands_but_allows_declared_high_risk() {
    let repository = empty_repository();
    let mut low_risk = creation_args().to_vec();
    low_risk.extend(["--command", "sudo rm -rf /var/example"]);
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(&low_risk)
        .assert()
        .code(2)
        .stderr(predicate::str::contains("blocking errors"));

    low_risk.extend(["--risk", "high"]);
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(low_risk)
        .assert()
        .success()
        .stdout(predicate::str::contains("high-risk-command"));
}

#[test]
fn repository_policy_blocks_a_denied_command_class() {
    let repository = empty_repository();
    fs::write(
        repository.path().join(".fixcard.toml"),
        "[lint]\ndeny-command-classes = [\"privileged-command\"]\n",
    )
    .expect("write policy");
    let mut args = creation_args().to_vec();
    args.extend(["--command", "sudo true", "--risk", "high"]);
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(args)
        .assert()
        .code(2)
        .stdout(predicate::str::contains("denied-command-class"))
        .stderr(predicate::str::contains("blocking errors"));
}

#[test]
fn private_cards_created_in_a_linked_worktree_use_the_common_git_directory() {
    let repository = empty_repository();
    fs::write(repository.path().join("README.md"), "worktree fixture").expect("write fixture");
    git(repository.path(), &["add", "README.md"]);
    git(repository.path(), &["commit", "-q", "-m", "fixture"]);
    let worktree = repository.path().join("linked-worktree");
    git(
        repository.path(),
        &[
            "worktree",
            "add",
            "-q",
            "-b",
            "test-worktree",
            worktree.to_str().expect("UTF-8 path"),
        ],
    );
    let mut args = creation_args().to_vec();
    args.retain(|argument| *argument != "--team");
    cargo_bin_cmd!("fixcard")
        .current_dir(&worktree)
        .args(args)
        .assert()
        .success();
    assert!(
        repository
            .path()
            .join(".git/fixcard/cards/generated-stale.md")
            .is_file()
    );
    assert!(!worktree.join(".git/fixcard").exists());
}

#[cfg(unix)]
#[test]
fn refuses_a_symlinked_team_card_directory() {
    use std::os::unix::fs::symlink;

    let repository = empty_repository();
    let outside = TempDir::new().expect("create outside directory");
    symlink(outside.path(), repository.path().join(".fixcards")).expect("create symlink");
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(creation_args())
        .assert()
        .code(2)
        .stderr(predicate::str::contains("refusing unsafe card storage"));
    assert!(!outside.path().join("generated-stale.md").exists());
}
