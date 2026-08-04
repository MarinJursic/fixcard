//! Fixcard command-line entry point.

macro_rules! outputln {
    () => {
        crate::write_stdout(format_args!(""))
    };
    ($($argument:tt)*) => {
        crate::write_stdout(format_args!($($argument)*))
    };
}

mod create;
mod runner;

use std::collections::BTreeMap;
use std::env;
use std::ffi::OsString;
use std::fmt;
use std::fs;
use std::io::{self, IsTerminal, Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, CommandFactory, Parser, Subcommand, ValueEnum};
use fixcard_core::{
    CardOrigin, Confidence, Environment, LoadedCard, MatchResult, Risk, SearchOptions,
    sanitize_terminal, search,
};
use fixcard_git::{
    MAX_CARDS, MAX_DIRECTORY_ENTRIES, MAX_SOURCE_BYTES, Repository, load_user_cards_resilient,
};
use fixcard_lint::{
    Diagnostic, LintPolicy, Severity, lint_card_set, lint_card_with_policy, parse_policy,
    redact_secrets,
};
use jiff::Zoned;
use semver::Version;

const MAX_QUERY_BYTES: usize = 1024 * 1024;
const MAX_POLICY_BYTES: u64 = 64 * 1024;
const POLICY_FILE: &str = ".fixcard.toml";

#[derive(Debug, Parser)]
#[command(
    name = "fixcard",
    version,
    about = "Recall a proven development fix without executing it",
    long_about = "Local lookup for repository, clone-private, and user-global troubleshooting cards. Card content is displayed, never executed."
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Show the complete best known fix for a failure.
    Fix(FindArgs),
    /// Find cards matching a pasted failure.
    Find(FindArgs),
    /// Show a complete card and its recorded evidence.
    Show {
        /// Stable card ID.
        id: String,
    },
    /// List available cards with stable scoped references.
    List,
    /// Show active storage paths, counts, and repository state.
    Status,
    /// Print a compatibility `fix` function for explicit capture or piped lookup.
    ShellInit {
        /// Shell whose function syntax should be generated; inferred from SHELL when omitted.
        #[arg(value_enum)]
        shell: Option<IntegrationShell>,
    },
    /// Generate command-line completion definitions.
    Completion {
        /// Shell whose completion syntax should be generated.
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },
    /// Create a private card, or explicitly create a repository card.
    New(Box<NewArgs>),
    /// Save a known resolution as a private, repository, or user-global card.
    Save(Box<NewArgs>),
    /// Run one explicit command and look up a known fix if it fails.
    Run {
        /// Program and arguments to run after `--`.
        #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
        command: Vec<OsString>,
    },
    /// Validate cards and flag unsafe or stale content.
    Lint {
        /// Card file or directory; defaults to this repository's cards.
        path: Option<PathBuf>,
    },
}

#[derive(Clone, Copy, Debug, ValueEnum)]
enum IntegrationShell {
    Bash,
    Zsh,
    Fish,
    #[value(name = "powershell", alias = "power-shell", alias = "pwsh")]
    PowerShell,
}

#[derive(Clone, Debug, Default, Args)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent lookup display and input switches map directly to CLI flags"
)]
struct FindArgs {
    /// Failure text. When omitted, read standard input.
    #[arg(allow_hyphen_values = true, trailing_var_arg = true)]
    query: Vec<String>,
    /// Prompt for a one-shot failure paste when standard input is a terminal.
    #[arg(long)]
    paste: bool,
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
    /// Save to `.fixcards/` for repository review instead of clone-private storage.
    #[arg(long)]
    team: bool,
    /// Save for reuse across all repositories in the per-user data directory.
    #[arg(long, conflicts_with = "team")]
    global: bool,
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
        Err(error) if is_broken_pipe(&error) => ExitCode::SUCCESS,
        Err(error) => {
            let _ = writeln!(
                io::stderr().lock(),
                "error: {}",
                sanitize_terminal(&format!("{error:#}"))
            );
            ExitCode::from(2)
        }
    }
}

static OUTPUT_TO_STDERR: AtomicBool = AtomicBool::new(false);

fn write_stdout(arguments: fmt::Arguments<'_>) -> io::Result<()> {
    if OUTPUT_TO_STDERR.load(Ordering::Relaxed) {
        let mut stderr = io::stderr().lock();
        stderr.write_fmt(arguments)?;
        stderr.write_all(b"\n")
    } else {
        let mut stdout = io::stdout().lock();
        stdout.write_fmt(arguments)?;
        stdout.write_all(b"\n")
    }
}

struct StderrOutputGuard;

impl Drop for StderrOutputGuard {
    fn drop(&mut self) {
        OUTPUT_TO_STDERR.store(false, Ordering::Relaxed);
    }
}

fn output_to_stderr() -> StderrOutputGuard {
    OUTPUT_TO_STDERR.store(true, Ordering::Relaxed);
    StderrOutputGuard
}

fn is_broken_pipe(error: &anyhow::Error) -> bool {
    error.chain().any(|cause| {
        cause
            .downcast_ref::<io::Error>()
            .is_some_and(|error| error.kind() == io::ErrorKind::BrokenPipe)
    })
}

fn run() -> Result<ExitCode> {
    let cli = Cli::parse();
    let current = env::current_dir().context("cannot determine current directory")?;
    let repository = Repository::discover(&current).ok();
    if cli.command.is_none() && io::stdin().is_terminal() {
        return status(repository.as_ref());
    }
    match cli.command.unwrap_or(Command::Fix(FindArgs::default())) {
        Command::Fix(args) | Command::Find(args) => find(repository.as_ref(), &args),
        Command::Show { id } => show(repository.as_ref(), &id),
        Command::List => list(repository.as_ref()),
        Command::Status => status(repository.as_ref()),
        Command::ShellInit { shell } => shell_init(shell),
        Command::Completion { shell } => completion(shell),
        Command::New(args) | Command::Save(args) => {
            if !args.global && repository.is_none() {
                bail!("private and team cards require a Git worktree; use --global outside Git")
            }
            let policy = repository
                .as_ref()
                .map_or_else(|| Ok(LintPolicy::default()), load_policy)?;
            create::create(repository.as_ref(), &args, &policy)
        }
        Command::Run { command } => runner::run_and_find(repository.as_ref(), &command),
        Command::Lint { path } => {
            let repository = repository.as_ref();
            let policy = repository.map_or_else(|| Ok(LintPolicy::default()), load_policy)?;
            lint(repository, path.as_deref(), &policy)
        }
    }
}

fn shell_init(shell: Option<IntegrationShell>) -> Result<ExitCode> {
    let shell = shell.or_else(detected_integration_shell).ok_or_else(|| {
        anyhow!("cannot detect the current shell; pass bash, zsh, fish, or powershell explicitly")
    })?;
    let source = match shell {
        IntegrationShell::Bash | IntegrationShell::Zsh => {
            "fix() { if [ \"$#\" -eq 0 ]; then command fixcard fix --paste; else command fixcard run -- \"$@\"; fi; }"
        }
        IntegrationShell::Fish => {
            "function fix; if test (count $argv) -eq 0; command fixcard fix --paste; else; command fixcard run -- $argv; end; end"
        }
        IntegrationShell::PowerShell => {
            "function fix { if ($args.Count -eq 0) { & fixcard fix --paste } else { & fixcard run -- @args } }"
        }
    };
    outputln!("{source}")?;
    Ok(ExitCode::SUCCESS)
}

fn detected_integration_shell() -> Option<IntegrationShell> {
    let path = PathBuf::from(env::var_os("SHELL")?);
    let name = path.file_name()?.to_string_lossy().to_ascii_lowercase();
    match name.trim_end_matches(".exe") {
        "bash" => Some(IntegrationShell::Bash),
        "zsh" => Some(IntegrationShell::Zsh),
        "fish" => Some(IntegrationShell::Fish),
        "powershell" | "pwsh" => Some(IntegrationShell::PowerShell),
        _ => None,
    }
}

fn completion(shell: clap_complete::Shell) -> Result<ExitCode> {
    let mut source = Vec::new();
    clap_complete::generate(shell, &mut Cli::command(), "fixcard", &mut source);
    io::stdout()
        .lock()
        .write_all(&source)
        .context("cannot write completion definitions")?;
    Ok(ExitCode::SUCCESS)
}

fn list(repository: Option<&Repository>) -> Result<ExitCode> {
    let mut cards = load_available_cards(repository)?;
    cards.sort_by(|left, right| {
        origin_order(left.origin)
            .cmp(&origin_order(right.origin))
            .then_with(|| left.document.card.id.cmp(&right.document.card.id))
    });
    if cards.is_empty() {
        outputln!("No Fixcards are available.")?;
        return Ok(ExitCode::SUCCESS);
    }
    for card in cards {
        outputln!(
            "{}:{}\t{}",
            scope_prefix(card.origin),
            render_untrusted(&card.document.card.id),
            render_untrusted(&card.document.card.title)
        )?;
    }
    Ok(ExitCode::SUCCESS)
}

fn status(repository: Option<&Repository>) -> Result<ExitCode> {
    let cards = load_available_cards(repository)?;
    outputln!("Fixcard {}", env!("CARGO_PKG_VERSION"))?;
    if let Some(repository) = repository {
        outputln!("Repository: {}", repository.root.display())?;
        outputln!("  repository cards: {}", repository.shared_cards.display())?;
        outputln!(
            "  clone-private cards: {}",
            repository.private_cards.display()
        )?;
    } else {
        outputln!("Repository: not detected (user-global cards remain available)")?;
    }
    outputln!("User-global cards: {}", user_cards_path()?.display())?;
    outputln!(
        "Available: {} repository · {} private · {} global",
        cards
            .iter()
            .filter(|card| card.origin == CardOrigin::Shared)
            .count(),
        cards
            .iter()
            .filter(|card| card.origin == CardOrigin::Private)
            .count(),
        cards
            .iter()
            .filter(|card| card.origin == CardOrigin::User)
            .count()
    )?;
    outputln!("Quick start:")?;
    outputln!("  fix                    # paste a failure for one-shot lookup")?;
    outputln!("  fix PROGRAM [ARGS...]  # run once and look up guidance after failure")?;
    outputln!("  existing-output | fix  # look up output you already have")?;
    outputln!("  fixcard save           # preserve a proven resolution")?;
    Ok(ExitCode::SUCCESS)
}

#[allow(
    clippy::too_many_lines,
    reason = "lint keeps bounded loading, per-card checks, set checks, and summary accounting together"
)]
fn lint(
    repository: Option<&Repository>,
    path: Option<&std::path::Path>,
    policy: &LintPolicy,
) -> Result<ExitCode> {
    let lint_set = path.is_none()
        || path.is_some_and(|value| {
            fs::symlink_metadata(value).is_ok_and(|metadata| metadata.file_type().is_dir())
        });
    let paths = if let Some(path) = path {
        lint_paths(path)?
    } else {
        load_available_cards(repository)?
            .into_iter()
            .map(|card| card.path)
            .collect()
    };
    if paths.is_empty() {
        outputln!("No Fixcards found to lint.")?;
        return Ok(ExitCode::SUCCESS);
    }
    let today = Some(Zoned::now().date());
    let mut error_count = 0_usize;
    let mut warning_count = 0_usize;
    let mut note_count = 0_usize;
    let mut cards = Vec::with_capacity(paths.len());
    let mut aggregate_source_bytes = 0_u64;
    for path in &paths {
        let metadata = fs::symlink_metadata(path)
            .with_context(|| format!("cannot inspect `{}`", path.display()))?;
        aggregate_source_bytes = aggregate_source_bytes.saturating_add(metadata.len());
        if aggregate_source_bytes > MAX_SOURCE_BYTES {
            bail!("lint input exceeds the {MAX_SOURCE_BYTES}-byte aggregate safety limit")
        }
        let source = fs::read_to_string(path)
            .with_context(|| format!("cannot read `{}`", path.display()))?;
        let document = fixcard_core::parse_card(&source)
            .with_context(|| format!("cannot parse `{}`", path.display()))?;
        cards.push((path, source, document));
    }
    let mut print_diagnostic = |path: &std::path::Path, diagnostic: &Diagnostic| -> Result<()> {
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
        outputln!(
            "{}: {}[{}]: {}",
            sanitize_terminal(&location),
            severity,
            diagnostic.code,
            sanitize_terminal(&diagnostic.message)
        )?;
        Ok(())
    };
    for (path, source, document) in &cards {
        for diagnostic in lint_card_with_policy(document, source, today, policy) {
            print_diagnostic(path, &diagnostic)?;
        }
        if path.file_stem().and_then(std::ffi::OsStr::to_str) != Some(&document.card.id) {
            print_diagnostic(
                path,
                &Diagnostic {
                    code: "id-filename-mismatch",
                    severity: Severity::Error,
                    message: format!(
                        "card ID `{}` must match its Markdown filename",
                        document.card.id
                    ),
                    line: None,
                },
            )?;
        }
    }
    if lint_set {
        let documents = cards
            .iter()
            .map(|(_, _, document)| document.clone())
            .collect::<Vec<_>>();
        for finding in lint_card_set(&documents) {
            if let Some((path, _, _)) = cards
                .iter()
                .find(|(_, _, document)| document.card.id == finding.card_id)
            {
                print_diagnostic(path, &finding.diagnostic)?;
            }
        }
    }
    outputln!(
        "\nLinted {} card{}: {error_count} error(s), {warning_count} warning(s), {note_count} note(s)",
        paths.len(),
        if paths.len() == 1 { "" } else { "s" }
    )?;
    Ok(if error_count == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    })
}

fn load_policy(repository: &Repository) -> Result<LintPolicy> {
    let path = repository.root.join(POLICY_FILE);
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(LintPolicy::default());
        }
        Err(error) => {
            return Err(error).with_context(|| format!("cannot inspect `{}`", path.display()));
        }
    };
    if !metadata.file_type().is_file() {
        bail!("Fixcard policy `{}` must be a regular file", path.display())
    }
    if metadata.len() > MAX_POLICY_BYTES {
        bail!("Fixcard policy exceeds the {MAX_POLICY_BYTES}-byte safety limit")
    }
    let source = fs::read_to_string(&path)
        .with_context(|| format!("cannot read Fixcard policy `{}`", path.display()))?;
    parse_policy(&source).map_err(|error| anyhow!(error))
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
    let entries =
        fs::read_dir(path).with_context(|| format!("cannot read `{}`", path.display()))?;
    let mut paths = Vec::new();
    for (index, entry) in entries.enumerate() {
        if index >= MAX_DIRECTORY_ENTRIES {
            bail!("lint directory exceeds the {MAX_DIRECTORY_ENTRIES}-entry safety limit")
        }
        let candidate = entry
            .with_context(|| format!("cannot read an entry in `{}`", path.display()))?
            .path();
        if candidate.extension().and_then(std::ffi::OsStr::to_str) == Some("md")
            && fs::symlink_metadata(&candidate).is_ok_and(|value| value.file_type().is_file())
        {
            if paths.len() >= MAX_CARDS {
                bail!("lint directory exceeds the {MAX_CARDS}-card safety limit")
            }
            paths.push(candidate);
        }
    }
    paths.sort();
    Ok(paths)
}

fn find(repository: Option<&Repository>, args: &FindArgs) -> Result<ExitCode> {
    let query = read_query(&args.query, args.paste)?;
    find_query(repository, args, &query)
}

fn find_query(repository: Option<&Repository>, args: &FindArgs, query: &str) -> Result<ExitCode> {
    if query.trim().is_empty() {
        bail!("the failure text is empty")
    }
    let cards = load_available_cards(repository)?;
    if cards.is_empty() {
        outputln!("No Fixcards are available yet.")?;
        if let Some(repository) = repository {
            outputln!("Repository cards: {}", repository.shared_cards.display())?;
            outputln!(
                "Clone-private cards: {}",
                repository.private_cards.display()
            )?;
        }
        outputln!("User-global cards: {}", user_cards_path()?.display())?;
        print_capture_hint(repository)?;
        return Ok(ExitCode::from(1));
    }
    let environment = environment(&args.tools)?;
    let options = SearchOptions {
        include_retired: args.include_retired,
        today: Some(Zoned::now().date()),
        ..SearchOptions::default()
    };
    let results = search(query, &cards, &environment, &options);
    let strong = results
        .iter()
        .filter(|result| result.confidence == Confidence::Strong)
        .collect::<Vec<_>>();

    if let Some(best) = strong.first() {
        outputln!("1 strong Fixcard match\n")?;
        print_match_evidence(best, args.explain)?;
        outputln!()?;
        print_card(repository, best.card)?;
        if args.all {
            print_other_candidates(&results, &best.card.document.card.id, args.explain)?;
        }
        return Ok(ExitCode::SUCCESS);
    }

    outputln!("No strong Fixcard match.")?;
    print_capture_hint(repository)?;
    if results.is_empty() {
        return Ok(ExitCode::from(1));
    }
    outputln!(
        "{} weak candidate{} available with --all.",
        results.len(),
        if results.len() == 1 { " is" } else { "s are" }
    )?;
    if args.all {
        for result in results.iter().take(10) {
            outputln!()?;
            print_summary(result, args.explain)?;
        }
    }
    Ok(ExitCode::from(1))
}

fn print_capture_hint(repository: Option<&Repository>) -> Result<()> {
    if repository.is_some() {
        outputln!("After solving this failure, preserve the resolution with: fixcard save")?;
    } else {
        outputln!(
            "After solving this failure, preserve a portable resolution with: fixcard save --global"
        )?;
    }
    Ok(())
}

fn show(repository: Option<&Repository>, id: &str) -> Result<ExitCode> {
    let cards = load_available_cards(repository)?;
    let (scope, bare_id) = id
        .split_once(':')
        .map_or((None, id), |(scope, id)| (Some(scope), id));
    let candidates = cards
        .iter()
        .filter(|candidate| candidate.document.card.id == bare_id)
        .filter(|candidate| match scope {
            None => true,
            Some("repo") => candidate.origin == CardOrigin::Shared,
            Some("private") => candidate.origin == CardOrigin::Private,
            Some("global") => candidate.origin == CardOrigin::User,
            Some(_) => false,
        })
        .collect::<Vec<_>>();
    if scope.is_some_and(|value| !matches!(value, "repo" | "private" | "global")) {
        bail!("unknown card scope; use repo:, private:, or global:")
    }
    if candidates.len() > 1 {
        let safe_id = sanitize_terminal(bare_id);
        bail!(
            "card id `{safe_id}` exists in multiple scopes; use repo:{safe_id}, private:{safe_id}, or global:{safe_id}"
        )
    }
    let card = candidates
        .first()
        .copied()
        .ok_or_else(|| anyhow!("no card with id `{}`", sanitize_terminal(id)))?;
    print_card(repository, card)?;
    Ok(ExitCode::SUCCESS)
}

fn print_card(repository: Option<&Repository>, card: &LoadedCard) -> Result<()> {
    let metadata = &card.document.card;
    outputln!("{}\n", render_untrusted(&metadata.title))?;
    outputln!("Card: {}", render_untrusted(&metadata.id))?;
    outputln!("Trust")?;
    outputln!("  origin: {}", trust_label(card))?;
    outputln!("  risk: {}", risk(metadata.risk))?;
    if metadata.retired {
        outputln!("  state: retired")?;
    } else if let Some(replacement) = &metadata.superseded_by {
        outputln!("  state: superseded by {}", render_untrusted(replacement))?;
    } else if metadata.verified.is_none() {
        outputln!("  state: unverified")?;
    } else {
        outputln!("  state: recorded validation")?;
    }
    if let Some(date) = metadata.last_verified.or(metadata.created) {
        outputln!("  last evidence: {date}")?;
    }
    if !metadata.applies.os.is_empty()
        || !metadata.applies.arch.is_empty()
        || !metadata.applies.tools.is_empty()
    {
        outputln!("  applies: {}", applies(card))?;
    }
    if !metadata.authors.is_empty() {
        outputln!(
            "  recorded authors: {}",
            render_untrusted(&metadata.authors.join(", "))
        )?;
    }

    outputln!("\nSuggested resolution — not executed")?;
    outputln!("\n{}", render_untrusted(card.document.body.trim()))?;
    if let Some(verification) = &metadata.verified {
        outputln!("\nValidation recorded")?;
        outputln!("  command: {}", render_untrusted(&verification.command))?;
        if let Some(exit_code) = verification.exit_code {
            outputln!("  observed exit: {exit_code}")?;
        }
        if let Some(commit) = &verification.source_commit {
            outputln!("  source commit: {}", sanitize_terminal(commit))?;
        }
    }
    if card.committed {
        if let Some(provenance) = repository
            .map(|value| value.provenance(&card.path))
            .transpose()?
            .flatten()
        {
            outputln!("\nGit provenance")?;
            outputln!("  commit: {}", provenance.commit)?;
            outputln!("  author: {}", render_untrusted(&provenance.author))?;
            outputln!("  authored: {}", provenance.authored_at)?;
        }
    }
    outputln!(
        "\nThis is evidence of a previous resolution, not a guarantee. Review commands before running them."
    )?;
    Ok(())
}

fn load_available_cards(repository: Option<&Repository>) -> Result<Vec<LoadedCard>> {
    let mut report = if let Some(repository) = repository {
        repository.load_cards_resilient()?
    } else {
        fixcard_git::LoadReport::default()
    };
    let user_report = load_user_cards_resilient(&user_cards_path()?)?;
    report.cards.extend(user_report.cards);
    report.diagnostics.extend(user_report.diagnostics);
    for diagnostic in report.diagnostics.iter().take(20) {
        let _ = writeln!(
            io::stderr().lock(),
            "warning: skipped `{}`: {}",
            sanitize_terminal(&diagnostic.path.display().to_string()),
            sanitize_terminal(&diagnostic.message)
        );
    }
    if report.diagnostics.len() > 20 {
        let _ = writeln!(
            io::stderr().lock(),
            "warning: {} additional invalid-card diagnostic(s) suppressed",
            report.diagnostics.len() - 20
        );
    }
    Ok(report.cards)
}

fn user_cards_path() -> Result<PathBuf> {
    if let Some(base) = env::var_os("FIXCARD_DATA_DIR") {
        let base = PathBuf::from(base);
        if !base.is_absolute() {
            bail!("FIXCARD_DATA_DIR must be an absolute path")
        }
        return Ok(base.join("cards"));
    }
    #[cfg(target_os = "windows")]
    let base = env::var_os("LOCALAPPDATA").map(PathBuf::from);
    #[cfg(target_os = "macos")]
    let base = env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join("Library/Application Support"));
    #[cfg(all(unix, not(target_os = "macos")))]
    let base = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| {
            env::var_os("HOME")
                .map(PathBuf::from)
                .map(|home| home.join(".local/share"))
        });
    base.map(|path| path.join("fixcard/cards"))
        .ok_or_else(|| anyhow!("cannot determine the per-user Fixcard data directory"))
}

fn read_query(arguments: &[String], read_terminal: bool) -> Result<String> {
    if !arguments.is_empty() {
        let query = arguments.join(" ");
        if query.len() > MAX_QUERY_BYTES {
            bail!("query exceeds the {MAX_QUERY_BYTES}-byte safety limit")
        }
        return Ok(query);
    }
    let terminal = io::stdin().is_terminal();
    if terminal && !read_terminal {
        bail!(
            "no failure input; use `fixcard run -- COMMAND`, pass failure text after `fix`, or pipe it on standard input"
        )
    }
    let bytes = if terminal {
        read_terminal_query()?
    } else {
        read_bounded_query(io::stdin().lock())?
    };
    decode_query(bytes)
}

fn read_bounded_query(reader: impl Read) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader
        .take(u64::try_from(MAX_QUERY_BYTES + 1).unwrap_or(u64::MAX))
        .read_to_end(&mut bytes)
        .context("cannot read failure text from standard input")?;
    if bytes.len() > MAX_QUERY_BYTES {
        bail!("query exceeds the {MAX_QUERY_BYTES}-byte safety limit")
    }
    Ok(bytes)
}

fn read_terminal_query() -> Result<Vec<u8>> {
    let token = completion_token()?;
    let mut raw_mode = RawModeGuard::enable()?;
    writeln!(
        io::stderr().lock(),
        "Paste failure text, press Enter, type `{token}`, then press Enter. Input is hidden, used once, and not saved."
    )
    .context("cannot write paste instructions")?;

    let result = read_framed_terminal_query(io::stdin().lock(), &token);
    raw_mode.restore()?;
    result
}

fn completion_token() -> Result<String> {
    const ALPHABET: &[u8; 32] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

    let mut random = [0_u8; 8];
    getrandom::fill(&mut random)
        .map_err(|error| anyhow!("cannot generate a secure paste completion token: {error}"))?;
    let value = random
        .into_iter()
        .fold(0_u64, |value, byte| (value << 8) | u64::from(byte));
    let mut token = String::from("END-");
    for shift in (0_u32..13).rev() {
        let index = u8::try_from((value >> (shift * 5)) & 0x1f)
            .map(usize::from)
            .context("completion-token index is out of range")?;
        token.push(char::from(ALPHABET[index]));
    }
    Ok(token)
}

fn read_framed_terminal_query(mut reader: impl Read, token: &str) -> Result<Vec<u8>> {
    let token = token.as_bytes();
    let mut query = Vec::new();
    let mut oversized = false;
    let mut line_prefix = Vec::with_capacity(token.len());
    let mut line_matches = true;
    let mut buffer = [0_u8; 8 * 1024];

    loop {
        let read = reader
            .read(&mut buffer)
            .context("cannot read failure text from the terminal")?;
        if read == 0 {
            bail!("terminal closed before the paste completion token was entered")
        }
        for &byte in &buffer[..read] {
            if matches!(byte, b'\r' | b'\n') {
                if line_matches && line_prefix == token {
                    if oversized {
                        bail!("query exceeds the {MAX_QUERY_BYTES}-byte safety limit")
                    }
                    return Ok(query);
                }
                append_query_bytes(&mut query, &line_prefix, &mut oversized);
                append_query_bytes(&mut query, &[byte], &mut oversized);
                line_prefix.clear();
                line_matches = true;
            } else if line_matches {
                let position = line_prefix.len();
                if token.get(position) == Some(&byte) {
                    line_prefix.push(byte);
                } else {
                    append_query_bytes(&mut query, &line_prefix, &mut oversized);
                    append_query_bytes(&mut query, &[byte], &mut oversized);
                    line_prefix.clear();
                    line_matches = false;
                }
            } else {
                append_query_bytes(&mut query, &[byte], &mut oversized);
            }
        }
    }
}

fn append_query_bytes(query: &mut Vec<u8>, bytes: &[u8], oversized: &mut bool) {
    let available = MAX_QUERY_BYTES.saturating_sub(query.len());
    let keep = available.min(bytes.len());
    query.extend_from_slice(&bytes[..keep]);
    *oversized |= keep < bytes.len();
}

struct RawModeGuard {
    active: bool,
}

impl RawModeGuard {
    fn enable() -> Result<Self> {
        crossterm::terminal::enable_raw_mode().context("cannot enable safe terminal paste mode")?;
        Ok(Self { active: true })
    }

    fn restore(&mut self) -> Result<()> {
        crossterm::terminal::disable_raw_mode()
            .context("cannot restore the terminal after reading failure text")?;
        self.active = false;
        Ok(())
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        if self.active {
            let _ = crossterm::terminal::disable_raw_mode();
        }
    }
}

fn decode_query(bytes: Vec<u8>) -> Result<String> {
    let query = String::from_utf8(bytes).context("failure text must be valid UTF-8")?;
    if query.trim().is_empty() {
        bail!("no failure text received")
    }
    Ok(query)
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

fn print_summary(result: &MatchResult<'_>, explain: bool) -> Result<()> {
    let card = &result.card.document.card;
    outputln!("{}", render_untrusted(&card.id))?;
    outputln!("{}", render_untrusted(&card.title))?;
    let mut states = vec![
        trust_label(result.card).to_owned(),
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
    outputln!("{}", states.join(" · "))?;
    let applies = applies(result.card);
    if !applies.is_empty() {
        outputln!("applies: {applies}")?;
    }
    if explain {
        outputln!("score: {}", result.score)?;
        for item in &result.evidence {
            outputln!("  {:+} {}", item.points, render_untrusted(&item.reason))?;
        }
    } else {
        let anchors = result
            .evidence
            .iter()
            .filter(|item| matches!(item.points, 12 | 50))
            .map(|item| render_untrusted(&item.reason))
            .collect::<Vec<_>>();
        if !anchors.is_empty() {
            outputln!("matched: {}", anchors.join(", "))?;
        }
    }
    Ok(())
}

fn print_match_evidence(result: &MatchResult<'_>, explain: bool) -> Result<()> {
    if explain {
        outputln!("Match score: {}", result.score)?;
        for item in &result.evidence {
            outputln!("  {:+} {}", item.points, render_untrusted(&item.reason))?;
        }
        return Ok(());
    }
    let anchors = result
        .evidence
        .iter()
        .filter(|item| matches!(item.points, 12 | 50))
        .map(|item| render_untrusted(&item.reason))
        .collect::<Vec<_>>();
    if !anchors.is_empty() {
        outputln!("Matched: {}", anchors.join(", "))?;
    }
    Ok(())
}

fn print_other_candidates(results: &[MatchResult<'_>], best_id: &str, explain: bool) -> Result<()> {
    let others = results
        .iter()
        .filter(|result| result.card.document.card.id != best_id)
        .take(9)
        .collect::<Vec<_>>();
    if others.is_empty() {
        return Ok(());
    }
    outputln!("\nOther candidates")?;
    for result in others {
        outputln!()?;
        print_summary(result, explain)?;
    }
    Ok(())
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
    render_untrusted(&parts.join(" · "))
}

fn render_untrusted(value: &str) -> String {
    sanitize_terminal(&redact_secrets(value))
}

const fn risk(value: Risk) -> &'static str {
    match value {
        Risk::Low => "low risk",
        Risk::Medium => "medium risk",
        Risk::High => "high risk",
    }
}

const fn trust_label(card: &LoadedCard) -> &'static str {
    match (card.origin, card.committed) {
        (CardOrigin::Private, _) => "private",
        (CardOrigin::Shared, true) => "repository-committed",
        (CardOrigin::Shared, false) => "repository-working-copy",
        (CardOrigin::User, _) => "user-global",
    }
}

const fn scope_prefix(origin: CardOrigin) -> &'static str {
    match origin {
        CardOrigin::Shared => "repo",
        CardOrigin::Private => "private",
        CardOrigin::User => "global",
    }
}

const fn origin_order(origin: CardOrigin) -> u8 {
    match origin {
        CardOrigin::Shared => 0,
        CardOrigin::Private => 1,
        CardOrigin::User => 2,
    }
}

const fn normalized_arch(value: &str) -> &str {
    match value.as_bytes() {
        b"aarch64" => "arm64",
        _ => value,
    }
}

#[cfg(test)]
mod tests {
    use std::io::{Cursor, Seek};

    use super::{MAX_QUERY_BYTES, read_bounded_query, read_framed_terminal_query};

    #[test]
    fn framed_terminal_query_treats_eot_and_following_lines_as_input() -> anyhow::Result<()> {
        let input = b"SAFE\n\x04echo PWNED\nEND-ABCDEFGHJKLMN\r";

        let query = read_framed_terminal_query(Cursor::new(input), "END-ABCDEFGHJKLMN")?;

        assert_eq!(query, b"SAFE\n\x04echo PWNED\n");
        Ok(())
    }

    #[test]
    fn framed_terminal_query_discards_oversize_input_until_its_token() -> anyhow::Result<()> {
        let mut input = vec![b'x'; MAX_QUERY_BYTES + 128];
        input.extend_from_slice(b"\nEND-ABCDEFGHJKLMN\r");
        let input_len = u64::try_from(input.len())?;
        let mut reader = Cursor::new(input);

        let result = read_framed_terminal_query(&mut reader, "END-ABCDEFGHJKLMN");

        assert!(result.is_err());
        assert_eq!(reader.stream_position()?, input_len);
        Ok(())
    }

    #[test]
    fn oversized_piped_query_fails_without_draining_the_source() -> anyhow::Result<()> {
        let input = vec![b'x'; MAX_QUERY_BYTES + 128];
        let mut reader = Cursor::new(input);

        let result = read_bounded_query(&mut reader);

        assert!(result.is_err());
        assert_eq!(
            reader.stream_position()?,
            u64::try_from(MAX_QUERY_BYTES + 1)?
        );
        Ok(())
    }
}
