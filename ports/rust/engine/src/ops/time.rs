use super::compare::{Side, read_sides, unread_cause};
use super::{Verdict, verdict};
use crate::cause::Cause;
use crate::path::Ctx;
use crate::value;
use serde_json::{Number, Value};
use std::cmp::Ordering;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Order {
    Before,
    After,
    OnOrBefore,
    OnOrAfter,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CompareTime {
    pub left: Side,
    pub right: Side,
    pub order: Order,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Time {
    Instant(i128),
    Date(i64),
    Number(Number),
}

pub const NANOS_PER_SECOND: i128 = 1_000_000_000;
pub const SECONDS_PER_DAY: i64 = 86_400;

pub fn read_time(v: &Value) -> Option<Time> {
    match v {
        Value::Number(n) => Some(Time::Number(n.clone())),
        Value::String(s) => date_days(s)
            .map(Time::Date)
            .or_else(|| instant_nanos(s).map(Time::Instant)),
        _ => None,
    }
}

pub fn compare_times(a: &Time, b: &Time) -> Option<Ordering> {
    match (a, b) {
        (Time::Instant(x), Time::Instant(y)) => Some(x.cmp(y)),
        (Time::Date(x), Time::Date(y)) => Some(x.cmp(y)),
        (Time::Number(x), Time::Number(y)) => value::compare_numbers(x, y),
        _ => None,
    }
}

impl CompareTime {
    pub fn refs(&self) -> Vec<crate::path::Path> {
        super::compare::side_refs(&self.left, &self.right)
    }
}

pub fn run(check: &CompareTime, ctx: &Ctx) -> Verdict {
    let (l, r, inputs) = read_sides(&check.left, &check.right, ctx);
    let cause = match unread_cause(&l, &r) {
        Some(cause) => cause,
        None => {
            let order = l
                .value
                .as_ref()
                .and_then(read_time)
                .zip(r.value.as_ref().and_then(read_time))
                .and_then(|(a, b)| compare_times(&a, &b));
            match order {
                Some(order) => verdict(match check.order {
                    Order::Before => order == Ordering::Less,
                    Order::After => order == Ordering::Greater,
                    Order::OnOrBefore => order != Ordering::Greater,
                    Order::OnOrAfter => order != Ordering::Less,
                }),
                None => Cause::Unusable,
            }
        }
    };
    Verdict { cause, inputs }
}

fn digits(text: &str) -> Option<i64> {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

fn is_leap(year: i64) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        2 if is_leap(year) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let year_of_era = y - era * 400;
    let day_of_year = (153 * ((month + 9) % 12) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

pub fn date_days(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let year = digits(&text[0..4])?;
    let month = digits(&text[5..7])?;
    let day = digits(&text[8..10])?;
    if !(1678..=2261).contains(&year) || !(1..=12).contains(&month) {
        return None;
    }
    if day < 1 || day > days_in_month(year, month) {
        return None;
    }
    Some(days_from_civil(year, month, day))
}

fn clock(text: &str, most_hours: i64) -> Option<(i64, i64)> {
    let b = text.as_bytes();
    if b.len() != 5 || b[2] != b':' {
        return None;
    }
    let hours = digits(&text[0..2])?;
    let minutes = digits(&text[3..5])?;
    (hours <= most_hours && minutes <= 59).then_some((hours, minutes))
}

pub fn instant_nanos(text: &str) -> Option<i128> {
    if !text.is_ascii() || text.len() < 20 || text.as_bytes()[10] != b'T' {
        return None;
    }
    let days = date_days(&text[0..10])?;
    let (hours, minutes) = clock(&text[11..16], 23)?;
    if text.as_bytes()[16] != b':' {
        return None;
    }
    let seconds = digits(&text[17..19])?;
    if seconds > 59 {
        return None;
    }
    let rest = &text[19..];
    let (fraction, zone) = match rest.strip_prefix('.') {
        Some(after) => {
            let end = after
                .find(|c: char| !c.is_ascii_digit())
                .unwrap_or(after.len());
            if end == 0 {
                return None;
            }
            (&after[..end], &after[end..])
        }
        None => ("", rest),
    };
    let offset_seconds = match zone {
        "Z" => 0,
        _ => {
            let sign = match zone.as_bytes().first() {
                Some(b'+') => 1,
                Some(b'-') => -1,
                _ => return None,
            };
            let (h, m) = clock(&zone[1..], 23)?;
            sign * (h * 3600 + m * 60)
        }
    };
    let mut nine = fraction.chars().take(9).collect::<String>();
    while nine.len() < 9 {
        nine.push('0');
    }
    let nanos: i128 = nine.parse().ok()?;
    let local =
        days as i128 * SECONDS_PER_DAY as i128 + (hours * 3600 + minutes * 60 + seconds) as i128;
    Some((local - offset_seconds as i128) * NANOS_PER_SECOND + nanos)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{Located, Location, Path, Start, Step};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn field(name: &str) -> Side {
        Side::Path(Path {
            start: Start::Subject,
            steps: vec![Step::Key(name.to_string())],
        })
    }

    fn cause_with(subject: Value, order: Order) -> Cause {
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
        let check = CompareTime {
            left: field("a"),
            right: field("b"),
            order,
        };
        run(&check, &ctx).cause
    }

    fn before(a: Value, b: Value) -> Cause {
        cause_with(json!({"a": a, "b": b}), Order::Before)
    }

    #[test]
    fn compares_rfc3339_strings_as_instants() {
        assert_eq!(
            before(json!("2024-01-01T00:00:00Z"), json!("2024-01-01T00:00:01Z")),
            Cause::Satisfied
        );
        assert_eq!(
            before(json!("2024-01-01T00:00:01Z"), json!("2024-01-01T00:00:00Z")),
            Cause::Value
        );
        assert_eq!(
            before(
                json!("2024-01-01T00:00:00.000000001Z"),
                json!("2024-01-01T00:00:00.00000001Z")
            ),
            Cause::Satisfied
        );
    }

    #[test]
    fn an_offset_names_the_same_instant_as_utc() {
        let same = json!({"a": "2024-01-01T01:00:00+01:00", "b": "2024-01-01T00:00:00Z"});
        assert_eq!(
            cause_with(same.clone(), Order::OnOrBefore),
            Cause::Satisfied
        );
        assert_eq!(cause_with(same.clone(), Order::OnOrAfter), Cause::Satisfied);
        assert_eq!(cause_with(same.clone(), Order::Before), Cause::Value);
        assert_eq!(cause_with(same, Order::After), Cause::Value);
    }

    #[test]
    fn only_the_first_nine_digits_of_a_fraction_count() {
        assert_eq!(
            instant_nanos("2024-01-01T00:00:00.1234567891Z"),
            instant_nanos("2024-01-01T00:00:00.123456789Z")
        );
    }

    #[test]
    fn compares_numbers_by_value_and_dates_as_days() {
        assert_eq!(before(json!(1.5), json!(2)), Cause::Satisfied);
        assert_eq!(
            cause_with(
                serde_json::from_str(r#"{"a": 2, "b": 2.0}"#).unwrap(),
                Order::OnOrAfter
            ),
            Cause::Satisfied
        );
        assert_eq!(
            before(json!("2024-01-31"), json!("2024-02-01")),
            Cause::Satisfied
        );
        assert_eq!(
            before(json!("2024-01-02"), json!("2024-01-01")),
            Cause::Value
        );
    }

    #[test]
    fn two_times_in_different_formats_fail_as_unusable() {
        assert_eq!(
            before(json!("2024-01-01T00:00:00Z"), json!(1)),
            Cause::Unusable
        );
        assert_eq!(
            before(json!("2024-01-01"), json!("2024-01-02T00:00:00Z")),
            Cause::Unusable
        );
        assert_eq!(before(json!(1), json!("2024-01-02")), Cause::Unusable);
    }

    #[test]
    fn anything_that_is_not_a_time_fails_as_unusable() {
        let later = json!("2024-03-02T00:00:01Z");
        for bad in [
            "2024-01-01t00:00:00z",
            "2024-02-30T00:00:00Z",
            "1900-02-29T00:00:00Z",
            "1677-12-31T23:59:59Z",
            "2262-01-01T00:00:00Z",
            "2024-01-01T00:00:00",
            "2016-12-31T23:59:60Z",
            "2024-01-01T24:00:00Z",
            "2024-01-01 00:00:00Z",
            "2024-01-01T00:00:00+0100",
            "2024-01-01T00:00:00.Z",
            "2024-01-01T00:00:00+24:00",
            "2024-01-01T00:00:00+01:60",
            "2024-01-01T00:00:00Zx",
            "2024-1-01T00:00:00Z",
            "+024-01-01T00:00:00Z",
            "yesterday",
        ] {
            assert_eq!(before(json!(bad), later.clone()), Cause::Unusable, "{bad}");
        }
        for bad in [
            "2023-02-29",
            "2024-13-01",
            "2024-00-10",
            "2024-01-00",
            "2024-01-1",
            "2024-01-01 ",
        ] {
            assert_eq!(
                before(json!(bad), json!("2024-12-01")),
                Cause::Unusable,
                "{bad}"
            );
        }
        assert_eq!(before(json!(true), json!(false)), Cause::Unusable);
    }

    #[test]
    fn the_first_and_last_years_allowed_are_times() {
        assert_eq!(
            before(
                json!("1678-01-01T00:00:00+05:00"),
                json!("2024-01-01T00:00:00Z")
            ),
            Cause::Satisfied
        );
        assert_eq!(
            before(
                json!("2024-01-01T00:00:00Z"),
                json!("2261-12-31T23:59:59-05:00")
            ),
            Cause::Satisfied
        );
        assert_eq!(
            before(json!("2000-02-29T00:00:00Z"), json!("2024-01-01T00:00:00Z")),
            Cause::Satisfied
        );
        assert_eq!(
            before(json!("1678-01-01"), json!("2261-12-31")),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_missing_or_null_side_fails_with_the_worse_outcome() {
        assert_eq!(
            cause_with(json!({"b": "2017-01-02T00:00:00Z"}), Order::Before),
            Cause::Absent
        );
        assert_eq!(
            cause_with(
                json!({"a": null, "b": "2017-01-02T00:00:00Z"}),
                Order::Before
            ),
            Cause::Null
        );
        assert_eq!(cause_with(json!({"a": null}), Order::Before), Cause::Absent);
    }

    #[test]
    fn days_count_from_1970() {
        assert_eq!(date_days("1970-01-01"), Some(0));
        assert_eq!(date_days("1970-01-02"), Some(1));
        assert_eq!(date_days("1969-12-31"), Some(-1));
        assert_eq!(
            instant_nanos("1970-01-01T00:00:01Z"),
            Some(NANOS_PER_SECOND)
        );
        assert_eq!(instant_nanos("1970-01-01T01:00:00+01:00"), Some(0));
    }

    #[test]
    fn a_written_time_on_the_right_has_no_input() {
        let input = json!({"things": [{"a": "2024-01-01"}]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        let check = CompareTime {
            left: field("a"),
            right: Side::Value(json!("2024-06-01")),
            order: Order::Before,
        };
        let v = run(&check, &ctx);
        assert_eq!(v.cause, Cause::Satisfied);
        assert_eq!(v.inputs.len(), 1);
    }
}
