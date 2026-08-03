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
    Regex::new(r"(?i)(?:/users|/home)/[^/\s:]+|[a-z]:\\users\\[^\\\s:]+")
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
static FILE_LINE_COLUMN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b([a-z0-9_.-]+\.[a-z0-9]+):\d+:\d+\b")
        .unwrap_or_else(|error| unreachable!("static file-location regex is valid: {error}"))
});
static DURATION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)\b\d+(?:\.\d+)?\s*(?:ns|µs|us|ms|milliseconds?|secs?|seconds?|mins?|minutes?)\b",
    )
    .unwrap_or_else(|error| unreachable!("static duration regex is valid: {error}"))
});
static HOSTNAME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(host(?:name)?)[ :=]+[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\b")
        .unwrap_or_else(|error| unreachable!("static hostname regex is valid: {error}"))
});
static STACK_FRAME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^\s*(?:at\s+\S|file\s+.+,\s+line\s+\d+|\d+:\s+0x[0-9a-f]+)")
        .unwrap_or_else(|error| unreachable!("static stack-frame regex is valid: {error}"))
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
    let safe = normalize_lines(&sanitize_terminal(input));
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
        (&*FILE_LINE_COLUMN, "${1}:<line>:<col>"),
        (&*DURATION, "<duration>"),
        (&*HOSTNAME, "${1} <hostname>"),
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

fn normalize_lines(input: &str) -> String {
    const MAX_STACK_FRAMES: usize = 12;
    let mut previous = None;
    let mut stack_frames = 0_usize;
    let mut omitted_stack = false;
    let mut kept = Vec::new();
    for line in input.lines() {
        let trimmed = line.trim_end();
        if previous == Some(trimmed) {
            continue;
        }
        previous = Some(trimmed);
        if STACK_FRAME.is_match(trimmed) {
            stack_frames += 1;
            if stack_frames > MAX_STACK_FRAMES {
                if !omitted_stack {
                    kept.push("<stack frames omitted>");
                    omitted_stack = true;
                }
                continue;
            }
        }
        kept.push(trimmed);
    }
    kept.join("\n")
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
    use std::fmt::Write as _;

    #[test]
    fn removes_noise_but_preserves_diagnostics() {
        let first = normalize_failure(
            "2026-08-03T10:11:12Z ERR_PNPM_OUTDATED_LOCKFILE /Users/alice/project/file.rs pid: 9876",
        );
        let second = normalize_failure(
            "2026-08-04T11:12:13Z ERR_PNPM_OUTDATED_LOCKFILE /home/bob/project/file.rs pid: 1234",
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

    #[test]
    fn removes_repeated_lines_and_deep_stack_frames() {
        let mut input = String::from("E_BUILD failed\nE_BUILD failed\n");
        for index in 0..20 {
            writeln!(input, "  at package::call_{index} (src/main.rs:{index}:2)")
                .unwrap_or_else(|error| unreachable!("String writes cannot fail: {error}"));
        }
        let normalized = normalize_failure(&input);
        assert_eq!(normalized.text.matches("e_build failed").count(), 1);
        assert!(normalized.text.contains("<stack frames omitted>"));
        assert!(!normalized.text.contains("call_19"));
    }

    #[test]
    fn normalizes_runtime_noise_and_preserves_file_names() {
        let first = normalize_failure("host=runner-123 config.toml:42:9 completed in 1834ms");
        let second = normalize_failure("host=runner-999 config.toml:84:2 completed in 9 seconds");
        assert_eq!(first, second);
        assert!(first.text.contains("config.toml"));
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
