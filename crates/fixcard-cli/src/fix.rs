//! Installed short command for Fixcard's explicit capture and lookup workflow.

use std::env;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{self, Command, ExitStatus};

use anyhow::{Context, Result, bail};
use fixcard_core::sanitize_terminal;

const HELP: &str = "Run a command once and recall a proven Fixcard if it fails.

Usage:
  fix PROGRAM [ARGS...]
  existing-output | fix
  fix

With arguments, fix directly executes the supplied program and argv through
`fixcard run --`. With piped input and no arguments, it performs a lookup.
Bare fix in a terminal shows status and next steps. It never invokes a shell
or executes text from a card.
";

fn main() {
    let exit_code = match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("error: {}", sanitize_terminal(&format!("{error:#}")));
            2
        }
    };
    process::exit(exit_code);
}

fn run() -> Result<i32> {
    let arguments: Vec<OsString> = env::args_os().skip(1).collect();
    if arguments.len() == 1 {
        match arguments[0].to_str() {
            Some("-h" | "--help") => {
                print!("{HELP}");
                return Ok(0);
            }
            Some("-V" | "--version") => {
                println!("fix {}", env!("CARGO_PKG_VERSION"));
                return Ok(0);
            }
            _ => {}
        }
    }

    let fixcard = sibling_fixcard()?;
    let mut command = Command::new(&fixcard);
    if !arguments.is_empty() {
        command.arg("run").arg("--").args(arguments);
    }
    let status = command
        .status()
        .with_context(|| format!("cannot start companion `{}`", fixcard.display()))?;
    Ok(process_exit_code(status))
}

fn sibling_fixcard() -> Result<PathBuf> {
    let current = env::current_exe().context("cannot locate the installed `fix` executable")?;
    sibling_fixcard_from(&current)
}

fn sibling_fixcard_from(current: &Path) -> Result<PathBuf> {
    let directory = current
        .parent()
        .context("installed `fix` executable has no parent directory")?;
    let companion = directory.join(if cfg!(windows) {
        "fixcard.exe"
    } else {
        "fixcard"
    });
    if !companion.is_file() {
        bail!(
            "companion `{}` is missing; reinstall Fixcard so `fix` and `fixcard` are together",
            companion.display()
        );
    }
    Ok(companion)
}

#[cfg(not(unix))]
fn process_exit_code(status: ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

#[cfg(unix)]
fn process_exit_code(status: ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;

    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(1))
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::expect_used,
        reason = "unit-test setup should fail immediately with context"
    )]

    use super::*;

    #[test]
    fn missing_companion_fails_with_reinstallation_guidance() {
        let directory = tempfile::tempdir().expect("create isolated binary directory");
        let current = directory
            .path()
            .join(format!("fix{}", env::consts::EXE_SUFFIX));
        let error = sibling_fixcard_from(&current).expect_err("companion should be absent");
        let message = error.to_string();
        assert!(message.contains("companion"));
        assert!(message.contains("reinstall Fixcard"));
    }
}
