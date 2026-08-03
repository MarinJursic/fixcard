//! Non-mutating diagnostics for card quality, privacy, and command risk.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::LazyLock;

use fixcard_core::{CardDocument, Risk};
use jiff::civil::Date;
use regex::Regex;
use semver::VersionReq;
use serde::Deserialize;

static SECRET_PATTERNS: LazyLock<Vec<(&'static str, Regex)>> = LazyLock::new(|| {
    [
        (
            "github-token",
            r"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{40,})\b",
        ),
        ("gitlab-token", r"\bglpat-[A-Za-z0-9_-]{20,}\b"),
        ("npm-token", r"\bnpm_[A-Za-z0-9]{36}\b"),
        ("slack-token", r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
        ("google-api-key", r"\bAIza[0-9A-Za-z_-]{35}\b"),
        ("stripe-secret-key", r"\bsk_live_[A-Za-z0-9]{20,}\b"),
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
        ("cookie-header", r"(?i)(?:set-)?cookie\s*:\s*[^\r\n]+"),
        (
            "url-credentials",
            r"(?i)\b[a-z][a-z0-9+.-]*://[^\s/@:]+:[^\s/@]+@",
        ),
        (
            "database-url",
            r"(?i)\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://[^\s]+",
        ),
        (
            "url-query-credential",
            r"(?i)\bhttps?://[^\s?]+\?[^\s]*(?:access[_-]?token|api[_-]?key|secret|signature|sig)=[^\s&#]+",
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

static RISK_PATTERNS: LazyLock<Vec<(&'static str, &'static str, Regex)>> = LazyLock::new(|| {
    [
        (
            "privileged-command",
            "privileged command",
            r"(?m)(?:^|[;&|]\s*)sudo\s+",
        ),
        (
            "recursive-deletion",
            "recursive deletion",
            r"(?m)\brm\s+[^\n]*(?:-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r)",
        ),
        (
            "force-push",
            "force push",
            r"(?m)\bgit\s+push\b[^\n]*(?:--force|-f\b)",
        ),
        (
            "remote-pipe-to-shell",
            "remote pipe to shell",
            r"(?im)\b(?:curl|wget)\b[^\n|]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b",
        ),
        (
            "database-migration",
            "database migration",
            r"(?i)\b(?:migrate|migration)\s+(?:up|run|deploy|apply)\b",
        ),
        (
            "production-target",
            "production target",
            r"(?i)(?:--(?:env|environment|target)[ =]production|\bprod(?:uction)?\b)",
        ),
        (
            "credential-change",
            "credential change",
            r"(?i)\b(?:passwd|rotate[-_ ]?key|delete[-_ ]?credential)\b",
        ),
    ]
    .into_iter()
    .map(|(class, name, pattern)| {
        (
            class,
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
static INTERNAL_HOSTNAME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:[a-z0-9-]+\.)+(?:corp|internal|intranet|lan|local)\b")
        .unwrap_or_else(|error| unreachable!("static hostname regex is valid: {error}"))
});
static CERTAINTY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:always fixes|guaranteed fix|will definitely fix|safe to run)\b")
        .unwrap_or_else(|error| unreachable!("static certainty regex is valid: {error}"))
});
static ENTROPY_TOKEN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"[A-Za-z0-9_+/=-]{24,200}")
        .unwrap_or_else(|error| unreachable!("static entropy-token regex is valid: {error}"))
});
static GIT_OBJECT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^[0-9a-fA-F]{7,64}$")
        .unwrap_or_else(|error| unreachable!("static Git object regex is valid: {error}"))
});
static PORTABLE_ID: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
        .unwrap_or_else(|error| unreachable!("static ID regex is valid: {error}"))
});
static TOOL_NAME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^[a-z0-9][a-z0-9_-]*$")
        .unwrap_or_else(|error| unreachable!("static tool regex is valid: {error}"))
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

/// A diagnostic that depends on relationships between multiple cards.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CardSetDiagnostic {
    /// Card whose relationship should be changed.
    pub card_id: String,
    /// The relationship finding.
    pub diagnostic: Diagnostic,
}

/// Optional repository policy applied by lint and shared-card creation.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
pub struct LintPolicy {
    /// Command classes that are forbidden even on declared high-risk cards.
    pub deny_command_classes: BTreeSet<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct PolicyDocument {
    lint: LintPolicy,
}

/// Parse and validate a repository `.fixcard.toml` policy.
///
/// # Errors
///
/// Returns a bounded human-readable error for malformed TOML, unknown fields,
/// or command classes that this binary does not recognize.
pub fn parse_policy(source: &str) -> Result<LintPolicy, String> {
    let document = toml::from_str::<PolicyDocument>(source)
        .map_err(|error| format!("invalid Fixcard policy: {error}"))?;
    let unknown = document
        .lint
        .deny_command_classes
        .iter()
        .filter(|class| {
            !RISK_PATTERNS
                .iter()
                .any(|(known, _, _)| known == &class.as_str())
        })
        .cloned()
        .collect::<Vec<_>>();
    if !unknown.is_empty() {
        return Err(format!(
            "unknown denied command class{}: {}",
            if unknown.len() == 1 { "" } else { "es" },
            unknown.join(", ")
        ));
    }
    Ok(document.lint)
}

/// Inspect a valid parsed document and its original source.
#[must_use]
pub fn lint_card(document: &CardDocument, source: &str, today: Option<Date>) -> Vec<Diagnostic> {
    lint_card_with_policy(document, source, today, &LintPolicy::default())
}

/// Inspect a card under an optional repository command-class policy.
#[must_use]
pub fn lint_card_with_policy(
    document: &CardDocument,
    source: &str,
    today: Option<Date>,
    policy: &LintPolicy,
) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    lint_anchors(document, &mut diagnostics);
    lint_versions(document, &mut diagnostics);
    lint_validation(document, &mut diagnostics);
    lint_lifecycle(document, today, &mut diagnostics);
    lint_secrets(source, &mut diagnostics);
    lint_risk(document, source, policy, &mut diagnostics);
    lint_local_data(source, &mut diagnostics);
    lint_language(source, &mut diagnostics);
    diagnostics.sort_by_key(|item| (item.severity, item.line.unwrap_or(usize::MAX), item.code));
    diagnostics.reverse();
    diagnostics
}

/// Check lifecycle references and cycles across a complete card set.
#[must_use]
pub fn lint_card_set(documents: &[CardDocument]) -> Vec<CardSetDiagnostic> {
    let mut seen = BTreeSet::new();
    let mut diagnostics = documents
        .iter()
        .filter(|document| !seen.insert(document.card.id.as_str()))
        .map(|document| {
            card_set_diagnostic(
                &document.card.id,
                "duplicate-card-id",
                Severity::Error,
                format!("card ID `{}` occurs more than once", document.card.id),
            )
        })
        .collect::<Vec<_>>();
    let cards = documents
        .iter()
        .map(|document| (document.card.id.as_str(), document))
        .collect::<BTreeMap<_, _>>();
    for document in documents {
        let card = &document.card;
        if let Some(replacement) = &card.superseded_by {
            match cards.get(replacement.as_str()) {
                None => diagnostics.push(card_set_diagnostic(
                    &card.id,
                    "missing-lifecycle-target",
                    Severity::Error,
                    format!("superseded_by references missing card `{replacement}`"),
                )),
                Some(target) if !target.card.supersedes.contains(&card.id) => {
                    diagnostics.push(card_set_diagnostic(
                        &card.id,
                        "non-reciprocal-supersession",
                        Severity::Warning,
                        format!("replacement `{replacement}` does not list `{}`", card.id),
                    ));
                }
                Some(_) => {}
            }
        }
        for prior in &card.supersedes {
            match cards.get(prior.as_str()) {
                None => diagnostics.push(card_set_diagnostic(
                    &card.id,
                    "missing-lifecycle-target",
                    Severity::Error,
                    format!("supersedes references missing card `{prior}`"),
                )),
                Some(target) if target.card.superseded_by.as_deref() != Some(card.id.as_str()) => {
                    diagnostics.push(card_set_diagnostic(
                        &card.id,
                        "non-reciprocal-supersession",
                        Severity::Warning,
                        format!("superseded card `{prior}` does not point to `{}`", card.id),
                    ));
                }
                Some(_) => {}
            }
        }

        let mut visited = BTreeSet::new();
        let mut current = card.id.as_str();
        while visited.insert(current) {
            let Some(next) = cards
                .get(current)
                .and_then(|item| item.card.superseded_by.as_deref())
            else {
                break;
            };
            if visited.contains(next) {
                diagnostics.push(card_set_diagnostic(
                    &card.id,
                    "supersession-cycle",
                    Severity::Error,
                    format!("supersession chain enters a cycle at `{next}`"),
                ));
                break;
            }
            current = next;
        }
    }
    diagnostics.sort_by(|left, right| {
        left.card_id
            .cmp(&right.card_id)
            .then_with(|| left.diagnostic.code.cmp(right.diagnostic.code))
    });
    diagnostics
}

fn card_set_diagnostic(
    card_id: &str,
    code: &'static str,
    severity: Severity,
    message: String,
) -> CardSetDiagnostic {
    CardSetDiagnostic {
        card_id: card_id.to_owned(),
        diagnostic: Diagnostic {
            code,
            severity,
            message,
            line: None,
        },
    }
}

/// Whether any diagnostic should block a shared-card save.
#[must_use]
pub fn blocks_team_save(diagnostics: &[Diagnostic]) -> bool {
    diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == Severity::Error)
}

/// Replace secret-like values before rendering a preview.
///
/// This is defense in depth and must not be treated as safe publication.
#[must_use]
pub fn redact_secrets(source: &str) -> String {
    let mut matches = sensitive_matches(source);
    matches.sort_by_key(|found| (found.start, found.end));
    let mut redacted = String::with_capacity(source.len());
    let mut cursor = 0;
    for found in matches {
        if found.end <= cursor {
            continue;
        }
        if found.start < cursor {
            cursor = found.end;
            continue;
        }
        if found.start > cursor {
            redacted.push_str(&source[cursor..found.start]);
        }
        redacted.push_str("[REDACTED]");
        cursor = found.end;
    }
    redacted.push_str(&source[cursor..]);
    redacted
}

fn lint_anchors(document: &CardDocument, diagnostics: &mut Vec<Diagnostic>) {
    let mut seen = BTreeSet::new();
    for anchor in document
        .card
        .match_spec
        .exact
        .iter()
        .chain(&document.card.match_spec.contains)
        .chain(&document.card.match_spec.not_contains)
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
        let normalized = trimmed.to_lowercase();
        if !seen.insert(normalized) {
            diagnostics.push(Diagnostic {
                code: "duplicate-anchor",
                severity: Severity::Warning,
                message: format!("match anchor `{trimmed}` is repeated"),
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
        if !TOOL_NAME.is_match(tool) {
            diagnostics.push(Diagnostic {
                code: "invalid-tool-name",
                severity: Severity::Error,
                message: format!("tool name `{tool}` must be a lowercase portable identifier"),
                line: None,
            });
        }
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
        if verification
            .source_commit
            .as_deref()
            .is_some_and(|commit| !GIT_OBJECT.is_match(commit))
        {
            diagnostics.push(Diagnostic {
                code: "invalid-source-commit",
                severity: Severity::Error,
                message: "source commit must be a 7–64 character hexadecimal Git object ID"
                    .to_owned(),
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
    if document.card.retired && document.card.superseded_by.is_some() {
        diagnostics.push(Diagnostic {
            code: "conflicting-lifecycle-state",
            severity: Severity::Error,
            message: "a card cannot be both retired and superseded".to_owned(),
            line: None,
        });
    }
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
    let mut referenced = BTreeSet::new();
    for id in document
        .card
        .supersedes
        .iter()
        .chain(document.card.superseded_by.iter())
    {
        if !PORTABLE_ID.is_match(id) {
            diagnostics.push(Diagnostic {
                code: "invalid-lifecycle-id",
                severity: Severity::Error,
                message: format!("lifecycle reference `{id}` is not a portable card ID"),
                line: None,
            });
        }
        if !referenced.insert(id) {
            diagnostics.push(Diagnostic {
                code: "duplicate-lifecycle-reference",
                severity: Severity::Warning,
                message: format!("lifecycle reference `{id}` is repeated"),
                line: None,
            });
        }
    }
    if let (Some(created), Some(last_verified)) =
        (document.card.created, document.card.last_verified)
    {
        if last_verified < created {
            diagnostics.push(Diagnostic {
                code: "verification-before-creation",
                severity: Severity::Error,
                message: "last_verified cannot be earlier than created".to_owned(),
                line: None,
            });
        }
    }
    if let (Some(today), Some(last_verified)) = (today, document.card.last_verified) {
        if last_verified > today {
            diagnostics.push(Diagnostic {
                code: "future-verification-date",
                severity: Severity::Error,
                message: format!("last verification date {last_verified} is in the future"),
                line: None,
            });
        } else if today.duration_since(last_verified).as_hours() / 24 > 365 {
            diagnostics.push(Diagnostic {
                code: "stale",
                severity: Severity::Warning,
                message: format!("last verification on {last_verified} is more than 365 days old"),
                line: None,
            });
        }
    }
    if let (Some(today), Some(created)) = (today, document.card.created) {
        if created > today {
            diagnostics.push(Diagnostic {
                code: "future-creation-date",
                severity: Severity::Error,
                message: format!("creation date {created} is in the future"),
                line: None,
            });
        }
    }
}

fn lint_secrets(source: &str, diagnostics: &mut Vec<Diagnostic>) {
    for found in sensitive_matches(source) {
        let (code, message) = match found.kind {
            SensitiveKind::Pattern(kind) => (
                "possible-secret",
                format!("possible {kind} detected; value omitted from diagnostic"),
            ),
            SensitiveKind::Entropy => (
                "high-entropy-value",
                "possible high-entropy credential detected; value omitted from diagnostic"
                    .to_owned(),
            ),
        };
        diagnostics.push(Diagnostic {
            code,
            severity: Severity::Error,
            message,
            line: Some(line_number(source, found.start)),
        });
    }
}

#[derive(Clone, Copy)]
enum SensitiveKind {
    Pattern(&'static str),
    Entropy,
}

#[derive(Clone, Copy)]
struct SensitiveMatch {
    start: usize,
    end: usize,
    kind: SensitiveKind,
}

fn sensitive_matches(source: &str) -> Vec<SensitiveMatch> {
    let mut matches = Vec::new();
    for (kind, pattern) in SECRET_PATTERNS.iter() {
        matches.extend(pattern.find_iter(source).map(|found| SensitiveMatch {
            start: found.start(),
            end: found.end(),
            kind: SensitiveKind::Pattern(kind),
        }));
    }
    matches.extend(
        ENTROPY_TOKEN
            .find_iter(source)
            .filter(|found| looks_high_entropy(found.as_str()))
            .map(|found| SensitiveMatch {
                start: found.start(),
                end: found.end(),
                kind: SensitiveKind::Entropy,
            }),
    );
    matches
}

fn lint_risk(
    document: &CardDocument,
    source: &str,
    policy: &LintPolicy,
    diagnostics: &mut Vec<Diagnostic>,
) {
    for (class, kind, pattern) in RISK_PATTERNS.iter() {
        if let Some(found) = pattern.find(source) {
            let declared_high = document.card.risk == Risk::High;
            let denied = policy.deny_command_classes.contains(*class);
            diagnostics.push(Diagnostic {
                code: if denied {
                    "denied-command-class"
                } else if declared_high {
                    "high-risk-command"
                } else {
                    "understated-risk"
                },
                severity: if denied || !declared_high {
                    Severity::Error
                } else {
                    Severity::Warning
                },
                message: if denied {
                    format!("repository policy forbids command class `{class}` ({kind})")
                } else if declared_high {
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
    for found in INTERNAL_HOSTNAME.find_iter(source) {
        diagnostics.push(Diagnostic {
            code: "internal-hostname",
            severity: Severity::Warning,
            message: "internal-looking hostname should be generalized before sharing".to_owned(),
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

    #[test]
    fn repository_policy_can_forbid_a_high_risk_class() {
        let policy = parse_policy("[lint]\ndeny-command-classes = [\"privileged-command\"]\n")
            .unwrap_or_else(|error| panic!("policy: {error}"));
        let source = source("sudo rm /var/example", "high");
        let card = parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"));
        let diagnostics = lint_card_with_policy(&card, &source, None, &policy);
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "denied-command-class")
        );
        assert!(blocks_team_save(&diagnostics));
        assert!(parse_policy("[lint]\ndeny-command-classes = [\"unknown\"]").is_err());
    }

    #[test]
    fn recognizes_additional_credential_and_internal_host_patterns() {
        let value = "glpat-1234567890abcdefghij";
        let source = source(
            &format!(
                "Cookie: session=example-value-long\ncurl https://build.corp/path?sig=example-signature\nTOKEN={value}"
            ),
            "low",
        );
        let card = parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"));
        let diagnostics = lint_card(&card, &source, None);
        assert!(
            diagnostics
                .iter()
                .filter(|item| item.code == "possible-secret")
                .count()
                >= 3
        );
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "internal-hostname")
        );
    }

    #[test]
    fn redacts_secret_values_from_previews() {
        let secret = "ghp_1234567890abcdefghijklmnopqrst";
        let preview = redact_secrets(&source(secret, "low"));
        assert!(!preview.contains(secret));
        assert!(preview.contains("[REDACTED]"));
    }

    #[test]
    fn rejects_future_and_invalid_validation_evidence() {
        let source = source("cargo test", "low").replace(
            "created: 2026-08-03",
            "created: 2026-08-04\nverified:\n  command: cargo test\n  exit_code: 0\n  source_commit: not-a-commit",
        );
        let card = parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"));
        let today = "2026-08-03"
            .parse::<Date>()
            .unwrap_or_else(|error| panic!("date: {error}"));
        let diagnostics = lint_card(&card, &source, Some(today));
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "future-creation-date")
        );
        assert!(
            diagnostics
                .iter()
                .any(|item| item.code == "invalid-source-commit")
        );
    }

    #[test]
    fn staleness_uses_exact_calendar_days() {
        let today = "2026-08-03"
            .parse::<Date>()
            .unwrap_or_else(|error| panic!("date: {error}"));
        let recent =
            source("cargo test", "low").replace("created: 2026-08-03", "last_verified: 2025-08-03");
        let stale = recent.replace("2025-08-03", "2025-08-02");
        let recent = parse_card(&recent).unwrap_or_else(|error| panic!("fixture: {error}"));
        let stale = parse_card(&stale).unwrap_or_else(|error| panic!("fixture: {error}"));
        assert!(
            lint_card(&recent, "", Some(today))
                .iter()
                .all(|item| item.code != "stale")
        );
        assert!(
            lint_card(&stale, "", Some(today))
                .iter()
                .any(|item| item.code == "stale")
        );
    }

    #[test]
    fn card_set_lint_finds_missing_targets_and_cycles() {
        let missing = lifecycle_card("missing-source", "superseded_by: absent");
        let missing_diagnostics = lint_card_set(&[missing]);
        assert!(
            missing_diagnostics
                .iter()
                .any(|item| item.diagnostic.code == "missing-lifecycle-target")
        );

        let first = lifecycle_card("first", "supersedes: [second]\nsuperseded_by: second");
        let second = lifecycle_card("second", "supersedes: [first]\nsuperseded_by: first");
        let cycle_diagnostics = lint_card_set(&[first, second]);
        assert_eq!(
            cycle_diagnostics
                .iter()
                .filter(|item| item.diagnostic.code == "supersession-cycle")
                .count(),
            2
        );

        let duplicate = lifecycle_card("first", "");
        assert!(
            lint_card_set(&[lifecycle_card("first", ""), duplicate,])
                .iter()
                .any(|item| item.diagnostic.code == "duplicate-card-id")
        );
    }

    fn lifecycle_card(id: &str, lifecycle: &str) -> CardDocument {
        let source = format!(
            "---\nfixcard: 1\nid: {id}\ntitle: Lifecycle test\nmatch:\n  exact: [ERR_LIFECYCLE_TEST]\nrisk: low\ncreated: 2026-08-03\n{lifecycle}\n---\n## What worked here\n\nReview the replacement.\n"
        );
        parse_card(&source).unwrap_or_else(|error| panic!("fixture: {error}"))
    }
}
