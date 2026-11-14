use super::compare::{self, Cmp, Compare};
use super::time::{self, NANOS_PER_SECOND, SECONDS_PER_DAY, Time};
use super::walk::{self, Options};
use super::{Check, Input, Part, SidePath, Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::lower::{Scope, UNSUPPORTED_SUFFIX};
use crate::name;
use crate::path::{self, Ctx, OUTER, Path};
use crate::value;
use ergo_policy_sentences as s;
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
    Counted(Counted),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Count,
    Sum,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Counted {
    pub text: String,
    pub kind: Kind,
    pub path: Path,
    pub distinct: bool,
    pub whose: Vec<Check>,
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
    Compare {
        cmp: Cmp,
        within: Option<Number>,
    },
    Between {
        min: Number,
        max: Number,
        outside: bool,
    },
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
    located: Vec<String>,
}

fn once<'a>(locations: impl IntoIterator<Item = &'a String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for location in locations {
        if !out.contains(location) {
            out.push(location.clone());
        }
    }
    out
}

fn side_paths(side: &Side) -> Vec<&Path> {
    match side {
        Side::Plain(plain) => plain.paths(),
        Side::Derived(derived) => {
            let mut paths = Vec::new();
            for term in &derived.terms {
                match term {
                    Term::Path(path) => paths.push(path),
                    Term::Number(_) => {}
                    Term::Elapsed(elapsed) => {
                        paths.push(&elapsed.from);
                        paths.push(&elapsed.to);
                    }
                    Term::Counted(counted) => paths.push(&counted.path),
                }
            }
            paths
        }
    }
}

fn side_candidates(side: &Side) -> Vec<SidePath<'_>> {
    let one = |path, needs_list| SidePath { path, needs_list };
    match side {
        Side::Plain(plain) => plain
            .paths()
            .into_iter()
            .map(|path| one(path, false))
            .collect(),
        Side::Derived(derived) => {
            let mut paths = Vec::new();
            for term in &derived.terms {
                match term {
                    Term::Path(path) => paths.push(one(path, false)),
                    Term::Number(_) => {}
                    Term::Elapsed(elapsed) => {
                        paths.push(one(&elapsed.from, false));
                        paths.push(one(&elapsed.to, false));
                    }
                    Term::Counted(counted) => paths.push(one(&counted.path, true)),
                }
            }
            paths
        }
    }
}

fn reads_hidden_path(path: &Path, hidden: &[&str]) -> bool {
    starts_at(path, hidden) || path.steps.iter().any(|step| match step {
        path::Step::Ref(reference) => {
            matches!(&reference.start, path::Start::Alias(name) if hidden.contains(&name.as_str()))
        }
        _ => false,
    })
}

fn check_reads_hidden(check: &Check, hidden: &[&str]) -> bool {
    check
        .paths()
        .into_iter()
        .any(|path| reads_hidden_path(path, hidden))
        || match check {
            Check::Tally(tally) => std::iter::once(&tally.left)
                .chain(tally.right.as_ref())
                .any(|side| match side {
                    Side::Derived(derived) => reads_derived(derived, hidden),
                    Side::Plain(_) => false,
                }),
            _ => false,
        }
}

fn reads_derived(derived: &Derived, hidden: &[&str]) -> bool {
    derived.terms.iter().any(|term| match term {
        Term::Path(path) => reads_hidden_path(path, hidden),
        Term::Elapsed(elapsed) => {
            reads_hidden_path(&elapsed.from, hidden) || reads_hidden_path(&elapsed.to, hidden)
        }
        Term::Counted(counted) => {
            reads_hidden_path(&counted.path, hidden)
                || counted
                    .whose
                    .iter()
                    .any(|check| check_reads_hidden(check, hidden))
        }
        Term::Number(_) => false,
    })
}

const MOST_SECONDS: i64 = 9_000_000_000;
const MICROS: i128 = 1_000_000;

impl Tally {
    pub fn counted_paths(&self) -> Vec<&Path> {
        let mut paths = Vec::new();
        for side in std::iter::once(&self.left).chain(self.right.as_ref()) {
            if let Side::Derived(derived) = side {
                for term in &derived.terms {
                    if let Term::Counted(counted) = term {
                        paths.push(&counted.path);
                    }
                }
            }
        }
        paths
    }

    pub fn unaliased_entries(&self, ctx: &Ctx, hidden: &[&str]) -> Vec<Input> {
        let reads_hidden = |derived: &Derived| reads_derived(derived, hidden);
        let mut entries = Vec::new();
        for side in std::iter::once(&self.left).chain(self.right.as_ref()) {
            if let Side::Derived(derived) = side
                && !reads_hidden(derived)
            {
                entries.extend(work_derived(derived, ctx).entries.into_iter().take(1));
            }
        }
        entries
    }

    pub fn paths_outside(&self, hidden: &[&str]) -> Vec<&Path> {
        let mut paths = Vec::new();
        for side in std::iter::once(&self.left).chain(self.right.as_ref()) {
            match side {
                Side::Derived(derived) if reads_derived(derived, hidden) => {
                    for term in &derived.terms {
                        if let Term::Counted(counted) = term {
                            paths.push(&counted.path);
                        }
                    }
                }
                other => paths.extend(side_paths(other)),
            }
        }
        paths
    }

    pub fn sides(&self) -> Vec<Vec<SidePath<'_>>> {
        std::iter::once(&self.left)
            .chain(self.right.as_ref())
            .map(side_candidates)
            .collect()
    }

    pub fn paths(&self) -> Vec<&Path> {
        let mut paths = Vec::new();
        for side in std::iter::once(&self.left).chain(self.right.as_ref()) {
            paths.extend(side_paths(side));
        }
        paths
    }

    pub fn refs(&self) -> Vec<Path> {
        let mut refs = Vec::new();
        for path in self.paths() {
            refs.extend(path::step_refs(path));
        }
        for side in std::iter::once(&self.left).chain(self.right.as_ref()) {
            if let Side::Derived(derived) = side {
                for term in &derived.terms {
                    if let Term::Counted(counted) = term {
                        for check in &counted.whose {
                            refs.extend(check.refs());
                        }
                    }
                }
            }
        }
        refs
    }

    pub fn walking_refs(&self) -> Vec<Path> {
        let mut refs = Vec::new();
        for side in std::iter::once(&self.left).chain(self.right.as_ref()) {
            if let Side::Derived(derived) = side {
                for term in &derived.terms {
                    if let Term::Counted(counted) = term {
                        for check in &counted.whose {
                            refs.extend(check.walking_refs());
                        }
                    }
                }
            }
        }
        refs
    }
}

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
        (Test::Between { min, max, outside }, None) => match left {
            Value::Number(n) => value::between(min, n, max)
                .map_or(Cause::Unusable, |inside| verdict(inside != *outside)),
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
                entries: read.inputs,
                located: Vec::new(),
            }
        }
        Side::Derived(derived) => {
            let worked = work_derived(derived, ctx);
            Worked {
                result: worked.result.map(Value::Number),
                entries: worked.entries,
                located: worked.located,
            }
        }
    }
}

fn number_entry(text: &str, result: &Result<Number, Cause>, locations: Vec<String>) -> Input {
    Input {
        name: text.to_string(),
        value: match result {
            Ok(n) => Value::Number(n.clone()),
            Err(_) => Value::Null,
        },
        locations,
        part: None,
        state: crate::path::Outcome::Found,
        null_at: None,
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
    let located = once(worked.iter().flat_map(|w| &w.located));
    let below: Vec<Input> = worked.into_iter().flat_map(|w| w.entries).collect();
    let mut sum = number_entry(&derived.text, &result, located.clone());
    let mut tags: Vec<&super::Part> = Vec::new();
    for tag in below.iter().filter_map(|entry| entry.part.as_ref()) {
        if !tags.contains(&tag) {
            tags.push(tag);
        }
    }
    if let [only] = tags.as_slice() {
        sum.part = Some((*only).clone());
    }
    let mut entries = vec![sum];
    entries.extend(below);
    Worked {
        result,
        entries,
        located,
    }
}

fn work_term(term: &Term, ctx: &Ctx) -> Worked<Number> {
    match term {
        Term::Number(n) => Worked {
            result: Ok(n.clone()),
            entries: Vec::new(),
            located: Vec::new(),
        },
        Term::Path(path) => {
            let read = read_path(path, ctx);
            let result = match (read.outcome.cause(), read.value) {
                (Some(cause), _) => Err(cause),
                (None, Some(Value::Number(n))) => Ok(n),
                (None, _) => Err(Cause::Unusable),
            };
            Worked {
                located: once(read.inputs.iter().take(1).flat_map(|e| &e.locations)),
                result,
                entries: read.inputs,
            }
        }
        Term::Elapsed(elapsed) => work_elapsed(elapsed, ctx),
        Term::Counted(counted) => work_counted(counted, ctx),
    }
}

fn starts_at(path: &Path, hidden: &[&str]) -> bool {
    matches!(&path.start, path::Start::Alias(name) if hidden.contains(&name.as_str()))
}

fn outer_ctx<'a>(ctx: &Ctx<'a>) -> Ctx<'a> {
    let mut outer = ctx.clone();
    if !outer.aliases.contains_key(OUTER) {
        outer.aliases.insert(OUTER.to_string(), ctx.subject.clone());
    }
    outer
}

fn unusable_ref(check: &Check, ctx: &Ctx) -> Option<Cause> {
    let keys: Vec<Path> = check
        .paths()
        .into_iter()
        .flat_map(path::step_refs)
        .collect();
    let causes = check.refs().into_iter().filter_map(|reference| {
        if let Some(walk) = super::lists::walked_in(check, &reference, ctx) {
            return walk.cause.filter(|cause| *cause != Cause::Value);
        }
        let read = path::read(&reference, ctx);
        match (read.outcome.cause(), read.value) {
            (Some(cause), _) => Some(cause),
            (None, Some(Value::String(_) | Value::Number(_))) => None,
            (None, _) if keys.contains(&reference) => Some(Cause::Unusable),
            (None, _) => None,
        }
    });
    Cause::worst(causes)
}

fn counted_entries(
    counted: &Counted,
    result: &Result<Number, Cause>,
    list: Input,
    outside: Vec<Input>,
    ctx: &Ctx,
) -> (Vec<Input>, Vec<String>) {
    let located = once(
        list.locations
            .iter()
            .chain(outside.iter().flat_map(|e| &e.locations)),
    );
    let mut entries = vec![Input {
        name: counted.text.clone(),
        value: match result {
            Ok(n) => Value::Number(n.clone()),
            Err(_) => Value::Null,
        },
        locations: list.locations.clone(),
        part: list.part.clone(),
        state: crate::path::Outcome::Found,
        null_at: None,
    }];
    entries.push(list);
    entries.extend(super::field_inputs(&counted.path, ctx));
    entries.extend(outside);
    (entries, located)
}

fn work_counted(counted: &Counted, ctx: &Ctx) -> Worked<Number> {
    let outer = outer_ctx(ctx);
    if walk::path_needs_an_object_subject(&counted.path, ctx) {
        let result = Err(Cause::NotAnObject);
        let list = Input {
            name: name::name(&counted.path),
            value: Value::Array(Vec::new()),
            locations: Vec::new(),
            part: None,
            state: crate::path::Outcome::Found,
            null_at: None,
        };
        let whose: Vec<&Check> = counted.whose.iter().collect();
        let mut outside = walk::outside_inputs_of(&whose, &outer);
        outside.sort_by(|a, b| a.name.cmp(&b.name));
        let (entries, located) = counted_entries(counted, &result, list, outside, ctx);
        return Worked {
            entries,
            located,
            result,
        };
    }
    let walked = walk::walk(
        &counted.path,
        &outer,
        Options {
            if_any: false,
            empty_adds_nothing: true,
        },
    );
    let whose: Vec<&Check> = counted.whose.iter().collect();
    let mut outside = walk::outside_inputs_of(&whose, &outer);
    outside.sort_by(|a, b| a.name.cmp(&b.name));
    if let Some(outcome) = walked.unreadable {
        let result = Err(outcome.cause().unwrap_or(Cause::Unusable));
        let list = Input {
            name: walked.name,
            value: Value::Array(Vec::new()),
            locations: Vec::new(),
            part: None,
            state: crate::path::Outcome::Found,
            null_at: None,
        };
        let (entries, located) = counted_entries(counted, &result, list, outside, ctx);
        return Worked {
            entries,
            located,
            result,
        };
    }
    let mut causes: Vec<Cause> = walked.failures.iter().map(|f| f.cause).collect();
    let whose_checks: Vec<&Check> = counted.whose.iter().collect();
    causes.extend(super::message::root_flaw(&whose_checks, &outer).map(|(cause, _)| cause));
    causes.extend(counted.whose.iter().filter_map(|c| unusable_ref(c, &outer)));
    let mut numbers: Vec<Value> = Vec::new();
    let mut at = outer.clone();
    for item in &walked.items {
        at.subject = item.item.clone();
        at.label = None;
        let focus = walk::focus_ctx(item, &outer);
        let verdicts: Vec<Cause> = counted
            .whose
            .iter()
            .map(|check| walk::focus_verdict(check, item, &at, &focus).0.cause)
            .collect();
        let undecided = verdicts
            .iter()
            .filter(|cause| !matches!(cause, Cause::Satisfied | Cause::Value))
            .copied();
        let before = causes.len();
        causes.extend(undecided);
        if causes.len() > before || verdicts.contains(&Cause::Value) {
            continue;
        }
        match item.end {
            Some(end) => numbers.push(end.clone()),
            None => causes.push(item.miss),
        }
    }
    if counted.distinct {
        let mut seen = std::collections::BTreeSet::new();
        numbers.retain(|value| seen.insert(crate::value::copy_key(value)));
    }
    let total = match counted.kind {
        Kind::Count => Ok(Number::from(numbers.len() as u64)),
        Kind::Sum => summed(&numbers),
    };
    causes.extend(total.as_ref().err());
    let result = match Cause::worst(causes) {
        Some(cause) => Err(cause),
        None => total,
    };
    let list = walked_list(&walked, &counted.path, &outer);
    let (entries, located) = counted_entries(counted, &result, list, outside, ctx);
    Worked {
        entries,
        located,
        result,
    }
}

fn walked_list(walked: &walk::Walked, path: &Path, outer: &Ctx) -> Input {
    Input {
        name: walked.name.clone(),
        value: Value::Array(walked.items.iter().map(walk::WalkItem::shown).collect()),
        locations: walked
            .items
            .iter()
            .map(|item| item.end_location.render())
            .collect(),
        part: path::part_tag(path, outer).map(|(name, id)| Part { name, id }),
        state: crate::path::Outcome::Found,
        null_at: None,
    }
}

pub(super) fn counted_list(path: &Path, ctx: &Ctx) -> Input {
    let outer = outer_ctx(ctx);
    let walked = walk::walk(
        path,
        &outer,
        Options {
            if_any: false,
            empty_adds_nothing: true,
        },
    );
    walked_list(&walked, path, &outer)
}

fn summed(values: &[Value]) -> Result<Number, Cause> {
    let mut numbers = Vec::new();
    let mut causes = Vec::new();
    for value in values {
        match value {
            Value::Number(n) => numbers.push(n.clone()),
            Value::Null => causes.push(Cause::Null),
            _ => causes.push(Cause::Unusable),
        }
    }
    match Cause::worst(causes) {
        Some(cause) => Err(cause),
        None => add(&numbers).ok_or(Cause::Unusable),
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
    let located = once(
        [&from.inputs, &to.inputs]
            .into_iter()
            .flat_map(|inputs| inputs.iter().take(1))
            .flat_map(|e| &e.locations),
    );
    let below: Vec<Input> = from.inputs.into_iter().chain(to.inputs).collect();
    let mut entries = vec![number_entry(&elapsed.text, &result, located.clone())];
    entries.extend(below);
    Worked {
        result,
        entries,
        located,
    }
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
    let below = value::compare_numbers(n, &limit(-MOST_SECONDS)).ok_or(Cause::Unusable)?;
    let above = value::compare_numbers(n, &limit(MOST_SECONDS)).ok_or(Cause::Unusable)?;
    if below == Ordering::Less || above == Ordering::Greater {
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

const WHOLE_LIMIT: i64 = 15;

fn add(numbers: &[Number]) -> Option<Number> {
    let parts: Vec<Parts> = numbers
        .iter()
        .map(|n| Parts::of(&n.to_string()))
        .collect::<Option<_>>()?;
    let places = parts
        .iter()
        .filter(|p| !p.digits.is_empty())
        .map(|p| p.exponent.checked_neg().unwrap_or(i64::MAX).max(0))
        .max()
        .unwrap_or(0);
    if places > WHOLE_LIMIT {
        return None;
    }
    let mut total: i128 = 0;
    for part in parts.iter().filter(|p| !p.digits.is_empty()) {
        let width = (part.digits.len() as i64)
            .saturating_add(part.exponent)
            .saturating_add(places);
        if width > WHOLE_LIMIT {
            return None;
        }
        let scaled: i128 = format!(
            "{}{}",
            part.digits,
            "0".repeat((part.exponent + places) as usize)
        )
        .parse()
        .ok()?;
        total += if part.negative { -scaled } else { scaled };
    }
    if total.unsigned_abs() >= 10_u128.pow(WHOLE_LIMIT as u32) {
        return None;
    }
    decimal_text(total, places).parse::<Number>().ok()
}

fn decimal_text(total: i128, places: i64) -> String {
    if total == 0 {
        return "0".to_string();
    }
    let sign = if total < 0 { "-" } else { "" };
    let magnitude = total.unsigned_abs().to_string();
    let places = places as usize;
    let padded = format!("{magnitude:0>width$}", width = places + 1);
    let (whole, fraction) = padded.split_at(padded.len() - places);
    let fraction = fraction.trim_end_matches('0');
    if fraction.is_empty() {
        format!("{sign}{whole}")
    } else {
        format!("{sign}{whole}.{fraction}")
    }
}

fn term_text(term: &s::Term, names: &[&str], left: Option<&[&str]>) -> String {
    if let Some(parents) = left {
        return s::print_left_term(term, names, parents);
    }
    s::print_term(term, names)
}

fn lower_term(term: &s::Term, scope: &Scope, names: &[&str]) -> Result<Option<Term>, Vec<String>> {
    let parent_names = scope.left_print_names();
    let parent_refs: Vec<&str> = parent_names.iter().map(String::as_str).collect();
    let scope_left = scope.prints_left().then_some(parent_refs.as_slice());
    match term {
        s::Term::Path(path) => scope.term_path(path).map(|p| Some(Term::Path(p))),
        s::Term::Number(text) => match scope.value(&s::Value::Number(text.clone()))? {
            Value::Number(n) => Ok(Some(Term::Number(n))),
            _ => Ok(None),
        },
        s::Term::Elapsed(elapsed) => {
            let from = scope.path(&elapsed.from);
            let to = scope.path(&elapsed.to);
            match (from, to) {
                (Ok(from), Ok(to)) => Ok(Some(Term::Elapsed(Elapsed {
                    text: term_text(term, names, scope_left),
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
        s::Term::Derived(derived) => lower_counted(term, derived, scope, names),
    }
}

fn lower_counted(
    term: &s::Term,
    derived: &s::Derived,
    scope: &Scope,
    names: &[&str],
) -> Result<Option<Term>, Vec<String>> {
    let parent_names = scope.left_print_names();
    let parent_refs: Vec<&str> = parent_names.iter().map(String::as_str).collect();
    let scope_left = scope.prints_left().then_some(parent_refs.as_slice());
    let mut problems = Vec::new();
    let path = match scope.counted_path(&derived.path) {
        Ok(path) => {
            problems.extend(crate::lower::walk_too_long(&path));
            Some(path)
        }
        Err(found) => {
            problems.extend(found);
            None
        }
    };
    let item = scope.in_tally_item();
    let mut whose = Vec::new();
    for condition in &derived.whose {
        match crate::lower::lower_tally_condition(condition, &item) {
            Ok(check) => whose.push(check),
            Err(found) => problems.extend(found),
        }
    }
    if !problems.is_empty() {
        return Err(problems);
    }
    Ok(path.map(|path| {
        Term::Counted(Counted {
            text: term_text(term, names, scope_left),
            kind: match derived.kind {
                s::DerivedKind::Count => Kind::Count,
                s::DerivedKind::Sum => Kind::Sum,
            },
            path,
            distinct: derived.distinct,
            whose,
        })
    }))
}

fn lower_side(
    terms: &[s::Term],
    scope: &Scope,
    names: &[&str],
) -> Result<Option<Side>, Vec<String>> {
    let parent_names = scope.left_print_names();
    let parent_refs: Vec<&str> = parent_names.iter().map(String::as_str).collect();
    let scope_left = scope.prints_left().then_some(parent_refs.as_slice());
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
                .map(|t| term_text(t, names, scope_left))
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
        s::Operand::Joined(_) => Ok(None),
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
        s::Phrase::Between { not, min, max } => Some(
            number(min, scope)
                .and_then(|min| number(max, scope).map(|max| (min, max)))
                .map(|(min, max)| {
                    (
                        Test::Between {
                            min,
                            max,
                            outside: *not,
                        },
                        None,
                    )
                }),
        ),
        _ => None,
    }
}

pub fn lower_assertion(
    assertion: &s::Assertion,
    scope: &Scope,
) -> Option<Result<Check, Vec<String>>> {
    let aliases = scope.aliases();
    let names: Vec<&str> = aliases.iter().map(String::as_str).collect();
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
    Some(
        lower_terms(&left, phrase, scope).and_then(|lowered| match lowered {
            Some(tally) => Ok(Check::Tally(tally)),
            None => Err(vec![format!(
                "{}{UNSUPPORTED_SUFFIX}",
                s::print_assertion(assertion, &names)
            )]),
        }),
    )
}

fn lower_terms(
    left: &[s::Term],
    phrase: &s::Phrase,
    scope: &Scope,
) -> Result<Option<Tally>, Vec<String>> {
    let aliases = scope.aliases();
    let names: Vec<&str> = aliases.iter().map(String::as_str).collect();
    let left = lower_side(left, &scope.as_left(), &names)?;
    let Some((test, right)) = lower_test(phrase, scope, &names).transpose()? else {
        return Ok(None);
    };
    Ok(left.map(|left| Tally { left, right, test }))
}

pub fn lower_condition(
    left: &s::Left,
    phrase: &s::Phrase,
    scope: &Scope,
) -> Option<Result<Option<Check>, Vec<String>>> {
    let term = match left {
        s::Left::Derived(derived) => s::Term::Derived(derived.clone()),
        s::Left::Elapsed(elapsed) => s::Term::Elapsed(elapsed.clone()),
        s::Left::Path(path) => match phrase {
            s::Phrase::Is {
                operand: s::Operand::Field(terms),
                ..
            }
            | s::Phrase::Order {
                operand: s::Operand::Field(terms),
                ..
            } if mine(terms) => s::Term::Path(path.clone()),
            _ => return None,
        },
    };
    Some(lower_terms(&[term], phrase, scope).map(|lowered| lowered.map(Check::Tally)))
}

pub fn derived_value(derived: &Derived, ctx: &Ctx) -> Result<Number, Cause> {
    work_derived(derived, ctx).result
}

pub fn derived_operands(derived: &Derived) -> (Vec<&Path>, Vec<&Path>, Vec<(&Path, &Path)>) {
    let mut plain = Vec::new();
    let mut counted = Vec::new();
    let mut elapsed = Vec::new();
    for term in &derived.terms {
        match term {
            Term::Path(path) => plain.push(path),
            Term::Elapsed(e) => elapsed.push((&e.from, &e.to)),
            Term::Counted(c) => counted.push(&c.path),
            Term::Number(_) => {}
        }
    }
    (plain, counted, elapsed)
}

pub(super) fn counted_faults(tally: &Tally, path: &Path, ctx: &Ctx) -> Vec<(Cause, String)> {
    let mut faults = Vec::new();
    for side in tally_sides(tally) {
        let Side::Derived(derived) = side else {
            continue;
        };
        for term in &derived.terms {
            if let Term::Counted(counted) = term
                && counted.path == *path
                && let Err(cause) = work_counted(counted, ctx).result
                && let Some(text) = counted_text(counted, ctx, cause)
            {
                faults.push((cause, text));
            }
        }
    }
    faults
}

pub fn with_walked_roots(check: &Tally, ctx: &Ctx, message: String) -> String {
    let outer = outer_ctx(ctx);
    let whose: Vec<&Check> = tally_sides(check)
        .into_iter()
        .filter_map(|side| match side {
            Side::Derived(derived) => Some(derived),
            _ => None,
        })
        .flat_map(|derived| derived.terms.iter())
        .filter_map(|term| match term {
            Term::Counted(counted) => {
                let walked = walk::walk(
                    &counted.path,
                    &outer,
                    Options {
                        if_any: false,
                        empty_adds_nothing: true,
                    },
                );
                (walked.unreadable.is_none() && walked.failures.is_empty())
                    .then(|| counted.whose.iter())
            }
            _ => None,
        })
        .flatten()
        .collect();
    super::message::walked_roots_ahead(Some(message.clone()), &whose, &outer, &whose)
        .unwrap_or(message)
}

pub fn tally_sides(check: &Tally) -> Vec<&Side> {
    std::iter::once(&check.left)
        .chain(check.right.as_ref())
        .collect()
}

pub fn counted_texts(derived: &Derived, ctx: &Ctx, cause: Cause) -> Vec<String> {
    derived
        .terms
        .iter()
        .filter_map(|term| match term {
            Term::Counted(counted) => counted_text(counted, ctx, cause),
            _ => None,
        })
        .collect()
}

impl Tally {
    /// Returns true when it reads a `count of` or a `sum of`, like
    /// `count of rs whose v is "a" is 1`.
    #[must_use]
    pub fn counts(&self) -> bool {
        std::iter::once(&self.left)
            .chain(self.right.as_ref())
            .any(|side| match side {
                Side::Derived(derived) => derived
                    .terms
                    .iter()
                    .any(|term| matches!(term, Term::Counted(_))),
                Side::Plain(_) => false,
            })
    }
}

pub fn counted_text(counted: &Counted, ctx: &Ctx, cause: Cause) -> Option<String> {
    let mut out = Vec::new();
    {
        let outer = outer_ctx(ctx);
        if walk::path_needs_an_object_subject(&counted.path, ctx) {
            return None;
        }
        let whose: Vec<&Check> = counted.whose.iter().collect();
        let any_root = super::message::root_flaw_counted(&whose, &outer);
        let root = any_root
            .clone()
            .filter(|(flaw, _)| *flaw == cause)
            .map(|(_, text)| text);
        let walked = walk::walk(
            &counted.path,
            &outer,
            Options {
                if_any: false,
                empty_adds_nothing: true,
            },
        );
        if let Some(outcome) = walked.unreadable {
            match outcome.cause() {
                Some(Cause::Absent) if cause == Cause::Absent => {
                    out.push(format!("{} is missing", walked.name));
                }
                Some(Cause::Null) if cause == Cause::Null => {
                    out.push(format!("{} is null", walked.name));
                }
                Some(Cause::Unusable) if cause == Cause::Unusable => {
                    let blocked = if walk::through_a_list(&counted.path, &outer) {
                        Vec::new()
                    } else {
                        super::message::blocked_of(&counted.path, &outer)
                    };
                    if !blocked.is_empty() {
                        out.push(super::message::joined(blocked));
                    } else {
                        let read = path::read(&counted.path, &outer);
                        if let (path::Outcome::Found, Some(value)) = (read.outcome, read.value)
                            && !value.is_array()
                            && !value.is_object()
                        {
                            out.push(super::message::isnt(
                                &walked.name,
                                value,
                                "a list or an object",
                            ));
                        }
                    }
                }
                _ => {}
            }
            out.extend(root);
            return if out.is_empty() {
                None
            } else {
                Some(super::message::joined(out))
            };
        }
        if let Some(text) = root {
            let mut said: Vec<String> = walked
                .failures
                .iter()
                .filter(|f| f.cause == cause)
                .map(|f| f.msg.clone())
                .collect();
            said.push(text);
            return Some(super::message::joined(said));
        }
        let mut always = std::collections::BTreeSet::new();
        let mut found: Vec<(Cause, String)> = walked
            .failures
            .iter()
            .map(|f| (f.cause, f.msg.clone()))
            .collect();
        let root_texts: Vec<String> = any_root
            .map(|(_, text)| text.split("; ").map(str::to_string).collect())
            .unwrap_or_default();
        for text in &root_texts {
            always.insert(found.len());
            found.push((cause, text.clone()));
        }
        let mut refs: Vec<Path> = counted.whose.iter().flat_map(Check::refs).collect();
        refs.sort_by_key(name::name);
        refs.dedup();
        for reference in &refs {
            let read = path::read(reference, &outer);
            let said = match read.outcome {
                path::Outcome::Absent => Some((Cause::Absent, "missing")),
                path::Outcome::Null => Some((Cause::Null, "null")),
                _ => None,
            };
            if let Some((found_cause, word)) = said {
                let named = super::null_step_name(reference, &outer)
                    .unwrap_or_else(|| name::name(reference));
                let text = format!("{named} is {word}");
                if !root_texts.contains(&text) {
                    found.push((found_cause, text));
                }
            }
        }
        let mut at = outer.clone();
        for item in &walked.items {
            at.subject = item.item.clone();
            at.label = None;
            let focus = walk::focus_ctx(item, &outer);
            let name = walked.item_name(&item.item_segs);
            let mut undecided = false;
            for check in &counted.whose {
                let (verdict, lost) = walk::focus_verdict(check, item, &at, &focus);
                if !matches!(verdict.cause, Cause::Satisfied | Cause::Value) {
                    undecided = true;
                    let said = if lost {
                        super::message::prefixed(
                            &name,
                            &super::message::message(&walk::focus_check(item), &at, &verdict),
                        )
                    } else {
                        let off = super::message::off_item(check, &outer, verdict.cause);
                        let walked_root = super::lists::field_walk_fault(check, &focus)
                            .filter(|(cause, _)| *cause == verdict.cause)
                            .map(|(_, text)| text);
                        if let Some(fault) =
                            super::message::root_fault(check, &outer, verdict.cause)
                        {
                            fault
                        } else if let Some(text) = walked_root {
                            text
                        } else if off.is_empty() {
                            super::message::prefixed(
                                &walked.item_name(walk::focus_segs(item, check)),
                                &super::message::message(check, &focus, &verdict),
                            )
                        } else {
                            off.join(", and ")
                        }
                    };
                    if !item.rest.is_empty() && walk::reads_focus(check) {
                        always.insert(found.len());
                    }
                    found.push((verdict.cause, said));
                }
            }
            let kept = counted
                .whose
                .iter()
                .all(|check| walk::focus_verdict(check, item, &at, &focus).0.cause != Cause::Value);
            if undecided || !kept {
                continue;
            }
            let rest = crate::name::name(&item.rest_path());
            if item.miss == Cause::NotAnObject {
                found.push((
                    Cause::NotAnObject,
                    super::message::isnt(&name, item.item.value, "an object"),
                ));
                continue;
            }
            match item.end {
                None if item.miss == Cause::Unusable => found.push((
                    item.miss,
                    super::message::prefixed(
                        &name,
                        &super::message::message(
                            &walk::focus_check(item),
                            &at,
                            &walk::lost_verdict(item, &at),
                        ),
                    ),
                )),
                None => found.push((
                    item.miss,
                    super::message::prefixed(
                        &name,
                        &super::message::stated(&rest, item.miss, &Value::Null, "a number"),
                    ),
                )),
                Some(end) if counted.kind == Kind::Sum && !end.is_number() => {
                    let c = if end.is_null() {
                        Cause::Null
                    } else {
                        Cause::Unusable
                    };
                    found.push((
                        c,
                        super::message::prefixed(
                            &name,
                            &super::message::stated(&rest, c, end, "a number"),
                        ),
                    ));
                }
                _ => {}
            }
        }
        let said: Vec<String> = super::message::once_of(
            found
                .into_iter()
                .enumerate()
                .filter(|(at, (c, _))| *c == cause || always.contains(at))
                .map(|(_, (_, text))| text)
                .collect(),
        );
        if !said.is_empty() {
            out.push(super::message::joined(said));
        }
    }
    out.pop()
}

#[cfg(test)]
mod tests;
