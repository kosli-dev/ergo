use serde_json::{Number, Value};
use std::cmp::Ordering;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Cause {
    IllFormed,
    NotAnObject,
    Ambiguous,
    Unmatched,
    Unusable,
    Absent,
    Null,
    Value,
    Missing,
    Substituted,
    Satisfied,
}

impl Cause {
    pub fn name(self) -> &'static str {
        match self {
            Cause::IllFormed => "ill_formed",
            Cause::NotAnObject => "not_an_object",
            Cause::Ambiguous => "ambiguous",
            Cause::Unmatched => "unmatched",
            Cause::Unusable => "unusable",
            Cause::Absent => "absent",
            Cause::Null => "null",
            Cause::Value => "value",
            Cause::Missing => "missing",
            Cause::Substituted => "substituted",
            Cause::Satisfied => "satisfied",
        }
    }

    pub fn is_problem(self) -> bool {
        self < Cause::Value
    }
}

pub fn worst_or_value(causes: impl IntoIterator<Item = Cause>) -> Cause {
    causes.into_iter().filter(|c| c.is_problem()).min().unwrap_or(Cause::Value)
}

pub fn group_cause(causes: &[Cause]) -> Cause {
    if causes.contains(&Cause::Missing) { Cause::Value } else { worst_or_value(causes.iter().copied()) }
}

pub fn verdict(passed: bool) -> Cause {
    if passed { Cause::Satisfied } else { Cause::Value }
}

pub fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => number_order(x, y) == Some(Ordering::Equal),
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(a, b)| same(a, b)),
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w)))
        }
        _ => a == b,
    }
}

pub fn contains(list: &[Value], want: &Value) -> bool {
    list.iter().any(|v| same(v, want))
}

pub fn number_order(a: &Number, b: &Number) -> Option<Ordering> {
    match (a.as_i64(), b.as_i64(), a.as_u64(), b.as_u64()) {
        (Some(x), Some(y), _, _) => Some(x.cmp(&y)),
        (_, _, Some(x), Some(y)) => Some(x.cmp(&y)),
        _ => a.as_f64()?.partial_cmp(&b.as_f64()?),
    }
}

fn rank(v: &Value) -> u8 {
    match v {
        Value::Null => 0,
        Value::Bool(_) => 1,
        Value::Number(_) => 2,
        Value::String(_) => 3,
        Value::Array(_) => 4,
        Value::Object(_) => 5,
    }
}

pub fn rego_order(a: &Value, b: &Value) -> Ordering {
    match (a, b) {
        (Value::Bool(x), Value::Bool(y)) => x.cmp(y),
        (Value::Number(x), Value::Number(y)) => number_order(x, y).unwrap_or(Ordering::Equal),
        (Value::String(x), Value::String(y)) => x.cmp(y),
        (Value::Array(x), Value::Array(y)) => {
            for (p, q) in x.iter().zip(y) {
                let o = rego_order(p, q);
                if o != Ordering::Equal {
                    return o;
                }
            }
            x.len().cmp(&y.len())
        }
        (Value::Object(x), Value::Object(y)) => {
            let xk: Vec<&String> = x.keys().collect();
            let yk: Vec<&String> = y.keys().collect();
            for (p, q) in xk.iter().zip(&yk) {
                match p.cmp(q) {
                    Ordering::Equal => match rego_order(&x[*p], &y[*q]) {
                        Ordering::Equal => continue,
                        o => return o,
                    },
                    o => return o,
                }
            }
            xk.len().cmp(&yk.len())
        }
        _ => rank(a).cmp(&rank(b)),
    }
}

pub fn literal_text(v: &Value) -> String {
    match v {
        Value::Array(items) => format!("[{}]", items.iter().map(literal_text).collect::<Vec<_>>().join(", ")),
        Value::Object(m) => format!(
            "{{{}}}",
            m.iter()
                .map(|(k, v)| format!("{}: {}", Value::String(k.clone()), literal_text(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        other => other.to_string(),
    }
}

pub fn type_name(v: &Value) -> &'static str {
    match v {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

pub fn holds(cmp: &str, l: &Value, r: &Value) -> bool {
    match cmp {
        "eq" => same(l, r),
        "ne" => !same(l, r),
        _ => {
            let order = match (l, r) {
                (Value::Number(a), Value::Number(b)) => number_order(a, b),
                (Value::String(a), Value::String(b)) => Some(a.cmp(b)),
                _ => None,
            };
            order.is_some_and(|o| ordered(cmp, o))
        }
    }
}

pub fn ordered(cmp: &str, o: Ordering) -> bool {
    match cmp {
        "eq" => o == Ordering::Equal,
        "ne" => o != Ordering::Equal,
        "gt" => o == Ordering::Greater,
        "gte" => o != Ordering::Less,
        "lt" => o == Ordering::Less,
        _ => o != Ordering::Greater,
    }
}

pub fn timestamp_ns(v: &Value) -> Option<i128> {
    static SHAPE: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
    let shape = SHAPE.get_or_init(|| {
        regex::Regex::new(r"^(1[6-9][0-9]{2}|2[0-2][0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])(\.[0-9]+)?(Z|([+-])([01][0-9]|2[0-3]):([0-5][0-9]))$").unwrap()
    });
    let c = shape.captures(v.as_str()?)?;
    let n = |i: usize| c.get(i).map_or(0, |m| m.as_str().parse::<i128>().unwrap());
    let (year, month, day) = (n(1), n(2), n(3));
    if !(1678..=2261).contains(&year) {
        return None;
    }
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    let days_in = match month {
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => 31,
    };
    if day > days_in {
        return None;
    }
    let (y, m) = if month <= 2 { (year - 1, month + 9) } else { (year, month - 3) };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * m + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    let fraction = c.get(7).map_or(0, |m| {
        let digits: String = m.as_str()[1..].chars().chain(std::iter::repeat('0')).take(9).collect();
        digits.parse::<i128>().unwrap()
    });
    let offset = match c.get(9).map(|m| m.as_str()) {
        Some("-") => -(n(10) * 3600 + n(11) * 60),
        Some(_) => n(10) * 3600 + n(11) * 60,
        None => 0,
    };
    Some((days * 86400 + n(4) * 3600 + n(5) * 60 + n(6) - offset) * 1_000_000_000 + fraction)
}
