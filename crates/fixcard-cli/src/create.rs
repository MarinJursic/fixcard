//! Reviewed private and team card creation.

use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{Context, Result, anyhow, bail};
use dialoguer::{Confirm, Input};
use fixcard_core::{Applies, Card, MatchSpec, Risk, Verification, parse_card, sanitize_terminal};
use fixcard_git::Repository;
use fixcard_lint::{LintPolicy, Severity, blocks_team_save, lint_card_with_policy, redact_secrets};
use jiff::Zoned;
use semver::VersionReq;

use crate::NewArgs;

#[allow(
    clippy::too_many_lines,
    reason = "creation is a linear reviewed transaction whose ordering is safety-relevant"
)]
pub(super) fn create(
    repository: &Repository,
    args: &NewArgs,
    policy: &LintPolicy,
) -> Result<ExitCode> {
    let interactive = std::io::stdin().is_terminal();
    let title = required(args.title.clone(), "Short title", interactive)?;
    let id = args.id.clone().unwrap_or_else(|| slugify(&title));
    let mut exact = args.exact.clone();
    if exact.is_empty() {
        exact.push(required(
            None,
            "Stable excerpt from the failure",
            interactive,
        )?);
    }
    let contains = if args.contains.is_empty() && interactive {
        split_optional(&prompt(
            "Additional match fragments (comma-separated, optional)",
            "",
        )?)
    } else {
        args.contains.clone()
    };
    let not_contains = if args.not_contains.is_empty() && interactive {
        split_optional(&prompt(
            "Contradicting match fragments (comma-separated, optional)",
            "",
        )?)
    } else {
        args.not_contains.clone()
    };
    let applies_tools = if args.applies_tools.is_empty() && interactive {
        split_optional(&prompt(
            "Applicable tool ranges (NAME=RANGE, comma-separated, optional)",
            "",
        )?)
    } else {
        args.applies_tools.clone()
    };
    let why = optional(args.why.clone(), "Why this happens (optional)", interactive)?;
    let do_not_apply = optional(
        args.do_not_apply.clone(),
        "Do not apply when (optional)",
        interactive,
    )?;
    let resolution = required(args.resolution.clone(), "What worked here", interactive)?;
    let commands = if args.commands.is_empty() && interactive {
        split_optional(&prompt(
            "Commands to review (semicolon-separated, optional)",
            "",
        )?)
    } else {
        args.commands.clone()
    };
    let validation_command = optional(
        args.validation_command.clone(),
        "Validation command (optional)",
        interactive,
    )?;
    let risk = parse_risk(&args.risk)?;
    let today = Zoned::now().date();
    let source_commit = if validation_command.is_some() {
        repository.head_commit()?
    } else {
        None
    };
    let verification = validation_command.map(|command| Verification {
        command,
        exit_code: args.validation_exit,
        source_commit,
    });
    let last_verified = verification.as_ref().map(|_| today);
    let authors = if args.no_author {
        Vec::new()
    } else {
        repository.author_name()?.into_iter().collect()
    };
    let tools = parse_tool_ranges(&applies_tools)?;
    let (os, arch) = if args.no_platform {
        (Vec::new(), Vec::new())
    } else {
        (
            vec![std::env::consts::OS.to_owned()],
            vec![normalized_arch(std::env::consts::ARCH).to_owned()],
        )
    };
    let card = Card {
        fixcard: fixcard_core::SUPPORTED_SCHEMA_VERSION,
        id,
        title,
        match_spec: MatchSpec {
            exact,
            contains,
            not_contains,
        },
        applies: Applies { os, arch, tools },
        risk,
        verified: verification,
        last_verified,
        created: Some(today),
        authors,
        supersedes: Vec::new(),
        superseded_by: None,
        retired: false,
        retirement_reason: None,
        extensions: BTreeMap::new(),
    };
    let source = render(
        &card,
        why.as_deref(),
        do_not_apply.as_deref(),
        &resolution,
        &commands,
    )?;
    let document = parse_card(&source).context("generated card failed format validation")?;
    let diagnostics = lint_card_with_policy(&document, &source, Some(today), policy);
    print_preview(&source, &diagnostics);
    if args.team && blocks_team_save(&diagnostics) {
        bail!("team card was not saved because lint reported blocking errors")
    }
    if !args.yes {
        if !interactive {
            bail!("non-interactive creation requires --yes after all required fields")
        }
        if !Confirm::new()
            .with_prompt("Save this card?")
            .default(true)
            .interact()
            .context("confirmation failed")?
        {
            println!("Card was not saved.");
            return Ok(ExitCode::from(1));
        }
    }
    let directory = prepare_directory(repository, args.team)?;
    let path = directory.join(format!("{}.md", document.card.id));
    if fs::symlink_metadata(&path).is_ok() {
        bail!("refusing to overwrite `{}`", path.display())
    }
    let mut temporary = tempfile::NamedTempFile::new_in(&directory).with_context(|| {
        format!(
            "cannot create a temporary card in `{}`",
            directory.display()
        )
    })?;
    temporary
        .write_all(source.as_bytes())
        .with_context(|| format!("cannot write `{}`", path.display()))?;
    temporary
        .as_file_mut()
        .sync_all()
        .with_context(|| format!("cannot sync `{}`", path.display()))?;
    set_team_permissions(temporary.as_file(), args.team)?;
    temporary
        .persist_noclobber(&path)
        .map_err(|error| error.error)
        .with_context(|| format!("refusing to overwrite `{}`", path.display()))?;
    println!(
        "Saved {} card: {}",
        if args.team { "team" } else { "private" },
        path.display()
    );
    Ok(ExitCode::SUCCESS)
}

fn prepare_directory(repository: &Repository, team: bool) -> Result<PathBuf> {
    if team {
        ensure_real_directory(&repository.shared_cards)?;
        return Ok(repository.shared_cards.clone());
    }
    let private_parent = repository.common_dir.join("fixcard");
    ensure_real_directory(&private_parent)?;
    ensure_real_directory(&repository.private_cards)?;
    Ok(repository.private_cards.clone())
}

fn ensure_real_directory(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_dir() => Ok(()),
        Ok(_) => bail!(
            "refusing unsafe card storage `{}`: expected a real directory, not a file or symlink",
            path.display()
        ),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => fs::create_dir(path)
            .with_context(|| format!("cannot create card directory `{}`", path.display())),
        Err(error) => Err(error).with_context(|| format!("cannot inspect `{}`", path.display())),
    }
}

#[cfg(unix)]
fn set_team_permissions(file: &File, team: bool) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mode = if team { 0o644 } else { 0o600 };
    file.set_permissions(fs::Permissions::from_mode(mode))
        .context("cannot set card permissions")
}

#[cfg(not(unix))]
fn set_team_permissions(_file: &File, _team: bool) -> Result<()> {
    Ok(())
}

fn required(value: Option<String>, label: &str, interactive: bool) -> Result<String> {
    let value = match value {
        Some(value) => value,
        None if interactive => prompt(label, "")?,
        None => bail!("non-interactive creation requires --{}", flag(label)),
    };
    if value.trim().is_empty() {
        bail!("{label} cannot be empty")
    }
    Ok(value.trim().to_owned())
}

fn optional(value: Option<String>, label: &str, interactive: bool) -> Result<Option<String>> {
    let value = match value {
        Some(value) => value,
        None if interactive => prompt(label, "")?,
        None => return Ok(None),
    };
    Ok((!value.trim().is_empty()).then(|| value.trim().to_owned()))
}

fn prompt(label: &str, default: &str) -> Result<String> {
    Input::new()
        .with_prompt(label)
        .default(default.to_owned())
        .allow_empty(true)
        .interact_text()
        .with_context(|| format!("prompt failed: {label}"))
}

fn render(
    card: &Card,
    why: Option<&str>,
    do_not_apply: Option<&str>,
    resolution: &str,
    commands: &[String],
) -> Result<String> {
    let yaml = serde_yaml_ng::to_string(card).context("cannot serialize card front matter")?;
    let mut body = String::new();
    if let Some(why) = why {
        body.push_str("## Why this happens\n\n");
        body.push_str(why);
        body.push_str("\n\n");
    }
    if let Some(condition) = do_not_apply {
        body.push_str("## Do not apply when\n\n");
        body.push_str(condition);
        body.push_str("\n\n");
    }
    body.push_str("## What worked here\n\n");
    body.push_str(resolution);
    body.push('\n');
    if !commands.is_empty() {
        body.push_str("\n## Commands to review\n\n```bash\n");
        body.push_str(&commands.join("\n"));
        body.push_str("\n```\n");
    }
    Ok(format!("---\n{yaml}---\n{body}"))
}

fn print_preview(source: &str, diagnostics: &[fixcard_lint::Diagnostic]) {
    println!(
        "\nPreview\n\n{}",
        sanitize_terminal(&redact_secrets(source))
    );
    if diagnostics.is_empty() {
        println!("\nLint: no findings");
        return;
    }
    println!("\nLint findings");
    for diagnostic in diagnostics {
        let severity = match diagnostic.severity {
            Severity::Error => "error",
            Severity::Warning => "warning",
            Severity::Note => "note",
        };
        println!(
            "  {severity}[{}]: {}",
            diagnostic.code,
            sanitize_terminal(&diagnostic.message)
        );
    }
}

fn parse_risk(value: &str) -> Result<Risk> {
    match value {
        "low" => Ok(Risk::Low),
        "medium" => Ok(Risk::Medium),
        "high" => Ok(Risk::High),
        _ => Err(anyhow!("risk must be low, medium, or high")),
    }
}

fn parse_tool_ranges(values: &[String]) -> Result<BTreeMap<String, String>> {
    let mut tools = BTreeMap::new();
    for value in values {
        let Some((name, requirement)) = value.split_once('=') else {
            bail!("tool applicability must be NAME=RANGE")
        };
        let name = name.trim();
        let requirement = requirement.trim();
        if name.is_empty() || requirement.is_empty() {
            bail!("tool applicability must contain a non-empty name and range")
        }
        if !name.chars().all(|character| {
            character.is_ascii_lowercase()
                || character.is_ascii_digit()
                || matches!(character, '-' | '_')
        }) || !name
            .chars()
            .next()
            .is_some_and(|character| character.is_ascii_lowercase() || character.is_ascii_digit())
        {
            bail!("tool applicability name `{name}` must be a lowercase portable identifier")
        }
        let normalized_requirement = requirement
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(", ");
        VersionReq::parse(&normalized_requirement).with_context(|| {
            format!("invalid semantic version range `{requirement}` for {name}")
        })?;
        if tools
            .insert(name.to_owned(), requirement.to_owned())
            .is_some()
        {
            bail!("tool applicability repeats `{name}`")
        }
    }
    Ok(tools)
}

fn slugify(value: &str) -> String {
    let slug = value
        .to_ascii_lowercase()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    slug.chars()
        .take(64)
        .collect::<String>()
        .trim_end_matches('-')
        .to_owned()
}

fn split_optional(value: &str) -> Vec<String> {
    value
        .split([',', ';'])
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn flag(label: &str) -> String {
    label
        .split_whitespace()
        .next()
        .unwrap_or("value")
        .to_ascii_lowercase()
}

const fn normalized_arch(value: &str) -> &str {
    match value.as_bytes() {
        b"aarch64" => "arm64",
        _ => value,
    }
}
