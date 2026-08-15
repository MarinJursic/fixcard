//! Worktree-safe repository discovery, storage paths, and Git provenance.

use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsStr;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Output, Stdio};
use std::thread;

use fixcard_core::{CardOrigin, LoadedCard, MAX_CARD_BYTES, ParseError, parse_card};
use thiserror::Error;

/// Directory containing repository-owned cards.
pub const SHARED_CARDS_DIR: &str = ".fixcards";

/// Directory containing private cards relative to Git's common directory.
pub const PRIVATE_CARDS_DIR: &str = "fixcard/cards";

/// Maximum number of cards loaded from one repository.
pub const MAX_CARDS: usize = 10_000;
/// Maximum directory entries inspected per card origin.
pub const MAX_DIRECTORY_ENTRIES: usize = 20_000;
/// Maximum aggregate source bytes loaded per card origin.
pub const MAX_SOURCE_BYTES: u64 = 32 * 1024 * 1024;
const MAX_GIT_TREE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_GIT_STDERR_BYTES: usize = 64 * 1024;

/// Worktree and common-directory paths resolved by Git itself.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Repository {
    /// Top-level worktree directory.
    pub root: PathBuf,
    /// Shared Git directory, including linked-worktree layouts.
    pub common_dir: PathBuf,
    /// Repository-owned card directory.
    pub shared_cards: PathBuf,
    /// Clone-private card directory.
    pub private_cards: PathBuf,
}

/// Last Git commit touching a shared card.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Provenance {
    /// Full commit object ID.
    pub commit: String,
    /// Git author name.
    pub author: String,
    /// Author timestamp from Git.
    pub authored_at: String,
}

/// One quarantined card that did not prevent valid cards from loading.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LoadDiagnostic {
    /// Path of the invalid card.
    pub path: PathBuf,
    /// Safe-to-display failure summary.
    pub message: String,
}

/// Valid cards plus diagnostics for quarantined invalid cards.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct LoadReport {
    /// Cards safe to search and display.
    pub cards: Vec<LoadedCard>,
    /// Invalid cards skipped during resilient lookup.
    pub diagnostics: Vec<LoadDiagnostic>,
}

/// Failure during bounded repository operations.
#[derive(Debug, Error)]
pub enum GitError {
    /// The starting directory is not inside a Git worktree.
    #[error("not inside a Git worktree")]
    NotInWorktree,
    /// A filesystem operation failed.
    #[error("{action} `{path}`: {source}")]
    Io {
        /// Operation description.
        action: &'static str,
        /// Affected path.
        path: PathBuf,
        /// Underlying error.
        source: std::io::Error,
    },
    /// Git rejected repository discovery or provenance lookup.
    #[error("Git command failed: {0}")]
    Command(String),
    /// Git emitted bytes that are not UTF-8.
    #[error("Git returned non-UTF-8 output")]
    Utf8,
    /// A card is malformed.
    #[error("cannot parse `{path}`: {source}")]
    Parse {
        /// Card path.
        path: PathBuf,
        /// Parser diagnostic.
        source: ParseError,
    },
    /// A filename conflicts with the card's portable ID.
    #[error("card `{path}` declares id `{id}`, which must match its filename")]
    IdFilename {
        /// Card path.
        path: PathBuf,
        /// Declared card ID.
        id: String,
    },
    /// More than one discovered card uses the same ID.
    #[error("duplicate card id `{id}` found at `{first}` and `{second}`")]
    DuplicateId {
        /// Duplicated ID.
        id: String,
        /// First path.
        first: PathBuf,
        /// Second path.
        second: PathBuf,
    },
    /// The repository exceeds the defensive discovery limit.
    #[error("repository contains more than {MAX_CARDS} cards")]
    TooManyCards,
    /// A card directory contains too many entries, including non-cards.
    #[error("card directory contains more than {MAX_DIRECTORY_ENTRIES} entries")]
    TooManyEntries,
    /// One origin exceeds the aggregate source-byte limit.
    #[error("card directory contains more than {MAX_SOURCE_BYTES} bytes of card source")]
    TooManySourceBytes,
    /// Git emitted more tree metadata than the bounded loader accepts.
    #[error("Git tree metadata exceeds the {MAX_GIT_TREE_BYTES}-byte safety limit")]
    TooMuchGitMetadata,
    /// A card collection path is not a real directory.
    #[error("refusing unsafe card directory `{0}`: expected a real directory")]
    UnsafeCardDirectory(PathBuf),
}

impl Repository {
    /// Discover the repository containing `start` using worktree-aware Git APIs.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] outside a worktree, when Git is unavailable, or when
    /// Git returns unusable paths.
    pub fn discover(start: &Path) -> Result<Self, GitError> {
        let root_output = git_output(start, ["rev-parse", "--show-toplevel"])?;
        if !root_output.status.success() {
            let stderr = String::from_utf8_lossy(&root_output.stderr);
            if stderr.contains("not a git repository")
                || stderr.contains("must be run in a work tree")
            {
                return Err(GitError::NotInWorktree);
            }
            return Err(command_error(&root_output));
        }
        let root = path_from_output(root_output)?;
        let common_dir = git_path(
            start,
            &["rev-parse", "--path-format=absolute", "--git-common-dir"],
        )?;
        Ok(Self {
            shared_cards: root.join(SHARED_CARDS_DIR),
            private_cards: common_dir.join(PRIVATE_CARDS_DIR),
            root,
            common_dir,
        })
    }

    /// Load private and shared Markdown cards without following symlinks.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] for unreadable or invalid cards, duplicate IDs,
    /// filename mismatches, or an excessive corpus.
    pub fn load_cards(&self) -> Result<Vec<LoadedCard>, GitError> {
        let mut cards = Vec::new();
        let mut diagnostics = Vec::new();
        let committed_sources = self.committed_shared_sources()?;
        reject_symlinked_storage_parent(&self.private_cards)?;
        Self::load_directory(
            &self.shared_cards,
            CardOrigin::Shared,
            Some(&committed_sources),
            &mut cards,
            &mut diagnostics,
            true,
        )?;
        Self::load_directory(
            &self.private_cards,
            CardOrigin::Private,
            None,
            &mut cards,
            &mut diagnostics,
            true,
        )?;
        cards.sort_by(|left, right| left.document.card.id.cmp(&right.document.card.id));
        reject_duplicate_ids(&cards)?;
        Ok(cards)
    }

    /// Load every valid repository card while quarantining malformed cards.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] only for unsafe storage, I/O failures, Git failures,
    /// or resource-limit violations.
    pub fn load_cards_resilient(&self) -> Result<LoadReport, GitError> {
        let mut report = LoadReport::default();
        let committed_sources = self.committed_shared_sources()?;
        reject_symlinked_storage_parent(&self.private_cards)?;
        Self::load_directory(
            &self.shared_cards,
            CardOrigin::Shared,
            Some(&committed_sources),
            &mut report.cards,
            &mut report.diagnostics,
            false,
        )?;
        Self::load_directory(
            &self.private_cards,
            CardOrigin::Private,
            None,
            &mut report.cards,
            &mut report.diagnostics,
            false,
        )?;
        report.cards.sort_by(|left, right| {
            left.document
                .card
                .id
                .cmp(&right.document.card.id)
                .then_with(|| left.path.cmp(&right.path))
        });
        record_duplicate_ids(&report.cards, &mut report.diagnostics);
        Ok(report)
    }

    /// Return the current commit object ID, or `None` before the first commit.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] when Git cannot be invoked or returns invalid UTF-8.
    pub fn head_commit(&self) -> Result<Option<String>, GitError> {
        let output = git_output(
            &self.root,
            [
                OsStr::new("rev-parse"),
                OsStr::new("--verify"),
                OsStr::new("HEAD"),
            ],
        )?;
        if !output.status.success() {
            return Ok(None);
        }
        let value = String::from_utf8(output.stdout).map_err(|_| GitError::Utf8)?;
        Ok(Some(value.trim().to_owned()))
    }

    /// Return the repository-local Git author name when configured.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] when Git cannot be invoked or returns invalid UTF-8.
    pub fn author_name(&self) -> Result<Option<String>, GitError> {
        let output = git_output(
            &self.root,
            [
                OsStr::new("config"),
                OsStr::new("--get"),
                OsStr::new("user.name"),
            ],
        )?;
        if !output.status.success() || output.stdout.is_empty() {
            return Ok(None);
        }
        let value = String::from_utf8(output.stdout).map_err(|_| GitError::Utf8)?;
        Ok(Some(value.trim().to_owned()))
    }

    /// Read Git's last-touch provenance for a shared card.
    ///
    /// Uncommitted cards return `Ok(None)`.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] when Git cannot be invoked or emits invalid output.
    pub fn provenance(&self, path: &Path) -> Result<Option<Provenance>, GitError> {
        let head = git_output(
            &self.root,
            [
                OsStr::new("rev-parse"),
                OsStr::new("--verify"),
                OsStr::new("HEAD"),
            ],
        )?;
        if !head.status.success() {
            return Ok(None);
        }
        let relative = path.strip_prefix(&self.root).unwrap_or(path);
        let output = git_output(
            &self.root,
            [
                OsStr::new("log"),
                OsStr::new("-1"),
                OsStr::new("--format=%H%x00%an%x00%aI"),
                OsStr::new("--"),
                relative.as_os_str(),
            ],
        )?;
        if !output.status.success() {
            return Err(command_error(&output));
        }
        if output.stdout.is_empty() {
            return Ok(None);
        }
        let text = String::from_utf8(output.stdout).map_err(|_| GitError::Utf8)?;
        let mut fields = text.trim_end().split('\0');
        let (Some(commit), Some(author), Some(authored_at)) =
            (fields.next(), fields.next(), fields.next())
        else {
            return Err(GitError::Command("unexpected provenance output".to_owned()));
        };
        Ok(Some(Provenance {
            commit: commit.to_owned(),
            author: author.to_owned(),
            authored_at: authored_at.to_owned(),
        }))
    }

    #[allow(
        clippy::too_many_lines,
        reason = "bounded filesystem inspection and quarantine decisions stay linear and auditable"
    )]
    fn load_directory(
        directory: &Path,
        origin: CardOrigin,
        committed_sources: Option<&BTreeMap<PathBuf, Vec<u8>>>,
        cards: &mut Vec<LoadedCard>,
        diagnostics: &mut Vec<LoadDiagnostic>,
        strict: bool,
    ) -> Result<(), GitError> {
        match fs::symlink_metadata(directory) {
            Ok(metadata) if metadata.file_type().is_dir() => {}
            Ok(_) => return Err(GitError::UnsafeCardDirectory(directory.to_owned())),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(source) => {
                return Err(GitError::Io {
                    action: "cannot inspect card directory",
                    path: directory.to_owned(),
                    source,
                });
            }
        }
        let entries = match fs::read_dir(directory) {
            Ok(entries) => entries,
            Err(source) => {
                return Err(GitError::Io {
                    action: "cannot read card directory",
                    path: directory.to_owned(),
                    source,
                });
            }
        };
        let mut paths = Vec::new();
        for (index, entry) in entries.enumerate() {
            if index >= MAX_DIRECTORY_ENTRIES {
                return Err(GitError::TooManyEntries);
            }
            paths.push(
                entry
                    .map_err(|source| GitError::Io {
                        action: "cannot read card directory entry",
                        path: directory.to_owned(),
                        source,
                    })?
                    .path(),
            );
        }
        paths.sort();
        let mut source_bytes = 0_u64;
        let initial_card_count = cards.len();
        for path in paths {
            let metadata = fs::symlink_metadata(&path).map_err(|source| GitError::Io {
                action: "cannot inspect card",
                path: path.clone(),
                source,
            })?;
            if !metadata.file_type().is_file()
                || path.extension().and_then(OsStr::to_str) != Some("md")
            {
                continue;
            }
            if cards.len().saturating_sub(initial_card_count) >= MAX_CARDS {
                return Err(GitError::TooManyCards);
            }
            source_bytes = source_bytes.saturating_add(metadata.len());
            if source_bytes > MAX_SOURCE_BYTES {
                return Err(GitError::TooManySourceBytes);
            }
            if metadata.len() > u64::try_from(MAX_CARD_BYTES).unwrap_or(u64::MAX) {
                if strict {
                    return Err(GitError::Parse {
                        path: path.clone(),
                        source: ParseError::TooLarge {
                            actual: usize::try_from(metadata.len()).unwrap_or(usize::MAX),
                            maximum: MAX_CARD_BYTES,
                        },
                    });
                }
                diagnostics.push(LoadDiagnostic {
                    path,
                    message: format!(
                        "card is {} bytes; maximum is {MAX_CARD_BYTES} bytes",
                        metadata.len()
                    ),
                });
                continue;
            }
            let bytes = fs::read(&path).map_err(|source| GitError::Io {
                action: "cannot read card",
                path: path.clone(),
                source,
            })?;
            let committed = committed_sources
                .and_then(|sources| sources.get(&path))
                .is_some_and(|source| source == &bytes);
            let text = match String::from_utf8(bytes) {
                Ok(text) => text,
                Err(_) if strict => return Err(GitError::Utf8),
                Err(_) => {
                    diagnostics.push(LoadDiagnostic {
                        path,
                        message: "card is not valid UTF-8".to_owned(),
                    });
                    continue;
                }
            };
            let document = match parse_card(&text) {
                Ok(document) => document,
                Err(source) if strict => {
                    return Err(GitError::Parse {
                        path: path.clone(),
                        source,
                    });
                }
                Err(source) => {
                    diagnostics.push(LoadDiagnostic {
                        path,
                        message: source.to_string(),
                    });
                    continue;
                }
            };
            if path.file_stem().and_then(OsStr::to_str) != Some(&document.card.id) {
                if strict {
                    return Err(GitError::IdFilename {
                        path,
                        id: document.card.id,
                    });
                }
                diagnostics.push(LoadDiagnostic {
                    path,
                    message: format!(
                        "declared id `{}` must match the Markdown filename",
                        document.card.id
                    ),
                });
                continue;
            }
            cards.push(LoadedCard {
                document,
                committed,
                path,
                origin,
            });
        }
        Ok(())
    }

    fn committed_shared_sources(&self) -> Result<BTreeMap<PathBuf, Vec<u8>>, GitError> {
        if self.head_commit()?.is_none() {
            return Ok(BTreeMap::new());
        }
        let output = bounded_git_output(
            &self.root,
            [
                OsStr::new("ls-tree"),
                OsStr::new("-z"),
                OsStr::new("HEAD"),
                OsStr::new("--"),
                OsStr::new(".fixcards/"),
            ],
        )?;
        if !output.status.success() {
            return Err(command_error(&output));
        }
        let mut objects = Vec::new();
        for (index, record) in output
            .stdout
            .split(|byte| *byte == 0)
            .filter(|item| !item.is_empty())
            .enumerate()
        {
            if index >= MAX_DIRECTORY_ENTRIES {
                return Err(GitError::TooManyEntries);
            }
            let Some(tab) = record.iter().position(|byte| *byte == b'\t') else {
                return Err(GitError::Command("unexpected ls-tree output".to_owned()));
            };
            let header = std::str::from_utf8(&record[..tab]).map_err(|_| GitError::Utf8)?;
            let mut fields = header.split_ascii_whitespace();
            let (_mode, Some(kind), Some(object)) = (fields.next(), fields.next(), fields.next())
            else {
                return Err(GitError::Command("unexpected ls-tree output".to_owned()));
            };
            if kind != "blob" {
                continue;
            }
            let relative = std::str::from_utf8(&record[tab + 1..]).map_err(|_| GitError::Utf8)?;
            let relative_path = Path::new(relative);
            if relative_path.parent() == Some(Path::new(SHARED_CARDS_DIR))
                && relative_path.extension().and_then(OsStr::to_str) == Some("md")
            {
                if objects.len() >= MAX_CARDS {
                    return Err(GitError::TooManyCards);
                }
                let path = self.root.join(relative_path);
                let Ok(metadata) = fs::symlink_metadata(&path) else {
                    continue;
                };
                if !metadata.file_type().is_file()
                    || metadata.len() > u64::try_from(MAX_CARD_BYTES).unwrap_or(u64::MAX)
                {
                    continue;
                }
                objects.push((path, object.to_owned()));
            }
        }
        read_git_blobs(&self.root, &objects)
    }
}

/// Load cards from a per-user application-data directory.
///
/// # Errors
///
/// Returns [`GitError`] for unsafe storage, malformed cards, duplicate IDs, or
/// resource-limit violations.
pub fn load_user_cards(directory: &Path) -> Result<Vec<LoadedCard>, GitError> {
    let mut cards = Vec::new();
    let mut diagnostics = Vec::new();
    reject_symlinked_storage_parent(directory)?;
    Repository::load_directory(
        directory,
        CardOrigin::User,
        None,
        &mut cards,
        &mut diagnostics,
        true,
    )?;
    cards.sort_by(|left, right| left.document.card.id.cmp(&right.document.card.id));
    reject_duplicate_ids(&cards)?;
    Ok(cards)
}

/// Load valid user-global cards while quarantining malformed cards.
///
/// # Errors
///
/// Returns [`GitError`] for unsafe storage, I/O failures, or resource limits.
pub fn load_user_cards_resilient(directory: &Path) -> Result<LoadReport, GitError> {
    let mut report = LoadReport::default();
    reject_symlinked_storage_parent(directory)?;
    Repository::load_directory(
        directory,
        CardOrigin::User,
        None,
        &mut report.cards,
        &mut report.diagnostics,
        false,
    )?;
    report
        .cards
        .sort_by(|left, right| left.document.card.id.cmp(&right.document.card.id));
    record_duplicate_ids(&report.cards, &mut report.diagnostics);
    Ok(report)
}

fn reject_symlinked_storage_parent(directory: &Path) -> Result<(), GitError> {
    let Some(parent) = directory.parent() else {
        return Ok(());
    };
    match fs::symlink_metadata(parent) {
        Ok(metadata) if metadata.file_type().is_dir() => Ok(()),
        Ok(_) => Err(GitError::UnsafeCardDirectory(parent.to_owned())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(source) => Err(GitError::Io {
            action: "cannot inspect card storage parent",
            path: parent.to_owned(),
            source,
        }),
    }
}

fn reject_duplicate_ids(cards: &[LoadedCard]) -> Result<(), GitError> {
    let mut seen = BTreeSet::new();
    for (index, card) in cards.iter().enumerate() {
        if !seen.insert(card.document.card.id.clone()) {
            let first = cards[..index]
                .iter()
                .find(|prior| prior.document.card.id == card.document.card.id)
                .map(|prior| prior.path.clone())
                .unwrap_or_default();
            return Err(GitError::DuplicateId {
                id: card.document.card.id.clone(),
                first,
                second: card.path.clone(),
            });
        }
    }
    Ok(())
}

fn record_duplicate_ids(cards: &[LoadedCard], diagnostics: &mut Vec<LoadDiagnostic>) {
    let mut seen = BTreeMap::<&str, &Path>::new();
    for card in cards {
        if let Some(first) = seen.insert(&card.document.card.id, &card.path) {
            diagnostics.push(LoadDiagnostic {
                path: card.path.clone(),
                message: format!(
                    "duplicate id `{}` also exists at `{}`; use a scoped card reference",
                    card.document.card.id,
                    first.display()
                ),
            });
        }
    }
}

fn read_git_blobs(
    directory: &Path,
    objects: &[(PathBuf, String)],
) -> Result<BTreeMap<PathBuf, Vec<u8>>, GitError> {
    let objects = readable_git_blobs(directory, objects)?;
    if objects.is_empty() {
        return Ok(BTreeMap::new());
    }
    let (mut child, mut stdin, mut stdout, stderr_thread) = start_git_batch(directory, "--batch")?;
    let result = (|| -> Result<BTreeMap<PathBuf, Vec<u8>>, GitError> {
        let mut sources = BTreeMap::new();
        for (path, object, expected_size) in &objects {
            request_git_object(&mut stdin, object, directory)?;
            let (returned, kind, size) = read_git_header(&mut stdout, path)?;
            if returned != *object || kind != "blob" || size != *expected_size {
                return Err(GitError::Command(
                    "Git object changed between metadata and content reads".to_owned(),
                ));
            }
            let mut bytes = vec![0; size];
            stdout
                .read_exact(&mut bytes)
                .map_err(|source| GitError::Io {
                    action: "cannot read committed card bytes",
                    path: path.clone(),
                    source,
                })?;
            let mut newline = [0_u8; 1];
            stdout
                .read_exact(&mut newline)
                .map_err(|source| GitError::Io {
                    action: "cannot finish committed card read",
                    path: path.clone(),
                    source,
                })?;
            if newline != [b'\n'] {
                return Err(GitError::Command(
                    "unexpected cat-file delimiter".to_owned(),
                ));
            }
            sources.insert(path.clone(), bytes);
        }
        Ok(sources)
    })();
    drop(stdin);
    drop(stdout);
    if result.is_err() {
        terminate_child(&mut child);
        let _ = stderr_thread.join();
        return result;
    }
    finish_git_child(&mut child, stderr_thread, directory)?;
    result
}

fn readable_git_blobs(
    directory: &Path,
    objects: &[(PathBuf, String)],
) -> Result<Vec<(PathBuf, String, usize)>, GitError> {
    if objects.is_empty() {
        return Ok(Vec::new());
    }
    let (mut child, mut stdin, mut stdout, stderr_thread) =
        start_git_batch(directory, "--batch-check")?;
    let result = (|| -> Result<Vec<(PathBuf, String, usize)>, GitError> {
        let mut readable = Vec::new();
        let mut aggregate = 0_u64;
        for (path, object) in objects {
            request_git_object(&mut stdin, object, directory)?;
            let (returned, kind, size) = read_git_header(&mut stdout, path)?;
            if returned != *object || kind != "blob" {
                return Err(GitError::Command("unexpected cat-file object".to_owned()));
            }
            if size > MAX_CARD_BYTES {
                continue;
            }
            aggregate = aggregate.saturating_add(u64::try_from(size).unwrap_or(u64::MAX));
            if aggregate > MAX_SOURCE_BYTES {
                return Err(GitError::TooManySourceBytes);
            }
            readable.push((path.clone(), object.clone(), size));
        }
        Ok(readable)
    })();
    drop(stdin);
    drop(stdout);
    if result.is_err() {
        terminate_child(&mut child);
        let _ = stderr_thread.join();
        return result;
    }
    finish_git_child(&mut child, stderr_thread, directory)?;
    result
}

type StderrThread = thread::JoinHandle<std::io::Result<Vec<u8>>>;

fn start_git_batch(
    directory: &Path,
    mode: &str,
) -> Result<(Child, ChildStdin, BufReader<ChildStdout>, StderrThread), GitError> {
    let mut child = Command::new("git")
        .args(["cat-file", mode])
        .current_dir(directory)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("LC_ALL", "C")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|source| GitError::Io {
            action: "cannot run Git",
            path: directory.to_owned(),
            source,
        })?;
    let Some(stdin) = child.stdin.take() else {
        terminate_child(&mut child);
        return Err(GitError::Command(
            "cannot open git cat-file standard input".to_owned(),
        ));
    };
    let Some(stdout) = child.stdout.take() else {
        terminate_child(&mut child);
        return Err(GitError::Command(
            "cannot open git cat-file standard output".to_owned(),
        ));
    };
    let Some(stderr) = child.stderr.take() else {
        terminate_child(&mut child);
        return Err(GitError::Command(
            "cannot open git cat-file standard error".to_owned(),
        ));
    };
    let stderr_thread = thread::spawn(move || read_bounded_stderr(stderr));
    Ok((child, stdin, BufReader::new(stdout), stderr_thread))
}

fn request_git_object(
    stdin: &mut ChildStdin,
    object: &str,
    directory: &Path,
) -> Result<(), GitError> {
    writeln!(stdin, "{object}")
        .and_then(|()| stdin.flush())
        .map_err(|source| GitError::Io {
            action: "cannot request committed card bytes",
            path: directory.to_owned(),
            source,
        })
}

fn read_git_header(
    reader: &mut BufReader<ChildStdout>,
    path: &Path,
) -> Result<(String, String, usize), GitError> {
    let mut header = String::new();
    reader
        .read_line(&mut header)
        .map_err(|source| GitError::Io {
            action: "cannot read committed card metadata",
            path: path.to_owned(),
            source,
        })?;
    let mut fields = header.split_ascii_whitespace();
    let (Some(object), Some(kind), Some(size), None) =
        (fields.next(), fields.next(), fields.next(), fields.next())
    else {
        return Err(GitError::Command("unexpected cat-file output".to_owned()));
    };
    let size = size
        .parse::<usize>()
        .map_err(|_| GitError::Command("invalid object size from git cat-file".to_owned()))?;
    Ok((object.to_owned(), kind.to_owned(), size))
}

fn finish_git_child(
    child: &mut Child,
    stderr_thread: StderrThread,
    directory: &Path,
) -> Result<(), GitError> {
    let status = match child.wait() {
        Ok(status) => status,
        Err(source) => {
            terminate_child(child);
            let _ = stderr_thread.join();
            return Err(GitError::Io {
                action: "cannot finish Git command",
                path: directory.to_owned(),
                source,
            });
        }
    };
    let stderr = join_stderr(stderr_thread, directory)?;
    if status.success() {
        Ok(())
    } else {
        Err(command_error(&Output {
            status,
            stdout: Vec::new(),
            stderr,
        }))
    }
}

fn bounded_git_output<I, S>(directory: &Path, args: I) -> Result<Output, GitError>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let mut child = Command::new("git")
        .args(args)
        .current_dir(directory)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("LC_ALL", "C")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|source| GitError::Io {
            action: "cannot run Git",
            path: directory.to_owned(),
            source,
        })?;
    let Some(mut stdout) = child.stdout.take() else {
        terminate_child(&mut child);
        return Err(GitError::Command(
            "cannot open Git standard output".to_owned(),
        ));
    };
    let Some(stderr) = child.stderr.take() else {
        terminate_child(&mut child);
        return Err(GitError::Command(
            "cannot open Git standard error".to_owned(),
        ));
    };
    let stderr_thread = thread::spawn(move || read_bounded_stderr(stderr));
    let mut stdout_bytes = Vec::new();
    if let Err(source) = stdout
        .by_ref()
        .take(MAX_GIT_TREE_BYTES + 1)
        .read_to_end(&mut stdout_bytes)
    {
        terminate_child(&mut child);
        let _ = stderr_thread.join();
        return Err(GitError::Io {
            action: "cannot read Git output",
            path: directory.to_owned(),
            source,
        });
    }
    if u64::try_from(stdout_bytes.len()).unwrap_or(u64::MAX) > MAX_GIT_TREE_BYTES {
        terminate_child(&mut child);
        let _ = stderr_thread.join();
        return Err(GitError::TooMuchGitMetadata);
    }
    let status = match child.wait() {
        Ok(status) => status,
        Err(source) => {
            terminate_child(&mut child);
            let _ = stderr_thread.join();
            return Err(GitError::Io {
                action: "cannot finish Git command",
                path: directory.to_owned(),
                source,
            });
        }
    };
    let stderr = join_stderr(stderr_thread, directory)?;
    Ok(Output {
        status,
        stdout: stdout_bytes,
        stderr,
    })
}

fn join_stderr(
    thread: thread::JoinHandle<std::io::Result<Vec<u8>>>,
    directory: &Path,
) -> Result<Vec<u8>, GitError> {
    thread
        .join()
        .map_err(|_| GitError::Command("Git stderr reader panicked".to_owned()))?
        .map_err(|source| GitError::Io {
            action: "cannot read Git standard error",
            path: directory.to_owned(),
            source,
        })
}

fn terminate_child(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn read_bounded_stderr<R: Read>(mut reader: R) -> std::io::Result<Vec<u8>> {
    let mut stored = Vec::new();
    let mut buffer = [0_u8; 8 * 1024];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            return Ok(stored);
        }
        let remaining = MAX_GIT_STDERR_BYTES.saturating_sub(stored.len());
        stored.extend_from_slice(&buffer[..read.min(remaining)]);
    }
}

fn git_path(start: &Path, args: &[&str]) -> Result<PathBuf, GitError> {
    let output = git_output(start, args.iter().map(OsStr::new))?;
    if !output.status.success() {
        return Err(command_error(&output));
    }
    path_from_output(output)
}

fn path_from_output(output: Output) -> Result<PathBuf, GitError> {
    let text = String::from_utf8(output.stdout).map_err(|_| GitError::Utf8)?;
    let path = text.trim();
    if path.is_empty() {
        return Err(GitError::Command("Git returned an empty path".to_owned()));
    }
    Ok(PathBuf::from(path))
}

fn git_output<I, S>(directory: &Path, args: I) -> Result<Output, GitError>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    bounded_git_output(directory, args)
}

fn command_error(output: &Output) -> GitError {
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    GitError::Command(if stderr.is_empty() {
        format!("Git exited with {}", output.status)
    } else {
        stderr
    })
}

#[cfg(test)]
#[allow(
    clippy::panic,
    reason = "test setup failures should include operation context"
)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn repository() -> (TempDir, Repository) {
        let temp = TempDir::new().unwrap_or_else(|error| panic!("tempdir: {error}"));
        let status = Command::new("git")
            .args(["init", "-q"])
            .current_dir(temp.path())
            .status()
            .unwrap_or_else(|error| panic!("git init: {error}"));
        assert!(status.success());
        let repository =
            Repository::discover(temp.path()).unwrap_or_else(|error| panic!("discover: {error}"));
        (temp, repository)
    }

    fn card(id: &str) -> String {
        format!(
            "---\nfixcard: 1\nid: {id}\ntitle: Fix build\nmatch:\n  exact: [E_BUILD]\nrisk: low\ncreated: 2026-08-03\n---\n## What worked here\n\nRebuild.\n"
        )
    }

    fn git(directory: &Path, args: &[&str]) {
        let status = Command::new("git")
            .args(args)
            .current_dir(directory)
            .status()
            .unwrap_or_else(|error| panic!("git {args:?}: {error}"));
        assert!(status.success(), "git command failed: {args:?}");
    }

    #[test]
    fn discovers_repository_from_nested_directory() {
        let (temp, repository) = repository();
        let nested = temp.path().join("a/b");
        fs::create_dir_all(&nested).unwrap_or_else(|error| panic!("mkdir: {error}"));
        let nested_repository =
            Repository::discover(&nested).unwrap_or_else(|error| panic!("discover: {error}"));
        assert_eq!(nested_repository.root, repository.root);
    }

    #[test]
    fn loads_shared_and_private_cards() {
        let (_temp, repository) = repository();
        fs::create_dir_all(&repository.shared_cards)
            .unwrap_or_else(|error| panic!("mkdir shared: {error}"));
        fs::create_dir_all(&repository.private_cards)
            .unwrap_or_else(|error| panic!("mkdir private: {error}"));
        fs::write(repository.shared_cards.join("shared.md"), card("shared"))
            .unwrap_or_else(|error| panic!("write shared: {error}"));
        fs::write(repository.private_cards.join("private.md"), card("private"))
            .unwrap_or_else(|error| panic!("write private: {error}"));
        let cards = repository
            .load_cards()
            .unwrap_or_else(|error| panic!("load: {error}"));
        assert_eq!(cards.len(), 2);
        assert!(cards.iter().any(|item| item.origin == CardOrigin::Shared));
        assert!(cards.iter().any(|item| item.origin == CardOrigin::Private));
        assert!(cards.iter().all(|item| !item.committed));
    }

    #[test]
    fn only_exact_head_bytes_are_committed() {
        let (temp, repository) = repository();
        fs::create_dir_all(&repository.shared_cards)
            .unwrap_or_else(|error| panic!("mkdir shared: {error}"));
        let path = repository.shared_cards.join("shared.md");
        let original = card("shared");
        fs::write(&path, &original).unwrap_or_else(|error| panic!("write shared: {error}"));

        assert!(!repository.load_cards().unwrap_or_default()[0].committed);
        git(temp.path(), &["add", ".fixcards/shared.md"]);
        assert!(!repository.load_cards().unwrap_or_default()[0].committed);
        git(
            temp.path(),
            &[
                "-c",
                "user.name=Fixcard Test",
                "-c",
                "user.email=fixcard@example.invalid",
                "commit",
                "-q",
                "-m",
                "add reviewed card",
            ],
        );
        assert!(repository.load_cards().unwrap_or_default()[0].committed);

        fs::write(&path, card("shared").replace("Rebuild.", "Rebuild twice."))
            .unwrap_or_else(|error| panic!("modify shared: {error}"));
        assert!(!repository.load_cards().unwrap_or_default()[0].committed);
        git(temp.path(), &["add", ".fixcards/shared.md"]);
        assert!(!repository.load_cards().unwrap_or_default()[0].committed);
        fs::write(&path, original).unwrap_or_else(|error| panic!("restore shared: {error}"));
        assert!(repository.load_cards().unwrap_or_default()[0].committed);
    }

    #[test]
    fn oversized_committed_blob_is_never_loaded_for_provenance() {
        let (temp, repository) = repository();
        fs::create_dir_all(&repository.shared_cards)
            .unwrap_or_else(|error| panic!("mkdir shared: {error}"));
        let path = repository.shared_cards.join("oversized.md");
        fs::write(&path, vec![b'x'; MAX_CARD_BYTES + 1])
            .unwrap_or_else(|error| panic!("write oversized card: {error}"));
        git(temp.path(), &["add", ".fixcards/oversized.md"]);
        git(
            temp.path(),
            &[
                "-c",
                "user.name=Fixcard Test",
                "-c",
                "user.email=fixcard@example.invalid",
                "commit",
                "-q",
                "-m",
                "add hostile oversized card",
            ],
        );
        fs::write(&path, card("oversized"))
            .unwrap_or_else(|error| panic!("replace oversized working card: {error}"));

        let report = repository
            .load_cards_resilient()
            .unwrap_or_else(|error| panic!("resilient load: {error}"));
        assert_eq!(report.cards.len(), 1);
        assert_eq!(report.cards[0].document.card.id, "oversized");
        assert!(!report.cards[0].committed);
    }

    #[test]
    fn oversized_or_nested_committed_cards_do_not_hide_a_valid_card() {
        let (temp, repository) = repository();
        fs::create_dir_all(repository.shared_cards.join("nested"))
            .unwrap_or_else(|error| panic!("mkdir shared: {error}"));
        fs::write(repository.shared_cards.join("valid.md"), card("valid"))
            .unwrap_or_else(|error| panic!("write valid card: {error}"));
        fs::write(
            repository.shared_cards.join("oversized.md"),
            vec![b'x'; MAX_CARD_BYTES + 1],
        )
        .unwrap_or_else(|error| panic!("write oversized card: {error}"));
        fs::write(
            repository.shared_cards.join("nested/ignored.md"),
            vec![b'x'; MAX_CARD_BYTES + 1],
        )
        .unwrap_or_else(|error| panic!("write nested card: {error}"));
        git(temp.path(), &["add", ".fixcards"]);
        git(
            temp.path(),
            &[
                "-c",
                "user.name=Fixcard Test",
                "-c",
                "user.email=fixcard@example.invalid",
                "commit",
                "-q",
                "-m",
                "add mixed cards",
            ],
        );

        let report = repository
            .load_cards_resilient()
            .unwrap_or_else(|error| panic!("resilient load: {error}"));
        assert_eq!(report.cards.len(), 1);
        assert_eq!(report.cards[0].document.card.id, "valid");
        assert!(report.cards[0].committed);
        assert_eq!(report.diagnostics.len(), 1);
        assert!(report.diagnostics[0].message.contains("maximum"));
    }

    #[test]
    fn large_batch_makes_progress_without_filling_git_pipes() {
        let (temp, repository) = repository();
        fs::create_dir_all(&repository.shared_cards)
            .unwrap_or_else(|error| panic!("mkdir shared: {error}"));
        fs::write(repository.shared_cards.join("valid.md"), card("valid"))
            .unwrap_or_else(|error| panic!("write valid card: {error}"));
        git(temp.path(), &["add", ".fixcards/valid.md"]);
        git(
            temp.path(),
            &[
                "-c",
                "user.name=Fixcard Test",
                "-c",
                "user.email=fixcard@example.invalid",
                "commit",
                "-q",
                "-m",
                "add valid card",
            ],
        );
        let output = git_output(temp.path(), ["rev-parse", "HEAD:.fixcards/valid.md"])
            .unwrap_or_else(|error| panic!("resolve object: {error}"));
        assert!(output.status.success());
        let object = String::from_utf8(output.stdout)
            .unwrap_or_else(|error| panic!("object utf8: {error}"))
            .trim()
            .to_owned();
        let objects = (0..2_000)
            .map(|index| {
                (
                    repository.shared_cards.join(format!("card-{index}.md")),
                    object.clone(),
                )
            })
            .collect::<Vec<_>>();

        let sources = read_git_blobs(temp.path(), &objects)
            .unwrap_or_else(|error| panic!("read large batch: {error}"));
        assert_eq!(sources.len(), objects.len());
    }

    #[test]
    fn resilient_loading_quarantines_oversized_working_card_without_reading_it() {
        let (_temp, repository) = repository();
        fs::create_dir_all(&repository.shared_cards)
            .unwrap_or_else(|error| panic!("mkdir shared: {error}"));
        fs::write(
            repository.shared_cards.join("oversized.md"),
            vec![b'x'; MAX_CARD_BYTES + 1],
        )
        .unwrap_or_else(|error| panic!("write oversized card: {error}"));

        let report = repository
            .load_cards_resilient()
            .unwrap_or_else(|error| panic!("resilient load: {error}"));
        assert!(report.cards.is_empty());
        assert_eq!(report.diagnostics.len(), 1);
        assert!(report.diagnostics[0].message.contains("maximum"));
    }

    #[cfg(unix)]
    #[test]
    fn ignores_symlinked_cards() {
        use std::os::unix::fs::symlink;
        let (temp, repository) = repository();
        fs::create_dir_all(&repository.shared_cards)
            .unwrap_or_else(|error| panic!("mkdir: {error}"));
        let outside = temp.path().join("outside.md");
        fs::write(&outside, card("outside")).unwrap_or_else(|error| panic!("write: {error}"));
        symlink(&outside, repository.shared_cards.join("outside.md"))
            .unwrap_or_else(|error| panic!("symlink: {error}"));
        assert!(repository.load_cards().unwrap_or_default().is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn refuses_a_symlinked_card_directory() {
        use std::os::unix::fs::symlink;
        let (temp, repository) = repository();
        let outside = temp.path().join("outside-cards");
        fs::create_dir(&outside).unwrap_or_else(|error| panic!("mkdir outside: {error}"));
        fs::write(outside.join("outside.md"), card("outside"))
            .unwrap_or_else(|error| panic!("write outside card: {error}"));
        symlink(&outside, &repository.shared_cards)
            .unwrap_or_else(|error| panic!("symlink card directory: {error}"));

        assert!(matches!(
            repository.load_cards(),
            Err(GitError::UnsafeCardDirectory(path)) if path == repository.shared_cards
        ));
    }

    #[cfg(unix)]
    #[test]
    fn refuses_a_symlinked_card_storage_parent() {
        use std::os::unix::fs::symlink;
        let temp = TempDir::new().unwrap_or_else(|error| panic!("tempdir: {error}"));
        let outside = temp.path().join("outside");
        fs::create_dir(&outside).unwrap_or_else(|error| panic!("mkdir outside: {error}"));
        fs::create_dir(outside.join("cards"))
            .unwrap_or_else(|error| panic!("mkdir cards: {error}"));
        let parent = temp.path().join("fixcard");
        symlink(&outside, &parent).unwrap_or_else(|error| panic!("symlink parent: {error}"));
        let directory = parent.join("cards");

        assert!(matches!(
            load_user_cards_resilient(&directory),
            Err(GitError::UnsafeCardDirectory(path)) if path == parent
        ));
    }
}
