use std::collections::BTreeMap;
use std::path::PathBuf;

use jiff::civil::Date;
use serde::{Deserialize, Serialize};
use serde_yaml_ng::Value;

/// A parsed Fixcard document.
#[derive(Clone, Debug, PartialEq)]
pub struct CardDocument {
    /// Structured YAML front matter.
    pub card: Card,
    /// Markdown following the front matter.
    pub body: String,
}

/// The structured v1 front matter.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct Card {
    /// Schema version.
    pub fixcard: u32,
    /// Portable lowercase identifier.
    pub id: String,
    /// Short human-readable resolution summary.
    pub title: String,
    /// Literal error anchors.
    #[serde(rename = "match")]
    pub match_spec: MatchSpec,
    /// Conditions in which the resolution is known to apply.
    #[serde(default)]
    pub applies: Applies,
    /// Author-declared risk level.
    pub risk: Risk,
    /// Optional observed validation.
    #[serde(default)]
    pub verified: Option<Verification>,
    /// Date on which validation was last observed.
    #[serde(default)]
    pub last_verified: Option<Date>,
    /// Creation date when no verification date exists.
    #[serde(default)]
    pub created: Option<Date>,
    /// Human-readable authorship identities.
    #[serde(default)]
    pub authors: Vec<String>,
    /// Card IDs replaced by this card.
    #[serde(default)]
    pub supersedes: Vec<String>,
    /// Card ID that replaces this card.
    #[serde(default)]
    pub superseded_by: Option<String>,
    /// Whether default search should omit this card.
    #[serde(default)]
    pub retired: bool,
    /// Required human explanation when retired.
    #[serde(default)]
    pub retirement_reason: Option<String>,
    /// Forward-compatible extension data using `x-` keys.
    #[serde(flatten)]
    pub extensions: BTreeMap<String, Value>,
}

/// Literal evidence used to match a failure.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MatchSpec {
    /// Stable literal anchors carrying the most weight.
    #[serde(default)]
    pub exact: Vec<String>,
    /// Additional case-insensitive literal fragments.
    #[serde(default)]
    pub contains: Vec<String>,
    /// Literal fragments that contradict this card.
    #[serde(default)]
    pub not_contains: Vec<String>,
}

/// Environment constraints attached to a card.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Applies {
    /// Supported operating-system identifiers.
    #[serde(default)]
    pub os: Vec<String>,
    /// Supported architecture identifiers.
    #[serde(default)]
    pub arch: Vec<String>,
    /// Tool name to semantic-version requirement.
    #[serde(default)]
    pub tools: BTreeMap<String, String>,
}

/// The risk stated by the author. Lint may raise the effective risk.
#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Risk {
    /// Read-only or readily reversible instructions.
    Low,
    /// Instructions that require deliberate review.
    Medium,
    /// Destructive, privileged, remote, or production-sensitive instructions.
    High,
}

/// A validation observation, never an execution instruction.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Verification {
    /// Command a human reported using for validation.
    pub command: String,
    /// Observed process exit status.
    #[serde(default)]
    pub exit_code: Option<i32>,
    /// Source Git object or unambiguous prefix.
    #[serde(default)]
    pub source_commit: Option<String>,
}

/// Where a card is stored.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CardOrigin {
    /// Stored under Git's common directory.
    Private,
    /// Stored in the repository's `.fixcards` directory.
    Shared,
    /// Stored in the operating system's per-user application-data directory.
    User,
}

/// A document with its local source information.
#[derive(Clone, Debug, PartialEq)]
pub struct LoadedCard {
    /// Parsed card document.
    pub document: CardDocument,
    /// File from which it was parsed.
    pub path: PathBuf,
    /// Private or repository origin.
    pub origin: CardOrigin,
    /// Whether the displayed bytes exactly match a tracked, committed card.
    pub committed: bool,
}
