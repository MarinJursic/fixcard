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
    if card.retired && !options.include_retired {
        return None;
    }
    let mut score = 0;
    let mut evidence = Vec::new();
    let query_lower = query.text.as_str();

    for anchor in &card.match_spec.exact {
        let anchor_normalized = normalize_failure(anchor);
        if !anchor_normalized.text.is_empty() && query_lower.contains(&anchor_normalized.text) {
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

    if loaded.origin == CardOrigin::Shared {
        add(
            &mut score,
            &mut evidence,
            3,
            "repository-reviewed card".to_owned(),
        );
    }

    let mut version_mismatch = false;
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
        let Some(current) = environment.tools.get(tool) else {
            continue;
        };
        match parse_requirement(requirement) {
            Some(required) if required.matches(current) => add(
                &mut score,
                &mut evidence,
                5,
                format!("{tool} {current} satisfies {requirement}"),
            ),
            Some(_) => {
                version_mismatch = true;
                add(
                    &mut score,
                    &mut evidence,
                    -60,
                    format!("{tool} {current} conflicts with {requirement}"),
                );
            }
            None => add(
                &mut score,
                &mut evidence,
                -10,
                format!("invalid recorded requirement `{requirement}` for {tool}"),
            ),
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

    let has_exact = evidence.iter().any(|item| item.points == 50);
    let positive_anchor_count = evidence
        .iter()
        .filter(|item| matches!(item.points, 12 | 50))
        .count();
    if score <= 0 && positive_anchor_count == 0 {
        return None;
    }
    let confidence = if !version_mismatch
        && negative.is_none()
        && !card.retired
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
        stale,
    })
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
    fn civil_day_conversion_has_expected_distance() {
        let older = "2025-08-03".parse().unwrap_or(Date::constant(2025, 8, 3));
        let newer = "2026-08-03".parse().unwrap_or(Date::constant(2026, 8, 3));
        assert_eq!(days_from_civil(newer) - days_from_civil(older), 365);
    }
}
