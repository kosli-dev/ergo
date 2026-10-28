use super::{Input, Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::path::{Ctx, Outcome, Path};
use crate::value;
use serde_json::{Number, Value};
use std::cmp::Ordering;

#[derive(Debug, Clone, PartialEq)]
pub enum Side {
    Path(Path),
    Value(Value),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cmp {
    Eq,
    Ne,
    Gt,
    Gte,
    Lt,
    Lte,
    StartsWith,
    EndsWith,
    AlphabeticallyBefore,
    AlphabeticallyAfter,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Compare {
    pub left: Side,
    pub right: Side,
    pub cmp: Cmp,
    pub within: Option<Number>,
}

pub struct SideRead {
    pub outcome: Outcome,
    pub value: Option<Value>,
    pub input: Option<Input>,
}

pub fn read_side(side: &Side, ctx: &Ctx) -> SideRead {
    match side {
        Side::Path(path) => {
            let read = read_path(path, ctx);
            SideRead {
                outcome: read.outcome,
                value: read.value,
                input: Some(read.input),
            }
        }
        Side::Value(Value::Null) => SideRead {
            outcome: Outcome::Null,
            value: None,
            input: None,
        },
        Side::Value(v) => SideRead {
            outcome: Outcome::Found,
            value: Some(v.clone()),
            input: None,
        },
    }
}

pub fn read_sides(left: &Side, right: &Side, ctx: &Ctx) -> (SideRead, SideRead, Vec<Input>) {
    let l = read_side(left, ctx);
    let r = read_side(right, ctx);
    let inputs = l.input.iter().chain(r.input.iter()).cloned().collect();
    (l, r, inputs)
}

pub fn unread_cause(l: &SideRead, r: &SideRead) -> Option<Cause> {
    Cause::worst([l.outcome, r.outcome].into_iter().filter_map(|o| o.cause()))
}

pub fn run(check: &Compare, ctx: &Ctx) -> Verdict {
    let (l, r, inputs) = read_sides(&check.left, &check.right, ctx);
    let cause = match unread_cause(&l, &r) {
        Some(cause) => cause,
        None => match (&l.value, &r.value) {
            (Some(a), Some(b)) => compared(check, a, b),
            _ => Cause::Unusable,
        },
    };
    Verdict { cause, inputs }
}

fn compared(check: &Compare, l: &Value, r: &Value) -> Cause {
    if let Some(distance) = &check.within {
        return match (l, r) {
            (Value::Number(a), Value::Number(b)) => verdict(within(a, b, distance)),
            _ => Cause::Unusable,
        };
    }
    match check.cmp {
        Cmp::Eq | Cmp::Ne if value::type_name(l) != value::type_name(r) => Cause::Unusable,
        Cmp::Eq => verdict(value::equal(l, r)),
        Cmp::Ne => verdict(!value::equal(l, r)),
        Cmp::Gt | Cmp::Gte | Cmp::Lt | Cmp::Lte => match (l, r) {
            (Value::Number(a), Value::Number(b)) => {
                verdict(ordered(check.cmp, value::compare_numbers(a, b)))
            }
            _ => Cause::Unusable,
        },
        Cmp::StartsWith | Cmp::EndsWith | Cmp::AlphabeticallyBefore | Cmp::AlphabeticallyAfter => {
            match (l, r) {
                (Value::String(a), Value::String(b)) => verdict(match check.cmp {
                    Cmp::StartsWith => a.starts_with(b.as_str()),
                    Cmp::EndsWith => a.ends_with(b.as_str()),
                    Cmp::AlphabeticallyBefore => a < b,
                    _ => a > b,
                }),
                _ => Cause::Unusable,
            }
        }
    }
}

pub fn ordered(cmp: Cmp, order: Ordering) -> bool {
    match cmp {
        Cmp::Gt => order == Ordering::Greater,
        Cmp::Gte => order != Ordering::Less,
        Cmp::Lt => order == Ordering::Less,
        Cmp::Lte => order != Ordering::Greater,
        Cmp::Eq => order == Ordering::Equal,
        Cmp::Ne => order != Ordering::Equal,
        _ => false,
    }
}

const WIDEST_EXACT_SPREAD: i64 = 4096;

struct Exact {
    negative: bool,
    digits: String,
    exponent: i64,
}

fn exact(number: &Number) -> Option<Exact> {
    let text = number.to_string();
    let (negative, rest) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text.as_str()),
    };
    let (mantissa, exponent) = match rest.split_once(['e', 'E']) {
        Some((m, e)) => (m, e.trim_start_matches('+').parse::<i64>().ok()?),
        None => (rest, 0),
    };
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let digits = format!("{whole}{fraction}");
    let digits = digits.trim_start_matches('0');
    Some(Exact {
        negative,
        digits: if digits.is_empty() {
            "0".to_string()
        } else {
            digits.to_string()
        },
        exponent: exponent.checked_sub(fraction.len() as i64)?,
    })
}

fn scaled(n: &Exact, exponent: i64) -> String {
    if n.digits == "0" {
        return "0".to_string();
    }
    format!(
        "{}{}",
        n.digits,
        "0".repeat((n.exponent - exponent) as usize)
    )
}

fn magnitude_order(a: &str, b: &str) -> Ordering {
    a.len().cmp(&b.len()).then_with(|| a.cmp(b))
}

fn add_magnitudes(a: &str, b: &str) -> String {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    let mut out = Vec::with_capacity(a.len().max(b.len()) + 1);
    let mut carry = 0;
    for i in 0..a.len().max(b.len()) {
        let x = if i < a.len() {
            a[a.len() - 1 - i] - b'0'
        } else {
            0
        };
        let y = if i < b.len() {
            b[b.len() - 1 - i] - b'0'
        } else {
            0
        };
        let sum = x + y + carry;
        out.push(b'0' + sum % 10);
        carry = sum / 10;
    }
    if carry > 0 {
        out.push(b'0' + carry);
    }
    trimmed(out)
}

fn subtract_magnitudes(a: &str, b: &str) -> String {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    let mut out = Vec::with_capacity(a.len());
    let mut borrow = 0;
    for i in 0..a.len() {
        let x = (a[a.len() - 1 - i] - b'0') as i8;
        let y = if i < b.len() {
            (b[b.len() - 1 - i] - b'0') as i8
        } else {
            0
        };
        let mut d = x - y - borrow;
        borrow = 0;
        if d < 0 {
            d += 10;
            borrow = 1;
        }
        out.push(b'0' + d as u8);
    }
    trimmed(out)
}

fn trimmed(mut reversed: Vec<u8>) -> String {
    while reversed.len() > 1 && reversed.last() == Some(&b'0') {
        reversed.pop();
    }
    reversed.reverse();
    String::from_utf8(reversed).unwrap_or_default()
}

fn within(a: &Number, b: &Number, distance: &Number) -> bool {
    let (Some(x), Some(y), Some(w)) = (exact(a), exact(b), exact(distance)) else {
        return within_as_floats(a, b, distance);
    };
    let exponents = [x.exponent, y.exponent, w.exponent];
    let low = exponents.iter().copied().min().unwrap_or(0);
    let high = exponents.iter().copied().max().unwrap_or(0);
    if high - low > WIDEST_EXACT_SPREAD {
        return within_as_floats(a, b, distance);
    }
    let (sx, sy, sw) = (scaled(&x, low), scaled(&y, low), scaled(&w, low));
    let gap = if x.negative != y.negative {
        add_magnitudes(&sx, &sy)
    } else if magnitude_order(&sx, &sy) == Ordering::Less {
        subtract_magnitudes(&sy, &sx)
    } else {
        subtract_magnitudes(&sx, &sy)
    };
    magnitude_order(&gap, &sw) != Ordering::Greater
}

fn within_as_floats(a: &Number, b: &Number, distance: &Number) -> bool {
    let float = |n: &Number| n.to_string().parse::<f64>().unwrap_or(f64::NAN);
    (float(a) - float(b)).abs() <= float(distance)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{Located, Location, Start, Step};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn field(name: &str) -> Side {
        Side::Path(Path {
            start: Start::Subject,
            steps: vec![Step::Key(name.to_string())],
        })
    }

    fn check(cmp: Cmp, right: Side) -> Compare {
        Compare {
            left: field("a"),
            right,
            cmp,
            within: None,
        }
    }

    fn number(text: &str) -> Number {
        match serde_json::from_str::<Value>(text).unwrap() {
            Value::Number(n) => n,
            _ => panic!("{text} isn't a number"),
        }
    }

    fn run_on(subject: Value, check: &Compare) -> Verdict {
        let input = json!({"things": [subject]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        run(check, &ctx)
    }

    fn cause(subject: Value, check: &Compare) -> Cause {
        run_on(subject, check).cause
    }

    fn parsed(text: &str) -> Value {
        serde_json::from_str(text).unwrap()
    }

    #[test]
    fn eq_compares_by_value() {
        let eq = check(Cmp::Eq, field("b"));
        assert_eq!(
            cause(parsed(r#"{"a": 1, "b": 1.0}"#), &eq),
            Cause::Satisfied
        );
        assert_eq!(
            cause(parsed(r#"{"a": {"n": 1}, "b": {"n": 1.0}}"#), &eq),
            Cause::Satisfied
        );
        assert_eq!(cause(json!({"a": 1, "b": 2}), &eq), Cause::Value);
    }

    #[test]
    fn eq_and_ne_fail_as_unusable_when_the_types_differ() {
        for cmp in [Cmp::Eq, Cmp::Ne] {
            assert_eq!(
                cause(json!({"a": "1", "b": 1}), &check(cmp, field("b"))),
                Cause::Unusable
            );
        }
    }

    #[test]
    fn ne_passes_on_different_values_of_one_type() {
        assert_eq!(
            cause(json!({"a": "x", "b": "y"}), &check(Cmp::Ne, field("b"))),
            Cause::Satisfied
        );
        assert_eq!(
            cause(json!({"a": "x", "b": "x"}), &check(Cmp::Ne, field("b"))),
            Cause::Value
        );
    }

    #[test]
    fn two_null_fields_fail_as_null_even_with_eq() {
        assert_eq!(
            cause(json!({"a": null, "b": null}), &check(Cmp::Eq, field("b"))),
            Cause::Null
        );
    }

    #[test]
    fn the_worse_outcome_of_the_two_sides_wins() {
        let eq = check(Cmp::Eq, field("b"));
        assert_eq!(cause(json!({"b": null}), &eq), Cause::Absent);
        assert_eq!(cause(json!({"a": null}), &eq), Cause::Absent);
        assert_eq!(
            cause(
                json!({"a": {"x": 1}, "b": "s"}),
                &check(
                    Cmp::Eq,
                    Side::Path(Path {
                        start: Start::Subject,
                        steps: vec![Step::Key("b".into()), Step::Key("c".into())],
                    })
                )
            ),
            Cause::Unusable
        );
    }

    #[test]
    fn order_only_works_on_two_numbers() {
        let lt = check(Cmp::Lt, field("b"));
        assert_eq!(cause(json!({"a": 1, "b": 2}), &lt), Cause::Satisfied);
        assert_eq!(cause(json!({"a": 2, "b": 1}), &lt), Cause::Value);
        assert_eq!(cause(json!({"a": "80", "b": "9"}), &lt), Cause::Unusable);
        assert_eq!(cause(json!({"a": false, "b": true}), &lt), Cause::Unusable);
        assert_eq!(
            cause(json!({"a": {"n": 1}, "b": {"o": 1}}), &lt),
            Cause::Unusable
        );
        assert_eq!(cause(json!({"a": 1, "b": "2"}), &lt), Cause::Unusable);
    }

    #[test]
    fn each_order_cmp_compares_by_value() {
        let subject = parsed(r#"{"a": 2, "b": 2.0, "c": 3}"#);
        let to_b = |cmp| cause(subject.clone(), &check(cmp, field("b")));
        let to_c = |cmp| cause(subject.clone(), &check(cmp, field("c")));
        assert_eq!(to_b(Cmp::Gte), Cause::Satisfied);
        assert_eq!(to_b(Cmp::Lte), Cause::Satisfied);
        assert_eq!(to_b(Cmp::Gt), Cause::Value);
        assert_eq!(to_b(Cmp::Lt), Cause::Value);
        assert_eq!(to_c(Cmp::Lt), Cause::Satisfied);
        assert_eq!(to_c(Cmp::Gt), Cause::Value);
    }

    #[test]
    fn a_written_value_on_the_right_has_no_input() {
        let v = run_on(json!({"a": 6}), &check(Cmp::Gte, Side::Value(json!(5))));
        assert_eq!(v.cause, Cause::Satisfied);
        assert_eq!(v.inputs.len(), 1);
        assert_eq!(v.inputs[0].name, ".a");
    }

    #[test]
    fn inputs_are_left_then_right() {
        let v = run_on(json!({"a": 1, "b": 2}), &check(Cmp::Lt, field("b")));
        let names: Vec<_> = v.inputs.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(names, [".a", "b"]);
        assert_eq!(v.inputs[0].locations, ["/things/0/a"]);
    }

    #[test]
    fn a_missing_side_still_has_its_input() {
        let v = run_on(json!({"b": 5}), &check(Cmp::Lt, field("b")));
        assert_eq!(v.cause, Cause::Absent);
        assert_eq!(v.inputs[0].value, Value::Null);
        assert_eq!(v.inputs[0].locations, ["/things/0"]);
    }

    #[test]
    fn starts_with_and_ends_with_take_two_strings() {
        let starts = check(Cmp::StartsWith, field("b"));
        let ends = check(Cmp::EndsWith, field("b"));
        assert_eq!(
            cause(json!({"a": "release/1", "b": "release/"}), &starts),
            Cause::Satisfied
        );
        assert_eq!(
            cause(json!({"a": "main", "b": "release/"}), &starts),
            Cause::Value
        );
        assert_eq!(
            cause(json!({"a": "a.md", "b": ".md"}), &ends),
            Cause::Satisfied
        );
        assert_eq!(cause(json!({"a": 12, "b": 1}), &starts), Cause::Unusable);
        assert_eq!(cause(json!({"a": "1", "b": 1}), &ends), Cause::Unusable);
    }

    #[test]
    fn alphabetical_order_is_by_code_point() {
        let before = check(Cmp::AlphabeticallyBefore, field("b"));
        let after = check(Cmp::AlphabeticallyAfter, field("b"));
        assert_eq!(
            cause(json!({"a": "Zoe", "b": "adam"}), &before),
            Cause::Satisfied
        );
        assert_eq!(
            cause(json!({"a": "\u{ff01}", "b": "\u{1f600}"}), &before),
            Cause::Satisfied
        );
        assert_eq!(
            cause(json!({"a": "\u{1f600}", "b": "\u{ff01}"}), &after),
            Cause::Satisfied
        );
        assert_eq!(cause(json!({"a": "x", "b": "x"}), &before), Cause::Value);
        assert_eq!(cause(json!({"a": "x", "b": "x"}), &after), Cause::Value);
        assert_eq!(cause(json!({"a": 1, "b": 2}), &before), Cause::Unusable);
    }

    #[test]
    fn within_passes_on_numbers_at_most_that_far_apart() {
        let near = |a: &str, b: &str, w: &str| {
            let c = Compare {
                left: field("a"),
                right: Side::Value(parsed(b)),
                cmp: Cmp::Eq,
                within: Some(number(w)),
            };
            cause(json!({"a": parsed(a)}), &c)
        };
        assert_eq!(near("1.4", "1", "0.5"), Cause::Satisfied);
        assert_eq!(near("1.5", "1", "0.5"), Cause::Satisfied);
        assert_eq!(near("0.5", "1", "0.5"), Cause::Satisfied);
        assert_eq!(near("1.6", "1", "0.5"), Cause::Value);
        assert_eq!(near("0.3", "0.1", "0.2"), Cause::Satisfied);
        assert_eq!(near("-1", "1", "2"), Cause::Satisfied);
        assert_eq!(near("-1", "1", "1.9"), Cause::Value);
        assert_eq!(near("1e2", "99", "1"), Cause::Satisfied);
        assert_eq!(near("5", "5", "0"), Cause::Satisfied);
    }

    #[test]
    fn within_falls_back_to_floats_for_numbers_far_outside_what_a_float_keeps() {
        let c = Compare {
            left: field("a"),
            right: Side::Value(parsed("1e-9000")),
            cmp: Cmp::Eq,
            within: Some(number("1")),
        };
        assert_eq!(cause(json!({"a": parsed("1e9000")}), &c), Cause::Value);
        assert_eq!(cause(json!({"a": parsed("0.5")}), &c), Cause::Satisfied);
    }

    #[test]
    fn within_fails_as_unusable_on_anything_but_two_numbers() {
        let c = Compare {
            left: field("a"),
            right: field("b"),
            cmp: Cmp::Eq,
            within: Some(number("1")),
        };
        assert_eq!(cause(json!({"a": "1", "b": 1}), &c), Cause::Unusable);
        assert_eq!(cause(json!({"a": "1", "b": "1"}), &c), Cause::Unusable);
        assert_eq!(cause(json!({"b": 1}), &c), Cause::Absent);
    }
}
