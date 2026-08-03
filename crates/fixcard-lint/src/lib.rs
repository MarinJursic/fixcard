//! Non-mutating diagnostics for card quality, privacy, and command risk.

/// Severity of a lint diagnostic.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum Severity {
    /// Advice that does not affect validity.
    Note,
    /// Suspicious content requiring human review.
    Warning,
    /// Invalid or unsafe content that blocks a team card by default.
    Error,
}
