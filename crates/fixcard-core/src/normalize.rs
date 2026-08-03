use regex::Regex;
use std::collections::BTreeSet;
use std::sync::LazyLock;
use unicode_normalization::UnicodeNormalization;

static ANSI_CSI: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\x1b\[[0-?]*[ -/]*[@-~]")
        .unwrap_or_else(|error| unreachable!("static ANSI regex is valid: {error}"))
});
static TIMESTAMP: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b\d{4}-\d{2}-\d{2}[t ][0-9:.+-]+z?\b")
        .unwrap_or_else(|error| unreachable!("static timestamp regex is valid: {error}"))
});
static UUID: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b")
        .unwrap_or_else(|error| unreachable!("static UUID regex is valid: {error}"))
});
static LONG_HEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b[0-9a-f]{16,}\b")
        .unwrap_or_else(|error| unreachable!("static hex regex is valid: {error}"))
});
static HOME_PATH: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:/users|/home)/[^/\s:]+(?:/[^\s:]+)*|[a-z]:\\users\\[^\s:]+(?:\\[^\s:]+)*")
        .unwrap_or_else(|error| unreachable!("static home-path regex is valid: {error}"))
});
static TEMP_PATH: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:/tmp|/var/tmp|\\temp\\)[^\s:]*")
        .unwrap_or_else(|error| unreachable!("static temp-path regex is valid: {error}"))
});
static PID: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:pid|process)[ :=#]+\d+\b")
        .unwrap_or_else(|error| unreachable!("static PID regex is valid: {error}"))
});
static PORT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:localhost|127\.0\.0\.1|::1):(\d{4,5})\b")
        .unwrap_or_else(|error| unreachable!("static port regex is valid: {error}"))
});
static LINE_COLUMN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(?:line|column|col)[ :=]+\d+\b")
        .unwrap_or_else(|error| unreachable!("static location regex is valid: {error}"))
});
static WHITESPACE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\s+")
        .unwrap_or_else(|error| unreachable!("static whitespace regex is valid: {error}"))
});

/// Stable normalized representation used for matching.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NormalizedFailure {
    /// Normalized searchable text.
    pub text: String,
    /// Unique diagnostic tokens.
    pub tokens: BTreeSet<String>,
}

/// Remove unstable log values while retaining diagnostic identity.
#[must_use]
pub fn normalize_failure(input: &str) -> NormalizedFailure {
    let safe = sanitize_terminal(input);
    let mut text = safe.nfkc().collect::<String>().to_lowercase();
    for (regex, replacement) in [
        (&*TIMESTAMP, "<timestamp>"),
        (&*UUID, "<uuid>"),
        (&*LONG_HEX, "<hex>"),
        (&*HOME_PATH, "<path>"),
        (&*TEMP_PATH, "<path>"),
        (&*PID, "pid <number>"),
        (&*PORT, "localhost:<port>"),
        (&*LINE_COLUMN, "line <number>"),
    ] {
        text = regex.replace_all(&text, replacement).into_owned();
    }
    text = WHITESPACE.replace_all(text.trim(), " ").into_owned();
    let tokens = text
        .split(|character: char| {
            !(character.is_alphanumeric() || matches!(character, '_' | '-' | '.'))
        })
        .filter(|token| token.len() >= 2)
        .map(ToOwned::to_owned)
        .collect();
    NormalizedFailure { text, tokens }
}

/// Neutralize escape sequences and unsafe control characters from untrusted text.
#[must_use]
pub fn sanitize_terminal(input: &str) -> String {
    let without_ansi = ANSI_CSI.replace_all(input, "");
    let stripped = strip_ansi_escapes::strip(without_ansi.as_bytes());
    String::from_utf8_lossy(&stripped)
        .chars()
        .filter(|character| {
            matches!(character, '\n' | '\r' | '\t')
                || (!character.is_control()
                    && !matches!(
                        *character,
                        '\u{061c}'
                            | '\u{200e}'
                            | '\u{200f}'
                            | '\u{202a}'..='\u{202e}'
                            | '\u{2066}'..='\u{2069}'
                    ))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn removes_noise_but_preserves_diagnostics() {
        let first = normalize_failure(
            "2026-08-03T10:11:12Z ERR_PNPM_OUTDATED_LOCKFILE /Users/alice/x pid: 9876",
        );
        let second = normalize_failure(
            "2026-08-04T11:12:13Z ERR_PNPM_OUTDATED_LOCKFILE /home/bob/y pid: 1234",
        );
        assert_eq!(first, second);
        assert!(first.text.contains("err_pnpm_outdated_lockfile"));
    }

    #[test]
    fn strips_terminal_and_bidi_controls() {
        assert_eq!(
            sanitize_terminal("safe\x1b[31mred\x1b[0m\u{202e}x"),
            "saferedx"
        );
    }

    proptest! {
        #[test]
        fn normalization_is_idempotent(value in ".{0,4096}") {
            let once = normalize_failure(&value);
            let twice = normalize_failure(&once.text);
            prop_assert_eq!(once, twice);
        }
    }
}
