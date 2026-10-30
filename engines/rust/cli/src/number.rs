//! The one place that decides how a YAML number becomes a JSON number.

use serde_json::Value;

/// Turns text that is already a plain JSON number, like `1.10`, `1e400` or `-8`, into a JSON number that keeps its digits as written.
pub fn number(text: &str) -> Value {
    text.parse::<serde_json::Number>()
        .map_or_else(|_| Value::String(text.to_string()), Value::Number)
}
