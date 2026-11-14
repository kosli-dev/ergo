use serde_json::Value;
use std::cmp::Ordering;

pub const MAX_POSITION: u64 = 9_007_199_254_740_991;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decimal {
    negative: bool,
    digits: String,
    exponent: i128,
}

impl Decimal {
    pub fn parse(text: &str) -> Option<Decimal> {
        let (negative, rest) = match text.strip_prefix('-') {
            Some(rest) => (true, rest),
            None => (false, text),
        };
        let (mantissa, exp_text) = match rest.find(['e', 'E']) {
            Some(at) => (&rest[..at], Some(&rest[at + 1..])),
            None => (rest, None),
        };
        let (int_part, frac_part) = match mantissa.split_once('.') {
            Some((i, f)) => (i, f),
            None => (mantissa, ""),
        };
        if int_part.is_empty() && frac_part.is_empty() {
            return None;
        }
        if !int_part
            .bytes()
            .chain(frac_part.bytes())
            .all(|b| b.is_ascii_digit())
        {
            return None;
        }
        let all = format!("{int_part}{frac_part}");
        let trimmed = all.trim_start_matches('0');
        let stripped = trimmed.trim_end_matches('0');
        if stripped.is_empty() {
            if let Some(t) = exp_text {
                exponent_digits(t)?;
            }
            return Some(Decimal {
                negative: false,
                digits: String::new(),
                exponent: 0,
            });
        }
        let written_exponent = match exp_text {
            None => 0,
            Some(t) => parse_exponent(t)?,
        };
        let exponent =
            written_exponent - frac_part.len() as i128 + (trimmed.len() - stripped.len()) as i128;
        Some(Decimal {
            negative,
            digits: stripped.to_string(),
            exponent,
        })
    }

    pub fn is_zero(&self) -> bool {
        self.digits.is_empty()
    }

    pub fn parts(&self) -> (bool, &str, i128) {
        (self.negative, &self.digits, self.exponent)
    }

    pub fn is_non_negative_whole(&self) -> bool {
        !self.negative && (self.is_zero() || self.exponent >= 0)
    }

    pub fn as_position(&self) -> Option<u64> {
        if self.negative {
            return None;
        }
        if self.is_zero() {
            return Some(0);
        }
        if self.exponent < 0 || self.digits.len() as i128 + self.exponent > 16 {
            return None;
        }
        let mut text = self.digits.clone();
        text.push_str(&"0".repeat(self.exponent as usize));
        let n: u64 = text.parse().ok()?;
        (n <= MAX_POSITION).then_some(n)
    }

    pub fn fits_a_float(&self) -> bool {
        if self.is_zero() {
            return true;
        }
        let (Some(low), Some(high)) = (
            Decimal::parse("2.2250738585072014e-308"),
            Decimal::parse("1.7976931348623157e308"),
        ) else {
            return false;
        };
        let size = Decimal {
            negative: false,
            digits: self.digits.clone(),
            exponent: self.exponent,
        };
        compare_decimals(&size, &low) != Ordering::Less
            && compare_decimals(&size, &high) != Ordering::Greater
    }

    pub fn plain_text(&self) -> String {
        if self.is_zero() {
            return "0".to_string();
        }
        let sign = if self.negative { "-" } else { "" };
        let places = self.digits.len() as i128;
        let body = if self.exponent >= 0 {
            format!("{}{}", self.digits, "0".repeat(self.exponent as usize))
        } else if -self.exponent < places {
            let at = (places + self.exponent) as usize;
            format!("{}.{}", &self.digits[..at], &self.digits[at..])
        } else {
            format!(
                "0.{}{}",
                "0".repeat((-self.exponent - places) as usize),
                self.digits
            )
        };
        format!("{sign}{body}")
    }

    fn magnitude_order(&self, other: &Decimal) -> Ordering {
        let a = self.digits.len() as i128 + self.exponent;
        let b = other.digits.len() as i128 + other.exponent;
        a.cmp(&b).then_with(|| self.digits.cmp(&other.digits))
    }
}

fn exponent_digits(text: &str) -> Option<(bool, &str)> {
    let (negative, digits) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text.strip_prefix('+').unwrap_or(text)),
    };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    Some((negative, digits))
}

fn parse_exponent(text: &str) -> Option<i128> {
    let (negative, digits) = exponent_digits(text)?;
    let trimmed = digits.trim_start_matches('0');
    let magnitude: i128 = if trimmed.len() > 36 {
        return None;
    } else if trimmed.is_empty() {
        0
    } else {
        trimmed.parse().ok()?
    };
    Some(if negative { -magnitude } else { magnitude })
}

fn decimal_of(number: &serde_json::Number) -> Option<Decimal> {
    Decimal::parse(&number.to_string())
}

pub fn compare_numbers(a: &serde_json::Number, b: &serde_json::Number) -> Option<Ordering> {
    Some(compare_decimals(&decimal_of(a)?, &decimal_of(b)?))
}

pub fn between(
    min: &serde_json::Number,
    n: &serde_json::Number,
    max: &serde_json::Number,
) -> Option<bool> {
    let low = compare_numbers(min, n)?;
    let high = compare_numbers(n, max)?;
    Some(low != Ordering::Greater && high != Ordering::Greater)
}

pub fn is_readable(number: &serde_json::Number) -> bool {
    decimal_of(number).is_some()
}

pub fn all_readable(value: &Value) -> bool {
    match value {
        Value::Number(number) => is_readable(number),
        Value::Array(items) => items.iter().all(all_readable),
        Value::Object(map) => map.values().all(all_readable),
        _ => true,
    }
}

pub fn compare_decimals(a: &Decimal, b: &Decimal) -> Ordering {
    match (a.is_zero(), b.is_zero()) {
        (true, true) => return Ordering::Equal,
        (true, false) => {
            return if b.negative {
                Ordering::Greater
            } else {
                Ordering::Less
            };
        }
        (false, true) => {
            return if a.negative {
                Ordering::Less
            } else {
                Ordering::Greater
            };
        }
        _ => {}
    }
    match (a.negative, b.negative) {
        (false, true) => Ordering::Greater,
        (true, false) => Ordering::Less,
        (false, false) => a.magnitude_order(b),
        (true, true) => b.magnitude_order(a),
    }
}

pub fn equal(a: &Value, b: &Value) -> Option<bool> {
    match (a, b) {
        (Value::Null, Value::Null) => Some(true),
        (Value::Bool(x), Value::Bool(y)) => Some(x == y),
        (Value::Number(x), Value::Number(y)) => Some(compare_numbers(x, y)? == Ordering::Equal),
        (Value::String(x), Value::String(y)) => Some(x == y),
        (Value::Array(x), Value::Array(y)) if x.len() == y.len() => {
            all_equal(x.iter().zip(y).map(|(p, q)| equal(p, q)))
        }
        (Value::Object(x), Value::Object(y)) if x.len() == y.len() => all_equal(
            x.iter()
                .map(|(k, v)| y.get(k).map_or(Some(false), |w| equal(v, w))),
        ),
        _ => Some(false),
    }
}

pub fn copy_key(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => match decimal_of(n) {
            Some(d) => {
                let (negative, digits, exponent) = d.parts();
                format!("#{}{digits}e{exponent}", if negative { "-" } else { "" })
            }
            None => format!("#?{n}"),
        },
        Value::String(s) => Value::String(s.clone()).to_string(),
        Value::Array(items) => {
            let parts: Vec<String> = items.iter().map(copy_key).collect();
            format!("[{}]", parts.join(","))
        }
        Value::Object(map) => {
            let mut parts: Vec<(String, String)> = map
                .iter()
                .map(|(k, v)| (Value::String(k.clone()).to_string(), copy_key(v)))
                .collect();
            parts.sort();
            let joined: Vec<String> = parts.into_iter().map(|(k, v)| format!("{k}:{v}")).collect();
            format!("{{{}}}", joined.join(","))
        }
    }
}

pub fn copied_locations(locations: &[String], first: &str, copies: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    for location in locations {
        match location.strip_prefix(first) {
            Some(rest) if rest.is_empty() || rest.starts_with('/') => {
                out.push(location.clone());
                out.extend(copies.iter().map(|copy| format!("{copy}{rest}")));
            }
            _ => out.push(location.clone()),
        }
    }
    out
}

pub fn all_equal(pairs: impl Iterator<Item = Option<bool>>) -> Option<bool> {
    let pairs: Vec<Option<bool>> = pairs.collect();
    if pairs.contains(&Some(false)) {
        Some(false)
    } else if pairs.contains(&None) {
        None
    } else {
        Some(true)
    }
}

pub fn any_equal(pairs: impl Iterator<Item = Option<bool>>) -> Option<bool> {
    let pairs: Vec<Option<bool>> = pairs.collect();
    if pairs.contains(&Some(true)) {
        Some(true)
    } else if pairs.contains(&None) {
        None
    } else {
        Some(false)
    }
}

pub fn type_name(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "list",
        Value::Object(_) => "object",
    }
}

pub fn fits_a_float(number: &serde_json::Number) -> bool {
    Decimal::parse(&number.to_string()).is_some_and(|decimal| decimal.fits_a_float())
}

pub fn too_long(number: &serde_json::Number) -> bool {
    Decimal::parse(&number.to_string())
        .is_some_and(|decimal| decimal.fits_a_float() && decimal.parts().1.len() > 15)
}

pub fn out_of_range(value: &Value) -> bool {
    match value {
        Value::Number(number) => !fits_a_float(number),
        Value::Array(items) => items.iter().any(out_of_range),
        Value::Object(map) => map.values().any(out_of_range),
        _ => false,
    }
}

pub fn literal_text(value: &Value) -> String {
    if out_of_range(value) {
        "<number out of range>".to_string()
    } else {
        json_text(value)
    }
}

pub fn plain_number(number: &serde_json::Number) -> serde_json::Number {
    let written = number.to_string();
    match Decimal::parse(&written) {
        Some(decimal) if decimal.fits_a_float() => {
            serde_json::from_str(&decimal.plain_text()).unwrap_or_else(|_| number.clone())
        }
        _ => number.clone(),
    }
}

pub fn plain(value: &Value) -> Value {
    match value {
        Value::Number(number) => Value::Number(plain_number(number)),
        Value::Array(items) => Value::Array(items.iter().map(plain).collect()),
        Value::Object(map) => {
            Value::Object(map.iter().map(|(k, v)| (k.clone(), plain(v))).collect())
        }
        other => other.clone(),
    }
}

pub fn json_text(value: &Value) -> String {
    plain(value).to_string()
}

#[cfg(test)]
mod tests;
