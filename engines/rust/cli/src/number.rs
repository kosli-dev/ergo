//! The one place that decides how a YAML number becomes a JSON number.

use serde_json::Value;

/// Turns text that is already a plain JSON number, like `1.10`, `1e400` or `-8`, into a JSON number that keeps its digits as written.
pub fn number(text: &str) -> Value {
    text.parse::<serde_json::Number>()
        .map_or_else(|_| Value::String(text.to_string()), Value::Number)
}

fn decimal(text: &str) -> Option<(bool, String, i128)> {
    let (negative, rest) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text),
    };
    let (mantissa, exponent) = match rest.find(['e', 'E']) {
        Some(at) => (&rest[..at], rest[at + 1..].parse::<i128>().ok()?),
        None => (rest, 0),
    };
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let all = format!("{whole}{fraction}");
    let digits = all.trim_start_matches('0').trim_end_matches('0');
    if digits.is_empty() {
        return Some((false, String::new(), 0));
    }
    let dropped = all.len() - all.trim_end_matches('0').len();
    let exponent = exponent
        .checked_sub(fraction.len() as i128)?
        .checked_add(dropped as i128)?;
    Some((negative, digits.to_string(), exponent))
}

/// Whether two JSON numbers have the same value, however they are written, so `7.0`, `7` and `0.7e1` are the same.
pub fn same_value(a: &serde_json::Number, b: &serde_json::Number) -> bool {
    match (decimal(&a.to_string()), decimal(&b.to_string())) {
        (Some(a), Some(b)) => a == b,
        _ => a.to_string() == b.to_string(),
    }
}
