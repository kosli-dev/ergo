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
        let written_exponent = match exp_text {
            None => 0,
            Some(t) => parse_exponent(t)?,
        };
        let mut exponent = written_exponent - frac_part.len() as i128;
        let all = format!("{int_part}{frac_part}");
        let trimmed = all.trim_start_matches('0');
        let stripped = trimmed.trim_end_matches('0');
        exponent += (trimmed.len() - stripped.len()) as i128;
        if stripped.is_empty() {
            return Some(Decimal {
                negative: false,
                digits: String::new(),
                exponent: 0,
            });
        }
        Some(Decimal {
            negative,
            digits: stripped.to_string(),
            exponent,
        })
    }

    pub fn is_zero(&self) -> bool {
        self.digits.is_empty()
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

    fn magnitude_order(&self, other: &Decimal) -> Ordering {
        let a = self.digits.len() as i128 + self.exponent;
        let b = other.digits.len() as i128 + other.exponent;
        a.cmp(&b).then_with(|| self.digits.cmp(&other.digits))
    }
}

fn parse_exponent(text: &str) -> Option<i128> {
    let (negative, digits) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text.strip_prefix('+').unwrap_or(text)),
    };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let trimmed = digits.trim_start_matches('0');
    let magnitude: i128 = if trimmed.len() > 30 {
        10i128.pow(30)
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

pub fn compare_numbers(a: &serde_json::Number, b: &serde_json::Number) -> Ordering {
    match (decimal_of(a), decimal_of(b)) {
        (Some(x), Some(y)) => compare_decimals(&x, &y),
        _ => Ordering::Equal,
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

pub fn equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Null, Value::Null) => true,
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Number(x), Value::Number(y)) => match (decimal_of(x), decimal_of(y)) {
            (Some(p), Some(q)) => compare_decimals(&p, &q) == Ordering::Equal,
            _ => false,
        },
        (Value::String(x), Value::String(y)) => x == y,
        (Value::Array(x), Value::Array(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| equal(p, q))
        }
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| equal(v, w)))
        }
        _ => false,
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

pub fn json_text(value: &Value) -> String {
    value.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(text: &str) -> Value {
        serde_json::from_str(text).unwrap()
    }

    fn num(text: &str) -> serde_json::Number {
        match v(text) {
            Value::Number(n) => n,
            _ => panic!("not a number"),
        }
    }

    #[test]
    fn one_written_four_ways_is_equal() {
        for other in ["1.0", "1e0", "10e-1", "0.1e1", "1.000"] {
            assert!(equal(&v("1"), &v(other)), "{other}");
        }
    }

    #[test]
    fn numbers_past_a_float_are_compared_exactly() {
        assert!(!equal(&v("9007199254740993"), &v("9007199254740992")));
        assert_eq!(
            compare_numbers(&num("9007199254740993"), &num("9007199254740992")),
            Ordering::Greater
        );
    }

    #[test]
    fn huge_exponents_are_compared_without_a_float() {
        assert!(equal(&v("1e400"), &v("10e399")));
        assert!(!equal(&v("1e400"), &v("1e401")));
        assert!(equal(&v("1e-400"), &v("10e-401")));
        assert_eq!(
            compare_numbers(&num("1e400"), &num("1e399")),
            Ordering::Greater
        );
        assert_eq!(
            compare_numbers(&num("1e-400"), &num("0")),
            Ordering::Greater
        );
    }

    #[test]
    fn an_exponent_too_big_for_any_integer_still_orders() {
        let big = "1e99999999999999999999999999999999999999999";
        assert_eq!(compare_numbers(&num(big), &num("1e400")), Ordering::Greater);
        assert_eq!(compare_numbers(&num("1e400"), &num(big)), Ordering::Less);
    }

    #[test]
    fn zero_is_zero_however_it_is_written() {
        for zero in ["0", "0.0", "-0", "0e5", "-0.000e-3"] {
            assert!(equal(&v("0"), &v(zero)), "{zero}");
        }
    }

    #[test]
    fn numbers_order_by_sign_then_size() {
        let order = |a, b| compare_numbers(&num(a), &num(b));
        assert_eq!(order("-1", "1"), Ordering::Less);
        assert_eq!(order("-2", "-1"), Ordering::Less);
        assert_eq!(order("-1", "-2"), Ordering::Greater);
        assert_eq!(order("-1", "0"), Ordering::Less);
        assert_eq!(order("0", "-1"), Ordering::Greater);
        assert_eq!(order("0", "1"), Ordering::Less);
        assert_eq!(order("1", "0"), Ordering::Greater);
        assert_eq!(order("0.5", "0.25"), Ordering::Greater);
        assert_eq!(order("12", "123"), Ordering::Less);
        assert_eq!(order("99", "100"), Ordering::Less);
        assert_eq!(order("0.001", "0.01"), Ordering::Less);
    }

    #[test]
    fn a_string_never_equals_a_number() {
        assert!(!equal(&v("\"1\""), &v("1")));
    }

    #[test]
    fn types_never_equal_each_other() {
        assert!(!equal(&v("null"), &v("false")));
        assert!(!equal(&v("0"), &v("false")));
        assert!(!equal(&v("[]"), &v("{}")));
        assert!(!equal(&v("null"), &v("0")));
    }

    #[test]
    fn lists_compare_in_order_and_by_length() {
        assert!(equal(&v("[1, 2]"), &v("[1.0, 2e0]")));
        assert!(!equal(&v("[1, 2]"), &v("[2, 1]")));
        assert!(!equal(&v("[1]"), &v("[1, 1]")));
    }

    #[test]
    fn objects_compare_by_keys_whatever_their_order() {
        assert!(equal(
            &v("{\"a\": 1, \"b\": 2}"),
            &v("{\"b\": 2.0, \"a\": 1}")
        ));
        assert!(!equal(&v("{\"a\": 1}"), &v("{\"a\": 1, \"b\": 2}")));
        assert!(!equal(
            &v("{\"a\": 1, \"b\": 2}"),
            &v("{\"a\": 1, \"c\": 2}")
        ));
        assert!(!equal(&v("{\"a\": null}"), &v("{\"b\": null}")));
    }

    #[test]
    fn strings_compare_by_code_points() {
        assert!(equal(&v("\"\\u00e9\""), &v("\"é\"")));
        assert!(!equal(&v("\"e\\u0301\""), &v("\"é\"")));
    }

    #[test]
    fn type_names_are_the_spec_words() {
        assert_eq!(type_name(&v("null")), "null");
        assert_eq!(type_name(&v("true")), "boolean");
        assert_eq!(type_name(&v("1")), "number");
        assert_eq!(type_name(&v("\"s\"")), "string");
        assert_eq!(type_name(&v("[]")), "list");
        assert_eq!(type_name(&v("{}")), "object");
    }

    #[test]
    fn json_text_keeps_numbers_as_serde_json_keeps_them() {
        assert_eq!(json_text(&v("1.0")), "1.0");
        assert_eq!(json_text(&v("1e400")), "1e+400");
        assert_eq!(json_text(&v("[1, \"a\"]")), "[1,\"a\"]");
    }

    #[test]
    fn json_text_sorts_as_bytes() {
        let mut texts = [
            json_text(&v("3")),
            json_text(&v("10")),
            json_text(&v("\"b\"")),
        ];
        texts.sort();
        assert_eq!(texts, ["\"b\"", "10", "3"]);
    }

    #[test]
    fn positions_are_whole_numbers_up_to_the_largest_a_float_holds() {
        let pos = |t: &str| Decimal::parse(t).unwrap().as_position();
        assert_eq!(pos("0"), Some(0));
        assert_eq!(pos("-0"), Some(0));
        assert_eq!(pos("3"), Some(3));
        assert_eq!(pos("3.0"), Some(3));
        assert_eq!(pos("1e2"), Some(100));
        assert_eq!(pos("9007199254740991"), Some(9_007_199_254_740_991));
        assert_eq!(pos("9007199254740992"), None);
        assert_eq!(pos("1.5"), None);
        assert_eq!(pos("-1"), None);
        assert_eq!(pos("1e400"), None);
        assert_eq!(pos("1e-1"), None);
    }

    #[test]
    fn text_that_is_not_a_number_does_not_parse() {
        for bad in ["", "-", ".", "1e", "1ea", "a", "1.2.3", "1e+"] {
            assert!(Decimal::parse(bad).is_none(), "{bad}");
        }
    }
}
