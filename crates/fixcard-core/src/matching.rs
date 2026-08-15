use std::collections::{BTreeMap, BTreeSet};

use jiff::civil::Date;
use semver::{Version, VersionReq};

use crate::{CardOrigin, LoadedCard, NormalizedFailure, normalize_failure};

/// Current environment used only to qualify recorded evidence.
#[derive(Clone, Debug, Default)]
pub struct Environment {
    /// Normalized operating-system identifier.
    pub os: Option<String>,
    /// Normalized CPU architecture.
    pub arch: Option<String>,
    /// Explicitly detected tool versions.
    pub tools: BTreeMap<String, Version>,
}

/// Search behavior shared by CLI and other implementations.
#[derive(Clone, Debug)]
pub struct SearchOptions {
    /// Include retired cards as weak candidates.
    pub include_retired: bool,
    /// Date used to assess staleness.
    pub today: Option<Date>,
    /// Age after which a card is visibly stale.
    pub stale_after_days: i64,
}

impl Default for SearchOptions {
    fn default() -> Self {
        Self {
            include_retired: false,
            today: None,
            stale_after_days: 365,
        }
    }
}

/// Conservative confidence class.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum Confidence {
    /// Insufficient evidence; never returned by default.
    Weak,
    /// Enough mutually compatible evidence for the default result.
    Strong,
}

/// Whether recorded tool constraints can be evaluated safely.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Applicability {
    /// Every recorded tool constraint has a supplied, parseable current value.
    Known,
    /// At least one constrained tool has no supplied current version.
    Unknown,
    /// At least one recorded tool constraint is not a valid semantic range.
    Invalid,
}

/// One human-readable contribution to a score.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MatchEvidence {
    /// Signed score contribution.
    pub points: i32,
    /// Concise deterministic reason.
    pub reason: String,
}

/// A ranked card with transparent evidence and trust flags.
#[derive(Clone, Debug)]
pub struct MatchResult<'a> {
    /// Source card.
    pub card: &'a LoadedCard,
    /// Total deterministic score.
    pub score: i32,
    /// Strong or weak classification.
    pub confidence: Confidence,
    /// Individual scoring contributions.
    pub evidence: Vec<MatchEvidence>,
    /// A current environment contradicts the card.
    pub version_mismatch: bool,
    /// Whether tool applicability is known, unknown, or invalid.
    pub applicability: Applicability,
    /// Recorded validation is older than policy.
    pub stale: bool,
}

/// Rank eligible cards against a raw failure.
#[must_use]
pub fn search<'a>(
    query: &str,
    cards: &'a [LoadedCard],
    environment: &Environment,
    options: &SearchOptions,
) -> Vec<MatchResult<'a>> {
    let normalized = normalize_failure(query);
    let mut results = cards
        .iter()
        .filter_map(|card| score_card(&normalized, card, environment, options))
        .collect::<Vec<_>>();
    results.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| origin_order(left.card.origin).cmp(&origin_order(right.card.origin)))
            .then_with(|| left.card.document.card.id.cmp(&right.card.document.card.id))
    });
    results
}

#[allow(
    clippy::too_many_lines,
    reason = "keeping the ordered scoring rules together makes the explanation auditable"
)]
fn score_card<'a>(
    query: &NormalizedFailure,
    loaded: &'a LoadedCard,
    environment: &Environment,
    options: &SearchOptions,
) -> Option<MatchResult<'a>> {
    let card = &loaded.document.card;
    let inactive = card.retired || card.superseded_by.is_some();
    if inactive && !options.include_retired {
        return None;
    }
    let mut score = 0;
    let mut evidence = Vec::new();
    let query_lower = query.text.as_str();

    for anchor in &card.match_spec.exact {
        let anchor_normalized = normalize_failure(anchor);
        if !anchor_normalized.text.is_empty()
            && exact_anchor_matches(query_lower, &anchor_normalized.text)
        {
            add(
                &mut score,
                &mut evidence,
                50,
                format!("exact anchor `{anchor}`"),
            );
        }
    }
    for anchor in &card.match_spec.contains {
        let anchor_normalized = normalize_failure(anchor);
        if !anchor_normalized.text.is_empty() && query_lower.contains(&anchor_normalized.text) {
            add(
                &mut score,
                &mut evidence,
                12,
                format!("contains anchor `{anchor}`"),
            );
        }
    }
    let negative = card.match_spec.not_contains.iter().find(|anchor| {
        let normalized = normalize_failure(anchor);
        !normalized.text.is_empty() && query_lower.contains(&normalized.text)
    });
    if let Some(anchor) = negative {
        add(
            &mut score,
            &mut evidence,
            -100,
            format!("negative condition `{anchor}`"),
        );
    }

    let card_tokens = card_tokens(loaded);
    let overlap = query.tokens.intersection(&card_tokens).count();
    let union = query.tokens.union(&card_tokens).count();
    if overlap > 0 && union > 0 {
        let points = i32::try_from((20 * overlap) / union).unwrap_or(20);
        add(
            &mut score,
            &mut evidence,
            points,
            format!("{overlap} diagnostic tokens overlap"),
        );
    }

    if loaded.committed {
        add(
            &mut score,
            &mut evidence,
            3,
            "repository-committed card".to_owned(),
        );
    }

    let mut version_mismatch = false;
    let mut applicability = Applicability::Known;
    compatibility(
        &card.applies.os,
        environment.os.as_deref(),
        "OS",
        &mut score,
        &mut evidence,
        &mut version_mismatch,
    );
    compatibility(
        &card.applies.arch,
        environment.arch.as_deref(),
        "architecture",
        &mut score,
        &mut evidence,
        &mut version_mismatch,
    );
    for (tool, requirement) in &card.applies.tools {
        let Some(required) = parse_requirement(requirement) else {
            applicability = Applicability::Invalid;
            add(
                &mut score,
                &mut evidence,
                -10,
                format!("invalid recorded requirement `{requirement}` for {tool}"),
            );
            continue;
        };
        let Some(current) = environment.tools.get(tool) else {
            if applicability == Applicability::Known {
                applicability = Applicability::Unknown;
            }
            add(
                &mut score,
                &mut evidence,
                0,
                format!("current {tool} version is unknown; card requires {requirement}"),
            );
            continue;
        };
        if required.matches(current) {
            add(
                &mut score,
                &mut evidence,
                5,
                format!("{tool} {current} satisfies {requirement}"),
            );
        } else {
            version_mismatch = true;
            add(
                &mut score,
                &mut evidence,
                -60,
                format!("{tool} {current} conflicts with {requirement}"),
            );
        }
    }

    let stale = options
        .today
        .zip(card.last_verified)
        .is_some_and(|(today, verified)| {
            days_from_civil(today) - days_from_civil(verified) > options.stale_after_days
        });
    if stale {
        add(
            &mut score,
            &mut evidence,
            -8,
            "validation is stale".to_owned(),
        );
    }
    if card.retired {
        add(&mut score, &mut evidence, -80, "card is retired".to_owned());
    }
    if let Some(replacement) = &card.superseded_by {
        add(
            &mut score,
            &mut evidence,
            -80,
            format!("card is superseded by `{replacement}`"),
        );
    }

    let has_exact = evidence.iter().any(|item| item.points == 50);
    let positive_anchor_count = evidence
        .iter()
        .filter(|item| matches!(item.points, 12 | 50))
        .count();
    if score <= 0 && positive_anchor_count == 0 {
        return None;
    }
    let confidence = if !version_mismatch
        && applicability == Applicability::Known
        && negative.is_none()
        && !inactive
        && ((has_exact && score >= 45) || (positive_anchor_count >= 2 && score >= 30))
    {
        Confidence::Strong
    } else {
        Confidence::Weak
    };

    Some(MatchResult {
        card: loaded,
        score,
        confidence,
        evidence,
        version_mismatch,
        applicability,
        stale,
    })
}

fn exact_anchor_matches(query: &str, anchor: &str) -> bool {
    if anchor
        .chars()
        .all(|character| character.is_alphanumeric() || matches!(character, '_' | '-'))
    {
        return query.match_indices(anchor).any(|(start, matched)| {
            let end = start + matched.len();
            let before_is_word = query[..start]
                .chars()
                .next_back()
                .is_some_and(is_anchor_character);
            let after_is_word = query[end..].chars().next().is_some_and(is_anchor_character);
            !before_is_word && !after_is_word
        });
    }
    query.contains(anchor)
}

fn is_anchor_character(character: char) -> bool {
    character.is_alphanumeric() || matches!(character, '_' | '-')
}

fn card_tokens(card: &LoadedCard) -> BTreeSet<String> {
    let source = format!(
        "{} {} {} {}",
        card.document.card.title,
        card.document.card.match_spec.exact.join(" "),
        card.document.card.match_spec.contains.join(" "),
        card.document.body
    );
    normalize_failure(&source).tokens
}

fn compatibility(
    supported: &[String],
    current: Option<&str>,
    label: &str,
    score: &mut i32,
    evidence: &mut Vec<MatchEvidence>,
    mismatch: &mut bool,
) {
    let Some(current) = current else { return };
    if supported.is_empty() {
        return;
    }
    if supported.iter().any(|value| value == current) {
        add(score, evidence, 3, format!("compatible {label}: {current}"));
    } else {
        *mismatch = true;
        add(
            score,
            evidence,
            -60,
            format!("{label} `{current}` is outside recorded conditions"),
        );
    }
}

fn parse_requirement(value: &str) -> Option<VersionReq> {
    let joined = value.split_whitespace().collect::<Vec<_>>().join(", ");
    VersionReq::parse(&joined).ok()
}

fn add(score: &mut i32, evidence: &mut Vec<MatchEvidence>, points: i32, reason: String) {
    *score += points;
    evidence.push(MatchEvidence { points, reason });
}

const fn origin_order(origin: CardOrigin) -> u8 {
    match origin {
        CardOrigin::Shared => 0,
        CardOrigin::Private => 1,
        CardOrigin::User => 2,
    }
}

fn days_from_civil(date: Date) -> i64 {
    let year = i64::from(date.year()) - i64::from(date.month() <= 2);
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let month = i64::from(date.month());
    let day_of_year =
        (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + i64::from(date.day()) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

#[cfg(test)]
#[allow(
    clippy::panic,
    reason = "test fixture construction should explain failures"
)]
mod tests {
    use super::*;
    use crate::{CardOrigin, LoadedCard, parse_card};
    use std::path::PathBuf;

    fn loaded(extra: &str) -> LoadedCard {
        let input = format!(
            r#"---
fixcard: 1
id: lockfile
title: Regenerate the lockfile
match:
  exact: [ERR_PNPM_OUTDATED_LOCKFILE]
  contains: [frozen-lockfile]
  not_contains: [permission denied]
applies:
  os: [macos, linux]
  tools:
    pnpm: ">=10 <11"
risk: low
last_verified: 2026-07-16
{extra}---
## What worked here

Use pnpm 10 to regenerate pnpm-lock.yaml.
"#
        );
        LoadedCard {
            document: parse_card(&input).unwrap_or_else(|error| panic!("fixture: {error}")),
            path: PathBuf::from("lockfile.md"),
            origin: CardOrigin::Shared,
            committed: true,
        }
    }

    #[test]
    fn exact_compatible_match_is_strong() {
        let cards = [loaded("")];
        let environment = Environment {
            os: Some("macos".to_owned()),
            tools: BTreeMap::from([("pnpm".to_owned(), Version::new(10, 13, 1))]),
            ..Environment::default()
        };
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE frozen-lockfile",
            &cards,
            &environment,
            &SearchOptions::default(),
        );
        assert_eq!(results[0].confidence, Confidence::Strong);
    }

    #[test]
    fn only_committed_shared_content_receives_the_review_bonus() {
        let mut card = loaded("");
        card.committed = false;
        let uncommitted = search(
            "ERR_PNPM_OUTDATED_LOCKFILE",
            std::slice::from_ref(&card),
            &Environment::default(),
            &SearchOptions::default(),
        );
        assert!(
            uncommitted[0]
                .evidence
                .iter()
                .all(|item| item.reason != "repository-committed card")
        );

        card.committed = true;
        let committed = search(
            "ERR_PNPM_OUTDATED_LOCKFILE",
            std::slice::from_ref(&card),
            &Environment::default(),
            &SearchOptions::default(),
        );
        assert!(
            committed[0]
                .evidence
                .iter()
                .any(|item| item.reason == "repository-committed card")
        );
    }

    #[test]
    fn version_conflict_forces_weak_result() {
        let cards = [loaded("")];
        let environment = Environment {
            tools: BTreeMap::from([("pnpm".to_owned(), Version::new(9, 9, 0))]),
            ..Environment::default()
        };
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE",
            &cards,
            &environment,
            &SearchOptions::default(),
        );
        assert_eq!(results[0].confidence, Confidence::Weak);
        assert!(results[0].version_mismatch);
    }

    #[test]
    fn unknown_constrained_tool_version_forces_weak_result() {
        let cards = [loaded("")];
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE",
            &cards,
            &Environment::default(),
            &SearchOptions::default(),
        );
        assert_eq!(results[0].confidence, Confidence::Weak);
        assert_eq!(results[0].applicability, Applicability::Unknown);
        assert!(results[0].evidence.iter().any(|item| {
            item.reason == "current pnpm version is unknown; card requires >=10 <11"
        }));
    }

    #[test]
    fn invalid_tool_requirement_forces_weak_despite_multiple_anchors() {
        let mut card = loaded("");
        card.document
            .card
            .applies
            .tools
            .insert("pnpm".to_owned(), "not-a-range".to_owned());
        let cards = [card];
        let environment = Environment {
            tools: BTreeMap::from([("pnpm".to_owned(), Version::new(10, 13, 1))]),
            ..Environment::default()
        };
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE frozen-lockfile",
            &cards,
            &environment,
            &SearchOptions::default(),
        );
        assert_eq!(results[0].confidence, Confidence::Weak);
        assert_eq!(results[0].applicability, Applicability::Invalid);

        let without_current_version = search(
            "ERR_PNPM_OUTDATED_LOCKFILE frozen-lockfile",
            &cards,
            &Environment::default(),
            &SearchOptions::default(),
        );
        assert_eq!(
            without_current_version[0].applicability,
            Applicability::Invalid
        );
    }

    #[test]
    fn negative_condition_forces_weak_result() {
        let cards = [loaded("")];
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE permission denied",
            &cards,
            &Environment::default(),
            &SearchOptions::default(),
        );
        assert_eq!(results[0].confidence, Confidence::Weak);
    }

    #[test]
    fn exact_anchor_does_not_match_a_longer_diagnostic_code() {
        let cards = [loaded("")];
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE_EXTRA",
            &cards,
            &Environment::default(),
            &SearchOptions::default(),
        );
        assert!(
            results
                .iter()
                .all(|result| result.confidence == Confidence::Weak)
        );
    }

    #[test]
    fn superseded_card_is_hidden_unless_inactive_cards_are_requested() {
        let cards = [loaded("superseded_by: replacement\n")];
        assert!(
            search(
                "ERR_PNPM_OUTDATED_LOCKFILE",
                &cards,
                &Environment::default(),
                &SearchOptions::default(),
            )
            .is_empty()
        );
        let options = SearchOptions {
            include_retired: true,
            ..SearchOptions::default()
        };
        let results = search(
            "ERR_PNPM_OUTDATED_LOCKFILE",
            &cards,
            &Environment::default(),
            &options,
        );
        assert_eq!(results[0].confidence, Confidence::Weak);
    }

    #[test]
    fn civil_day_conversion_has_expected_distance() {
        let older = "2025-08-03".parse().unwrap_or(Date::constant(2025, 8, 3));
        let newer = "2026-08-03".parse().unwrap_or(Date::constant(2026, 8, 3));
        assert_eq!(days_from_civil(newer) - days_from_civil(older), 365);
    }
}
