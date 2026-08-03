//! Worktree-safe repository discovery, storage paths, and Git provenance.

use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use fixcard_core::{CardOrigin, LoadedCard, ParseError, parse_card};
use thiserror::Error;

/// Directory containing repository-reviewed cards.
pub const SHARED_CARDS_DIR: &str = ".fixcards";

/// Directory containing private cards relative to Git's common directory.
pub const PRIVATE_CARDS_DIR: &str = "fixcard/cards";

/// Maximum number of cards loaded from one repository.
pub const MAX_CARDS: usize = 10_000;

/// Worktree and common-directory paths resolved by Git itself.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Repository {
    /// Top-level worktree directory.
    pub root: PathBuf,
    /// Shared Git directory, including linked-worktree layouts.
    pub common_dir: PathBuf,
    /// Repository-reviewed card directory.
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

/// Failure during bounded repository operations.
#[derive(Debug, Error)]
pub enum GitError {
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
}

impl Repository {
    /// Discover the repository containing `start` using worktree-aware Git APIs.
    ///
    /// # Errors
    ///
    /// Returns [`GitError`] outside a worktree, when Git is unavailable, or when
    /// Git returns unusable paths.
    pub fn discover(start: &Path) -> Result<Self, GitError> {
        let root = git_path(start, &["rev-parse", "--show-toplevel"])?;
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
        Self::load_directory(&self.shared_cards, CardOrigin::Shared, &mut cards)?;
        Self::load_directory(&self.private_cards, CardOrigin::Private, &mut cards)?;
        cards.sort_by(|left, right| left.document.card.id.cmp(&right.document.card.id));

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
        Ok(cards)
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

    fn load_directory(
        directory: &Path,
        origin: CardOrigin,
        cards: &mut Vec<LoadedCard>,
    ) -> Result<(), GitError> {
        let entries = match fs::read_dir(directory) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(source) => {
                return Err(GitError::Io {
                    action: "cannot read card directory",
                    path: directory.to_owned(),
                    source,
                });
            }
        };
        let mut paths = entries
            .map(|entry| {
                entry
                    .map(|value| value.path())
                    .map_err(|source| GitError::Io {
                        action: "cannot read card directory entry",
                        path: directory.to_owned(),
                        source,
                    })
            })
            .collect::<Result<Vec<_>, _>>()?;
        paths.sort();
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
            if cards.len() >= MAX_CARDS {
                return Err(GitError::TooManyCards);
            }
            let text = fs::read_to_string(&path).map_err(|source| GitError::Io {
                action: "cannot read card",
                path: path.clone(),
                source,
            })?;
            let document = parse_card(&text).map_err(|source| GitError::Parse {
                path: path.clone(),
                source,
            })?;
            if path.file_stem().and_then(OsStr::to_str) != Some(&document.card.id) {
                return Err(GitError::IdFilename {
                    path,
                    id: document.card.id,
                });
            }
            cards.push(LoadedCard {
                document,
                path,
                origin,
            });
        }
        Ok(())
    }
}

fn git_path(start: &Path, args: &[&str]) -> Result<PathBuf, GitError> {
    let output = git_output(start, args.iter().map(OsStr::new))?;
    if !output.status.success() {
        return Err(command_error(&output));
    }
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
    Command::new("git")
        .args(args)
        .current_dir(directory)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("LC_ALL", "C")
        .output()
        .map_err(|source| GitError::Io {
            action: "cannot run Git",
            path: directory.to_owned(),
            source,
        })
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
}
