use regex::Regex;
use std::sync::LazyLock;
use thiserror::Error;

use crate::{Card, CardDocument, SUPPORTED_SCHEMA_VERSION};

/// Maximum accepted card size. Large logs do not belong in cards.
pub const MAX_CARD_BYTES: usize = 256 * 1024;

static ID: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
        .unwrap_or_else(|error| unreachable!("static ID regex is valid: {error}"))
});

/// Failure to parse or validate a card document.
#[derive(Debug, Error)]
pub enum ParseError {
    /// The input exceeds the safety limit.
    #[error("card is {actual} bytes; maximum is {maximum} bytes")]
    TooLarge {
        /// Actual byte length.
        actual: usize,
        /// Maximum accepted length.
        maximum: usize,
    },
    /// Front-matter delimiters are missing or malformed.
    #[error("card must start with YAML front matter delimited by exact `---` lines")]
    MissingFrontMatter,
    /// YAML could not be decoded into the v1 model.
    #[error("invalid YAML front matter: {0}")]
    Yaml(#[from] serde_yaml_ng::Error),
    /// A semantic format rule was violated.
    #[error("invalid card: {0}")]
    Invalid(String),
}

/// Parse and semantically validate one UTF-8 Fixcard document.
///
/// # Errors
///
/// Returns [`ParseError`] when the document exceeds the size limit, has invalid
/// delimiters or YAML, uses an unsupported schema, or violates a v1 invariant.
pub fn parse_card(input: &str) -> Result<CardDocument, ParseError> {
    if input.len() > MAX_CARD_BYTES {
        return Err(ParseError::TooLarge {
            actual: input.len(),
            maximum: MAX_CARD_BYTES,
        });
    }

    let normalized = input.replace("\r\n", "\n");
    let rest = normalized
        .strip_prefix("---\n")
        .ok_or(ParseError::MissingFrontMatter)?;
    let (front_matter, body) = rest
        .split_once("\n---\n")
        .ok_or(ParseError::MissingFrontMatter)?;
    let card: Card = serde_yaml_ng::from_str(front_matter)?;
    validate(&card, body)?;

    Ok(CardDocument {
        card,
        body: body.to_owned(),
    })
}

fn validate(card: &Card, body: &str) -> Result<(), ParseError> {
    if card.fixcard != SUPPORTED_SCHEMA_VERSION {
        return Err(ParseError::Invalid(format!(
            "unsupported schema version {}; this binary supports {}",
            card.fixcard, SUPPORTED_SCHEMA_VERSION
        )));
    }
    if !ID.is_match(&card.id) {
        return Err(ParseError::Invalid(format!(
            "id `{}` is not a portable lowercase slug",
            card.id
        )));
    }
    let title_len = card.title.chars().count();
    if card.title.trim().is_empty() || title_len > 120 {
        return Err(ParseError::Invalid(
            "title must contain 1–120 characters".to_owned(),
        ));
    }
    if card
        .match_spec
        .exact
        .iter()
        .all(|value| value.trim().is_empty())
        && card
            .match_spec
            .contains
            .iter()
            .all(|value| value.trim().is_empty())
    {
        return Err(ParseError::Invalid(
            "at least one non-empty exact or contains anchor is required".to_owned(),
        ));
    }
    if card.created.is_none() && card.last_verified.is_none() {
        return Err(ParseError::Invalid(
            "created or last_verified is required".to_owned(),
        ));
    }
    if let Some(verification) = &card.verified
        && verification.command.trim().is_empty()
    {
        return Err(ParseError::Invalid(
            "verified.command cannot be empty".to_owned(),
        ));
    }
    if card.retired
        && card
            .retirement_reason
            .as_deref()
            .is_none_or(|reason| reason.trim().is_empty())
    {
        return Err(ParseError::Invalid(
            "retirement_reason is required when retired is true".to_owned(),
        ));
    }
    if card.extensions.keys().any(|key| !key.starts_with("x-")) {
        return Err(ParseError::Invalid(
            "unknown fields must use the `x-` extension prefix".to_owned(),
        ));
    }
    if !has_non_empty_section(body, "What worked here") {
        return Err(ParseError::Invalid(
            "Markdown body requires a non-empty `## What worked here` section".to_owned(),
        ));
    }
    Ok(())
}

fn has_non_empty_section(body: &str, heading: &str) -> bool {
    let marker = format!("## {heading}");
    let Some((_, following)) = body.split_once(&marker) else {
        return false;
    };
    let section = following
        .lines()
        .skip_while(|line| line.trim().is_empty())
        .take_while(|line| !line.starts_with("## "))
        .collect::<Vec<_>>()
        .join("\n");
    !section.trim().is_empty()
}

#[cfg(test)]
#[allow(
    clippy::panic,
    reason = "test failures should include parser diagnostics"
)]
mod tests {
    use super::*;

    const VALID: &str = r"---
fixcard: 1
id: build-failed
title: Rebuild the generated client
match:
  exact: [E_GENERATED_STALE]
risk: low
created: 2026-08-03
x-owner: platform
---
## What worked here

Run the repository generator and review its diff.
";

    #[test]
    fn parses_a_valid_extension() {
        let parsed = parse_card(VALID).unwrap_or_else(|error| panic!("parse failed: {error}"));
        assert_eq!(parsed.card.id, "build-failed");
        assert!(parsed.card.extensions.contains_key("x-owner"));
    }

    #[test]
    fn rejects_unknown_unprefixed_fields() {
        let input = VALID.replace("x-owner", "owner");
        assert!(parse_card(&input).is_err());
    }

    #[test]
    fn rejects_empty_resolution() {
        let input = VALID.replace(
            "Run the repository generator and review its diff.",
            "\n## Notes\nNothing",
        );
        assert!(parse_card(&input).is_err());
    }

    #[test]
    fn accepts_crlf() {
        assert!(parse_card(&VALID.replace('\n', "\r\n")).is_ok());
    }
}
