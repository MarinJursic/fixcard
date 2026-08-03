//! Versioned Fixcard documents, normalization, and deterministic matching.

mod matching;
mod model;
mod normalize;
mod parser;

pub use matching::{Confidence, Environment, MatchEvidence, MatchResult, SearchOptions, search};
pub use model::{
    Applies, Card, CardDocument, CardOrigin, LoadedCard, MatchSpec, Risk, Verification,
};
pub use normalize::{NormalizedFailure, normalize_failure, sanitize_terminal};
pub use parser::{MAX_CARD_BYTES, ParseError, parse_card};

/// The only card schema understood by this release.
pub const SUPPORTED_SCHEMA_VERSION: u32 = 1;
