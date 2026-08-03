//! Worktree-safe repository discovery, storage paths, and Git provenance.

/// Directory containing repository-reviewed cards.
pub const SHARED_CARDS_DIR: &str = ".fixcards";

/// Directory containing private cards relative to Git's common directory.
pub const PRIVATE_CARDS_DIR: &str = "fixcard/cards";
