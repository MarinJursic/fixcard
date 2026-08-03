//! Non-mutating diagnostics for card quality, privacy, and command risk.

use std::sync::LazyLock;

use fixcard_core::{CardDocument, Risk};
use jiff::civil::Date;
use regex::Regex;
use semver::VersionReq;

static SECRET_PATTERNS: LazyLock<Vec<(&'static str, Regex)>> = LazyLock::new(|| {
    [
        ("github-token", r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
        ("aws-access-key", r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
        (
            "private-key",
            r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
        ),
        (
            "jwt",
            r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}\b",
        ),
        (
            "authorization-header",
            r"(?i)authorization\s*:\s*(?:bearer|basic)\s+\S+",
        ),
        (
            "url-credentials",
            r"(?i)\b[a-z][a-z0-9+.-]*://[^\s/@:]+:[^\s/@]+@",
        ),
        (
            "database-url",
            r"(?i)\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://[^\s]+",
        ),
        (
            "secret-assignment",
            r"(?i)\b(?:api[_-]?key|secret|password|passwd|token)\s*=\s*[^\s$<{][^\s]{7,}",
        ),
    ]
    .into_iter()
    .map(|(name, pattern)| {
        (
            name,
            Regex::new(pattern)
                .unwrap_or_else(|error| unreachable!("static secret regex is valid: {error}")),
        )
    })
    .collect()
});

static RISK_PATTERNS: LazyLock<Vec<(&'static str, Regex)>> = LazyLock::new(|| {
    [
        ("privileged command", r"(?m)(?:^|[;&|]\s*)sudo\s+"),
        (
            "recursive deletion",
            r"(?m)\brm\s+[^\n]*(?:-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r)",
        ),
        ("force push", r"(?m)\bgit\s+push\b[^\n]*(?:--force|-f\b)"),
        (
            "remote pipe to shell",
            r"(?im)\b(?:curl|wget)\b[^\n|]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b",
        ),
        (
            "database migration",
            r"(?i)\b(?:migrate|migration)\s+(?:up|run|deploy|apply)\b",
        ),
        (
            "production target",
            r"(?i)(?:--(?:env|environment|target)[ =]production|\bprod(?:uction)?\b)",
        ),
        (
            "credential change",
            r"(?i)\b(?:passwd|rotate[-_ ]?key|delete[-_ ]?credential)\b",
        ),
    ]
    .into_iter()
    .map(|(name, pattern)| {
        (
            name,
            Regex::new(pattern)
                .unwrap_or_else(|error| unreachable!("static risk regex is valid: {error}")),
        )
    })
    .collect()
});

static LOCAL_PATH: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:/users|/home)/[^/\s:]+|[a-z]:\\users\\[^\\\s:]+")
        .unwrap_or_else(|error| unreachable!("static path regex is valid: {error}"))
});
static CERTAINTY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:always fixes|guaranteed fix|will definitely fix|safe to run)\b")
        .unwrap_or_else(|error| unreachable!("static certainty regex is valid: {error}"))
});
static ENTROPY_TOKEN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"[A-Za-z0-9_+/=-]{24,200}")
        .unwrap_or_else(|error| unreachable!("static entropy-token regex is valid: {error}"))
});

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

/// One stable machine-readable and human-readable lint result.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    /// Stable kebab-case rule identifier.
    pub code: &'static str,
    /// Diagnostic severity.
    pub severity: Severity,
    /// Explanation without reproducing detected secret material.
    pub message: String,
    /// One-based source line when available.
    pub line: Option<usize>,
}

/// Inspect a valid parsed document and its original source.
#[must_use]
pub fn lint_card(document: &CardDocument, source: &str, today: Option<Date>) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    lint_anchors(document, &mut diagnostics);
    lint_versions(document, &mut diagnostics);
    lint_validation(document, &mut diagnostics);
    lint_lifecycle(document, today, &mut diagnostics);
    lint_secrets(source, &mut diagnostics);
    lint_risk(document, source, &mut diagnostics);
    lint_local_data(source, &mut diagnostics);
    lint_language(source, &mut diagnostics);
    diagnostics.sort_by_key(|item| (item.severity, item.line.unwrap_or(usize::MAX), item.code));
    diagnostics.reverse();
    diagnostics
}

/// Whether any diagnostic should block a shared-card save.
#[must_use]
pub fn blocks_team_save(diagnostics: &[Diagnostic]) -> bool {
    diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == Severity::Error)
}

fn lint_anchors(document: &CardDocument, diagnostics: &mut Vec<Diagnostic>) {
    for anchor in document
        .card
        .match_spec
        .exact
        .iter()
        .chain(&document.card.match_spec.contains)
    {
        let trimmed = anchor.trim();
        if trimmed.chars().count() < 4
            || matches!(
                trimmed.to_ascii_lowercase().as_str(),
                "error" | "failed" | "failure"
            )
        {
            diagnostics.push(Diagnostic {
                code: "generic-anchor",
                severity: Severity::Error,
                message: format!("match anchor `{trimmed}` is too generic for safe ranking"),
                line: None,
            });
        }
        if LOCAL_PATH.is_match(trimmed) {
            diagnostics.push(Diagnostic {
                code: "local-anchor",
                severity: Severity::Warning,
                message: "match anchor contains a machine-local home path".to_owned(),
                line: None,
            });
        }
    }
}

fn lint_versions(document: &CardDocument, diagnostics: &mut Vec<Diagnostic>) {
    for (tool, requirement) in &document.card.applies.tools {
        let normalized = requirement
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(", ");
        if VersionReq::parse(&normalized).is_err() {
            diagnostics.push(Diagnostic {
                code: "invalid-version-range",
                severity: Severity::Error,
                message: format!("`{requirement}` is not a valid version range for `{tool}`"),
                line: None,
            });
        }
    }
}

fn lint_validation(document: &CardDocument, diagnostics: &mut Vec<Diagnostic>) {
    if let Some(verification) = &document.card.verified {
        if verification.exit_code.is_none() {
            diagnostics.push(Diagnostic {
                code: "missing-observed-exit",
                severity: Severity::Warning,
                message: "validation command has no observed exit status".to_owned(),
                line: None,
            });
        }
    } else {
        diagnostics.push(Diagnostic {
            code: "unverified",
            severity: Severity::Note,
            message: "card records no validation observation".to_owned(),
            line: None,
        });
    }
}

fn lint_lifecycle(document: &CardDocument, today: Option<Date>, diagnostics: &mut Vec<Diagnostic>) {
    if document.card.superseded_by.as_deref() == Some(&document.card.id) {
        diagnostics.push(Diagnostic {
            code: "self-supersession",
            severity: Severity::Error,
            message: "a card cannot supersede itself".to_owned(),
            line: None,
        });
    }
    if document
        .card
        .supersedes
        .iter()
        .any(|id| id == &document.card.id)
    {
        diagnostics.push(Diagnostic {
            code: "self-supersession",
            severity: Severity::Error,
            message: "a card cannot list itself in supersedes".to_owned(),
            line: None,
        });
    }
    if let (Some(today), Some(last_verified)) = (today, document.card.last_verified) {
        if approximate_days(today) - approximate_days(last_verified) > 365 {
            diagnostics.push(Diagnostic {
                code: "stale",
                severity: Severity::Warning,
                message: format!("last verification on {last_verified} is more than 365 days old"),
                line: None,
            });
        }
    }
}

fn lint_secrets(source: &str, diagnostics: &mut Vec<Diagnostic>) {
    for (kind, pattern) in SECRET_PATTERNS.iter() {
        for found in pattern.find_iter(source) {
            diagnostics.push(Diagnostic {
                code: "possible-secret",
                severity: Severity::Error,
                message: format!("possible {kind} detected; value omitted from diagnostic"),
                line: Some(line_number(source, found.start())),
            });
        }
    }
    for found in ENTROPY_TOKEN.find_iter(source) {
        if looks_high_entropy(found.as_str()) {
            diagnostics.push(Diagnostic {
                code: "high-entropy-value",
                severity: Severity::Error,
                message: "possible high-entropy credential detected; value omitted from diagnostic"
                    .to_owned(),
                line: Some(line_number(source, found.start())),
            });
        }
    }
}

fn lint_risk(document: &CardDocument, source: &str, diagnostics: &mut Vec<Diagnostic>) {
    for (kind, pattern) in RISK_PATTERNS.iter() {
        if let Some(found) = pattern.find(source) {
            let declared_high = document.card.risk == Risk::High;
            diagnostics.push(Diagnostic {
                code: if declared_high {
                    "high-risk-command"
                } else {
                    "understated-risk"
                },
                severity: if declared_high {
                    Severity::Warning
                } else {
                    Severity::Error
                },
                message: if declared_high {
                    format!("declared high-risk card contains {kind}")
                } else {
                    format!("card contains {kind} but risk is not `high`")
                },
                line: Some(line_number(source, found.start())),
            });
        }
    }
}

fn lint_local_data(source: &str, diagnostics: &mut Vec<Diagnostic>) {
    for found in LOCAL_PATH.find_iter(source) {
        diagnostics.push(Diagnostic {
            code: "local-home-path",
            severity: Severity::Warning,
            message: "machine-local home path should be generalized before sharing".to_owned(),
            line: Some(line_number(source, found.start())),
        });
    }
}

fn lint_language(source: &str, diagnostics: &mut Vec<Diagnostic>) {
    for found in CERTAINTY.find_iter(source) {
        diagnostics.push(Diagnostic {
            code: "certainty-claim",
            severity: Severity::Warning,
            message: "replace certainty language with bounded evidence".to_owned(),
            line: Some(line_number(source, found.start())),
        });
    }
}

fn line_number(source: &str, byte_offset: usize) -> usize {
    source[..byte_offset]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1
}

fn looks_high_entropy(token: &str) -> bool {
    if !(24..=200).contains(&token.len())
        || token.starts_with("ERR_")
        || token.chars().all(|character| character.is_ascii_hexdigit())
    {
        return false;
    }
    let classes = [
        token
            .chars()
            .any(|character| character.is_ascii_lowercase()),
        token
            .chars()
            .any(|character| character.is_ascii_uppercase()),
        token.chars().any(|character| character.is_ascii_digit()),
        token
            .chars()
            .any(|character| matches!(character, '_' | '-' | '+' | '/' | '=')),
    ]
    .into_iter()
    .filter(|present| *present)
    .count();
    classes >= 3 && shannon_entropy(token) >= 4.0
}

fn shannon_entropy(value: &str) -> f64 {
    let mut counts = [0_u16; 128];
    let mut length = 0_u16;
    for byte in value.bytes().filter(u8::is_ascii) {
        counts[usize::from(byte)] += 1;
        length += 1;
    }
    if length == 0 {
        return 0.0;
    }
    counts
        .into_iter()
        .filter(|count| *count > 0)
        .map(|count| {
            let probability = f64::from(count) / f64::from(length);
            -probability * probability.log2()
        })
        .sum()
}

fn approximate_days(date: Date) -> i64 {
    i64::from(date.year()) * 365 + i64::from(date.month()) * 31 + i64::from(date.day())
}

#[cfg(test)]
#[allow(
    clippy::panic,
    reason = "test fixture parsing should report diagnostics"
)]
mod tests {
    use super::*;
    use fixcard_core::parse_card;

    fn source(extra: &str, risk: &str) -> String {
        format!(
            "---\nfixcard: 1\nid: test-card\ntitle: Test card\nmatch:\n  exact: [ERR_USEFUL_CODE]\nrisk: {risk}\ncreated: 2026-08-03\n---\n## What worked here\n\nReview this command:\n```bash\n{extra}\n```\n"
        )
    }

    #[test]
    fn catches_secrets_without_echoing_them() {
        let secret = "ghp_1234567890abcdefghijklmnopqrst";
        let source = source(secret, "low");
        let card = parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"));
        let diagnostics = lint_card(&card, &source, None);
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "possible-secret")
        );
        assert!(
            diagnostics
                .iter()
                .all(|item| !item.message.contains(secret))
        );
        assert!(blocks_team_save(&diagnostics));
    }

    #[test]
    fn requires_high_risk_for_destructive_commands() {
        let source = source("sudo rm -rf /var/example", "low");
        let card = parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"));
        let diagnostics = lint_card(&card, &source, None);
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "understated-risk")
        );
    }

    #[test]
    fn declared_high_risk_warns_but_does_not_block() {
        let source = source("sudo rm -rf /var/example", "high");
        let card = parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"));
        let diagnostics = lint_card(&card, &source, None);
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "high-risk-command")
        );
        assert!(!blocks_team_save(&diagnostics));
    }
}
