//! End-to-end tests for repository discovery, input modes, lookup, and display.

#![allow(
    clippy::expect_used,
    clippy::panic,
    clippy::unwrap_used,
    reason = "integration-test setup should fail immediately with context"
)]

use std::fs;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};

use assert_cmd::cargo::cargo_bin_cmd;
use assert_cmd::prelude::*;
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
        .stdout(predicate::str::contains("1 strong Fixcard match"))
        .stdout(predicate::str::contains("known-build"));
}

#[test]
fn fix_renders_the_complete_resolution_in_one_invocation() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["fix", "E_GENERATED_STALE", "generated-client"])
        .assert()
        .success()
        .stdout(predicate::str::contains("1 strong Fixcard match"))
        .stdout(predicate::str::contains(
            "Run the repository generator and review its diff.",
        ))
        .stdout(predicate::str::contains("Run: fixcard show").not());
}

#[test]
fn bare_fixcard_uses_the_one_step_fix_flow() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .write_stdin("E_GENERATED_STALE generated-client")
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "Run the repository generator and review its diff.",
        ));
}

#[test]
fn installed_fix_uses_the_one_step_piped_lookup_flow() {
    let repository = repository();
    cargo_bin_cmd!("fix")
        .current_dir(repository.path())
        .write_stdin("E_GENERATED_STALE generated-client")
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "Run the repository generator and review its diff.",
        ));
}

#[test]
fn installed_fix_has_its_own_help_and_version() {
    cargo_bin_cmd!("fix")
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("fix PROGRAM [ARGS...]"))
        .stdout(predicate::str::contains("never invokes a shell"));
    cargo_bin_cmd!("fix")
        .arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::starts_with("fix 1.0.0-rc."));
}

#[test]
fn installed_fix_fails_clearly_without_its_companion() {
    let directory = TempDir::new().expect("create isolated binary directory");
    let standalone = directory
        .path()
        .join(format!("fix{}", std::env::consts::EXE_SUFFIX));
    fs::copy(env!("CARGO_BIN_EXE_fix"), &standalone).expect("copy fix executable");
    Command::new(standalone)
        .assert()
        .code(2)
        .stderr(predicate::str::contains("companion"))
        .stderr(predicate::str::contains("reinstall Fixcard"));
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
fn lookup_quarantines_a_malformed_card_without_hiding_valid_cards() {
    let repository = repository();
    fs::write(
        repository.path().join(".fixcards/broken.md"),
        "not a Fixcard",
    )
    .expect("write malformed card");
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["fix", "E_GENERATED_STALE", "generated-client"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "Run the repository generator and review its diff.",
        ))
        .stderr(predicate::str::contains("warning: skipped"))
        .stderr(predicate::str::contains("broken.md"));
}

#[cfg(unix)]
#[test]
fn run_preserves_child_output_and_failure_status() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args([
            "run",
            "--",
            "sh",
            "-c",
            "printf child-output; printf 'E_GENERATED_STALE generated-client' >&2; exit 23",
        ])
        .assert()
        .code(23)
        .stdout(predicate::eq(b"child-output".as_slice()))
        .stderr(predicate::str::contains("1 strong Fixcard match"))
        .stderr(predicate::str::contains(
            "Run the repository generator and review its diff.",
        ));
}

#[cfg(unix)]
#[test]
fn installed_fix_preserves_child_output_and_failure_status() {
    let repository = repository();
    cargo_bin_cmd!("fix")
        .current_dir(repository.path())
        .args([
            "sh",
            "-c",
            "printf child-output; printf 'E_GENERATED_STALE generated-client' >&2; exit 23",
        ])
        .assert()
        .code(23)
        .stdout(predicate::eq(b"child-output".as_slice()))
        .stderr(predicate::str::contains("1 strong Fixcard match"))
        .stderr(predicate::str::contains(
            "Run the repository generator and review its diff.",
        ));
}

#[cfg(unix)]
#[test]
fn installed_fix_passes_shell_metacharacters_as_literal_arguments() {
    let repository = repository();
    cargo_bin_cmd!("fix")
        .current_dir(repository.path())
        .args(["printf", "%s", "$(not-run);*;$HOME"])
        .assert()
        .success()
        .stdout(predicate::eq(b"$(not-run);*;$HOME".as_slice()));
}

#[cfg(unix)]
#[test]
fn run_passes_shell_metacharacters_as_literal_arguments() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["run", "--", "printf", "%s", "$(not-run);*;$HOME"])
        .assert()
        .success()
        .stdout(predicate::eq(b"$(not-run);*;$HOME".as_slice()));
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
fn exits_cleanly_when_a_stdout_consumer_closes_early() {
    let repository = repository();
    let large_body = "x".repeat(128 * 1024);
    let source = CARD.replace(
        "Run the repository generator and review its diff.",
        &large_body,
    );
    fs::write(repository.path().join(".fixcards/known-build.md"), source)
        .expect("write large card");

    let mut child = Command::new(env!("CARGO_BIN_EXE_fixcard"))
        .current_dir(repository.path())
        .args(["show", "known-build"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("start fixcard");
    let mut stdout = child.stdout.take().expect("capture stdout");
    let mut first_byte = [0_u8; 1];
    stdout
        .read_exact(&mut first_byte)
        .expect("read initial output");
    drop(stdout);

    let output = child.wait_with_output().expect("wait for fixcard");
    assert!(
        output.status.success(),
        "closed stdout should be a successful early exit: {output:?}"
    );
    assert!(
        !String::from_utf8_lossy(&output.stderr).contains("panicked"),
        "broken pipes must not produce a panic"
    );
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
fn reports_no_cards_outside_a_repository() {
    let directory = TempDir::new().expect("create non-repository directory");
    let data = TempDir::new().expect("create isolated data directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["find", "failure"])
        .assert()
        .code(1)
        .stdout(predicate::str::contains("No Fixcards are available"))
        .stdout(predicate::str::contains("fixcard save --global"));
}

#[test]
fn an_unmatched_failure_suggests_private_capture() {
    let repository = repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(["fix", "E_NOT_RECORDED"])
        .assert()
        .code(1)
        .stdout(predicate::str::contains("No strong Fixcard match"))
        .stdout(predicate::str::contains(
            "preserve the resolution with: fixcard save",
        ));
}

#[test]
fn status_is_actionable_outside_git() {
    let directory = TempDir::new().expect("create non-repository directory");
    let data = TempDir::new().expect("create isolated data directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .arg("status")
        .assert()
        .success()
        .stdout(predicate::str::contains("Repository: not detected"))
        .stdout(predicate::str::contains("fix PROGRAM [ARGS...]"))
        .stdout(predicate::str::contains("fixcard save"));
}

#[test]
fn status_surfaces_the_installed_literal_fix_workflow() {
    let directory = TempDir::new().expect("create non-repository directory");
    let data = TempDir::new().expect("create isolated data directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .env("SHELL", "/bin/zsh")
        .arg("status")
        .assert()
        .success()
        .stdout(predicate::str::contains("fix PROGRAM [ARGS...]"))
        .stdout(predicate::str::contains("existing-output | fix"))
        .stdout(predicate::str::contains("shell-init").not());
}

#[test]
fn shell_init_generates_an_explicit_fix_wrapper() {
    let directory = TempDir::new().expect("create directory");
    let data = TempDir::new().expect("create isolated data directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["shell-init", "bash"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "if [ \"$#\" -eq 0 ]; then command fixcard",
        ))
        .stdout(predicate::str::contains(
            "else command fixcard run -- \"$@\"",
        ));
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["shell-init", "fish"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "if test (count $argv) -eq 0; command fixcard",
        ))
        .stdout(predicate::str::contains(
            "else; command fixcard run -- $argv",
        ));
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["shell-init", "powershell"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "if ($args.Count -eq 0) { & fixcard } else { & fixcard run -- @args }",
        ));
}

#[test]
fn shell_init_detects_common_shells_when_omitted() {
    let directory = TempDir::new().expect("create directory");
    let data = TempDir::new().expect("create isolated data directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .env("SHELL", "/usr/bin/zsh")
        .arg("shell-init")
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "else command fixcard run -- \"$@\"",
        ));

    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .env("SHELL", "/bin/tcsh")
        .arg("shell-init")
        .assert()
        .code(2)
        .stderr(predicate::str::contains(
            "pass bash, zsh, fish, or powershell explicitly",
        ));
}

#[cfg(unix)]
#[test]
fn generated_bash_fix_wrapper_preserves_literal_arguments() {
    let directory = TempDir::new().expect("create directory");
    let data = TempDir::new().expect("create isolated data directory");
    let fixcard = env!("CARGO_BIN_EXE_fixcard");
    let generated = Command::new(fixcard)
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["shell-init", "bash"])
        .output()
        .expect("generate Bash integration");
    assert!(generated.status.success());

    let mut script = String::from_utf8(generated.stdout).expect("UTF-8 Bash integration");
    script.push_str("\nfix printf '%s' '$(not-run);*;$HOME'\n");
    let binary_directory = Path::new(fixcard)
        .parent()
        .expect("fixcard binary directory");
    let inherited_path = std::env::var_os("PATH").unwrap_or_default();
    let mut path = vec![binary_directory.to_path_buf()];
    path.extend(std::env::split_paths(&inherited_path));
    let path = std::env::join_paths(path).expect("compose PATH");

    let output = Command::new("bash")
        .arg("-c")
        .arg(script)
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .env("PATH", path)
        .output()
        .expect("execute generated Bash integration");
    assert!(
        output.status.success(),
        "Bash integration failed: {output:?}"
    );
    assert_eq!(output.stdout, b"$(not-run);*;$HOME");
}

#[cfg(unix)]
#[test]
fn generated_bash_fix_wrapper_looks_up_piped_failure_without_arguments() {
    let repository = repository();
    let data = TempDir::new().expect("create isolated data directory");
    let fixcard = env!("CARGO_BIN_EXE_fixcard");
    let generated = Command::new(fixcard)
        .current_dir(repository.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["shell-init", "bash"])
        .output()
        .expect("generate Bash integration");
    assert!(generated.status.success());

    let mut script = String::from_utf8(generated.stdout).expect("UTF-8 Bash integration");
    script.push_str("\nprintf '%s' 'E_GENERATED_STALE generated-client' | fix\n");
    let binary_directory = Path::new(fixcard)
        .parent()
        .expect("fixcard binary directory");
    let inherited_path = std::env::var_os("PATH").unwrap_or_default();
    let mut path = vec![binary_directory.to_path_buf()];
    path.extend(std::env::split_paths(&inherited_path));
    let path = std::env::join_paths(path).expect("compose PATH");

    let output = Command::new("bash")
        .arg("-c")
        .arg(script)
        .current_dir(repository.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .env("PATH", path)
        .output()
        .expect("execute generated Bash integration");
    assert!(
        output.status.success(),
        "Bash integration failed: {output:?}"
    );
    assert!(
        String::from_utf8_lossy(&output.stdout)
            .contains("Run the repository generator and review its diff."),
        "piped lookup did not render the recorded resolution: {output:?}"
    );
}

#[test]
fn generates_shell_completion_definitions() {
    cargo_bin_cmd!("fixcard")
        .args(["completion", "bash"])
        .assert()
        .success()
        .stdout(predicate::str::contains("_fixcard"));
}

#[test]
fn saves_and_finds_a_user_global_card_outside_git() {
    let directory = TempDir::new().expect("create non-repository directory");
    let data = TempDir::new().expect("create isolated data directory");
    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args([
            "save",
            "--global",
            "--id",
            "generated-stale",
            "--title",
            "Rebuild generated output",
            "--exact",
            "E_GENERATED_STALE",
            "--resolution",
            "Run the generator.",
            "--yes",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains("Saved user-global card"));
    assert!(data.path().join("cards/generated-stale.md").is_file());

    cargo_bin_cmd!("fixcard")
        .current_dir(directory.path())
        .env("FIXCARD_DATA_DIR", data.path())
        .args(["fix", "E_GENERATED_STALE"])
        .assert()
        .success()
        .stdout(predicate::str::contains("origin: user-global"))
        .stdout(predicate::str::contains("Run the generator."));
}

#[test]
fn creates_and_lints_a_team_card_non_interactively() {
    let repository = empty_repository();
    cargo_bin_cmd!("fixcard")
        .current_dir(repository.path())
        .args(creation_args())
        .assert()
        .success()
        .stdout(predicate::str::contains("Saved repository card"));

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
        .stdout(predicate::str::contains("Saved clone-private card"));
    assert!(
        repository
            .path()
            .join(".git/fixcard/cards/generated-stale.md")
            .is_file()
    );
    assert!(!repository.path().join(".fixcards").exists());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let directory_mode = fs::metadata(repository.path().join(".git/fixcard/cards"))
            .expect("private card directory metadata")
            .permissions()
            .mode()
            & 0o777;
        let file_mode = fs::metadata(
            repository
                .path()
                .join(".git/fixcard/cards/generated-stale.md"),
        )
        .expect("private card metadata")
        .permissions()
        .mode()
            & 0o777;
        assert_eq!(directory_mode, 0o700);
        assert_eq!(file_mode, 0o600);
    }
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
