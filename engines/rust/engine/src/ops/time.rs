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
mod tests;
