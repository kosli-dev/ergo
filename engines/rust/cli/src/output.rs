//! Prints a value the way `opa eval --format=pretty` does.

use serde_json::Value;

/// Writes `value` with sorted keys and a trailing newline: two-space indented, or on one line when `compact` is set. Like OPA, it writes `<`, `>`, `&`, U+2028 and U+2029 as `\u` escapes.
pub fn render(value: &Value, compact: bool) -> String {
    let text = if compact {
        serde_json::to_string(value)
    } else {
        serde_json::to_string_pretty(value)
    }
    .unwrap_or_default();
    let mut out = String::with_capacity(text.len() + 1);
    for c in text.chars() {
        match c {
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c => out.push(c),
        }
    }
    out.push('\n');
    out
}
