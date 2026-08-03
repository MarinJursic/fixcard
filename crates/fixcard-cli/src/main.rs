//! Fixcard command-line entry point.

mod create;

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{self, IsTerminal, Read};
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Parser, Subcommand};
use fixcard_core::{
    CardOrigin, Confidence, Environment, LoadedCard, MatchResult, Risk, SearchOptions,
    sanitize_terminal, search,
};
use fixcard_git::Repository;
use fixcard_lint::{Severity, lint_card};
use jiff::Zoned;
use semver::Version;

const MAX_QUERY_BYTES: usize = 1024 * 1024;

#[derive(Debug, Parser)]
#[command(
    name = "fixcard",
    version,
    about = "Find the fix this repository already proved",
    long_about = "Local, Git-aware lookup for repository-owned, human-verified troubleshooting cards. Commands are displayed, never executed."
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Find cards matching a pasted failure.
    Find(FindArgs),
    /// Show a complete card and its recorded evidence.
    Show {
        /// Stable card ID.
        id: String,
    },
    /// Create a private card, or explicitly create a repository card.
    New(Box<NewArgs>),
    /// Validate cards and flag unsafe or stale content.
    Lint {
        /// Card file or directory; defaults to this repository's cards.
        path: Option<PathBuf>,
    },
}

#[derive(Clone, Debug, Default, Args)]
struct FindArgs {
    /// Failure text. When omitted, read standard input or interactive paste mode.
    #[arg(allow_hyphen_values = true, trailing_var_arg = true)]
    query: Vec<String>,
    /// Include weak candidates and their caution states.
    #[arg(long)]
    all: bool,
    /// Explain each deterministic scoring contribution.
    #[arg(long)]
    explain: bool,
    /// Supply a current tool version as NAME=SEMVER; repeatable.
    #[arg(long = "tool", value_name = "NAME=VERSION")]
    tools: Vec<String>,
    /// Include retired or superseded cards as weak candidates.
    #[arg(long, alias = "include-inactive")]
    include_retired: bool,
}

#[derive(Clone, Debug, Args)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent opt-in CLI switches are clearer than artificial enum state"
)]
struct NewArgs {
    /// Save to `.fixcards/` for Git review instead of private clone storage.
    #[arg(long)]
    team: bool,
    /// Stable lowercase ID; prompted when omitted in a terminal.
    #[arg(long)]
    id: Option<String>,
    /// Short resolution title; prompted when omitted in a terminal.
    #[arg(long)]
    title: Option<String>,
    /// Stable exact failure anchor; repeatable.
    #[arg(long = "exact")]
    exact: Vec<String>,
    /// Additional literal failure fragment; repeatable.
    #[arg(long = "contains")]
    contains: Vec<String>,
    /// Literal fragment that disproves this match; repeatable.
    #[arg(long = "not-contains")]
    not_contains: Vec<String>,
    /// Known-compatible tool range as NAME=RANGE; repeatable.
    #[arg(long = "applies-tool", value_name = "NAME=RANGE")]
    applies_tools: Vec<String>,
    /// Do not restrict this card to the current OS and architecture.
    #[arg(long)]
    no_platform: bool,
    /// Explanation of the failure's cause.
    #[arg(long)]
    why: Option<String>,
    /// Situation in which this resolution should not be used.
    #[arg(long)]
    do_not_apply: Option<String>,
    /// Human-confirmed resolution text.
    #[arg(long)]
    resolution: Option<String>,
    /// Inert command to display for review; repeatable.
    #[arg(long = "command")]
    commands: Vec<String>,
    /// Command whose observed result validated the resolution.
    #[arg(long)]
    validation_command: Option<String>,
    /// Observed exit status for the validation command.
    #[arg(long, requires = "validation_command")]
    validation_exit: Option<i32>,
    /// Declared risk: low, medium, or high.
    #[arg(long, default_value = "low")]
    risk: String,
    /// Omit the current Git author identity from the card.
    #[arg(long)]
    no_author: bool,
    /// Accept the rendered preview without an interactive confirmation.
    #[arg(long, short = 'y')]
    yes: bool,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("error: {}", sanitize_terminal(&format!("{error:#}")));
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<ExitCode> {
    let cli = Cli::parse();
    let current = env::current_dir().context("cannot determine current directory")?;
    let repository = Repository::discover(&current)
        .map_err(|error| anyhow!("Fixcard must run inside a Git worktree ({error})"))?;
    match cli.command.unwrap_or(Command::Find(FindArgs::default())) {
        Command::Find(args) => find(&repository, &args),
        Command::Show { id } => show(&repository, &id),
        Command::New(args) => create::create(&repository, &args),
        Command::Lint { path } => lint(&repository, path.as_deref()),
    }
}

fn lint(repository: &Repository, path: Option<&std::path::Path>) -> Result<ExitCode> {
    let paths = if let Some(path) = path {
        lint_paths(path)?
    } else {
        repository
            .load_cards()?
            .into_iter()
            .map(|card| card.path)
            .collect()
    };
    if paths.is_empty() {
        println!("No Fixcards found to lint.");
        return Ok(ExitCode::SUCCESS);
    }
    let today = Some(Zoned::now().date());
    let mut error_count = 0_usize;
    let mut warning_count = 0_usize;
    let mut note_count = 0_usize;
    for path in &paths {
        let source = fs::read_to_string(path)
            .with_context(|| format!("cannot read `{}`", path.display()))?;
        let document = fixcard_core::parse_card(&source)
            .with_context(|| format!("cannot parse `{}`", path.display()))?;
        let diagnostics = lint_card(&document, &source, today);
        for diagnostic in diagnostics {
            let severity = match diagnostic.severity {
                Severity::Error => {
                    error_count += 1;
                    "error"
                }
                Severity::Warning => {
                    warning_count += 1;
                    "warning"
                }
                Severity::Note => {
                    note_count += 1;
                    "note"
                }
            };
            let location = diagnostic.line.map_or_else(
                || path.display().to_string(),
                |line| format!("{}:{line}", path.display()),
            );
            println!(
                "{}: {}[{}]: {}",
                sanitize_terminal(&location),
                severity,
                diagnostic.code,
                sanitize_terminal(&diagnostic.message)
            );
        }
    }
    println!(
        "\nLinted {} card{}: {error_count} error(s), {warning_count} warning(s), {note_count} note(s)",
        paths.len(),
        if paths.len() == 1 { "" } else { "s" }
    );
    Ok(if error_count == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    })
}

fn lint_paths(path: &std::path::Path) -> Result<Vec<PathBuf>> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("cannot inspect `{}`", path.display()))?;
    if metadata.file_type().is_file() {
        return Ok(vec![path.to_owned()]);
    }
    if !metadata.file_type().is_dir() {
        bail!("lint path must be a regular file or directory")
    }
    let mut paths = fs::read_dir(path)
        .with_context(|| format!("cannot read `{}`", path.display()))?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|candidate| {
            candidate.extension().and_then(std::ffi::OsStr::to_str) == Some("md")
                && fs::symlink_metadata(candidate).is_ok_and(|value| value.file_type().is_file())
        })
        .collect::<Vec<_>>();
    paths.sort();
    Ok(paths)
}

fn find(repository: &Repository, args: &FindArgs) -> Result<ExitCode> {
    let query = read_query(&args.query)?;
    if query.trim().is_empty() {
        bail!("the failure text is empty")
    }
    let cards = repository.load_cards()?;
    if cards.is_empty() {
        println!("No Fixcards exist in this repository yet.");
        println!("Shared cards: {}", repository.shared_cards.display());
        println!("Private cards: {}", repository.private_cards.display());
        return Ok(ExitCode::from(1));
    }
    let environment = environment(&args.tools)?;
    let options = SearchOptions {
        include_retired: args.include_retired,
        today: Some(Zoned::now().date()),
        ..SearchOptions::default()
    };
    let results = search(&query, &cards, &environment, &options);
    let strong = results
        .iter()
        .filter(|result| result.confidence == Confidence::Strong)
        .collect::<Vec<_>>();

    if let Some(best) = strong.first() {
        println!("1 strong repository match\n");
        print_summary(best, args.explain);
        println!("\nRun: fixcard show {}", best.card.document.card.id);
        if args.all {
            print_other_candidates(&results, &best.card.document.card.id, args.explain);
        }
        return Ok(ExitCode::SUCCESS);
    }

    println!("No strong repository match.");
    if results.is_empty() {
        return Ok(ExitCode::from(1));
    }
    println!(
        "{} weak candidate{} available with --all.",
        results.len(),
        if results.len() == 1 { " is" } else { "s are" }
    );
    if args.all {
        for result in results.iter().take(10) {
            println!();
            print_summary(result, args.explain);
        }
    }
    Ok(ExitCode::from(1))
}

fn show(repository: &Repository, id: &str) -> Result<ExitCode> {
    let cards = repository.load_cards()?;
    let card = cards
        .iter()
        .find(|candidate| candidate.document.card.id == id)
        .ok_or_else(|| anyhow!("no card with id `{}`", sanitize_terminal(id)))?;
    let metadata = &card.document.card;
    println!("{}\n", sanitize_terminal(&metadata.title));
    println!("Trust");
    println!("  origin: {}", origin(card.origin));
    println!("  risk: {}", risk(metadata.risk));
    if metadata.retired {
        println!("  state: retired");
    } else if let Some(replacement) = &metadata.superseded_by {
        println!("  state: superseded by {}", sanitize_terminal(replacement));
    } else if metadata.verified.is_none() {
        println!("  state: unverified");
    } else {
        println!("  state: recorded validation");
    }
    if let Some(date) = metadata.last_verified.or(metadata.created) {
        println!("  last evidence: {date}");
    }
    if !metadata.applies.os.is_empty() || !metadata.applies.arch.is_empty() {
        println!("  applies: {}", applies(card));
    }

    println!("\n{}", sanitize_terminal(card.document.body.trim()));
    if let Some(verification) = &metadata.verified {
        println!("\nValidation recorded");
        println!("  command: {}", sanitize_terminal(&verification.command));
        if let Some(exit_code) = verification.exit_code {
            println!("  observed exit: {exit_code}");
        }
        if let Some(commit) = &verification.source_commit {
            println!("  source commit: {}", sanitize_terminal(commit));
        }
    }
    if card.origin == CardOrigin::Shared {
        if let Some(provenance) = repository.provenance(&card.path)? {
            println!("\nGit provenance");
            println!("  commit: {}", provenance.commit);
            println!("  author: {}", sanitize_terminal(&provenance.author));
            println!("  authored: {}", provenance.authored_at);
        }
    }
    println!(
        "\nThis is evidence of a previous resolution, not a guarantee. Review commands before running them."
    );
    Ok(ExitCode::SUCCESS)
}

fn read_query(arguments: &[String]) -> Result<String> {
    if !arguments.is_empty() {
        let query = arguments.join(" ");
        if query.len() > MAX_QUERY_BYTES {
            bail!("query exceeds the {MAX_QUERY_BYTES}-byte safety limit")
        }
        return Ok(query);
    }
    if io::stdin().is_terminal() {
        eprintln!("Paste the failure, then press Ctrl-D:");
    }
    let mut bytes = Vec::new();
    io::stdin()
        .lock()
        .take(u64::try_from(MAX_QUERY_BYTES + 1).unwrap_or(u64::MAX))
        .read_to_end(&mut bytes)
        .context("cannot read failure text from standard input")?;
    if bytes.len() > MAX_QUERY_BYTES {
        bail!("query exceeds the {MAX_QUERY_BYTES}-byte safety limit")
    }
    String::from_utf8(bytes).context("failure text must be valid UTF-8")
}

fn environment(values: &[String]) -> Result<Environment> {
    let mut tools = BTreeMap::new();
    for value in values {
        let (name, version) = value
            .split_once('=')
            .ok_or_else(|| anyhow!("tool version `{value}` must use NAME=VERSION"))?;
        if name.is_empty()
            || !name.chars().all(|character| {
                character.is_ascii_alphanumeric() || matches!(character, '-' | '_')
            })
        {
            bail!("tool name `{name}` is invalid")
        }
        tools.insert(
            name.to_lowercase(),
            Version::parse(version)
                .with_context(|| format!("invalid semantic version `{version}` for {name}"))?,
        );
    }
    Ok(Environment {
        os: Some(env::consts::OS.to_owned()),
        arch: Some(normalized_arch(env::consts::ARCH).to_owned()),
        tools,
    })
}

fn print_summary(result: &MatchResult<'_>, explain: bool) {
    let card = &result.card.document.card;
    println!("{}", sanitize_terminal(&card.id));
    println!("{}", sanitize_terminal(&card.title));
    let mut states = vec![
        origin(result.card.origin).to_owned(),
        risk(card.risk).to_owned(),
    ];
    if card.verified.is_none() {
        states.push("unverified".to_owned());
    }
    if result.stale {
        states.push("stale".to_owned());
    }
    if result.version_mismatch {
        states.push("version-mismatch".to_owned());
    }
    println!("{}", states.join(" · "));
    let applies = applies(result.card);
    if !applies.is_empty() {
        println!("applies: {applies}");
    }
    if explain {
        println!("score: {}", result.score);
        for item in &result.evidence {
            println!("  {:+} {}", item.points, sanitize_terminal(&item.reason));
        }
    } else {
        let anchors = result
            .evidence
            .iter()
            .filter(|item| matches!(item.points, 12 | 50))
            .map(|item| sanitize_terminal(&item.reason))
            .collect::<Vec<_>>();
        if !anchors.is_empty() {
            println!("matched: {}", anchors.join(", "));
        }
    }
}

fn print_other_candidates(results: &[MatchResult<'_>], best_id: &str, explain: bool) {
    let others = results
        .iter()
        .filter(|result| result.card.document.card.id != best_id)
        .take(9)
        .collect::<Vec<_>>();
    if others.is_empty() {
        return;
    }
    println!("\nOther candidates");
    for result in others {
        println!();
        print_summary(result, explain);
    }
}

fn applies(card: &LoadedCard) -> String {
    let applies = &card.document.card.applies;
    let mut parts = Vec::new();
    if !applies.os.is_empty() {
        parts.push(applies.os.join("/"));
    }
    if !applies.arch.is_empty() {
        parts.push(applies.arch.join("/"));
    }
    parts.extend(
        applies
            .tools
            .iter()
            .map(|(tool, requirement)| format!("{tool} {requirement}")),
    );
    sanitize_terminal(&parts.join(" · "))
}

const fn risk(value: Risk) -> &'static str {
    match value {
        Risk::Low => "low risk",
        Risk::Medium => "medium risk",
        Risk::High => "high risk",
    }
}

const fn origin(value: CardOrigin) -> &'static str {
    match value {
        CardOrigin::Private => "private",
        CardOrigin::Shared => "repo-reviewed",
    }
}

const fn normalized_arch(value: &str) -> &str {
    match value.as_bytes() {
        b"aarch64" => "arm64",
        _ => value,
    }
}
