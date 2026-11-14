use super::equals::Equals;
use super::range::Range;
use super::time::{CompareTime, Order};
use super::{Check, Input, Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::lower::Scope;
use crate::path::{self, Ctx, Outcome, Path};
use crate::value;
use ergo_policy_sentences as tree;
use serde_json::{Number, Value};
use std::cmp::Ordering;

#[derive(Debug, Clone, PartialEq)]
pub enum Side {
    Path(Path),
    Value(Value),
    Join(Vec<Side>),
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
    NotStartsWith,
    NotEndsWith,
    AlphabeticallyBefore,
    AlphabeticallyAfter,
    AlphabeticallyOnOrBefore,
    AlphabeticallyOnOrAfter,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Compare {
    pub left: Side,
    pub right: Side,
    pub cmp: Cmp,
    pub within: Option<Number>,
}

impl Side {
    pub fn paths(&self) -> Vec<&Path> {
        match self {
            Side::Path(path) => vec![path],
            Side::Value(_) => Vec::new(),
            Side::Join(pieces) => pieces.iter().flat_map(Side::paths).collect(),
        }
    }
}

pub struct SideRead {
    pub outcome: Outcome,
    pub value: Option<Value>,
    pub inputs: Vec<Input>,
}

pub fn read_side(side: &Side, ctx: &Ctx) -> SideRead {
    match side {
        Side::Path(path) => {
            let read = read_path(path, ctx);
            SideRead {
                outcome: read.outcome,
                value: read.value,
                inputs: read.inputs,
            }
        }
        Side::Join(pieces) => read_join(pieces, ctx),
        Side::Value(Value::Null) => SideRead {
            outcome: Outcome::Null,
            value: None,
            inputs: Vec::new(),
        },
        Side::Value(v) => SideRead {
            outcome: Outcome::Found,
            value: Some(v.clone()),
            inputs: Vec::new(),
        },
    }
}

fn read_join(pieces: &[Side], ctx: &Ctx) -> SideRead {
    let reads: Vec<SideRead> = pieces.iter().map(|piece| read_side(piece, ctx)).collect();
    let inputs = reads
        .iter()
        .flat_map(|r| r.inputs.iter().cloned())
        .collect();
    let mut text = String::new();
    for read in &reads {
        match (read.outcome, &read.value) {
            (Outcome::Found, Some(Value::String(piece))) => text.push_str(piece),
            (Outcome::Found, _) => {
                return SideRead {
                    outcome: Outcome::Found,
                    value: None,
                    inputs,
                };
            }
            (outcome, _) => {
                return SideRead {
                    outcome,
                    value: None,
                    inputs,
                };
            }
        }
    }
    SideRead {
        outcome: Outcome::Found,
        value: Some(Value::String(text)),
        inputs,
    }
}

pub fn read_sides(left: &Side, right: &Side, ctx: &Ctx) -> (SideRead, SideRead, Vec<Input>) {
    let l = read_side(left, ctx);
    let r = read_side(right, ctx);
    let inputs = l.inputs.iter().chain(r.inputs.iter()).cloned().collect();
    (l, r, inputs)
}

pub fn unread_cause(l: &SideRead, r: &SideRead) -> Option<Cause> {
    Cause::worst([l.outcome, r.outcome].into_iter().filter_map(|o| o.cause()))
}

pub fn side_refs(left: &Side, right: &Side) -> Vec<Path> {
    let mut refs = Vec::new();
    for side in [left, right] {
        match side {
            Side::Path(path) => refs.extend(path::step_refs(path)),
            Side::Join(pieces) => {
                for piece in pieces {
                    if let Side::Path(path) = piece {
                        if path::is_ref(path) {
                            refs.push(path.clone());
                        }
                        refs.extend(path::step_refs(path));
                    }
                }
            }
            Side::Value(_) => {}
        }
    }
    refs
}

impl Compare {
    pub fn refs(&self) -> Vec<Path> {
        side_refs(&self.left, &self.right)
    }
}

pub fn run(check: &Compare, ctx: &Ctx) -> Verdict {
    let (l, r, inputs) = read_sides(&check.left, &check.right, ctx);
    let joined_cause = match &check.right {
        Side::Join(_) => r
            .outcome
            .cause()
            .or_else(|| r.value.is_none().then_some(Cause::Unusable)),
        _ => None,
    };
    let cause = match joined_cause.or_else(|| unread_cause(&l, &r)) {
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
            (Value::Number(a), Value::Number(b)) => within(a, b, distance)
                .map_or(Cause::Unusable, |inside| {
                    verdict(inside != (check.cmp == Cmp::Ne))
                }),
            _ => Cause::Unusable,
        };
    }
    match check.cmp {
        Cmp::Eq | Cmp::Ne if value::type_name(l) != value::type_name(r) => Cause::Unusable,
        Cmp::Eq => value::equal(l, r).map_or(Cause::Unusable, verdict),
        Cmp::Ne => value::equal(l, r).map_or(Cause::Unusable, |same| verdict(!same)),
        Cmp::Gt | Cmp::Gte | Cmp::Lt | Cmp::Lte => match (l, r) {
            (Value::Number(a), Value::Number(b)) => value::compare_numbers(a, b)
                .map_or(Cause::Unusable, |order| verdict(ordered(check.cmp, order))),
            _ => Cause::Unusable,
        },
        Cmp::StartsWith
        | Cmp::EndsWith
        | Cmp::NotStartsWith
        | Cmp::NotEndsWith
        | Cmp::AlphabeticallyBefore
        | Cmp::AlphabeticallyAfter
        | Cmp::AlphabeticallyOnOrBefore
        | Cmp::AlphabeticallyOnOrAfter => match (l, r) {
            (Value::String(a), Value::String(b)) => verdict(match check.cmp {
                Cmp::StartsWith => a.starts_with(b.as_str()),
                Cmp::EndsWith => a.ends_with(b.as_str()),
                Cmp::NotStartsWith => !a.starts_with(b.as_str()),
                Cmp::NotEndsWith => !a.ends_with(b.as_str()),
                Cmp::AlphabeticallyBefore => a < b,
                Cmp::AlphabeticallyAfter => a > b,
                Cmp::AlphabeticallyOnOrBefore => a <= b,
                _ => a >= b,
            }),
            _ => Cause::Unusable,
        },
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
    let decimal = value::Decimal::parse(&number.to_string())?;
    let (negative, digits, exponent) = decimal.parts();
    Some(Exact {
        negative,
        digits: if digits.is_empty() {
            "0".to_string()
        } else {
            digits.to_string()
        },
        exponent: i64::try_from(exponent).ok()?,
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

pub(super) fn magnitude_order(a: &str, b: &str) -> Ordering {
    a.len().cmp(&b.len()).then_with(|| a.cmp(b))
}

pub(super) fn add_magnitudes(a: &str, b: &str) -> String {
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

pub(super) fn subtract_magnitudes(a: &str, b: &str) -> String {
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

fn within(a: &Number, b: &Number, distance: &Number) -> Option<bool> {
    let (x, y, w) = (exact(a)?, exact(b)?, exact(distance)?);
    let exponents = [x.exponent, y.exponent, w.exponent];
    let low = exponents.iter().copied().min().unwrap_or(0);
    let high = exponents.iter().copied().max().unwrap_or(0);
    if high.checked_sub(low)? > WIDEST_EXACT_SPREAD {
        return None;
    }
    let (sx, sy, sw) = (scaled(&x, low), scaled(&y, low), scaled(&w, low));
    let gap = if x.negative != y.negative {
        add_magnitudes(&sx, &sy)
    } else if magnitude_order(&sx, &sy) == Ordering::Less {
        subtract_magnitudes(&sy, &sx)
    } else {
        subtract_magnitudes(&sx, &sy)
    };
    Some(magnitude_order(&gap, &sw) != Ordering::Greater)
}

pub fn joined<A, B>(
    a: Result<A, Vec<String>>,
    b: Result<B, Vec<String>>,
) -> Result<(A, B), Vec<String>> {
    match (a, b) {
        (Ok(a), Ok(b)) => Ok((a, b)),
        (a, b) => Err(a.err().into_iter().chain(b.err()).flatten().collect()),
    }
}

fn number(text: &str, scope: &Scope) -> Result<Number, Vec<String>> {
    match scope.value(&tree::Value::Number(text.to_string()))? {
        Value::Number(n) => Ok(n),
        _ => Err(vec![format!("{text} isn't a number")]),
    }
}

fn operand_side(operand: &tree::Operand, scope: &Scope) -> Option<Result<Side, Vec<String>>> {
    match operand {
        tree::Operand::Value(v) => Some(scope.value(v).map(Side::Value)),
        tree::Operand::Field(terms) => match terms.as_slice() {
            [tree::Term::Path(p)] => Some(scope.path(p).map(Side::Path)),
            _ => None,
        },
        tree::Operand::Joined(pieces) => {
            let mut sides = Vec::new();
            let mut problems = Vec::new();
            for piece in pieces {
                match operand_side(piece, scope) {
                    Some(Ok(side)) => sides.push(side),
                    Some(Err(found)) => problems.extend(found),
                    None => return None,
                }
            }
            Some(if problems.is_empty() {
                Ok(Side::Join(sides))
            } else {
                Err(problems)
            })
        }
    }
}

pub fn lower_phrase(
    path: &tree::Path,
    phrase: &tree::Phrase,
    scope: &Scope,
) -> Option<Result<Check, Vec<String>>> {
    let compare =
        |operand: &tree::Operand, cmp: Cmp, within: Option<&String>| {
            let right = operand_side(operand, scope)?;
            let within = within.map(|w| number(w, scope)).transpose();
            Some(joined(joined(scope.left_path(path), right), within).map(
                |((left, right), within)| match (cmp, right, within) {
                    (Cmp::Eq, Side::Value(value), None) => {
                        Check::Equals(Equals { path: left, value })
                    }
                    (cmp, right, within) => Check::Compare(Compare {
                        left: Side::Path(left),
                        right,
                        cmp,
                        within,
                    }),
                },
            ))
        };
    match phrase {
        tree::Phrase::Is {
            not,
            operand,
            within,
        } => compare(
            operand,
            if *not { Cmp::Ne } else { Cmp::Eq },
            within.as_ref(),
        ),
        tree::Phrase::Order { order, operand } => compare(
            operand,
            match order {
                tree::Order::AtLeast => Cmp::Gte,
                tree::Order::AtMost => Cmp::Lte,
                tree::Order::MoreThan => Cmp::Gt,
                tree::Order::LessThan => Cmp::Lt,
            },
            None,
        ),
        tree::Phrase::StartsWith(operand) => compare(operand, Cmp::StartsWith, None),
        tree::Phrase::EndsWith(operand) => compare(operand, Cmp::EndsWith, None),
        tree::Phrase::NotStartsWith(operand) => compare(operand, Cmp::NotStartsWith, None),
        tree::Phrase::NotEndsWith(operand) => compare(operand, Cmp::NotEndsWith, None),
        tree::Phrase::Alphabetically {
            after,
            or_equal,
            operand,
        } => compare(
            operand,
            match (*after, *or_equal) {
                (false, false) => Cmp::AlphabeticallyBefore,
                (true, false) => Cmp::AlphabeticallyAfter,
                (false, true) => Cmp::AlphabeticallyOnOrBefore,
                (true, true) => Cmp::AlphabeticallyOnOrAfter,
            },
            None,
        ),
        tree::Phrase::Between { not, min, max } => Some(
            joined(
                scope.left_path(path),
                joined(number(min, scope), number(max, scope)),
            )
            .map(|(path, (min, max))| {
                Check::Range(Range {
                    path,
                    min,
                    max,
                    outside: *not,
                })
            }),
        ),
        tree::Phrase::Time { time, operand } => {
            let right = operand_side(operand, scope)?;
            Some(joined(scope.left_path(path), right).map(|(left, right)| {
                Check::CompareTime(CompareTime {
                    left: Side::Path(left),
                    right,
                    order: match time {
                        tree::TimeOrder::Before => Order::Before,
                        tree::TimeOrder::After => Order::After,
                        tree::TimeOrder::OnOrBefore => Order::OnOrBefore,
                        tree::TimeOrder::OnOrAfter => Order::OnOrAfter,
                    },
                })
            }))
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests;
