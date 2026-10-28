use super::compare::{self, Cmp, Compare};
use super::time::{self, NANOS_PER_SECOND, SECONDS_PER_DAY, Time};
use super::{Check, Input, Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::lower::Scope;
use crate::path::{Ctx, Path};
use crate::value;
use ergo_sentences as s;
use serde_json::{Number, Value};
use std::cmp::Ordering;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unit {
    Seconds,
    Minutes,
    Hours,
    Days,
    Weeks,
}

impl Unit {
    fn seconds(self) -> i128 {
        match self {
            Unit::Seconds => 1,
            Unit::Minutes => 60,
            Unit::Hours => 3600,
            Unit::Days => 86_400,
            Unit::Weeks => 604_800,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Elapsed {
    pub text: String,
    pub unit: Unit,
    pub from: Path,
    pub to: Path,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Term {
    Path(Path),
    Number(Number),
    Elapsed(Elapsed),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Derived {
    pub text: String,
    pub terms: Vec<Term>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Side {
    Plain(compare::Side),
    Derived(Derived),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Test {
    Compare { cmp: Cmp, within: Option<Number> },
    Between { min: Number, max: Number },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tally {
    pub left: Side,
    pub right: Option<Side>,
    pub test: Test,
}

struct Worked<T> {
    result: Result<T, Cause>,
    entries: Vec<Input>,
}

const MOST_SECONDS: i64 = 9_000_000_000;
const MICROS: i128 = 1_000_000;

pub fn run(check: &Tally, ctx: &Ctx) -> Verdict {
    let left = work_side(&check.left, ctx);
    let right = check.right.as_ref().map(|side| work_side(side, ctx));
    let mut entries = left.entries;
    let mut causes = Vec::new();
    if let Err(cause) = &left.result {
        causes.push(*cause);
    }
    let mut right_value = None;
    if let Some(right) = right {
        entries.extend(right.entries);
        match right.result {
            Ok(v) => right_value = Some(v),
            Err(cause) => causes.push(cause),
        }
    }
    let cause = match (Cause::worst(causes), left.result) {
        (Some(cause), _) => cause,
        (None, Ok(left)) => decide(&check.test, &left, right_value, ctx),
        (None, Err(_)) => Cause::Unusable,
    };
    Verdict {
        cause,
        inputs: merged(entries),
    }
}

fn decide(test: &Test, left: &Value, right: Option<Value>, ctx: &Ctx) -> Cause {
    match (test, right) {
        (Test::Compare { cmp, within }, Some(right)) => {
            let compare = Compare {
                left: compare::Side::Value(left.clone()),
                right: compare::Side::Value(right),
                cmp: *cmp,
                within: within.clone(),
            };
            compare::run(&compare, ctx).cause
        }
        (Test::Between { min, max }, None) => match left {
            Value::Number(n) => verdict(
                value::compare_numbers(min, n) != Ordering::Greater
                    && value::compare_numbers(n, max) != Ordering::Greater,
            ),
            _ => Cause::Unusable,
        },
        _ => Cause::Unusable,
    }
}

fn merged(entries: Vec<Input>) -> Vec<Input> {
    let mut out: Vec<Input> = Vec::new();
    for entry in entries {
        if !out.contains(&entry) {
            out.push(entry);
        }
    }
    out
}

fn work_side(side: &Side, ctx: &Ctx) -> Worked<Value> {
    match side {
        Side::Plain(side) => {
            let read = compare::read_side(side, ctx);
            let result = match (read.outcome.cause(), read.value) {
                (Some(cause), _) => Err(cause),
                (None, Some(v)) => Ok(v),
                (None, None) => Err(Cause::Unusable),
            };
            Worked {
                result,
                entries: read.input.into_iter().collect(),
            }
        }
        Side::Derived(derived) => {
            let worked = work_derived(derived, ctx);
            Worked {
                result: worked.result.map(Value::Number),
                entries: worked.entries,
            }
        }
    }
}

fn number_entry(text: &str, result: &Result<Number, Cause>, below: &[Input]) -> Input {
    let mut locations: Vec<String> = Vec::new();
    for location in below.iter().flat_map(|entry| &entry.locations) {
        if !locations.contains(location) {
            locations.push(location.clone());
        }
    }
    Input {
        name: text.to_string(),
        value: match result {
            Ok(n) => Value::Number(n.clone()),
            Err(_) => Value::Null,
        },
        locations,
        part: None,
    }
}

fn work_derived(derived: &Derived, ctx: &Ctx) -> Worked<Number> {
    let mut worked: Vec<Worked<Number>> = derived
        .terms
        .iter()
        .map(|term| work_term(term, ctx))
        .collect();
    if worked.len() == 1 {
        return worked.remove(0);
    }
    let cause = Cause::worst(
        worked
            .iter()
            .filter_map(|w| w.result.as_ref().err().copied()),
    );
    let result = match cause {
        Some(cause) => Err(cause),
        None => {
            let numbers: Vec<Number> = worked
                .iter()
                .filter_map(|w| w.result.as_ref().ok().cloned())
                .collect();
            add(&numbers).ok_or(Cause::Unusable)
        }
    };
    let below: Vec<Input> = worked.into_iter().flat_map(|w| w.entries).collect();
    let mut entries = vec![number_entry(&derived.text, &result, &below)];
    entries.extend(below);
    Worked { result, entries }
}

fn work_term(term: &Term, ctx: &Ctx) -> Worked<Number> {
    match term {
        Term::Number(n) => Worked {
            result: Ok(n.clone()),
            entries: Vec::new(),
        },
        Term::Path(path) => {
            let read = read_path(path, ctx);
            let result = match (read.outcome.cause(), read.value) {
                (Some(cause), _) => Err(cause),
                (None, Some(Value::Number(n))) => Ok(n),
                (None, _) => Err(Cause::Unusable),
            };
            Worked {
                result,
                entries: vec![read.input],
            }
        }
        Term::Elapsed(elapsed) => work_elapsed(elapsed, ctx),
    }
}

fn work_elapsed(elapsed: &Elapsed, ctx: &Ctx) -> Worked<Number> {
    let from = read_path(&elapsed.from, ctx);
    let to = read_path(&elapsed.to, ctx);
    let unread = Cause::worst(
        [from.outcome, to.outcome]
            .into_iter()
            .filter_map(|o| o.cause()),
    );
    let result = match unread {
        Some(cause) => Err(cause),
        None => match (&from.value, &to.value) {
            (Some(a), Some(b)) => elapsed_between(elapsed.unit, a, b),
            _ => Err(Cause::Unusable),
        },
    };
    let below = vec![from.input, to.input];
    let mut entries = vec![number_entry(&elapsed.text, &result, &below)];
    entries.extend(below);
    Worked { result, entries }
}

fn elapsed_between(unit: Unit, from: &Value, to: &Value) -> Result<Number, Cause> {
    let (Some(a), Some(b)) = (time::read_time(from), time::read_time(to)) else {
        return Err(Cause::Unusable);
    };
    let nanos = match (&a, &b) {
        (Time::Instant(x), Time::Instant(y)) => y - x,
        (Time::Date(x), Time::Date(y)) => {
            (*y as i128 - *x as i128) * SECONDS_PER_DAY as i128 * NANOS_PER_SECOND
        }
        (Time::Number(x), Time::Number(y)) => {
            let (x, y) = (seconds_in_micros(x)?, seconds_in_micros(y)?);
            (y - x) * 1000
        }
        _ => return Err(Cause::Unusable),
    };
    if nanos < 0 {
        return Err(Cause::Value);
    }
    let step = unit.seconds() * 1000;
    micro_units_text(nanos / step)
}

fn micro_units_text(micro_units: i128) -> Result<Number, Cause> {
    let whole = micro_units / MICROS;
    let fraction = micro_units % MICROS;
    let text = if fraction == 0 {
        whole.to_string()
    } else {
        let digits = format!("{fraction:06}");
        format!("{whole}.{}", digits.trim_end_matches('0'))
    };
    text.parse::<Number>().map_err(|_| Cause::Unusable)
}

fn seconds_in_micros(n: &Number) -> Result<i128, Cause> {
    let limit = |v: i64| Number::from(v);
    if value::compare_numbers(n, &limit(-MOST_SECONDS)) == Ordering::Less
        || value::compare_numbers(n, &limit(MOST_SECONDS)) == Ordering::Greater
    {
        return Err(Cause::Unusable);
    }
    let parts = Parts::of(&n.to_string()).ok_or(Cause::Unusable)?;
    let shift = parts.exponent + 6;
    let magnitude: i128 = if parts.digits.is_empty() {
        0
    } else if shift >= 0 {
        if parts.digits.len() as i64 + shift > 30 {
            return Err(Cause::Unusable);
        }
        let scaled = format!("{}{}", parts.digits, "0".repeat(shift as usize));
        scaled.parse().map_err(|_| Cause::Unusable)?
    } else {
        let cut = (-shift) as usize;
        if cut > parts.digits.len() {
            0
        } else {
            let (head, tail) = parts.digits.split_at(parts.digits.len() - cut);
            let head: i128 = if head.is_empty() {
                0
            } else {
                head.parse().map_err(|_| Cause::Unusable)?
            };
            if tail.as_bytes().first().is_some_and(|d| *d >= b'5') {
                head + 1
            } else {
                head
            }
        }
    };
    Ok(if parts.negative {
        -magnitude
    } else {
        magnitude
    })
}

struct Parts {
    negative: bool,
    digits: String,
    exponent: i64,
}

impl Parts {
    fn of(text: &str) -> Option<Parts> {
        let (negative, rest) = match text.strip_prefix('-') {
            Some(rest) => (true, rest),
            None => (false, text),
        };
        let (mantissa, written) = match rest.split_once(['e', 'E']) {
            Some((m, e)) => (m, e.trim_start_matches('+').parse::<i64>().ok()?),
            None => (rest, 0),
        };
        let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
        let all = format!("{whole}{fraction}");
        if all.is_empty() || !all.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        let trimmed = all.trim_start_matches('0');
        let stripped = trimmed.trim_end_matches('0');
        if stripped.is_empty() {
            return Some(Parts {
                negative: false,
                digits: String::new(),
                exponent: 0,
            });
        }
        let exponent = written
            .checked_sub(fraction.len() as i64)?
            .checked_add((trimmed.len() - stripped.len()) as i64)?;
        Some(Parts {
            negative,
            digits: stripped.to_string(),
            exponent,
        })
    }
}

const WIDEST_SPREAD: i64 = 100_000;

fn add(numbers: &[Number]) -> Option<Number> {
    let parts: Vec<Parts> = numbers
        .iter()
        .map(|n| Parts::of(&n.to_string()))
        .collect::<Option<_>>()?;
    let nonzero: Vec<&Parts> = parts.iter().filter(|p| !p.digits.is_empty()).collect();
    let Some(low) = nonzero.iter().map(|p| p.exponent).min() else {
        return "0".parse().ok();
    };
    let reach = nonzero
        .iter()
        .map(|p| p.exponent.saturating_add(p.digits.len() as i64))
        .max()?;
    if reach.saturating_sub(low) > WIDEST_SPREAD {
        return None;
    }
    let mut positive = "0".to_string();
    let mut negative = "0".to_string();
    for part in nonzero {
        let scaled = format!(
            "{}{}",
            part.digits,
            "0".repeat((part.exponent - low) as usize)
        );
        if part.negative {
            negative = compare::add_magnitudes(&negative, &scaled);
        } else {
            positive = compare::add_magnitudes(&positive, &scaled);
        }
    }
    let (is_negative, magnitude) = match compare::magnitude_order(&positive, &negative) {
        Ordering::Less => (true, compare::subtract_magnitudes(&negative, &positive)),
        _ => (false, compare::subtract_magnitudes(&positive, &negative)),
    };
    scaled_text(is_negative, &magnitude, low)
        .parse::<Number>()
        .ok()
}

fn scaled_text(negative: bool, magnitude: &str, exponent: i64) -> String {
    if magnitude == "0" {
        return "0".to_string();
    }
    let sign = if negative { "-" } else { "" };
    if exponent >= 0 {
        return format!("{sign}{magnitude}{}", "0".repeat(exponent as usize));
    }
    let places = (-exponent) as usize;
    let padded = format!("{magnitude:0>width$}", width = places + 1);
    let (whole, fraction) = padded.split_at(padded.len() - places);
    let fraction = fraction.trim_end_matches('0');
    if fraction.is_empty() {
        format!("{sign}{whole}")
    } else {
        format!("{sign}{whole}.{fraction}")
    }
}

fn term_text(term: &s::Term, names: &[&str]) -> String {
    s::print_term(term, names)
}

fn lower_term(term: &s::Term, scope: &Scope, names: &[&str]) -> Result<Option<Term>, Vec<String>> {
    match term {
        s::Term::Path(path) => scope.path(path).map(|p| Some(Term::Path(p))),
        s::Term::Number(text) => match scope.value(&s::Value::Number(text.clone()))? {
            Value::Number(n) => Ok(Some(Term::Number(n))),
            _ => Ok(None),
        },
        s::Term::Elapsed(elapsed) => {
            let from = scope.path(&elapsed.from);
            let to = scope.path(&elapsed.to);
            match (from, to) {
                (Ok(from), Ok(to)) => Ok(Some(Term::Elapsed(Elapsed {
                    text: term_text(term, names),
                    unit: match elapsed.unit {
                        s::Unit::Seconds => Unit::Seconds,
                        s::Unit::Minutes => Unit::Minutes,
                        s::Unit::Hours => Unit::Hours,
                        s::Unit::Days => Unit::Days,
                        s::Unit::Weeks => Unit::Weeks,
                    },
                    from,
                    to,
                }))),
                (from, to) => Err(from.err().into_iter().chain(to.err()).flatten().collect()),
            }
        }
        s::Term::Derived(_) => Ok(None),
    }
}

fn lower_side(
    terms: &[s::Term],
    scope: &Scope,
    names: &[&str],
) -> Result<Option<Side>, Vec<String>> {
    let mut lowered = Vec::new();
    let mut problems = Vec::new();
    let mut not_yet = false;
    for term in terms {
        match lower_term(term, scope, names) {
            Ok(Some(term)) => lowered.push(term),
            Ok(None) => not_yet = true,
            Err(found) => problems.extend(found),
        }
    }
    if !problems.is_empty() {
        return Err(problems);
    }
    if not_yet {
        return Ok(None);
    }
    Ok(Some(match lowered.as_slice() {
        [Term::Path(path)] => Side::Plain(compare::Side::Path(path.clone())),
        [Term::Number(n)] => Side::Plain(compare::Side::Value(Value::Number(n.clone()))),
        _ => Side::Derived(Derived {
            text: terms
                .iter()
                .map(|t| term_text(t, names))
                .collect::<Vec<_>>()
                .join(" plus "),
            terms: lowered,
        }),
    }))
}

fn mine(terms: &[s::Term]) -> bool {
    terms.len() > 1 || terms.iter().any(|t| !matches!(t, s::Term::Path(_)))
}

fn plain_right(
    operand: &s::Operand,
    scope: &Scope,
    names: &[&str],
) -> Result<Option<Side>, Vec<String>> {
    match operand {
        s::Operand::Value(v) => Ok(Some(Side::Plain(compare::Side::Value(scope.value(v)?)))),
        s::Operand::Field(terms) => lower_side(terms, scope, names),
    }
}

fn number(text: &str, scope: &Scope) -> Result<Number, Vec<String>> {
    match scope.value(&s::Value::Number(text.to_string()))? {
        Value::Number(n) => Ok(n),
        _ => Err(vec![format!("{text} isn't a number")]),
    }
}

type Tested = (Test, Option<Side>);

fn lower_test(
    phrase: &s::Phrase,
    scope: &Scope,
    names: &[&str],
) -> Option<Result<Tested, Vec<String>>> {
    let compared = |cmp: Cmp, within: Option<Number>, operand: &s::Operand| {
        plain_right(operand, scope, names)
            .transpose()
            .map(|right| right.map(|right| (Test::Compare { cmp, within }, Some(right))))
    };
    match phrase {
        s::Phrase::Is {
            not,
            operand,
            within,
        } => {
            if *not && within.is_some() {
                return None;
            }
            let within = match within {
                Some(text) => match number(text, scope) {
                    Ok(n) => Some(n),
                    Err(found) => return Some(Err(found)),
                },
                None => None,
            };
            compared(if *not { Cmp::Ne } else { Cmp::Eq }, within, operand)
        }
        s::Phrase::Order { order, operand } => compared(
            match order {
                s::Order::AtLeast => Cmp::Gte,
                s::Order::AtMost => Cmp::Lte,
                s::Order::MoreThan => Cmp::Gt,
                s::Order::LessThan => Cmp::Lt,
            },
            None,
            operand,
        ),
        s::Phrase::Between { min, max } => Some(
            number(min, scope)
                .and_then(|min| number(max, scope).map(|max| (min, max)))
                .map(|(min, max)| (Test::Between { min, max }, None)),
        ),
        _ => None,
    }
}

pub fn lower_assertion(
    assertion: &s::Assertion,
    scope: &Scope,
) -> Option<Result<Check, Vec<String>>> {
    let (left, phrase): (Vec<s::Term>, &s::Phrase) = match assertion {
        s::Assertion::Derived { terms, phrase } => (terms.clone(), phrase),
        s::Assertion::Plain {
            path,
            phrase:
                phrase @ (s::Phrase::Is {
                    operand: s::Operand::Field(terms),
                    ..
                }
                | s::Phrase::Order {
                    operand: s::Operand::Field(terms),
                    ..
                }),
        } if mine(terms) => (vec![s::Term::Path(path.clone())], phrase),
        _ => return None,
    };
    let aliases = scope.aliases();
    let names: Vec<&str> = aliases.iter().map(String::as_str).collect();
    let lowered = (|| {
        let left = lower_side(&left, scope, &names)?;
        let Some((test, right)) = lower_test(phrase, scope, &names).transpose()? else {
            return Ok(Check::NotYet);
        };
        match left {
            Some(left) => Ok(Check::Tally(Tally { left, right, test })),
            None => Ok(Check::NotYet),
        }
    })();
    Some(lowered)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{Located, Location};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn lowered(sentence: &str) -> Check {
        let tree = s::parse_check(sentence).unwrap();
        crate::lower::lower_assertion(&tree.assertions[0], &Scope::new()).unwrap()
    }

    fn verdict_of(sentence: &str, subject: Value) -> Verdict {
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
        crate::ops::run(&lowered(sentence), &ctx)
    }

    fn cause(sentence: &str, subject: Value) -> Cause {
        verdict_of(sentence, subject).cause
    }

    fn entries(sentence: &str, subject: Value) -> Vec<Value> {
        verdict_of(sentence, subject)
            .inputs
            .iter()
            .map(Input::to_json)
            .collect()
    }

    fn number(text: &str) -> Number {
        text.parse().unwrap()
    }

    fn sum_text(texts: &[&str]) -> String {
        let numbers: Vec<Number> = texts.iter().map(|t| number(t)).collect();
        add(&numbers).unwrap().to_string()
    }

    fn days(from: Value, to: Value, wanted: &str) -> Cause {
        cause(
            &format!("days elapsed from x to y is {wanted}"),
            json!({"x": from, "y": to}),
        )
    }

    #[test]
    fn thirty_six_hours_is_one_and_a_half_days() {
        assert_eq!(
            days(
                json!("2026-10-01T00:00:00Z"),
                json!("2026-10-02T12:00:00Z"),
                "1.5"
            ),
            Cause::Satisfied
        );
    }

    #[test]
    fn one_second_is_rounded_down_to_eleven_millionths_of_a_day() {
        assert_eq!(
            days(
                json!("2026-10-01T00:00:00Z"),
                json!("2026-10-01T00:00:01Z"),
                "0.000011"
            ),
            Cause::Satisfied
        );
        assert_eq!(
            days(
                json!("2026-10-01T00:00:00Z"),
                json!("2026-10-01T00:00:01Z"),
                "0.000012"
            ),
            Cause::Value
        );
    }

    #[test]
    fn two_equal_times_are_zero_apart() {
        assert_eq!(
            days(json!("2026-10-01"), json!("2026-10-01"), "0"),
            Cause::Satisfied
        );
    }

    #[test]
    fn units_are_one_sixty_thirty_six_hundred_and_so_on_seconds() {
        let subject = json!({"x": 0, "y": 1209600});
        for (sentence, wanted) in [
            ("seconds", "1209600"),
            ("minutes", "20160"),
            ("hours", "336"),
            ("days", "14"),
            ("weeks", "2"),
        ] {
            assert_eq!(
                cause(
                    &format!("{sentence} elapsed from x to y is {wanted}"),
                    subject.clone()
                ),
                Cause::Satisfied,
                "{sentence}"
            );
        }
    }

    #[test]
    fn offsets_move_the_instant_they_name() {
        assert_eq!(
            days(
                json!("2026-10-01T00:00:00+02:00"),
                json!("2026-10-01T00:00:00Z"),
                "0.083333"
            ),
            Cause::Satisfied
        );
        assert_eq!(
            days(
                json!("2026-10-01T05:30:00-04:00"),
                json!("2026-10-01T09:30:00.5Z"),
                "0.000005"
            ),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_fraction_past_nine_digits_is_cut_off() {
        assert_eq!(
            cause(
                "seconds elapsed from x to y is 1",
                json!({"x": "2026-10-01T00:00:00.1234567899Z", "y": "2026-10-01T00:00:01.1234567890Z"})
            ),
            Cause::Satisfied
        );
    }

    #[test]
    fn two_dates_are_whole_days_apart() {
        assert_eq!(
            days(json!("2026-10-01"), json!("2026-10-08"), "7"),
            Cause::Satisfied
        );
        assert_eq!(
            days(json!("2026-02-28"), json!("2026-03-01"), "1"),
            Cause::Satisfied
        );
    }

    #[test]
    fn two_numbers_are_seconds_rounded_to_the_nearest_microsecond() {
        assert_eq!(days(json!(100), json!(129700), "1.5"), Cause::Satisfied);
        assert_eq!(
            cause(
                "seconds elapsed from x to y is 0.000001",
                json!({"x": 0, "y": 0.0000014})
            ),
            Cause::Satisfied
        );
        assert_eq!(
            cause(
                "seconds elapsed from x to y is 0.000002",
                json!({"x": 0, "y": 0.0000015})
            ),
            Cause::Satisfied
        );
        assert_eq!(
            cause(
                "seconds elapsed from x to y is 0",
                json!({"x": 0.0000004, "y": 0})
            ),
            Cause::Satisfied
        );
    }

    #[test]
    fn numbers_from_minus_nine_billion_to_nine_billion_are_times() {
        assert_eq!(
            cause(
                "seconds elapsed from x to y is 18000000000",
                json!({"x": -9000000000i64, "y": 9000000000i64})
            ),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_number_past_either_edge_is_unusable() {
        assert_eq!(
            days(json!(9000000001i64), json!(9000000001i64), "0"),
            Cause::Unusable
        );
        assert_eq!(days(json!(-9000000001i64), json!(0), "0"), Cause::Unusable);
        assert_eq!(
            days(json!(0), json!(1700000000000i64), "0"),
            Cause::Unusable
        );
    }

    #[test]
    fn the_end_before_the_start_fails_as_value_and_shows_no_number() {
        let sentence = "days elapsed from x to y is at most 5";
        let subject = json!({"x": "2026-01-02T00:00:00Z", "y": "2026-01-01T00:00:00Z"});
        assert_eq!(cause(sentence, subject.clone()), Cause::Value);
        assert_eq!(entries(sentence, subject)[0]["value"], Value::Null);
        assert_eq!(cause(sentence, json!({"x": 5, "y": 4})), Cause::Value);
        assert_eq!(
            cause(sentence, json!({"x": "2026-01-02", "y": "2026-01-01"})),
            Cause::Value
        );
    }

    #[test]
    fn times_in_different_formats_are_unusable() {
        let pairs = [
            (json!("2026-10-01"), json!("2026-10-01T00:00:00Z")),
            (json!("2026-10-01T00:00:00Z"), json!("2026-10-01")),
            (json!(0), json!("2026-10-01")),
            (json!("2026-10-01T00:00:00Z"), json!(5)),
        ];
        for (x, y) in pairs {
            assert_eq!(days(x, y, "0"), Cause::Unusable);
        }
    }

    #[test]
    fn things_that_are_not_times_are_unusable() {
        let pairs = [
            (json!("yesterday"), json!("today")),
            (json!(true), json!(true)),
            (json!([1]), json!([1])),
            (json!({}), json!({})),
            (json!("2026-02-30"), json!("2026-03-01")),
            (json!("2026-10-01t00:00:00z"), json!("2026-10-01t00:00:00z")),
        ];
        for (x, y) in pairs {
            assert_eq!(days(x, y, "0"), Cause::Unusable);
        }
    }

    #[test]
    fn a_missing_or_null_path_fails_as_absent_or_null_and_the_worst_wins() {
        let sentence = "days elapsed from x to y is at least 0";
        assert_eq!(cause(sentence, json!({"y": 1})), Cause::Absent);
        assert_eq!(cause(sentence, json!({"x": 1})), Cause::Absent);
        assert_eq!(cause(sentence, json!({"x": null, "y": 1})), Cause::Null);
        assert_eq!(cause(sentence, json!({"x": 1, "y": null})), Cause::Null);
        assert_eq!(cause(sentence, json!({"x": null})), Cause::Absent);
        assert_eq!(cause(sentence, json!({"x": "x", "y": null})), Cause::Null);
        assert_eq!(cause(sentence, json!({"x": "x"})), Cause::Absent);
    }

    #[test]
    fn a_subject_that_is_not_an_object_fails_as_not_an_object() {
        assert_eq!(
            cause("days elapsed from x to y is at least 0", json!("s")),
            Cause::NotAnObject
        );
    }

    #[test]
    fn an_elapsed_side_shows_its_number_then_each_path_in_order() {
        assert_eq!(
            entries(
                "days elapsed from x to y is 1.5",
                json!({"x": 100, "y": 129700})
            ),
            [
                json!({"name": "days elapsed from x to y", "value": 1.5, "locations": ["/things/0/x", "/things/0/y"]}),
                json!({"name": "x", "value": 100, "locations": ["/things/0/x"]}),
                json!({"name": "y", "value": 129700, "locations": ["/things/0/y"]}),
            ]
        );
    }

    #[test]
    fn a_failed_elapsed_side_shows_null_and_where_each_read_stopped() {
        assert_eq!(
            entries("days elapsed from x to y is 1", json!({"x": 100})),
            [
                json!({"name": "days elapsed from x to y", "value": null, "locations": ["/things/0/x", "/things/0"]}),
                json!({"name": "x", "value": 100, "locations": ["/things/0/x"]}),
                json!({"name": "y", "value": null, "locations": ["/things/0"]}),
            ]
        );
    }

    #[test]
    fn decimals_are_added_as_decimals() {
        assert_eq!(sum_text(&["0.1", "0.2"]), "0.3");
        assert_eq!(sum_text(&["0.1", "0.7"]), "0.8");
        assert_eq!(sum_text(&["1", "2"]), "3");
        assert_eq!(sum_text(&["-0.5", "0.25"]), "-0.25");
        assert_eq!(sum_text(&["-1.5", "1.5"]), "0");
        assert_eq!(sum_text(&["1e2", "0.5"]), "100.5");
        assert_eq!(sum_text(&["0.000000000000001", "1"]), "1.000000000000001");
    }

    #[test]
    fn a_sum_stays_exact_past_fifteen_places() {
        assert_eq!(sum_text(&["0.1234567890123456", "1"]), "1.1234567890123456");
        assert_eq!(
            sum_text(&["0.1000000000000000001", "0.2"]),
            "0.3000000000000000001"
        );
    }

    #[test]
    fn a_sum_stays_exact_past_ten_to_the_fifteenth() {
        assert_eq!(sum_text(&["1e15", "0.5"]), "1000000000000000.5");
        assert_eq!(sum_text(&["999999999999999", "1"]), "1000000000000000");
        assert_eq!(
            sum_text(&["1e300", "1e300"]),
            format!("2{}", "0".repeat(300))
        );
    }

    #[test]
    fn a_sum_has_no_exponent_and_no_trailing_zeros() {
        assert_eq!(sum_text(&["1.5", "1.5"]), "3");
        assert_eq!(sum_text(&["0.5", "0.5", "-1"]), "0");
        assert_eq!(sum_text(&["-0.5", "-0.25"]), "-0.75");
        assert_eq!(sum_text(&["1e-3", "1e-3"]), "0.002");
        assert_eq!(sum_text(&["0", "-0.0"]), "0");
    }

    #[test]
    fn a_sum_with_digits_further_apart_than_a_hundred_thousand_is_unusable() {
        let numbers = [number("1e200000"), number("1")];
        assert!(add(&numbers).is_none());
        assert_eq!(
            cause(
                "x plus 1 is 2",
                json!({"x": serde_json::from_str::<Value>("1e200000").unwrap()})
            ),
            Cause::Unusable
        );
    }

    #[test]
    fn a_plus_in_a_sentence_adds_decimals() {
        assert_eq!(
            cause("x plus y is 0.3", json!({"x": 0.1, "y": 0.2})),
            Cause::Satisfied
        );
        assert_eq!(cause("0.1 plus 0.2 is 0.3", json!({})), Cause::Satisfied);
        assert_eq!(cause("x plus 2 is 5", json!({"x": 4})), Cause::Value);
        assert_eq!(
            cause("1 plus x plus y is 6", json!({"x": 2, "y": 3})),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_plus_fails_as_its_worst_operand() {
        let sentence = "x plus y is 3";
        assert_eq!(cause(sentence, json!({"x": 1})), Cause::Absent);
        assert_eq!(cause(sentence, json!({"x": null, "y": 2})), Cause::Null);
        assert_eq!(cause(sentence, json!({"x": "1", "y": 2})), Cause::Unusable);
        assert_eq!(
            cause(sentence, json!({"x": true, "y": null})),
            Cause::Unusable
        );
        assert_eq!(
            cause(sentence, json!({"x": null, "y": {}})),
            Cause::Unusable
        );
        assert_eq!(cause(sentence, json!({"x": "1"})), Cause::Unusable);
        assert_eq!(cause(sentence, json!({"x": [1], "y": {}})), Cause::Unusable);
        assert_eq!(cause(sentence, json!("s")), Cause::NotAnObject);
    }

    #[test]
    fn a_plus_shows_its_number_then_each_operand_and_a_number_shows_nothing() {
        assert_eq!(
            entries("x plus 2 is 5", json!({"x": 3})),
            [
                json!({"name": "x plus 2", "value": 5, "locations": ["/things/0/x"]}),
                json!({"name": "x", "value": 3, "locations": ["/things/0/x"]}),
            ]
        );
    }

    #[test]
    fn a_failed_plus_shows_null() {
        assert_eq!(
            entries("x plus 2 is 5", json!({"x": "3"})),
            [
                json!({"name": "x plus 2", "value": null, "locations": ["/things/0/x"]}),
                json!({"name": "x", "value": "3", "locations": ["/things/0/x"]}),
            ]
        );
    }

    #[test]
    fn a_plus_with_an_elapsed_term_lists_the_elapsed_entry_then_its_paths() {
        assert_eq!(
            entries(
                "1 plus days elapsed from x to y is 2",
                json!({"x": 0, "y": 86400})
            ),
            [
                json!({"name": "1 plus days elapsed from x to y", "value": 2, "locations": ["/things/0/x", "/things/0/y"]}),
                json!({"name": "days elapsed from x to y", "value": 1, "locations": ["/things/0/x", "/things/0/y"]}),
                json!({"name": "x", "value": 0, "locations": ["/things/0/x"]}),
                json!({"name": "y", "value": 86400, "locations": ["/things/0/y"]}),
            ]
        );
    }

    #[test]
    fn a_path_read_twice_is_shown_once_and_its_location_listed_once() {
        assert_eq!(
            entries("x plus x is 4", json!({"x": 2})),
            [
                json!({"name": "x plus x", "value": 4, "locations": ["/things/0/x"]}),
                json!({"name": "x", "value": 2, "locations": ["/things/0/x"]}),
            ]
        );
    }

    #[test]
    fn the_right_side_comes_after_the_left_and_a_repeat_is_dropped() {
        assert_eq!(
            entries(
                "n is days elapsed from x to y",
                json!({"n": 1, "x": 0, "y": 86400})
            ),
            [
                json!({"name": "n", "value": 1, "locations": ["/things/0/n"]}),
                json!({"name": "days elapsed from x to y", "value": 1, "locations": ["/things/0/x", "/things/0/y"]}),
                json!({"name": "x", "value": 0, "locations": ["/things/0/x"]}),
                json!({"name": "y", "value": 86400, "locations": ["/things/0/y"]}),
            ]
        );
        assert_eq!(
            entries("x plus 1 is at least x", json!({"x": 2})),
            [
                json!({"name": "x plus 1", "value": 3, "locations": ["/things/0/x"]}),
                json!({"name": "x", "value": 2, "locations": ["/things/0/x"]}),
            ]
        );
    }

    #[test]
    fn both_sides_failing_gives_the_worst_cause_and_both_sides_entries() {
        let verdict = verdict_of("x plus 1 is y plus 1", json!({"x": null}));
        assert_eq!(verdict.cause, Cause::Absent);
        let names: Vec<&str> = verdict.inputs.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(names, ["x plus 1", "x", "y plus 1", "y"]);
        assert_eq!(
            cause("x plus 1 is y plus 1", json!({"x": null, "y": null})),
            Cause::Null
        );
        assert_eq!(
            cause("x plus 1 is y plus 1", json!({"x": 1})),
            Cause::Absent
        );
    }

    #[test]
    fn a_derived_side_can_be_on_the_left_the_right_or_both() {
        let subject = json!({"x": 1, "y": 2, "c": 3});
        assert_eq!(cause("x plus y is c", subject.clone()), Cause::Satisfied);
        assert_eq!(cause("c is x plus y", subject.clone()), Cause::Satisfied);
        assert_eq!(
            cause("x plus y is 1 plus 2", subject.clone()),
            Cause::Satisfied
        );
        assert_eq!(cause("x plus y is not c", subject), Cause::Value);
    }

    #[test]
    fn a_derived_side_takes_is_is_not_within_the_orders_and_between() {
        let subject = json!({"x": 1, "y": 2});
        for (sentence, wanted) in [
            ("x plus y is 3", Cause::Satisfied),
            ("x plus y is 4", Cause::Value),
            ("x plus y is not 4", Cause::Satisfied),
            ("x plus y is not 3", Cause::Value),
            ("x plus y is 3.5 within 0.5", Cause::Satisfied),
            ("x plus y is 3.6 within 0.5", Cause::Value),
            ("x plus y is at least 3", Cause::Satisfied),
            ("x plus y is at least 4", Cause::Value),
            ("x plus y is at most 3", Cause::Satisfied),
            ("x plus y is at most 2", Cause::Value),
            ("x plus y is more than 2", Cause::Satisfied),
            ("x plus y is more than 3", Cause::Value),
            ("x plus y is less than 4", Cause::Satisfied),
            ("x plus y is less than 3", Cause::Value),
            ("x plus y is between 3 and 4", Cause::Satisfied),
            ("x plus y is between 2 and 3", Cause::Satisfied),
            ("x plus y is between 4 and 5", Cause::Value),
            ("x plus y is between 1 and 2", Cause::Value),
        ] {
            assert_eq!(cause(sentence, subject.clone()), wanted, "{sentence}");
        }
    }

    #[test]
    fn between_fails_with_the_cause_of_a_side_that_fails() {
        assert_eq!(
            cause("x plus 2 is between 4 and 6", json!({})),
            Cause::Absent
        );
        assert_eq!(
            cause("x plus 2 is between 4 and 6", json!({"x": null})),
            Cause::Null
        );
        assert_eq!(
            cause("x plus 2 is between 4 and 6", json!({"x": "x"})),
            Cause::Unusable
        );
        assert_eq!(
            cause(
                "days elapsed from x to y is between 1 and 2",
                json!({"x": 86400, "y": 0})
            ),
            Cause::Value
        );
    }

    #[test]
    fn a_plain_side_that_is_not_a_number_is_unusable() {
        assert_eq!(
            cause("x plus 1 is y", json!({"x": 1, "y": "2"})),
            Cause::Unusable
        );
        assert_eq!(
            cause("y is x plus 1", json!({"x": 1, "y": "2"})),
            Cause::Unusable
        );
        assert_eq!(cause("x plus 1 is \"2\"", json!({"x": 1})), Cause::Unusable);
        assert_eq!(cause("x plus 1 is true", json!({"x": 1})), Cause::Unusable);
        assert_eq!(
            cause("x plus 1 is at least \"2\"", json!({"x": 1})),
            Cause::Unusable
        );
        assert_eq!(
            cause("x plus 1 is 2 within 1", json!({"x": 1})),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_null_value_on_the_right_fails_as_null_and_a_missing_path_as_absent() {
        assert_eq!(cause("x plus 1 is null", json!({"x": 1})), Cause::Null);
        assert_eq!(cause("x plus 1 is y", json!({"x": 1})), Cause::Absent);
        assert_eq!(
            cause("x plus 1 is y", json!({"x": 1, "y": null})),
            Cause::Null
        );
    }

    #[test]
    fn elapsed_days_compare_with_a_field_or_a_sum_on_the_right() {
        let subject = json!({"n": 1, "x": 0, "y": 86400});
        assert_eq!(
            cause("n is days elapsed from x to y", subject.clone()),
            Cause::Satisfied
        );
        assert_eq!(
            cause(
                "n is more than 1 plus days elapsed from x to y",
                subject.clone()
            ),
            Cause::Value
        );
        assert_eq!(
            cause("n plus 1 is 1 plus days elapsed from x to y", subject),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_count_or_a_sum_anywhere_is_not_yet_supported() {
        for sentence in [
            "count of xs is 2",
            "sum of xs.n is 2",
            "x plus count of xs is 2",
            "x is count of xs",
            "n is sum of xs.n plus 1",
            "count of xs plus 1 is between 1 and 2",
        ] {
            assert_eq!(lowered(sentence), Check::NotYet, "{sentence}");
        }
    }

    #[test]
    fn a_sentence_that_is_not_derived_is_not_lowered_here() {
        let tree = s::parse_check("x is y").unwrap();
        assert!(lower_assertion(&tree.assertions[0], &Scope::new()).is_none());
        let tree = s::parse_check("every xs is 1").unwrap();
        assert!(lower_assertion(&tree.assertions[0], &Scope::new()).is_none());
    }

    #[test]
    fn a_number_out_of_range_is_written_wrong() {
        let tree = s::parse_check("x plus 1e999 is 2").unwrap();
        assert!(
            lower_assertion(&tree.assertions[0], &Scope::new())
                .unwrap()
                .is_err()
        );
    }

    fn row_names(checks: Value) -> Vec<String> {
        let policy = json!({
            "ergo_spec": "v0.2",
            "subjects": {"t": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "t", "checks": {"c": checks}}}
        });
        let input = json!({"things": [{"id": 1, "x": 1, "y": 3}]});
        let report = crate::report(&input, &policy, &json!({}));
        let row = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        row["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|entry| entry["name"].as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn a_row_of_one_sentence_lists_its_entries_in_reading_order_not_by_name() {
        assert_eq!(
            row_names(json!("y is more than x plus 1")),
            ["y", "x plus 1", "x"]
        );
    }

    #[test]
    fn a_row_of_several_sentences_lists_its_entries_sorted_by_name() {
        assert_eq!(
            row_names(json!({"assert": ["y is more than x plus 1", "y is 3"]})),
            ["x", "x plus 1", "y"]
        );
    }
}
