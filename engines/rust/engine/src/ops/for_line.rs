use super::clause::Clause;
use super::tally::{Side, Tally, Term};
use super::time::{self, Time};
use super::walk::{self, Failure, Options, Seg, WalkItem};
use super::{Check, Input, Part, Verdict, push_new, run_full};
use crate::cause::Cause;
use crate::lower::{self, Scope};
use crate::path::{self, Ctx, Located, Location, OUTER, Path, Start, Step};
use ergo_policy_sentences as s;
use serde_json::{Value, json};
use std::cmp::Ordering;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Spot {
    First,
    Last,
    Nth(u64),
    NthFromLast(u64),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Sorted {
    pub path: Path,
    pub alphabetically: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum How {
    Every { if_any: bool },
    Some { if_any: bool },
    Pick { spot: Spot, sorted: Option<Sorted> },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Item {
    pub how: How,
    pub path: Path,
    pub distinct: bool,
    pub whose: Vec<Check>,
    pub alias: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Sentence {
    pub text: String,
    pub check: Check,
    pub reads_last: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct For {
    pub items: Vec<Item>,
    pub sentences: Vec<Sentence>,
}

impl For {
    pub fn refs(&self) -> Vec<Path> {
        let mut refs = Vec::new();
        for item in &self.items {
            refs.extend(path::step_refs(&item.path));
            for check in &item.whose {
                refs.extend(check.refs());
            }
        }
        for sentence in &self.sentences {
            refs.extend(sentence.check.refs());
        }
        refs
    }

    pub fn walking_refs(&self) -> Vec<Path> {
        let mut refs = Vec::new();
        for item in &self.items {
            for check in &item.whose {
                refs.extend(check.walking_refs());
            }
        }
        for sentence in &self.sentences {
            refs.extend(sentence.check.walking_refs());
        }
        refs
    }
}

pub struct Run {
    pub verdict: Verdict,
    pub failed_items: Vec<Value>,
    pub message: Option<String>,
    pub items: Vec<Clause>,
}

#[cfg(test)]
type Ran = (Cause, Option<String>, Vec<Clause>, Vec<Clause>);

#[cfg(test)]
thread_local! {
    pub static RAN: std::cell::RefCell<Vec<Ran>> = const { std::cell::RefCell::new(Vec::new()) };
}

pub(crate) fn all_paths(check: &Check) -> Vec<&Path> {
    let mut paths = check.paths();
    match check {
        Check::Tally(tally) => {
            for side in std::iter::once(&tally.left).chain(tally.right.as_ref()) {
                if let Side::Derived(derived) = side {
                    for term in &derived.terms {
                        if let Term::Counted(counted) = term {
                            for inner in &counted.whose {
                                paths.extend(item_paths(inner));
                            }
                        }
                    }
                }
            }
        }
        Check::Walk(walk) => {
            paths.push(&walk.path);
            for inner in walk.whose.iter().chain(std::iter::once(&*walk.check)) {
                paths.extend(item_paths(inner));
            }
        }
        _ => {}
    }
    paths
}

fn tally_paths<'a>(tally: &'a Tally, hidden: &[&str]) -> (Vec<&'a Path>, Vec<&'a Path>) {
    let paths = tally.paths_outside(hidden);
    let mut whose = Vec::new();
    for side in std::iter::once(&tally.left).chain(tally.right.as_ref()) {
        if let Side::Derived(derived) = side {
            for term in &derived.terms {
                if let Term::Counted(counted) = term {
                    for inner in &counted.whose {
                        whose.extend(item_paths(inner));
                    }
                }
            }
        }
    }
    (paths, whose)
}

fn listed_walk(path: &Path, listed: &[*const Path], ctx: &Ctx, hidden: &[&str]) -> Option<Input> {
    if !listed.contains(&std::ptr::from_ref(path)) {
        return None;
    }
    let walks = match &path.start {
        Start::Subject | Start::Own => true,
        Start::Part(_) => true,
        Start::Alias(name) => !hidden.contains(&name.as_str()),
        _ => false,
    };
    walks
        .then(|| super::lists::walked(path, ctx))
        .flatten()
        .map(|walked| walked.input())
}

fn walked_paths(check: &Check) -> Vec<(&Path, bool)> {
    match check {
        Check::Walk(walk) => vec![(&walk.path, walk.if_any)],
        Check::Tally(tally) => tally
            .counted_paths()
            .into_iter()
            .map(|p| (p, false))
            .collect(),
        _ => Vec::new(),
    }
}

fn item_paths(check: &Check) -> Vec<&Path> {
    all_paths(check)
        .into_iter()
        .filter(|path| !matches!(path.start, Start::Subject | Start::Own))
        .collect()
}

/// The message an entry of a `for` line's `failures` gives for the item
/// `name`, from the texts its sentence said for that item.
pub fn rendered(name: &str, texts: &[String]) -> String {
    match texts {
        [] => String::new(),
        [one] if !one.starts_with(MARK) => one.clone(),
        _ => {
            let mut once: Vec<String> = Vec::new();
            for text in texts {
                push_new(&mut once, text.clone());
            }
            group_by_lead(&once)
                .iter()
                .map(|group| {
                    let said = under(name, &group_text(group));
                    match said.strip_prefix(&format!("{name}: ")) {
                        Some(rest) => rest.to_string(),
                        None => said,
                    }
                })
                .collect::<Vec<_>>()
                .join("; ")
        }
    }
}

/// Whether `check` reads the `for` alias `alias`.
pub fn reads_alias(check: &Check, alias: &str) -> bool {
    nested_checks(check).into_iter().any(|inner| {
        all_paths(inner)
            .into_iter()
            .chain(inner.paths())
            .any(|path| reads_path(path, alias))
    })
}

fn reads_path(path: &Path, alias: &str) -> bool {
    matches!(&path.start, Start::Alias(name) if name == alias)
        || path.steps.iter().any(|step| match step {
            Step::Ref(reference) => matches!(&reference.start, Start::Alias(name) if name == alias),
            _ => false,
        })
}

fn position_of(number: &str) -> Result<u64, Vec<String>> {
    match number.parse::<u64>() {
        Ok(at) if (1..=lower::MAX_POSITION).contains(&at) => Ok(at - 1),
        _ => Err(vec![format!("{number} can't be a list position")]),
    }
}

fn lower_whose(whose: &[s::Condition], scope: &Scope, problems: &mut Vec<String>) -> Vec<Check> {
    let mut checks = Vec::new();
    for condition in whose {
        match lower::lower_condition(condition, scope) {
            Ok(check) => checks.push(check),
            Err(found) => problems.extend(found),
        }
    }
    checks
}

pub fn lower_for(
    line: &s::ForLine,
    assertions: &[s::Assertion],
    places: &[String],
    scope: &Scope,
) -> Result<Check, Vec<String>> {
    let mut problems = Vec::new();
    let mut items = Vec::new();
    let mut bound = scope.clone();
    for (at, item) in line.items.iter().enumerate() {
        let later = line.items[at..].iter().map(|item| match item {
            s::ForItem::Walk { alias, .. } | s::ForItem::Pick { alias, .. } => alias.as_str(),
        });
        let here = bound.clone().with_pending(later);
        let item_scope = here.in_item();
        let (path, whose, alias, how) = match item {
            s::ForItem::Walk {
                quantifier,
                path,
                whose,
                if_any,
                alias,
                ..
            } => (
                path,
                whose,
                alias,
                match quantifier {
                    s::Quantifier::Every => How::Every { if_any: *if_any },
                    s::Quantifier::Some => How::Some { if_any: *if_any },
                },
            ),
            s::ForItem::Pick {
                position,
                path,
                whose,
                sorted_by,
                alias,
            } => {
                let spot = match position {
                    s::Position::First => Some(Spot::First),
                    s::Position::Last => Some(Spot::Last),
                    s::Position::Item { number, from_last } => match position_of(number) {
                        Ok(at) if *from_last => Some(Spot::NthFromLast(at)),
                        Ok(at) => Some(Spot::Nth(at)),
                        Err(found) => {
                            problems.extend(found);
                            None
                        }
                    },
                };
                let sorted = match sorted_by {
                    Some(sorted) => match item_scope
                        .item_scope_for_sort_key(&sorted.path)
                        .path(&item_scope.sort_key_path(&sorted.path))
                    {
                        Ok(path) => Some(Sorted {
                            path,
                            alphabetically: sorted.alphabetically,
                        }),
                        Err(found) => {
                            problems.extend(found);
                            None
                        }
                    },
                    None => None,
                };
                let how = spot.map(|spot| How::Pick { spot, sorted });
                match how {
                    Some(how) => (path, whose, alias, how),
                    None => {
                        bound = bound.with_for_alias(alias);
                        continue;
                    }
                }
            }
        };
        let walk_path = match here.path(path) {
            Ok(found) => {
                problems.extend(lower::walk_too_long(&found));
                Some(lower::with_members(
                    found,
                    matches!(item, s::ForItem::Walk { member: true, .. }),
                ))
            }
            Err(found) => {
                problems.extend(found);
                None
            }
        };
        let checks = lower_whose(whose, &item_scope, &mut problems);
        if let Some(path) = walk_path {
            items.push(Item {
                how,
                path,
                distinct: matches!(item, s::ForItem::Walk { distinct: true, .. }),
                whose: checks,
                alias: alias.clone(),
            });
        }
        bound = bound.with_for_alias(alias);
    }
    let mut problems: Vec<String> = problems
        .into_iter()
        .map(|problem| crate::lower::in_place("for: ", &problem))
        .collect();
    let names = bound.aliases();
    let names: Vec<&str> = names.iter().map(String::as_str).collect();
    let last_alias = line.items.last().map(|item| match item {
        s::ForItem::Walk { alias, .. } | s::ForItem::Pick { alias, .. } => alias.clone(),
    });
    let mut sentences = Vec::new();
    for (assertion, place) in assertions.iter().zip(places) {
        match lower::lower_assertion(assertion, &bound) {
            Ok(check) => sentences.push(Sentence {
                text: s::print_assertion(assertion, &names),
                reads_last: last_alias
                    .as_ref()
                    .is_some_and(|alias| reads_alias(&check, alias)),
                check,
            }),
            Err(found) => {
                problems.extend(found.into_iter().map(|p| crate::lower::in_place(place, &p)))
            }
        }
    }
    if !problems.is_empty() {
        return Err(problems);
    }
    Ok(Check::For(Box::new(For { items, sentences })))
}

struct Live<'a> {
    at: Located<'a>,
    name: String,
    bare: Option<String>,
    focus: String,
    said: String,
    order: Vec<Seg>,
    shown: Value,
    location: Location,
    copies: Vec<String>,
}

fn merged_live(live: Vec<Live<'_>>) -> Vec<Live<'_>> {
    let mut out: Vec<Live> = Vec::new();
    let mut seen: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
    for entry in live {
        let key = crate::value::copy_key(entry.at.value);
        match seen.get(&key) {
            Some(&at) => out[at].copies.push(entry.location.render()),
            None => {
                seen.insert(key, out.len());
                out.push(entry);
            }
        }
    }
    out
}

#[derive(Clone)]
struct Dead {
    wants_object: bool,
    raw: Option<Value>,
    msg: Option<String>,
    told: Option<Option<Clause>>,
    bare: Option<String>,
    shared: bool,
    list: bool,
    order: Vec<Seg>,
    name: String,
    said: String,
    path: String,
    cause: Cause,
    value: Value,
    location: Option<Location>,
    sorted: Option<Value>,
}

impl Dead {
    fn at(name: String, cause: Cause, value: Value, location: Option<Location>) -> Dead {
        Dead {
            wants_object: false,
            raw: None,
            bare: None,
            msg: None,
            told: None,
            shared: false,
            list: false,
            order: Vec::new(),
            path: name.clone(),
            name,
            said: String::new(),
            cause,
            value,
            location,
            sorted: None,
        }
    }

    fn shown(&self) -> &str {
        if self.said.is_empty() {
            &self.name
        } else {
            &self.said
        }
    }

    fn of_failure(failure: &Failure, list: bool) -> Dead {
        Dead {
            wants_object: failure.wants_object,
            bare: None,
            msg: None,
            told: None,
            shared: false,
            list,
            order: failure.order.clone(),
            name: failure.item.clone(),
            said: failure.said.clone(),
            path: failure.path.clone(),
            cause: failure.cause,
            value: failure.value.clone(),
            location: failure.location.clone(),
            raw: None,
            sorted: None,
        }
    }

    fn copy(&self) -> Dead {
        Dead {
            wants_object: self.wants_object,
            raw: self.raw.clone(),
            bare: self.bare.clone(),
            msg: self.msg.clone(),
            told: self.told.clone(),
            shared: self.shared,
            list: self.list,
            order: self.order.clone(),
            name: self.name.clone(),
            said: self.said.clone(),
            path: self.path.clone(),
            cause: self.cause,
            value: self.value.clone(),
            location: self.location.clone(),
            sorted: self.sorted.clone(),
        }
    }

    fn plain(&self) -> Value {
        let locations: Vec<String> = self.location.iter().map(Location::render).collect();
        json!({
            "path": self.path,
            "item": self.name,
            "cause": self.cause.name(),
            "value": self.value,
            "locations": locations,
        })
    }

    fn json(&self, assertions: Vec<Value>, inner: Vec<Value>) -> Value {
        let locations: Vec<String> = self.location.iter().map(Location::render).collect();
        let mut entry = json!({
            "path": self.path,
            "item": self.name,
            "cause": self.cause.name(),
            "value": self.value,
            "locations": locations,
            "failed_assertions": assertions,
        });
        if !inner.is_empty() {
            entry["failed_items"] = Value::Array(inner);
        }
        entry
    }
}

struct Cands<'a> {
    live: Vec<Live<'a>>,
    dead: Vec<Dead>,
    list: Input,
    unreadable: Option<Cause>,
    walked_none: bool,
    kept: usize,
    picked: bool,
    before_pick: usize,
}

fn outer_ctx<'a>(ctx: &Ctx<'a>) -> Ctx<'a> {
    let mut outer = ctx.clone();
    outer.aliases.insert(OUTER.to_string(), ctx.subject.clone());
    outer
}

fn empty_list(name: String) -> Input {
    Input {
        name,
        value: Value::Array(Vec::new()),
        locations: Vec::new(),
        part: None,
        state: crate::path::Outcome::Found,
        null_at: None,
        worked: false,
    }
}

enum Key {
    Number(serde_json::Number),
    Time(Time),
    Text(String),
}

fn kind(key: &Key) -> u8 {
    match key {
        Key::Number(_) => 0,
        Key::Time(Time::Instant(_)) => 1,
        Key::Time(_) => 2,
        Key::Text(_) => 3,
    }
}

fn compare_keys(a: &Key, b: &Key) -> Ordering {
    match (a, b) {
        (Key::Text(x), Key::Text(y)) => x.cmp(y),
        (Key::Time(x), Key::Time(y)) => time::compare_times(x, y).unwrap_or(Ordering::Equal),
        (Key::Number(x), Key::Number(y)) => {
            crate::value::compare_numbers(x, y).unwrap_or(Ordering::Equal)
        }
        _ => Ordering::Equal,
    }
}

fn sort_key(value: &Value, alphabetically: bool) -> Option<Key> {
    if alphabetically {
        return match value {
            Value::String(text) => Some(Key::Text(text.clone())),
            _ => None,
        };
    }
    match time::read_time(value)? {
        Time::Number(n) if !crate::value::is_readable(&n) => None,
        Time::Number(n) => Some(Key::Number(n)),
        other => Some(Key::Time(other)),
    }
}

impl For {
    fn candidates<'a>(&self, depth: usize, ctx: &Ctx<'a>) -> Cands<'a> {
        let item = &self.items[depth];
        let outer = outer_ctx(ctx);
        let (if_any, empty_ok) = match &item.how {
            How::Every { if_any } | How::Some { if_any } => (*if_any, false),
            How::Pick { .. } => (false, true),
        };
        let walked = walk::walk(
            &item.path,
            &outer,
            Options {
                if_any,
                empty_adds_nothing: empty_ok,
            },
        );
        if let Some(outcome) = walked.unreadable {
            let state = if super::key_base::field_key_flawed(&item.path, &outer) {
                crate::path::Outcome::Found
            } else {
                outcome
            };
            return Cands {
                live: Vec::new(),
                dead: walked
                    .failures
                    .iter()
                    .map(|failure| {
                        let list = !failure.order.iter().any(|seg| matches!(seg, Seg::Index(_)));
                        Dead::of_failure(failure, list)
                    })
                    .collect(),
                list: Input {
                    state,
                    ..empty_list(walked.name)
                },
                unreadable: Some(outcome.cause().unwrap_or(Cause::Unusable)),
                walked_none: false,
                kept: 0,
                picked: false,
                before_pick: 0,
            };
        }
        let list = Input {
            name: walked.name.clone(),
            value: Value::Array(walked.items.iter().map(WalkItem::shown).collect()),
            locations: walked
                .items
                .iter()
                .map(|w| w.end_location.render())
                .collect(),
            part: path::part_tag(&item.path, &outer).map(|(name, id)| Part { name, id }),
            state: walk::list_state(&walked),
            null_at: None,
            worked: false,
        };
        let first_walked = walked.walked.iter().next().copied();
        let mut dead: Vec<Dead> = walked
            .failures
            .iter()
            .map(|failure| {
                let list = first_walked.is_none_or(|level| failure.order.len() <= level);
                Dead::of_failure(failure, list)
            })
            .collect();
        let from_list = walked.failures.len();
        let mut live = Vec::new();
        let mut kept = 0;
        let mut at = outer.clone();
        for w in &walked.items {
            at.subject = w.item.clone();
            at.label = None;
            let focus = walk::focus_ctx(w, &outer);
            let verdicts: Vec<Verdict> = item
                .whose
                .iter()
                .map(|check| walk::focus_verdict(check, w, &at, &focus).0)
                .collect();
            let causes: Vec<Cause> = verdicts.iter().map(|v| v.cause).collect();
            let name = walked.name_of(&w.item_segs, w.unaliased);
            let undecided = Cause::worst(causes.iter().copied().filter(|c| c.is_failure()));
            let undecided_whose = || {
                item.whose
                    .iter()
                    .zip(&verdicts)
                    .filter(|(_, verdict)| verdict.cause.is_failure())
            };
            let told =
                undecided_whose().find_map(|(check, _)| walk::item_own(check, w, &walked, &outer));
            let first_alias = self.items[0].alias.as_str();
            let root = undecided_whose().find_map(|(check, _)| {
                let keys = super::key_base::unreadable_keys(check, &outer);
                let roots: Vec<Clause> =
                    super::message::listed_root_clauses(&[check], &outer, true)
                        .into_iter()
                        .chain(super::message::walked_root_clauses(&[check], &outer))
                        .filter(|root| !keys.iter().any(|(_, key)| *key == root.text))
                        .collect();
                let line = super::clause::lines(&roots).into_iter().next()?;
                Some(if reads_alias(check, first_alias) {
                    line
                } else {
                    format!("{FREE}{line}")
                })
            });
            let unread_key = undecided_whose()
                .any(|(check, _)| !super::key_base::unreadable_keys(check, &outer).is_empty());
            let rootless = root.is_none()
                && !unread_key
                && !undecided_whose().any(|(check, _)| check.flawed(&outer));
            let keyed_input = undecided_whose().find_map(|(check, _)| {
                super::lists::input_key_fault(check, &outer)
                    .into_iter()
                    .next()
            });
            let said = match (&keyed_input, &told) {
                (Some(text), _) => Some(text.clone()),
                (None, Some(clause)) => Some(super::clause::text(std::slice::from_ref(clause))),
                (None, None) if rootless => undecided_whose().next().map(|(check, verdict)| {
                    super::message::prefixed(
                        &walked.item_name_dotted(walk::focus_segs(w, check)),
                        &super::message::message(check, &focus, verdict),
                    )
                }),
                (None, None) if depth > 0 => root.clone().or_else(|| unread_key.then(String::new)),
                (None, None) => Some(String::new()),
            };
            let says = undecided.is_some() && (depth > 0 || !matches!(item.how, How::Pick { .. }));
            let dead_item = |cause: Cause| Dead {
                raw: (w.end.is_none() && !w.item.value.is_object()).then(|| w.item.value.clone()),
                msg: if says { said.clone() } else { None },
                told: (says && keyed_input.is_none() && (told.is_some() || !rootless))
                    .then(|| told.clone()),
                order: w.item_segs.clone(),
                said: if !w.rest.is_empty() && w.item.value.is_object() && cause != Cause::Unusable
                {
                    walked.item_name_dotted(&w.end_segs)
                } else {
                    walked.item_name_dotted(&w.item_segs)
                },
                ..Dead::at(name.clone(), cause, w.shown(), Some(w.end_location.clone()))
            };
            if let Some(cause) = undecided {
                let keyed = undecided_whose().any(|(check, _)| {
                    check
                        .paths()
                        .into_iter()
                        .any(|path| super::key_base::of_path(path, false, &at).is_some())
                });
                let own = told.as_ref().filter(|_| keyed).map(|clause| clause.cause);
                dead.push(dead_item(own.unwrap_or(cause)));
                continue;
            }
            if causes.contains(&Cause::Value) {
                continue;
            }
            kept += 1;
            match w.end {
                Some(end) => live.push(Live {
                    at: Located {
                        value: end,
                        location: w.end_location.clone(),
                    },
                    said: walked.item_name_dotted(&w.item_segs),
                    bare: (!w.rest.is_empty() && w.item.value.is_object())
                        .then(|| walked.item_name_dotted(&w.end_segs)),
                    focus: if w.rest.is_empty() {
                        name.clone()
                    } else {
                        walked.item_name(&w.end_segs)
                    },
                    name,
                    order: w.item_segs.clone(),
                    shown: end.clone(),
                    location: w.end_location.clone(),
                    copies: Vec::new(),
                }),
                None => dead.push(dead_item(
                    if matches!(w.miss, Cause::Absent | Cause::NotAnObject) {
                        w.miss
                    } else {
                        Cause::Unusable
                    },
                )),
            }
        }
        if item.distinct {
            live = merged_live(live);
        }
        if depth > 0 {
            let first = &self.items[0].alias;
            let depends = reads_path(&item.path, first);
            let whose_reads = item.whose.iter().any(|check| reads_alias(check, first));
            for (at, entry) in dead.iter_mut().enumerate() {
                entry.shared = !depends && (at < from_list || !whose_reads);
            }
        }
        let mut cands = Cands {
            live,
            dead,
            list,
            unreadable: None,
            walked_none: walked.walked.is_empty(),
            kept,
            picked: false,
            before_pick: 0,
        };
        if let How::Pick { spot, sorted } = &item.how {
            cands.before_pick = cands.dead.len();
            let through_first = depth > 0 && reads_path(&item.path, &self.items[0].alias);
            let nothing = through_first.then(|| {
                let shown = crate::name::name(&item.path);
                Dead::at(shown, Cause::Absent, Value::Null, None)
            });
            self.pick(
                &mut cands,
                *spot,
                sorted.as_ref(),
                &outer,
                &walked,
                (through_first, nothing),
            );
            if depth > 0 {
                let first = &self.items[0].alias;
                let shared = !reads_path(&item.path, first)
                    && !item.whose.iter().any(|check| reads_alias(check, first));
                for entry in cands.dead.iter_mut().skip(from_list) {
                    entry.shared = shared;
                }
            }
        }
        cands
    }

    fn pick<'a>(
        &self,
        cands: &mut Cands<'a>,
        spot: Spot,
        sorted: Option<&Sorted>,
        outer: &Ctx<'a>,
        walked: &walk::Walked<'a>,
        (through_first, nothing): (bool, Option<Dead>),
    ) {
        if !cands.dead.is_empty() || cands.walked_none {
            if through_first && !cands.dead.is_empty() {
                cands.list.value = Value::Array(Vec::new());
                cands.list.locations.clear();
            }
            cands.live.clear();
            if cands.dead.is_empty() {
                cands.dead.extend(nothing);
            }
            return;
        }
        let mut live = std::mem::take(&mut cands.live);
        if let Some(sorted) = sorted {
            let mut failed: Vec<Dead> = Vec::new();
            let mut at = outer.clone();
            let mut checks: Vec<SortRead> = Vec::new();
            let key_name = crate::name::name(&sorted.path);
            for found in live {
                at.subject = found.at.clone();
                at.label = None;
                let read = path::read(&sorted.path, &at);
                let location = read.location.clone();
                let result = match (read.outcome.cause(), read.value) {
                    (Some(cause), _) => Err(cause),
                    (None, Some(value)) => Ok(value.clone()),
                    (None, None) => Err(Cause::Unusable),
                };
                let text = match &result {
                    Ok(value) => {
                        let want = if sorted.alphabetically {
                            "text"
                        } else {
                            "a number, a time or a date"
                        };
                        super::message::isnt(&key_name, value, want)
                    }
                    Err(cause) => {
                        let present = Check::Present(super::present::Present {
                            path: sorted.path.clone(),
                            missing: false,
                        });
                        let verdict = Verdict {
                            cause: *cause,
                            inputs: Vec::new(),
                        };
                        let mut faults = if *cause == Cause::Unusable {
                            let mut all = super::message::key_faults_of(&sorted.path, &at);
                            all.extend(super::message::blocked_of(&sorted.path, &at));
                            all
                        } else {
                            Vec::new()
                        };
                        if faults.is_empty() {
                            faults.push(super::message::message(&present, &at, &verdict));
                        }
                        faults.join(", and ")
                    }
                };
                checks.push((found, result, location, text));
            }
            let mut keys: Vec<(Live, Key, Value, Option<Location>)> = Vec::new();
            for (found, result, location, text) in checks {
                match result {
                    Ok(value) => match sort_key(&value, sorted.alphabetically) {
                        Some(key) => keys.push((found, key, value, location)),
                        None => failed.push(sort_failure(
                            &found,
                            Cause::Unusable,
                            value,
                            location,
                            &text,
                            &key_name,
                        )),
                    },
                    Err(cause) => failed.push(sort_failure(
                        &found,
                        cause,
                        Value::Null,
                        location,
                        &text,
                        &key_name,
                    )),
                }
            }
            if let Some(first) = keys.iter().map(|(_, k, _, _)| kind(k)).min() {
                let mut rest = Vec::new();
                for entry in keys {
                    if kind(&entry.1) == first {
                        rest.push(entry);
                    } else {
                        let word = match first {
                            0 => "a number",
                            1 => "a time",
                            2 => "a date",
                            _ => "text",
                        };
                        let text =
                            super::message::isnt(&crate::name::name(&sorted.path), &entry.2, word);
                        failed.push(sort_failure(
                            &entry.0,
                            Cause::Unusable,
                            entry.2,
                            entry.3,
                            &text,
                            &crate::name::name(&sorted.path),
                        ));
                    }
                }
                keys = rest;
            }
            if !failed.is_empty() {
                if through_first {
                    cands.list.value = Value::Array(Vec::new());
                    cands.list.locations.clear();
                }
                cands.dead.extend(failed);
                return;
            }
            keys.sort_by(|a, b| compare_keys(&a.1, &b.1));
            let len = keys.len();
            let at_index = match spot {
                Spot::First => (len > 0).then_some(0),
                Spot::Last => len.checked_sub(1),
                Spot::Nth(n) => usize::try_from(n).ok().filter(|n| *n < len),
                Spot::NthFromLast(n) => {
                    usize::try_from(n).ok().and_then(|n| len.checked_sub(n + 1))
                }
            };
            let Some(index) = at_index else {
                cands.dead.extend(nothing);
                return;
            };
            let tied: Vec<usize> = (0..len)
                .filter(|i| compare_keys(&keys[*i].1, &keys[index].1) == Ordering::Equal)
                .collect();
            if tied.len() > 1 {
                for i in tied {
                    let (found, _, value, location) = &keys[i];
                    cands.dead.push(Dead {
                        order: found.order.clone(),
                        said: found.said.clone(),
                        sorted: Some(sorted_stash(
                            found,
                            &crate::name::name(&sorted.path),
                            Cause::Ambiguous,
                        )),
                        ..Dead::at(
                            found.name.clone(),
                            Cause::Ambiguous,
                            value.clone(),
                            location.clone(),
                        )
                    });
                }
                if through_first {
                    cands.list.value = Value::Array(Vec::new());
                    cands.list.locations.clear();
                }
                cands.dead.sort_by(|a, b| a.order.cmp(&b.order));
                return;
            }
            let chosen = keys.swap_remove(index);
            live = vec![chosen.0];
        } else {
            let len = live.len();
            let at_index = match spot {
                Spot::First => (len > 0).then_some(0),
                Spot::Last => len.checked_sub(1),
                Spot::Nth(n) => usize::try_from(n).ok().filter(|n| *n < len),
                Spot::NthFromLast(n) => {
                    usize::try_from(n).ok().and_then(|n| len.checked_sub(n + 1))
                }
            };
            let Some(index) = at_index else {
                cands.dead.extend(nothing);
                return;
            };
            live = vec![live.swap_remove(index)];
        }
        let found = &live[0];
        cands.list = if through_first {
            Input {
                name: walked.name.clone(),
                value: Value::Array(vec![found.shown.clone()]),
                locations: vec![found.location.render()],
                part: cands.list.part.clone(),
                state: crate::path::Outcome::Found,
                null_at: None,
                worked: false,
            }
        } else {
            Input {
                name: found.name.clone(),
                value: found.shown.clone(),
                locations: vec![found.location.render()],
                part: cands.list.part.clone(),
                state: crate::path::Outcome::Found,
                null_at: None,
                worked: false,
            }
        };
        cands.picked = true;
        cands.live = live;
    }
}

fn sort_failure(
    found: &Live,
    cause: Cause,
    value: Value,
    location: Option<Location>,
    text: &str,
    key: &str,
) -> Dead {
    let said = if text.starts_with('$') {
        text.to_string()
    } else {
        super::message::prefixed(
            if found.at.value.is_object() {
                &found.focus
            } else {
                &found.name
            },
            text,
        )
    };
    Dead {
        msg: Some(said),
        order: found.order.clone(),
        said: found.said.clone(),
        sorted: Some(sorted_stash(found, key, cause)),
        ..Dead::at(found.name.clone(), cause, value, location)
    }
}

fn sorted_stash(found: &Live, key: &str, cause: Cause) -> Value {
    let outcome = match cause {
        Cause::Absent => "absent",
        Cause::Null => "null",
        Cause::Unusable => "unusable",
        Cause::NotAnObject => "not_an_object",
        _ => "usable",
    };
    json!({"key": key, "value": found.shown, "at": found.location.render(), "outcome": outcome})
}

type SortRead<'a> = (Live<'a>, Result<Value, Cause>, Option<Location>, String);

struct Sfail {
    own: bool,
    one: bool,
    said: Vec<String>,
    text: String,
    parts: Vec<String>,
    reads_last: bool,
    idx: usize,
    cause: Cause,
    inputs: Vec<Value>,
    clauses: Vec<Clause>,
}

struct Child {
    order: Vec<Seg>,
    entry: Dead,
    failed: Option<Outcome>,
    sfails: Vec<Sfail>,
    copies: Vec<String>,
    rooted: Vec<Clause>,
}

struct Outcome {
    parts: Vec<String>,
    leaf: Vec<(String, bool)>,
    said: String,
    cause: Cause,
    assertions: Vec<Value>,
    inner: Vec<Dead>,
    clauses: Vec<Clause>,
    lifted: usize,
    bare: bool,
}

struct Level {
    cause: Cause,
    dead: Vec<Dead>,
    children: Vec<Child>,
    unreadable: bool,
}

struct Collect {
    lists: Vec<(usize, Input)>,
    seen: Vec<bool>,
}

fn is_empty_list(list: &Input) -> bool {
    matches!(&list.value, Value::Array(items) if items.is_empty())
}

impl Collect {
    fn add(&mut self, depth: usize, list: Input, independent: bool) {
        self.seen[depth] = true;
        let at = self
            .lists
            .iter()
            .position(|(d, l)| *d == depth && (l.name == list.name || is_empty_list(l)));
        match at {
            None if is_empty_list(&list) && self.lists.iter().any(|(d, _)| *d == depth) => {}
            None => self.lists.push((depth, list)),
            Some(at) => {
                let found = &mut self.lists[at].1;
                if is_empty_list(&list) {
                    if is_empty_list(found)
                        && list.name.ends_with("[]")
                        && !found.name.ends_with("[]")
                    {
                        *found = list;
                    }
                } else if is_empty_list(found) {
                    *found = list;
                } else if !independent {
                    if let (Value::Array(a), Value::Array(b)) = (&mut found.value, list.value) {
                        a.extend(b);
                    }
                    found.locations.extend(list.locations);
                }
            }
        }
    }
}

impl For {
    fn level<'a>(&self, depth: usize, ctx: &Ctx<'a>, collect: &mut Collect) -> Level {
        let item = &self.items[depth];
        let cands = self.candidates(depth, ctx);
        let list_name = cands.list.name.clone();
        let independent = depth > 0 && !reads_path(&item.path, &self.items[0].alias);
        collect.add(depth, cands.list, independent);
        if let Some(cause) = cands.unreadable {
            let shared = depth > 0 && !reads_path(&item.path, &self.items[0].alias);
            let dead = if !cands.dead.is_empty() {
                cands
                    .dead
                    .into_iter()
                    .map(|entry| Dead { shared, ..entry })
                    .collect()
            } else if depth > 0 {
                let before: Vec<Step> = item
                    .path
                    .steps
                    .iter()
                    .take_while(|step| matches!(step, Step::Key(_) | Step::Index(_)))
                    .cloned()
                    .collect();
                let read = path::read(
                    &Path {
                        start: item.path.start.clone(),
                        steps: before,
                    },
                    ctx,
                );
                let shown = crate::name::name(&item.path);
                let outer = outer_ctx(ctx);
                let named_by_a_field = item.path.steps.iter().any(|step| {
                    matches!(step, Step::Ref(key) | Step::Field(key) if key.start != Start::Params)
                });
                let keyed = if !named_by_a_field {
                    Vec::new()
                } else {
                    match cause {
                        Cause::Absent => super::message::key_states_of(
                            &item.path,
                            &outer,
                            crate::path::Outcome::Absent,
                        ),
                        Cause::Null => super::message::key_states_of(
                            &item.path,
                            &outer,
                            crate::path::Outcome::Null,
                        ),
                        Cause::Unusable => super::message::key_faults_of(&item.path, &outer),
                        Cause::NotAnObject => super::lists::input_key_fault_of(
                            &crate::path::step_refs(&item.path),
                            &outer,
                        ),
                        _ => Vec::new(),
                    }
                };
                vec![Dead {
                    msg: (!keyed.is_empty()).then(|| keyed.join(", and ")),
                    shared: !reads_path(&item.path, &self.items[0].alias),
                    list: true,
                    ..Dead::at(shown, cause, Value::Null, read.location)
                }]
            } else {
                Vec::new()
            };
            return Level {
                cause,
                dead,
                children: Vec::new(),
                unreadable: true,
            };
        }
        let last = depth + 1 == self.items.len();
        let mut children = Vec::new();
        let mut passed = 0;
        for live in cands.live {
            let mut bound = ctx.clone();
            bound.aliases.insert(item.alias.clone(), live.at.clone());
            let entry = Dead {
                bare: live.bare.clone(),
                order: live.order.clone(),
                said: live.said.clone(),
                ..Dead::at(
                    live.name.clone(),
                    Cause::Satisfied,
                    live.shown.clone(),
                    Some(live.location.clone()),
                )
            };
            let into_non_object = !last && {
                let next = &self.items[depth + 1].path;
                matches!(&next.start, Start::Alias(name) if *name == item.alias)
                    && !matches!(next.steps.first(), None | Some(Step::Index(_)))
                    && !live.at.value.is_object()
                    && !(live.at.value.is_array()
                        && !matches!(self.items[depth + 1].how, How::Pick { .. })
                        && matches!(next.steps.first(), Some(Step::Key(_))))
            };
            let (outcome, sfails) = if into_non_object {
                (
                    Some(Outcome {
                        parts: Vec::new(),
                        leaf: Vec::new(),
                        said: String::new(),
                        cause: Cause::NotAnObject,
                        assertions: Vec::new(),
                        inner: Vec::new(),
                        clauses: Vec::new(),
                        lifted: 0,
                        bare: false,
                    }),
                    Vec::new(),
                )
            } else if last {
                self.try_sentences(&bound, false)
            } else {
                let mut nested = self.level(depth + 1, &bound, collect);
                if nested.cause == Cause::Satisfied
                    && nested.children.is_empty()
                    && matches!(self.items[depth + 1].how, How::Every { if_any: true })
                    && let (Some(failed), sfails) = self.try_sentences(&bound, true)
                {
                    nested = Level {
                        cause: failed.cause,
                        dead: Vec::new(),
                        children: vec![Child {
                            order: Vec::new(),
                            entry: entry.clone(),
                            failed: Some(failed),
                            sfails,
                            copies: Vec::new(),
                            rooted: Vec::new(),
                        }],
                        unreadable: false,
                    };
                }
                if nested.cause == Cause::Satisfied {
                    (None, Vec::new())
                } else {
                    let assertions = self.aggregate(&nested.children);
                    let mut leaf: Vec<(String, bool)> = Vec::new();
                    let mut parts: Vec<String> = match self.two_list_parts(&nested.children) {
                        Some(grouped) => {
                            leaf = grouped;
                            Vec::new()
                        }
                        None => nested
                            .children
                            .iter()
                            .flat_map(|c| self.child_texts(c))
                            .map(|(text, _)| text)
                            .collect(),
                    };
                    let second = self.shared_second();
                    if assertions.is_empty() {
                        parts.extend(
                            nested
                                .dead
                                .iter()
                                .filter(|d| !(second && d.shared) && d.cause != Cause::Ambiguous)
                                .map(|d| self.dead_text(d))
                                .filter(|text| !text.is_empty()),
                        );
                    }
                    let ties: Vec<&Dead> = nested
                        .dead
                        .iter()
                        .filter(|d| d.cause == Cause::Ambiguous)
                        .collect();
                    if !ties.is_empty() && (!second || self.tied_per_item()) {
                        if leaf.is_empty() {
                            parts.push(self.tie_text(&ties, depth + 1));
                        } else {
                            leaf.push((self.tie_text(&ties, depth + 1), false));
                        }
                    }
                    let lifted = self.item_roots(depth, &bound);
                    let texts: Vec<&str> = lifted.iter().map(|root| root.text.as_str()).collect();
                    let mut first_alias = self.first_alias_clauses(&nested, depth, &bound);
                    let bare = !live.at.value.is_object()
                        && first_alias
                            .iter()
                            .any(|clause| clause.cause == Cause::NotAnObject);
                    first_alias.retain(|clause| !bare || clause.cause != Cause::NotAnObject);
                    let clauses: Vec<Clause> = first_alias
                        .into_iter()
                        .chain(self.nested_clauses(
                            &nested,
                            assertions.is_empty(),
                            depth + 1,
                            &bound,
                        ))
                        .filter_map(|clause| unrooted(clause, &texts))
                        .collect();
                    let clauses: Vec<Clause> = lifted.iter().cloned().chain(clauses).collect();
                    let said = if leaf.is_empty() {
                        parts.join("; ").replace(FREE, "")
                    } else {
                        leaf.iter()
                            .map(|(text, _)| text.as_str())
                            .collect::<Vec<_>>()
                            .join("; ")
                    };
                    (
                        Some(Outcome {
                            parts,
                            leaf,
                            said,
                            cause: nested.cause,
                            assertions,
                            inner: nested.dead,
                            clauses,
                            lifted: lifted.len(),
                            bare,
                        }),
                        Vec::new(),
                    )
                }
            };
            let rooted = if outcome.is_none() && !last {
                self.item_roots(depth, &bound)
            } else {
                Vec::new()
            };
            if outcome.is_none() {
                passed += 1;
            }
            children.push(Child {
                order: live.order,
                entry,
                failed: outcome,
                sfails,
                copies: live.copies,
                rooted,
            });
        }
        let _ = list_name;
        let mut causes: Vec<Cause> = cands.dead.iter().map(|d| d.cause).collect();
        causes.extend(
            children
                .iter()
                .filter_map(|c| c.failed.as_ref().map(|o| o.cause)),
        );
        let every = matches!(item.how, How::Every { .. } | How::Pick { .. });
        let if_any = matches!(
            item.how,
            How::Every { if_any: true } | How::Some { if_any: true }
        );
        let worst = Cause::worst(causes.iter().copied());
        let cause = if cands.walked_none && !matches!(item.how, How::Pick { .. }) {
            cands.dead.first().map_or(Cause::Value, |d| d.cause)
        } else if matches!(item.how, How::Pick { .. }) {
            match (cands.picked, worst) {
                (_, Some(cause)) => cause,
                (true, None) => Cause::Satisfied,
                (false, None) => Cause::Absent,
            }
        } else if every {
            match worst {
                Some(cause) => cause,
                None if if_any || cands.kept > 0 => Cause::Satisfied,
                None => Cause::Value,
            }
        } else if passed > 0 {
            Cause::Satisfied
        } else {
            worst.unwrap_or(Cause::Value)
        };
        let dead = cands.dead;
        Level {
            cause,
            dead,
            children,
            unreadable: false,
        }
    }

    fn alias_names(&self) -> Vec<&str> {
        self.items.iter().map(|i| i.alias.as_str()).collect()
    }

    fn last_alias(&self) -> &str {
        self.items
            .last()
            .map(|i| i.alias.as_str())
            .unwrap_or_default()
    }

    fn try_sentences(&self, ctx: &Ctx, skip_last: bool) -> (Option<Outcome>, Vec<Sfail>) {
        let alias = self.last_alias();
        let mut sfails = Vec::new();
        for (idx, sentence) in self.sentences.iter().enumerate() {
            if skip_last && sentence.reads_last {
                continue;
            }
            let ran = run_full(&sentence.check, ctx);
            let verdict = ran.verdict.clone();
            if !verdict.passed() {
                let (_, clauses) = self.said_clauses(sentence, &ran, ctx);
                let own = sentence.reads_last && !reads_other(&sentence.check, alias);
                let walks = matches!(sentence.check, Check::Walk(_));
                let mut verdict = verdict;
                let mut text = match (&ran.message, walks) {
                    (Some(said), true) => said.clone(),
                    _ => super::message::message(&sentence.check, ctx, &verdict),
                };
                if !walks
                    && let Some((key, base, cause)) = sentence
                        .check
                        .paths()
                        .into_iter()
                        .find_map(|path| super::key_base::alias_base(path, ctx))
                    && text == key
                {
                    text = format!("{key}; {base}");
                    verdict.cause = Cause::worst([verdict.cause, cause]).unwrap_or(cause);
                    for input in &mut verdict.inputs {
                        if let Some(state) = super::key_base::worse_state(input.state, cause)
                            && input.state != crate::path::Outcome::Found
                        {
                            input.state = state;
                        }
                    }
                }
                let parts = match ran.parts {
                    Some(parts) if walks && !parts.is_empty() => {
                        let mut once: Vec<String> = Vec::new();
                        for part in super::clause::lines(&parts) {
                            push_new(&mut once, part);
                        }
                        once
                    }
                    _ => vec![text.clone()],
                };
                let inputs: Vec<Value> =
                    reading_order(&sentence.check, &verdict.inputs, &self.alias_names())
                        .iter()
                        .filter(|input| !self.keyed_alias_input(&sentence.check, input))
                        .map(|input| {
                            crate::parts::with_outcome(
                                input,
                                crate::checks::input_unfit(&[&sentence.check], input, ctx),
                            )
                        })
                        .collect();
                sfails.push(Sfail {
                    own,
                    one: inputs.len() == 1 && !keyed_by_alias(&sentence.check, alias),
                    said: Vec::new(),
                    text,
                    parts,
                    reads_last: sentence.reads_last,
                    idx,
                    cause: verdict.cause,
                    inputs,
                    clauses,
                });
            }
        }
        let Some(cause) = Cause::worst(sfails.iter().map(|f| f.cause)) else {
            return (None, sfails);
        };
        let all_own = sfails.iter().all(|f| f.own);
        let two = self.items.len() > 1 && sfails.iter().any(|f| f.reads_last);
        let mut texts: Vec<String> = Vec::new();
        for f in &mut sfails {
            let lines: &[String] = if two {
                std::slice::from_ref(&f.text)
            } else {
                &f.parts
            };
            let mut own: Vec<String> = Vec::new();
            for line in lines {
                let text = if all_own {
                    own_text(line, alias, f.one)
                } else {
                    line.clone()
                };
                if !text.is_empty() {
                    push_new(&mut own, text);
                }
            }
            f.said = own;
        }
        let assertions = sfails
            .iter()
            .map(|f| {
                json!({
                    "assertion": self.sentences[f.idx].text,
                    "cause": f.cause.name(),
                    "inputs": f.inputs,
                    "ergo/texts": f.said,
                })
            })
            .collect();
        let mut clauses: Vec<String> = Vec::new();
        for f in &sfails {
            let lines: &[String] = if two {
                std::slice::from_ref(&f.text)
            } else {
                &f.parts
            };
            let prior = clauses.clone();
            for line in lines {
                let text = if all_own {
                    own_text(line, alias, f.one)
                } else {
                    line.clone()
                };
                let mut seen = prior.clone();
                let text = if two {
                    text
                } else {
                    super::message::unsaid(&text, &mut seen)
                };
                for clause in seen.into_iter().skip(prior.len()) {
                    push_new(&mut clauses, clause);
                }
                if !text.is_empty() && !texts.contains(&text) {
                    texts.push(text);
                }
            }
        }
        let groups = if two {
            vec![vec![first_marked(&texts).join(", and ")]]
        } else {
            group_by_lead(&texts)
        };
        let outcome = |leaf: Vec<(String, bool)>, said: String| Outcome {
            parts: Vec::new(),
            leaf,
            said,
            cause,
            assertions,
            inner: Vec::new(),
            clauses: Vec::new(),
            lifted: 0,
            bare: false,
        };
        if groups.len() > 1 {
            let leaf = groups
                .iter()
                .map(|group| (group_text(group), lead_of(&group[0]).is_empty()))
                .collect();
            return (Some(outcome(leaf, String::new())), sfails);
        }
        let said = groups.first().map(|g| group_text(g)).unwrap_or_default();
        (Some(outcome(Vec::new(), said)), sfails)
    }

    fn aggregate(&self, children: &[Child]) -> Vec<Value> {
        let mut out = Vec::new();
        for (idx, sentence) in self.sentences.iter().enumerate() {
            let mut found: Vec<(&Child, &Sfail)> = Vec::new();
            for child in children {
                if let Some(f) = child.sfails.iter().find(|f| f.idx == idx) {
                    found.push((child, f));
                }
            }
            let Some(cause) = Cause::worst(found.iter().map(|(_, f)| f.cause)) else {
                continue;
            };
            if sentence.reads_last {
                let items: Vec<Value> = found
                    .iter()
                    .map(|(child, f)| {
                        let mut locations: Vec<String> =
                            child.entry.location.iter().map(Location::render).collect();
                        locations.extend(child.copies.iter().cloned());
                        json!({
                            "item": child.entry.name,
                            "cause": f.cause.name(),
                            "inputs": f.inputs,
                            "ergo/texts": f.said,
                            "ergo/said": child.entry.shown(),
                            "value": child.entry.value,
                            "locations": locations,
                        })
                    })
                    .collect();
                out.push(json!({
                    "assertion": sentence.text,
                    "cause": cause.name(),
                    "items": items,
                }));
            } else {
                out.push(json!({
                    "assertion": sentence.text,
                    "cause": cause.name(),
                    "inputs": found[0].1.inputs,
                    "ergo/texts": found[0].1.said,
                }));
            }
        }
        out
    }

    fn list_entry(&self, path: &Path, if_any: bool, ctx: &Ctx) -> Input {
        let outer = outer_ctx(ctx);
        let walked = walk::walk(
            path,
            &outer,
            Options {
                if_any,
                empty_adds_nothing: false,
            },
        );
        Input {
            name: walked.name.clone(),
            value: Value::Array(walked.items.iter().map(WalkItem::shown).collect()),
            locations: walked
                .items
                .iter()
                .map(|w| w.end_location.render())
                .collect(),
            part: path::part_tag(path, &outer).map(|(name, id)| Part { name, id }),
            state: crate::path::Outcome::Found,
            null_at: None,
            worked: false,
        }
    }

    fn subject_inputs(&self, ctx: &Ctx) -> Vec<Input> {
        let hidden: Vec<&str> = self.items.iter().map(|i| i.alias.as_str()).collect();
        let hides = |path: &Path| matches!(&path.start, Start::Alias(name) if hidden.contains(&name.as_str()));
        let mut inputs = Vec::new();
        let mut paths: Vec<&Path> = Vec::new();
        let mut in_walk: Vec<*const Path> = Vec::new();
        let mut in_whose: Vec<*const Path> = Vec::new();
        for sentence in &self.sentences {
            let (mut found, mut whose) = match &sentence.check {
                Check::Tally(tally) => tally_paths(tally, &hidden),
                other => (all_paths(other), Vec::new()),
            };
            let named = nested_checks(&sentence.check)
                .into_iter()
                .flat_map(super::lists::named_refs);
            if matches!(sentence.check, Check::Tally(_)) {
                whose.extend(named);
            } else {
                found.extend(named);
            }
            if matches!(sentence.check, Check::Walk(_)) {
                in_walk.extend(found.iter().map(|path| std::ptr::from_ref(*path)));
            }
            in_walk.extend(whose.iter().map(|path| std::ptr::from_ref(*path)));
            in_whose.extend(whose.iter().map(|path| std::ptr::from_ref(*path)));
            paths.extend(found);
            paths.extend(whose);
        }
        for item in &self.items {
            for check in &item.whose {
                let found: Vec<&Path> = all_paths(check)
                    .into_iter()
                    .filter(|path| hides(path))
                    .collect();
                in_walk.extend(found.iter().map(|path| std::ptr::from_ref(*path)));
                paths.extend(found);
            }
        }
        let walked: Vec<(&Path, bool)> = self
            .sentences
            .iter()
            .flat_map(|sentence| walked_paths(&sentence.check))
            .collect();
        let listed: Vec<*const Path> = self
            .sentences
            .iter()
            .flat_map(|sentence| match &sentence.check {
                Check::Walk(walk) => std::iter::once(&*walk.check)
                    .chain(walk.whose.iter())
                    .collect::<Vec<_>>(),
                other => nested_checks(other),
            })
            .filter_map(super::lists::walked_right)
            .map(std::ptr::from_ref)
            .collect();
        let counted: Vec<*const Path> = self
            .sentences
            .iter()
            .flat_map(|sentence| nested_checks(&sentence.check).into_iter().skip(1))
            .flat_map(|check| match check {
                Check::Tally(tally) => tally.counted_paths(),
                _ => Vec::new(),
            })
            .map(std::ptr::from_ref)
            .collect();
        for path in paths {
            let own = walked.iter().find(|(p, _)| std::ptr::eq(*p, path));
            if matches!(path.start, Start::Params)
                && own.is_none()
                && in_walk.contains(&std::ptr::from_ref(path))
                && !walk::has_root_field(path)
            {
                continue;
            }
            match own {
                Some((_, if_any))
                    if !hides(path) && walk::cut_at(path, &hidden, false).is_none() =>
                {
                    inputs.push(self.list_entry(path, *if_any, ctx));
                    inputs.extend(super::field_inputs(path, ctx));
                }
                _ if in_whose.contains(&std::ptr::from_ref(path)) => {
                    let outer = outer_ctx(ctx);
                    if counted.contains(&std::ptr::from_ref(path))
                        && !hides(path)
                        && super::lists::walked(path, &outer).is_some()
                    {
                        inputs.push(super::tally::counted_list(path, &outer));
                        continue;
                    }
                    match listed_walk(path, &listed, &outer, &hidden) {
                        Some(input) => inputs.push(input),
                        None => inputs.extend(walk::path_inputs(path, &outer, &hidden, true)),
                    }
                }
                _ => {
                    let on_items = in_walk.contains(&std::ptr::from_ref(path));
                    let at = if matches!(path.start, Start::Part(_)) {
                        outer_ctx(ctx)
                    } else {
                        ctx.clone()
                    };
                    match listed_walk(path, &listed, &at, &hidden) {
                        Some(input) => inputs.push(input),
                        None => inputs.extend(walk::path_inputs(path, &at, &hidden, on_items)),
                    }
                }
            }
        }
        for sentence in &self.sentences {
            if let Check::Tally(tally) = &sentence.check {
                inputs.extend(tally.unaliased_entries(ctx, &hidden));
            }
            inputs.extend(super::lists::ref_inputs(&sentence.check, ctx, true));
            for inner in nested_checks(&sentence.check).into_iter().skip(1) {
                inputs.extend(super::lists::ref_inputs(inner, ctx, false));
            }
        }
        let whose: Vec<&Check> = self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .collect();
        inputs.extend(walk::listed_outside_inputs(&whose, &outer_ctx(ctx)));
        inputs
    }

    /// What the sentence at `idx` says about a root it reads outside the
    /// items, when that root can't be read or used.
    pub fn sentence_roots(&self, idx: usize, ctx: &Ctx) -> Vec<String> {
        let Some(sentence) = self.sentences.get(idx) else {
            return Vec::new();
        };
        let outer = outer_ctx(ctx);
        let mut texts: Vec<String> = Vec::new();
        let forms = root_forms(&sentence.check);
        if let Some((_, found)) = sentence_root_flaw(&forms, &outer) {
            for text in found {
                for piece in text.split("; ") {
                    push_new(&mut texts, piece.to_string());
                }
            }
        }
        let mut checks: Vec<&Check> = nested_checks(&sentence.check);
        if let Check::Walk(walk) = &sentence.check {
            checks.push(&walk.check);
        }
        for check in checks {
            if let Some((_, text)) = super::message::root_flaw(&[check], &outer) {
                for piece in text.split("; ") {
                    push_new(&mut texts, piece.to_string());
                }
            }
        }
        texts
    }

    /// What the `whose` clauses of the `for` line's own items say about a
    /// root they read outside the items, when it can't be read or used.
    pub fn whose_roots(&self, ctx: &Ctx) -> Vec<String> {
        let outer = outer_ctx(ctx);
        let mut texts: Vec<String> = Vec::new();
        for check in self.items.iter().flat_map(|item| item.whose.iter()) {
            let mut found: Vec<String> = Vec::new();
            if let Some((_, text)) = super::message::root_flaw(&[check], &outer) {
                found.push(text);
            }
            if let Some((_, more)) = sentence_root_flaw(&root_forms(check), &outer) {
                found.extend(more);
            }
            found.extend(super::message::walked_roots_ahead(
                None,
                &[check],
                &outer,
                &[],
            ));
            for text in found {
                for piece in text.split("; ") {
                    push_new(&mut texts, piece.to_string());
                }
            }
        }
        texts
    }

    pub fn run(&self, ctx: &Ctx) -> Run {
        let mut run = self.run_items(ctx);
        let clauses: Vec<Clause> = self
            .root_clauses(ctx)
            .into_iter()
            .chain(run.items.iter().cloned())
            .collect();
        let shown = super::clause::shown(&clauses);
        run.verdict.cause =
            Cause::worst(tree_causes(&clauses).into_iter().chain([run.verdict.cause]))
                .unwrap_or(Cause::Satisfied);
        if run.verdict.cause != Cause::Satisfied {
            self.key_inputs(&mut run, ctx);
            run.message = (!shown.is_empty()).then(|| super::clause::text(&shown));
        }
        #[cfg(test)]
        RAN.with(|ran| {
            ran.borrow_mut().push((
                run.verdict.cause,
                run.message.clone(),
                self.root_clauses(ctx),
                run.items.clone(),
            ));
        });
        run
    }

    /// The first list's `named by` key that can't be read, when there is one.
    pub fn first_key(&self, ctx: &Ctx) -> Option<super::key_base::ForKey> {
        let first = self.items.first()?;
        let if_any = matches!(
            first.how,
            How::Every { if_any: true } | How::Some { if_any: true }
        );
        super::key_base::for_list(&first.path, if_any, ctx)
    }

    pub fn root_clauses(&self, ctx: &Ctx) -> Vec<Clause> {
        let outer = outer_ctx(ctx);
        let whose: Vec<&Check> = self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .collect();
        let mut clauses = super::message::listed_root_clauses(&whose, &outer, true);
        clauses.extend(super::message::walked_root_clauses(&whose, &outer));
        for key in self.items.iter().flat_map(|item| sort_keys(&item.how)) {
            if let Some((outcome, text, input)) = super::key_base::key_flaw(key, &outer) {
                let cause = outcome.cause().unwrap_or(Cause::Unusable);
                clauses.push(Clause::root(&input.name, cause, text));
            }
        }
        if let Some(first) = self.items.first()
            && matches!(first.path.start, Start::Subject | Start::Own)
            && let Some(at) = first
                .path
                .steps
                .iter()
                .position(|step| matches!(step, Step::Field(_)))
            && let Step::Field(key) = &first.path.steps[at]
            && path::read(
                &Path {
                    start: first.path.start.clone(),
                    steps: first.path.steps[..at].to_vec(),
                },
                &outer,
            )
            .outcome
                == path::Outcome::Found
            && let Some((outcome, text, input)) = super::key_base::key_flaw(key, &outer)
        {
            let cause = outcome.cause().unwrap_or(Cause::Unusable);
            clauses.push(Clause::root(&input.name, cause, text));
        }
        if let Some(found) = self.first_key(ctx) {
            let cause = found.key.state.cause().unwrap_or(Cause::Unusable);
            clauses.push(Clause::root(&found.key.name, cause, found.key_text));
            if let Some((text, cause, input)) = found.base {
                clauses.push(Clause::list(&input.name, cause, text));
            }
        }
        let mut clauses: Vec<Clause> = clauses
            .into_iter()
            .map(|clause| clause.in_group(self.sentences.len()))
            .collect();
        for (at, sentence) in self.sentences.iter().enumerate() {
            let said = sentence_roots_listed(&sentence.check, &outer);
            let group = self.sentence_group(at);
            clauses.extend(said.into_iter().map(|clause| clause.in_group(group)));
        }
        let mut once: Vec<Clause> = Vec::new();
        for clause in clauses {
            let line = super::clause::text(std::slice::from_ref(&clause));
            if !once
                .iter()
                .any(|seen| super::clause::text(std::slice::from_ref(seen)) == line)
            {
                once.push(clause);
            }
        }
        listed_roots(once)
    }

    #[cfg_attr(not(test), expect(dead_code))]
    pub fn sentence_clauses(&self, idx: usize, ctx: &Ctx) -> (Cause, Vec<Clause>) {
        let Some(sentence) = self.sentences.get(idx) else {
            return (Cause::Satisfied, Vec::new());
        };
        self.said_clauses(sentence, &run_full(&sentence.check, ctx), ctx)
    }

    fn said_clauses(
        &self,
        sentence: &Sentence,
        ran: &super::Ran,
        ctx: &Ctx,
    ) -> (Cause, Vec<Clause>) {
        use super::message::Piece;
        let mut cause = ran.verdict.cause;
        if ran.verdict.passed() {
            return (cause, Vec::new());
        }
        if super::message::params_that_arent_an_object(&sentence.check, ctx).is_some() {
            return (Cause::Unusable, Vec::new());
        }
        let walks = matches!(sentence.check, Check::Walk(_));
        let said = match &ran.parts {
            Some(parts) if walks && !parts.is_empty() => vec![vec![Piece::Counted(parts.clone())]],
            _ => super::message::row_said(&sentence.check, ctx, &ran.verdict),
        };
        let mut line = ctx.clone();
        for item in &self.items {
            line.aliases.remove(&item.alias);
        }
        let mut seen: Vec<Clause> = sentence_roots_said(&sentence.check, &outer_ctx(&line))
            .into_iter()
            .flat_map(|root| [Clause::said(Cause::Value, root.text.clone()), root])
            .collect();
        let roots: Vec<String> = seen.iter().map(|root| root.text.clone()).collect();
        for group in &said {
            if roots.contains(&super::message::pieces_text(group)) {
                for piece in group {
                    if let Piece::Said(text) = piece {
                        seen.push(Clause::said(Cause::Value, text.clone()));
                    }
                }
            }
        }
        let whole = !self
            .items
            .iter()
            .any(|item| reads_alias(&sentence.check, &item.alias));
        let mut clauses: Vec<Clause> = Vec::new();
        for group in super::message::unsaid_clauses(&said, &mut seen) {
            let mut texts: Vec<String> = Vec::new();
            for piece in group {
                match piece {
                    Piece::Said(text) if whole => texts.push(text),
                    Piece::Said(text) => push_new(&mut clauses, Clause::said(cause, text)),
                    Piece::Counted(counted) => {
                        for clause in counted {
                            push_new(&mut clauses, clause);
                        }
                    }
                }
            }
            if !texts.is_empty() {
                push_new(&mut clauses, Clause::said(cause, texts.join(", and ")));
            }
        }
        let said_texts: Vec<&str> = seen.iter().map(|clause| clause.text.as_str()).collect();
        let again: Vec<String> = key_paths_said(&sentence.check, ctx)
            .into_iter()
            .filter(|(key, _)| said_texts.contains(&key.as_str()))
            .map(|(_, path)| path)
            .collect();
        clauses.retain(|clause| {
            clause.kind == super::clause::Kind::Item || !again.contains(&clause.text)
        });
        if !walks
            && let Some((key, base, worse)) = sentence
                .check
                .paths()
                .into_iter()
                .find_map(|path| super::key_base::alias_base(path, ctx))
            && super::message::said_text(&said) == key
        {
            cause = Cause::worst([cause, worse]).unwrap_or(worse);
            clauses.push(Clause::said(cause, base));
        }
        (cause, clauses)
    }

    fn key_inputs(&self, run: &mut Run, ctx: &Ctx) {
        let keys = self
            .first_key(ctx)
            .map(|found| found.key)
            .into_iter()
            .chain(self.whose_keys(ctx).into_iter().map(|(_, _, input)| input));
        for input in keys {
            if !run
                .verdict
                .inputs
                .iter()
                .any(|seen| seen.name == input.name)
            {
                run.verdict.inputs.push(input);
            }
        }
    }

    /// Each `$params` or `$input` key the lines' `whose` checks read that
    /// can't be read, once, with its cause, what is said and its read.
    pub fn whose_keys(&self, ctx: &Ctx) -> Vec<(Cause, String, Input)> {
        let outer = outer_ctx(ctx);
        let mut keys: Vec<(Cause, String, Input)> = Vec::new();
        for key in self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .flat_map(|check| super::key_base::unreadable_key_reads(check, &outer))
        {
            if !keys.iter().any(|(_, said, _)| *said == key.1) {
                keys.push(key);
            }
        }
        keys
    }

    fn reads_a_flawed_root(&self, outer: &Ctx) -> bool {
        let forms: Vec<(Check, bool)> = self
            .sentences
            .iter()
            .flat_map(|s| root_forms(&s.check))
            .collect();
        let nested: Vec<&Check> = self
            .sentences
            .iter()
            .flat_map(|s| nested_whose(&s.check, false))
            .collect();
        let whose: Vec<&Check> = self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .collect();
        sentence_root_flaw(&forms, outer).is_some()
            || super::message::root_flaw_ordered(&nested, outer, &[], &[]).is_some()
            || super::message::root_flaw_ordered(&whose, outer, &[], &[]).is_some()
    }

    fn none_kept(&self, ctx: &Ctx) -> bool {
        if !matches!(
            self.items[0].how,
            How::Every { if_any: true } | How::Some { if_any: true }
        ) {
            return false;
        }
        let cands = self.candidates(0, ctx);
        cands.unreadable.is_none() && cands.dead.is_empty() && cands.live.is_empty()
    }

    fn after_first(&self) -> Option<For> {
        let [first, second] = self.items.as_slice() else {
            return None;
        };
        if reads_path(&second.path, &first.alias)
            || second
                .whose
                .iter()
                .any(|check| reads_alias(check, &first.alias))
        {
            return None;
        }
        let sentences: Vec<Sentence> = self
            .sentences
            .iter()
            .filter(|sentence| !reads_alias(&sentence.check, &first.alias))
            .cloned()
            .collect();
        (!sentences.is_empty()).then(|| For {
            items: vec![second.clone()],
            sentences,
        })
    }

    fn flawed(&self, ctx: &Ctx) -> bool {
        let outer = outer_ctx(ctx);
        self.items
            .iter()
            .flat_map(|item| item.whose.iter())
            .chain(self.sentences.iter().map(|s| &s.check))
            .any(|check| check.flawed(&outer))
            && !self.reads_a_flawed_root(&outer)
    }

    fn run_items(&self, ctx: &Ctx) -> Run {
        let mut run = self.run_items_of(ctx);
        if run.verdict.cause != Cause::NotAnObject && !self.flawed(ctx) && self.none_kept(ctx) {
            if let Some(rest) = self.after_first() {
                let mut reduced = rest.run_items(ctx);
                reduced.verdict.inputs = run.verdict.inputs;
                return reduced;
            }
            if run.verdict.cause == Cause::Satisfied {
                let lines = root_lines(&self.root_clauses(ctx));
                let roots: Vec<&str> = lines.iter().map(String::as_str).collect();
                run.items = self
                    .free_clauses(ctx)
                    .into_iter()
                    .filter_map(|clause| unrooted(clause, &roots))
                    .collect();
            }
        }
        run
    }

    fn walked_root_clauses(&self, ctx: &Ctx) -> Vec<Clause> {
        let outer = outer_ctx(ctx);
        let mut checks: Vec<&Check> = self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .collect();
        for sentence in &self.sentences {
            checks.push(&sentence.check);
            checks.extend(nested_whose(&sentence.check, false));
            if let Check::Walk(walk) = &sentence.check {
                checks.push(&walk.check);
            }
        }
        let mut roots: Vec<Clause> = Vec::new();
        for check in checks {
            for path in super::lists::right_paths(check) {
                if !super::message::reads_from_a_root(path) {
                    continue;
                }
                if let Some((cause, text)) = super::lists::walked_root_fault(check, path, &outer)
                    && cause != Cause::Value
                    && !roots.iter().any(|root| root.text == text)
                {
                    roots.push(Clause::root(&crate::name::name(path), cause, text));
                }
            }
        }
        roots
    }

    fn run_items_of(&self, ctx: &Ctx) -> Run {
        let first = &self.items[0];
        let whole_subject = !ctx.subject.value.is_object()
            && (!ctx.subject.value.is_array() || matches!(first.how, How::Pick { .. }))
            && first.path.steps.is_empty()
            && match &first.path.start {
                Start::Subject => true,
                Start::Part(part) => part.base == Start::Subject && part.steps.is_empty(),
                _ => false,
            };
        if whole_subject || walk::path_needs_an_object_subject(&first.path, ctx) {
            return Run {
                verdict: Verdict {
                    cause: Cause::NotAnObject,
                    inputs: Vec::new(),
                },
                failed_items: Vec::new(),
                message: None,
                items: Vec::new(),
            };
        }
        let mut collect = Collect {
            lists: Vec::new(),
            seen: vec![false; self.items.len()],
        };
        let level = self.level(0, ctx, &mut collect);
        let mut inputs: Vec<Input> = collect.lists.into_iter().map(|(_, list)| list).collect();
        for (depth, (item, seen)) in self.items.iter().zip(&collect.seen).enumerate() {
            if *seen {
                continue;
            }
            if depth > 0 && !reads_path(&item.path, &first.alias) {
                inputs.push(self.candidates(depth, ctx).list);
            } else {
                inputs.push(empty_list(crate::name::name(&item.path)));
            }
        }
        for item in &self.items {
            for step in &item.path.steps {
                if let Step::Field(field) = step
                    && !matches!(field.start, Start::Alias(_))
                {
                    inputs.extend(super::field_inputs(
                        &Path {
                            start: item.path.start.clone(),
                            steps: vec![step.clone()],
                        },
                        ctx,
                    ));
                }
            }
        }
        inputs.extend(self.subject_inputs(ctx));
        inputs.sort_by(|a, b| {
            a.name
                .cmp(&b.name)
                .then_with(|| a.locations.cmp(&b.locations))
        });
        inputs.dedup();
        let outer = outer_ctx(ctx);
        let flawed = self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .chain(self.sentences.iter().map(|s| &s.check))
            .any(|check| check.flawed(&outer))
            && !self.reads_a_flawed_root(&outer);
        let second = if flawed || !level.children.is_empty() {
            None
        } else {
            self.second_pick_failure(ctx)
        };
        let cause = if flawed {
            Cause::Unusable
        } else {
            second.as_ref().map_or(level.cause, |(cause, _)| *cause)
        };
        let unread = |child: &Child| child.failed.is_none() && !child.rooted.is_empty();
        let rooted = level.children.iter().any(unread)
            && (!matches!(first.how, How::Some { .. })
                || level
                    .children
                    .iter()
                    .all(|child| child.failed.is_some() || unread(child)));
        let (free, mut items) =
            if second.is_some() || flawed || cause == Cause::Satisfied && !rooted {
                (Vec::new(), Vec::new())
            } else {
                let roots = root_lines(&self.root_clauses(ctx));
                let texts: Vec<&str> = roots.iter().map(String::as_str).collect();
                (
                    self.free_clauses(ctx)
                        .into_iter()
                        .filter_map(|clause| unrooted(clause, &texts))
                        .collect(),
                    self.level_clauses(&level, &self.root_clauses(ctx), ctx),
                )
            };
        let failed = if let Some((_, listed)) = second {
            listed
        } else if cause == Cause::Satisfied || flawed {
            Vec::new()
        } else {
            self.failed_items(level)
        };
        let walked = self.walked_root_clauses(ctx);
        if flawed && !walked.is_empty() {
            items.extend(walked);
        } else if (flawed || failed.is_empty())
            && items.is_empty()
            && !matches!(cause, Cause::Satisfied | Cause::NotAnObject)
        {
            let listed: Vec<super::message::ForItem> = self
                .items
                .iter()
                .map(|item| super::message::ForItem {
                    path: &item.path,
                    whose: &item.whose,
                    picks: matches!(item.how, How::Pick { .. }),
                })
                .collect();
            let roots = super::clause::lines(&self.root_clauses(ctx));
            items.extend(
                super::message::for_empty(&listed, &outer, cause)
                    .into_iter()
                    .filter(|text| !roots.contains(text))
                    .map(|text| Clause::list(&text.clone(), cause, text).in_group(self.sentences.len())),
            );
        }
        Run {
            verdict: Verdict { cause, inputs },
            failed_items: failed,
            message: None,
            items: free.into_iter().chain(items).collect(),
        }
    }

    fn second_pick_failure(&self, ctx: &Ctx) -> Option<(Cause, Vec<Value>)> {
        let [first, second] = self.items.as_slice() else {
            return None;
        };
        let depends = reads_path(&second.path, &first.alias)
            || second
                .whose
                .iter()
                .any(|check| reads_alias(check, &first.alias));
        if !matches!(second.how, How::Pick { .. })
            || matches!(first.how, How::Pick { .. })
            || depends
        {
            return None;
        }
        let cands = self.candidates(1, ctx);
        if let Some(cause) = cands.unreadable {
            return Some((cause, Vec::new()));
        }
        if cands.picked {
            return None;
        }
        let Some(cause) = Cause::worst(cands.dead.iter().map(|d| d.cause)) else {
            return Some((Cause::Absent, Vec::new()));
        };
        let mut dead: Vec<&Dead> = cands.dead.iter().skip(cands.before_pick).collect();
        dead.sort_by(|a, b| a.order.cmp(&b.order));
        let ties: Vec<&Dead> = dead
            .iter()
            .copied()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        let tie = ties.first().map(|_| self.tie_text(&ties, 1));
        Some((
            cause,
            dead.into_iter()
                .map(|d| {
                    let mut out = self.dead_json(d);
                    if let (Cause::Ambiguous, Some(text)) = (d.cause, &tie) {
                        out["ergo/text"] = json!(text);
                    }
                    out
                })
                .collect(),
        ))
    }

    fn strip(&self, text: &str) -> String {
        text.to_string()
    }

    fn tie_text(&self, ties: &[&Dead], from: usize) -> String {
        let names: Vec<&str> = ties.iter().map(|d| d.name.as_str()).collect();
        let split: Vec<Option<(&str, &str)>> = names
            .iter()
            .map(|n| {
                n.strip_prefix("item ")
                    .and_then(|rest| rest.split_once(" of "))
            })
            .collect();
        let listed = match split.first().copied().flatten() {
            Some((_, list))
                if split
                    .iter()
                    .all(|part| part.is_some_and(|(_, other)| other == list)) =>
            {
                let numbers: Vec<&str> = split.iter().flatten().map(|(n, _)| *n).collect();
                format!("item {} of {list}", numbers.join(" and item "))
            }
            _ => names.join(" and "),
        };
        let by = self
            .items
            .iter()
            .skip(from)
            .find_map(|item| match &item.how {
                How::Pick {
                    sorted: Some(sorted),
                    ..
                } => Some(crate::name::name(&sorted.path)),
                _ => None,
            });
        match by {
            Some(by) => format!("{listed} tie on {by}"),
            None => format!("{listed} tie"),
        }
    }

    fn dead_text(&self, dead: &Dead) -> String {
        if let Some(text) = &dead.msg {
            return text.clone();
        }
        let kind = if dead.wants_object {
            "an object"
        } else if matches!(dead.value, Value::Object(_)) {
            "a list"
        } else {
            "a list or an object"
        };
        let name = dead.shown().to_string();
        let value = match (&dead.raw, dead.cause) {
            (Some(raw), Cause::NotAnObject) => raw,
            _ => &dead.value,
        };
        super::message::stated(&name, dead.cause, value, kind)
    }

    fn keyed_alias_input(&self, check: &Check, input: &Input) -> bool {
        let mut paths = all_paths(check);
        if let Check::Tally(tally) = check {
            paths.extend(tally_paths(tally, &[]).1);
        }
        paths.into_iter().any(|path| {
            matches!(&path.start, Start::Alias(alias) if self.items.iter().any(|item| &item.alias == alias))
                && walk::has_root_field(path)
                && crate::name::name(path) == input.name
        })
    }

    fn two_list_parts(&self, children: &[Child]) -> Option<Vec<(String, bool)>> {
        let failing: Vec<&Child> = children.iter().filter(|c| c.failed.is_some()).collect();
        if self.items.len() != 2
            || failing.is_empty()
            || failing.iter().any(|c| c.sfails.is_empty())
        {
            return None;
        }
        let mut texts: Vec<String> = Vec::new();
        let mut two = false;
        for (idx, sentence) in self.sentences.iter().enumerate() {
            for child in &failing {
                let Some(fail) = child.sfails.iter().find(|f| f.idx == idx) else {
                    continue;
                };
                let own = child.sfails.iter().all(|f| f.own);
                let name = self.strip(child.entry.shown());
                for line in &fail.parts {
                    let said = if own {
                        own_text(line, self.last_alias(), fail.one)
                    } else {
                        line.clone()
                    };
                    let text = if sentence.reads_last {
                        two = true;
                        if said.starts_with(MARK) {
                            under(&name, &said)
                        } else {
                            super::message::prefixed(&name, &said)
                        }
                    } else {
                        unmarked(&said)
                    };
                    if !text.is_empty() && !texts.contains(&text) {
                        texts.push(text);
                    }
                }
                if !sentence.reads_last {
                    break;
                }
            }
        }
        if texts.is_empty() {
            return Some(Vec::new());
        }
        let leads: Vec<String> = texts.iter().map(|text| lead_of(text)).collect();
        if texts.len() < 2 || leads.iter().all(String::is_empty) {
            return Some(vec![(group_text(&texts), false)]);
        }
        if !two {
            let groups = group_by_lead(&texts);
            let several = groups.len() > 1;
            return Some(
                groups
                    .iter()
                    .map(|group| (group_text(group), several && lead_of(&group[0]).is_empty()))
                    .collect(),
            );
        }
        let mut numbered: Vec<(u64, usize, String)> = Vec::new();
        for (at, lead) in leads.iter().enumerate() {
            if lead.is_empty() || numbered.iter().any(|(_, _, other)| other == lead) {
                continue;
            }
            let number = lead
                .strip_prefix("item ")
                .and_then(|rest| rest.split(' ').next())
                .and_then(|n| n.parse::<u64>().ok())
                .unwrap_or(0);
            numbered.push((number, at, lead.clone()));
        }
        numbered.sort();
        Some(
            numbered
                .iter()
                .enumerate()
                .map(|(k, (_, _, lead))| {
                    let group: Vec<String> = texts
                        .iter()
                        .zip(&leads)
                        .filter(|(_, l)| *l == lead || (k == 0 && l.is_empty()))
                        .map(|(text, _)| text.clone())
                        .collect();
                    (group_text(&group), false)
                })
                .collect(),
        )
    }

    fn child_texts(&self, child: &Child) -> Vec<(String, bool)> {
        match &child.failed {
            Some(outcome) if !outcome.leaf.is_empty() && !bare_item(outcome, &child.entry) => {
                let name = self.strip(child.entry.shown());
                outcome
                    .leaf
                    .iter()
                    .map(|(part, extra)| (under(&name, part), *extra))
                    .collect()
            }
            Some(outcome) if !outcome.parts.is_empty() && !bare_item(outcome, &child.entry) => {
                let name = self.strip(child.entry.shown());
                outcome
                    .parts
                    .iter()
                    .map(|part| match part.strip_prefix(FREE) {
                        Some(free) => (free.to_string(), false),
                        None => (format!("{name}: {part}"), false),
                    })
                    .collect()
            }
            _ => self
                .child_text(child)
                .into_iter()
                .map(|text| (text, false))
                .collect(),
        }
    }

    fn child_text(&self, child: &Child) -> Option<String> {
        let outcome = child.failed.as_ref()?;
        let name = self.strip(child.entry.shown());
        Some(if bare_item(outcome, &child.entry) {
            let bare = child
                .entry
                .bare
                .as_deref()
                .map_or_else(|| name.clone(), |bare| self.strip(bare));
            super::message::isnt(
                &bare,
                child.entry.raw.as_ref().unwrap_or(&child.entry.value),
                "an object",
            )
        } else if outcome.said.is_empty() {
            if outcome.assertions.is_empty() && outcome.inner.is_empty() {
                if self.items.len() > 1
                    && matches!(self.items.get(1), Some(item) if matches!(item.how, How::Pick { .. }))
                {
                    return None;
                }
                super::message::is(&name, &child.entry.value)
            } else {
                return None;
            }
        } else {
            under(&name, &outcome.said)
        })
    }

    fn failed_items(&self, level: Level) -> Vec<Value> {
        let ties: Vec<&Dead> = level
            .dead
            .iter()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        let tie = ties.first().map(|_| self.tie_text(&ties, 0));
        let mut failed: Vec<(Vec<Seg>, Value)> = level
            .dead
            .iter()
            .map(|d| {
                let mut out = self.dead_json(d);
                if let (Cause::Ambiguous, Some(text)) = (d.cause, &tie) {
                    out["ergo/text"] = json!(text);
                }
                (d.order.clone(), out)
            })
            .collect();
        let mut hoisted: Vec<Dead> = Vec::new();
        for child in level.children {
            let own_said: Vec<String> = self
                .child_texts(&child)
                .into_iter()
                .map(|(text, _)| text)
                .collect();
            let Child {
                order,
                mut entry,
                failed: outcome,
                copies,
                ..
            } = child;
            let Some(outcome) = outcome else {
                continue;
            };
            let (shared, mut inner): (Vec<Dead>, Vec<Dead>) =
                outcome.inner.into_iter().partition(|d| d.shared);
            let nothing_checked = outcome.assertions.is_empty();
            let picks_second =
                matches!(self.items.get(1), Some(item) if matches!(item.how, How::Pick { .. }));
            let dropped = nothing_checked
                && inner.is_empty()
                && self.items.len() > 1
                && (picks_second || !shared.is_empty());
            if self.items.len() > 1 && !self.shared_second() && !shared.is_empty() {
                inner.extend(shared.iter().map(Dead::copy));
            }
            if self.shared_second() {
                for entry in shared {
                    if !hoisted
                        .iter()
                        .any(|h| h.order == entry.order && h.name == entry.name)
                    {
                        hoisted.push(entry);
                    }
                }
            }
            if dropped && self.shared_second() {
                continue;
            }
            inner.sort_by(|a, b| a.order.cmp(&b.order));
            let causes = inner.iter().map(|d| d.cause).chain(
                outcome
                    .assertions
                    .iter()
                    .filter_map(|a| a["cause"].as_str().and_then(cause_named)),
            );
            entry.cause = if self.shared_second() {
                Cause::worst(causes).unwrap_or(outcome.cause)
            } else {
                outcome.cause
            };
            let inner = inner
                .iter()
                .map(|d| {
                    let mut plain = d.plain();
                    plain["ergo/text"] = json!(self.dead_text(d).replace(FREE, ""));
                    plain["ergo/said"] = json!(d.shown());
                    plain
                })
                .collect();
            let said_name = entry.shown().to_string();
            let mut json = entry.json(outcome.assertions, inner);
            json["ergo/said"] = json!(said_name);
            json["ergo/text"] = json!(own_said.join("; ").replace(FREE, ""));
            if let Some(Value::Array(locations)) = json.get_mut("locations") {
                locations.extend(copies.into_iter().map(Value::String));
            }
            failed.push((order, json));
        }
        for entry in hoisted {
            failed.push((entry.order.clone(), self.dead_json(&entry)));
        }
        failed.sort_by(|a, b| a.0.cmp(&b.0));
        failed.into_iter().map(|(_, v)| v).collect()
    }

    fn is_free(&self, fail: &Sfail) -> bool {
        !fail.reads_last
            && !self
                .items
                .iter()
                .any(|item| reads_alias(&self.sentences[fail.idx].check, &item.alias))
    }

    fn dead_clause(&self, dead: &Dead, ctx: &Ctx) -> Clause {
        if let Some(own) = self.unsorted_own(dead, ctx) {
            let (cause, text) = own.map_or((dead.cause, String::new()), |(text, cause, _)| {
                (cause, super::message::prefixed(dead.shown(), &text))
            });
            return Clause::item(dead.shown(), cause, text, Vec::new());
        }
        if let Some(told) = &dead.told {
            return match told {
                Some(clause) => Clause {
                    cause: dead.cause,
                    ..clause.clone()
                },
                None => Clause::item(dead.shown(), dead.cause, String::new(), Vec::new()),
            };
        }
        let text = self.dead_text(dead).replace(FREE, "");
        if dead.list {
            return Clause::list(dead.shown(), dead.cause, text);
        }
        Clause::item(dead.shown(), dead.cause, text, Vec::new())
    }

    fn unsorted_own(&self, dead: &Dead, ctx: &Ctx) -> Option<Option<(String, Cause, Input)>> {
        let stash = dead.sorted.as_ref()?;
        let item = stash.get("value").filter(|value| value.is_object())?;
        let (path, keys) = self.items.iter().find_map(|line| match &line.how {
            How::Pick {
                sorted: Some(sorted),
                ..
            } if Some(crate::name::name(&sorted.path).as_str()) == stash["key"].as_str() => {
                Some((&sorted.path, sort_keys(&line.how)))
            }
            _ => None,
        })?;
        let outer = outer_ctx(ctx);
        if !keys
            .into_iter()
            .any(|key| super::key_base::key_flaw(key, &outer).is_some())
        {
            return None;
        }
        let mut at = outer;
        at.subject = Located {
            value: item,
            location: Location::input_root(),
        };
        at.label = None;
        Some(super::key_base::of_path(path, false, &at).and_then(|found| found.base))
    }

    fn child_clause(
        &self,
        child: &Child,
        mut riders: Option<&mut Vec<(usize, Clause)>>,
    ) -> Option<Clause> {
        let name = child.entry.shown();
        let Some(outcome) = child.failed.as_ref() else {
            let cause = Cause::worst(child.rooted.iter().map(|clause| clause.cause))?;
            return Some(Clause::item(
                name,
                cause,
                String::new(),
                child.rooted.clone(),
            ));
        };
        if bare_item(outcome, &child.entry) || outcome.bare {
            let bare = child.entry.bare.as_deref().unwrap_or(name);
            let value = child.entry.raw.as_ref().unwrap_or(&child.entry.value);
            let text = super::message::isnt(bare, value, "an object");
            let said = if outcome.bare {
                outcome.clauses.clone()
            } else {
                Vec::new()
            };
            return Some(Clause::item(name, Cause::NotAnObject, text, said));
        }
        let mut said: Vec<Clause> = outcome.clauses.clone();
        let mut text = String::new();
        let alias = self.last_alias();
        let all_own = child.sfails.iter().all(|fail| fail.own);
        let mut marked: Option<&Clause> = None;
        let mut marked_causes: Vec<Cause> = Vec::new();
        let taken: Vec<usize> = riders
            .as_deref()
            .map(|riders| riders.iter().map(|(idx, _)| *idx).collect())
            .unwrap_or_default();
        for fail in &child.sfails {
            if !fail.reads_last && self.is_free(fail) {
                continue;
            }
            for clause in &fail.clauses {
                if marked.is_some_and(|marked| marked.text == clause.text) {
                    continue;
                }
                let own = matches!(
                    clause.kind,
                    super::clause::Kind::Root | super::clause::Kind::List
                ) && all_own
                    && fail.one
                    && text.is_empty()
                    && said.is_empty();
                match clause
                    .text
                    .strip_prefix(alias)
                    .filter(|rest| own && rest.starts_with(" is "))
                {
                    Some(rest) => {
                        text = format!("{name}{rest}");
                        marked_causes.push(clause.cause);
                        marked = Some(clause);
                    }
                    None => match riders.as_deref_mut() {
                        Some(riders) if !fail.reads_last => {
                            if !taken.contains(&fail.idx) {
                                push_new(riders, (fail.idx, clause.clone()));
                            }
                        }
                        _ => merge_clause(&mut said, clause),
                    },
                }
            }
        }
        in_list_order(&mut said);
        if !said.is_empty() || !text.is_empty() {
            let cause = Cause::worst(
                marked_causes
                    .into_iter()
                    .chain(said.iter().skip(outcome.lifted).map(|clause| clause.cause)),
            )
            .or_else(|| {
                Cause::worst(
                    said.iter()
                        .take(outcome.lifted)
                        .map(|clause| clause.cause)
                        .chain([outcome.cause]),
                )
            })
            .unwrap_or(outcome.cause);
            return Some(Clause::item(name, cause, text, said));
        }
        let picks_second =
            matches!(self.items.get(1), Some(item) if matches!(item.how, How::Pick { .. }));
        (outcome.assertions.is_empty() && outcome.inner.is_empty() && !picks_second).then(|| {
            let text = super::message::is(name, &child.entry.value);
            Clause::item(name, outcome.cause, text, Vec::new())
        })
    }

    fn free_clauses(&self, ctx: &Ctx) -> Vec<Clause> {
        let mut out: Vec<Clause> = Vec::new();
        for (at, sentence) in self.sentences.iter().enumerate() {
            if !self.reads_no_alias(sentence) {
                continue;
            }
            let (_, clauses) = self.said_clauses(sentence, &run_full(&sentence.check, ctx), ctx);
            for clause in clauses {
                merge_clause(&mut out, &clause.in_group(at));
            }
        }
        out
    }

    fn reads_no_alias(&self, sentence: &Sentence) -> bool {
        !self
            .items
            .iter()
            .any(|item| reads_alias(&sentence.check, &item.alias))
    }

    fn sentence_group(&self, at: usize) -> usize {
        if self.reads_no_alias(&self.sentences[at]) {
            at
        } else {
            self.sentences.len() + 1 + at
        }
    }

    fn first_alias_clauses(&self, nested: &Level, depth: usize, ctx: &Ctx) -> Vec<Clause> {
        let mut out: Vec<Clause> = Vec::new();
        if !nested.children.is_empty() || nested.cause == Cause::Satisfied {
            return out;
        }
        let alias = &self.items[depth].alias;
        for sentence in self
            .sentences
            .iter()
            .filter(|sentence| !sentence.reads_last && reads_alias(&sentence.check, alias))
        {
            let (_, clauses) = self.said_clauses(sentence, &run_full(&sentence.check, ctx), ctx);
            for clause in clauses {
                merge_clause(&mut out, &clause);
            }
        }
        out
    }

    fn item_roots(&self, depth: usize, ctx: &Ctx) -> Vec<Clause> {
        let roots = |ctx: &Ctx| -> Vec<Clause> {
            let outer = outer_ctx(ctx);
            let whose: Vec<&Check> = self.items[depth + 1..]
                .iter()
                .flat_map(|item| item.whose.iter())
                .collect();
            let mut said = super::message::root_clauses(&whose, &outer);
            said.extend(super::message::walked_root_clauses(&whose, &outer));
            for sentence in &self.sentences {
                said.extend(sentence_roots_said(&sentence.check, &outer));
            }
            said
        };
        let whole = ctx
            .aliases
            .get(&self.items[depth].alias)
            .is_some_and(|at| !at.value.is_object());
        let mut up = ctx.clone();
        up.aliases.remove(&self.items[depth].alias);
        let before: Vec<String> = roots(&up).into_iter().map(|root| root.text).collect();
        let mut out: Vec<Clause> = Vec::new();
        for root in roots(ctx) {
            if !before.contains(&root.text) && !(whole && root.cause == Cause::NotAnObject) {
                push_new(&mut out, Clause::said(root.cause, root.text));
            }
        }
        out
    }

    fn nested_clauses(
        &self,
        nested: &Level,
        nothing_checked: bool,
        depth: usize,
        ctx: &Ctx,
    ) -> Vec<Clause> {
        let mut riders: Vec<(usize, Clause)> = Vec::new();
        let mut clauses: Vec<Clause> = nested
            .children
            .iter()
            .filter_map(|child| self.child_clause(child, Some(&mut riders)))
            .collect();
        riders.sort_by_key(|(idx, _)| *idx);
        let (walked, mut riders): (Vec<Clause>, Vec<Clause>) = riders
            .into_iter()
            .map(|(_, clause)| clause)
            .partition(|clause| clause.kind == super::clause::Kind::Item);
        if !walked.is_empty() {
            for clause in &walked {
                merge_clause(&mut clauses, clause);
            }
            in_list_order(&mut clauses);
        }
        match clauses.iter_mut().find(|clause| !clause.said.is_empty()) {
            Some(first) => {
                for rider in riders {
                    merge_clause(&mut first.said, &rider);
                }
            }
            None => {
                riders.append(&mut clauses);
                clauses = riders;
            }
        }
        let second = self.shared_second();
        if nothing_checked {
            clauses.extend(
                nested
                    .dead
                    .iter()
                    .filter(|d| !(second && d.shared) && d.cause != Cause::Ambiguous)
                    .map(|d| self.dead_clause(d, ctx)),
            );
        }
        let ties: Vec<&Dead> = nested
            .dead
            .iter()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        if !ties.is_empty() && (!second || self.tied_per_item()) {
            clauses.push(tie_clause(self.tie_text(&ties, depth)));
        }
        clauses
    }

    fn level_clauses(&self, level: &Level, roots: &[Clause], ctx: &Ctx) -> Vec<Clause> {
        let lines = root_lines(roots);
        let texts: Vec<&str> = lines.iter().map(String::as_str).collect();
        let walk = self.sentences.len();
        if level.unreadable {
            return level
                .dead
                .iter()
                .filter(|d| d.cause != Cause::Ambiguous)
                .map(|d| self.dead_clause(d, ctx).in_group(walk))
                .filter_map(|clause| unrooted(clause, &texts))
                .collect();
        }
        let mut items: Vec<(Vec<Seg>, Clause)> = level
            .dead
            .iter()
            .filter(|d| d.cause != Cause::Ambiguous)
            .map(|d| (d.order.clone(), self.dead_clause(d, ctx)))
            .collect();
        let ties: Vec<&Dead> = level
            .dead
            .iter()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        if let Some(first) = ties.first() {
            items.push((first.order.clone(), tie_clause(self.tie_text(&ties, 0))));
        }
        let mut hoisted: Vec<&Dead> = Vec::new();
        for child in &level.children {
            items.extend(
                self.child_clause(child, None)
                    .map(|clause| (child.order.clone(), clause)),
            );
            if !self.shared_second() {
                continue;
            }
            for entry in child.failed.iter().flat_map(|o| &o.inner) {
                if entry.shared
                    && !hoisted
                        .iter()
                        .any(|h| h.order == entry.order && h.name == entry.name)
                {
                    hoisted.push(entry);
                }
            }
        }
        items.sort_by(|a, b| a.0.cmp(&b.0));
        let hoisted_ties: Vec<&Dead> = hoisted
            .iter()
            .copied()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        let mut first: Vec<(Vec<Seg>, Clause)> = Vec::new();
        if let Some(tie) = hoisted_ties.first() {
            first.push((
                tie.order.clone(),
                tie_clause(self.tie_text(&hoisted_ties, 1)),
            ));
        }
        first.extend(
            hoisted
                .iter()
                .filter(|d| d.cause != Cause::Ambiguous)
                .map(|d| (d.order.clone(), self.dead_clause(d, ctx))),
        );
        first.sort_by(|a, b| a.0.cmp(&b.0));
        first
            .into_iter()
            .chain(items)
            .map(|(_, clause)| clause.in_group(walk))
            .filter_map(|clause| unrooted(clause, &texts))
            .collect()
    }

    fn dead_json(&self, dead: &Dead) -> Value {
        let mut out = dead.json(Vec::new(), Vec::new());
        out["ergo/said"] = json!(dead.shown());
        if let Some(sorted) = &dead.sorted {
            out["ergo/sorted"] = sorted.clone();
        }
        if dead.cause != Cause::Ambiguous {
            out["ergo/text"] = json!(self.dead_text(dead).replace(FREE, ""));
        }
        out
    }

    fn shared_second(&self) -> bool {
        self.items.len() == 2 && !reads_path(&self.items[1].path, &self.items[0].alias)
    }

    fn tied_per_item(&self) -> bool {
        let [first, second] = self.items.as_slice() else {
            return false;
        };
        matches!(second.how, How::Pick { .. })
            && second
                .whose
                .iter()
                .any(|check| reads_alias(check, &first.alias))
    }
}

fn tree_causes(clauses: &[Clause]) -> Vec<Cause> {
    clauses
        .iter()
        .flat_map(|clause| std::iter::once(clause.cause).chain(tree_causes(&clause.said)))
        .collect()
}

fn root_lines(roots: &[Clause]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for line in super::clause::lines(roots) {
        for piece in line.split("; ") {
            push_new(&mut out, piece.to_string());
        }
        push_new(&mut out, line);
    }
    out
}

fn listed_roots(clauses: Vec<Clause>) -> Vec<Clause> {
    let mut out: Vec<Clause> = Vec::new();
    let mut lists: Vec<(usize, String, Vec<Clause>)> = Vec::new();
    for clause in clauses {
        if clause.kind != super::clause::Kind::Root || clause.said.is_empty() {
            out.push(clause);
            continue;
        }
        let list = lists
            .iter_mut()
            .find(|(group, name, _)| *group == clause.group && *name == clause.name);
        let Some((_, _, items)) = list else {
            lists.push((clause.group, clause.name, clause.said));
            continue;
        };
        for item in clause.said {
            let line = super::clause::text(std::slice::from_ref(&item));
            if !items
                .iter()
                .any(|seen| super::clause::text(std::slice::from_ref(seen)) == line)
            {
                items.push(item);
            }
        }
    }
    for (group, list, items) in lists {
        let cause = Cause::worst(items.iter().map(|item| item.cause)).unwrap_or(Cause::Value);
        let text = super::clause::text(&super::clause::shown(&items));
        out.push(Clause::root(&list, cause, text).in_group(group));
    }
    out
}

fn unrooted(clause: Clause, roots: &[&str]) -> Option<Clause> {
    let rooted = roots.contains(&clause.text.as_str())
        || clause.text.split("; ").all(|piece| roots.contains(&piece));
    if rooted && clause.said.is_empty() {
        return None;
    }
    let said: Vec<Clause> = clause
        .said
        .into_iter()
        .filter_map(|inner| unrooted(inner, roots))
        .collect();
    let empty =
        clause.kind == super::clause::Kind::Item && clause.text.is_empty() && said.is_empty();
    (!empty).then_some(Clause { said, ..clause })
}

fn sort_keys(how: &How) -> Vec<&Path> {
    let How::Pick {
        sorted: Some(sorted),
        ..
    } = how
    else {
        return Vec::new();
    };
    sorted
        .path
        .steps
        .iter()
        .filter_map(|step| match step {
            Step::Ref(key) if matches!(key.start, Start::Params | Start::Input) => Some(&**key),
            _ => None,
        })
        .collect()
}

fn key_paths_said(check: &Check, ctx: &Ctx) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    for path in check.paths() {
        for (at, step) in path.steps.iter().enumerate() {
            let (Step::Ref(key) | Step::Field(key)) = step else {
                continue;
            };
            let word = match path::read(key, ctx).outcome {
                path::Outcome::Absent => "missing",
                path::Outcome::Null => "null",
                _ => continue,
            };
            let through = Path {
                start: path.start.clone(),
                steps: path.steps[..=at].to_vec(),
            };
            out.push((
                format!("{} is {word}", crate::name::name(key)),
                format!("{} is {word}", crate::name::name(&through)),
            ));
        }
    }
    out
}

fn tie_clause(text: String) -> Clause {
    Clause::item(&text.clone(), Cause::Ambiguous, text, Vec::new())
}

fn in_list_order(said: &mut [Clause]) {
    let mut lists: Vec<&str> = Vec::new();
    let mut keyed: Vec<(usize, u64, Clause)> = Vec::new();
    for clause in said.iter() {
        if clause.kind != super::clause::Kind::Item {
            continue;
        }
        let (number, list) = clause
            .name
            .strip_prefix("item ")
            .and_then(|rest| rest.split_once(" of "))
            .and_then(|(number, list)| Some((number.parse::<u64>().ok()?, list)))
            .unwrap_or((0, clause.name.as_str()));
        let rank = lists
            .iter()
            .position(|seen| *seen == list)
            .unwrap_or_else(|| {
                lists.push(list);
                lists.len() - 1
            });
        keyed.push((rank, number, clause.clone()));
    }
    keyed.sort_by_key(|(rank, number, _)| (*rank, *number));
    let mut sorted = keyed.into_iter().map(|(_, _, clause)| clause);
    for slot in said.iter_mut() {
        if slot.kind == super::clause::Kind::Item
            && let Some(clause) = sorted.next()
        {
            *slot = clause;
        }
    }
}

fn merge_clause(said: &mut Vec<Clause>, clause: &Clause) {
    let item = clause.kind == super::clause::Kind::Item;
    let same = said.iter_mut().find(|seen| {
        seen.kind == clause.kind
            && if item {
                seen.name == clause.name
            } else {
                seen.text == clause.text
            }
    });
    match same {
        Some(seen) if item => {
            for inner in &clause.said {
                push_new(&mut seen.said, inner.clone());
            }
        }
        Some(seen) => seen.cause = Cause::worst([seen.cause, clause.cause]).unwrap_or(seen.cause),
        None => said.push(clause.clone()),
    }
}

fn bare_item(outcome: &Outcome, entry: &Dead) -> bool {
    let only_shared = outcome.assertions.is_empty()
        && !outcome.inner.is_empty()
        && outcome.inner.iter().all(|dead| dead.shared);
    outcome.cause == Cause::NotAnObject && !entry.value.is_object() && !only_shared
}

const MARK: char = '\u{1}';

const FREE: char = '\u{3}';

fn reads_other(check: &Check, alias: &str) -> bool {
    let at_alias = |path: &Path| matches!(&path.start, Start::Alias(name) if name == alias);
    let mut top: Vec<&Path> = check.paths();
    if let Check::Walk(walk) = check {
        top.push(&walk.path);
    }
    top.iter().any(|path| !at_alias(path))
        || check.refs().iter().any(|path| !at_alias(path))
        || nested_checks(check).into_iter().any(|inner| {
            worked_out(inner)
                || inner
                    .paths()
                    .into_iter()
                    .chain(match inner {
                        Check::Walk(walk) => Some(&walk.path),
                        _ => None,
                    })
                    .any(|path| foreign_step(path, alias))
        })
}

pub(crate) fn nested_checks(check: &Check) -> Vec<&Check> {
    let mut out = vec![check];
    match check {
        Check::Walk(walk) => {
            for inner in walk.whose.iter().chain(std::iter::once(&*walk.check)) {
                out.extend(nested_checks(inner));
            }
        }
        Check::Tally(tally) => {
            for side in std::iter::once(&tally.left).chain(tally.right.as_ref()) {
                if let Side::Derived(derived) = side {
                    for term in &derived.terms {
                        if let Term::Counted(counted) = term {
                            for inner in &counted.whose {
                                out.extend(nested_checks(inner));
                            }
                        }
                    }
                }
            }
        }
        Check::AnyOf(any) => {
            for option in &any.options {
                for inner in option {
                    out.extend(nested_checks(inner));
                }
            }
        }
        _ => {}
    }
    out
}

fn worked_out(check: &Check) -> bool {
    let joined = |side: &super::compare::Side| matches!(side, super::compare::Side::Join(_));
    match check {
        Check::Tally(tally) => std::iter::once(&tally.left)
            .chain(tally.right.as_ref())
            .any(|side| match side {
                Side::Derived(_) => true,
                Side::Plain(plain) => joined(plain),
            }),
        Check::Compare(compare) => joined(&compare.left) || joined(&compare.right),
        Check::CompareTime(compare) => joined(&compare.left) || joined(&compare.right),
        _ => false,
    }
}

fn foreign_step(path: &Path, alias: &str) -> bool {
    path.steps.iter().any(|step| match step {
        Step::Field(_) => true,
        Step::Ref(reference) => {
            !matches!(&reference.start, Start::Alias(name) if name == alias)
                || foreign_step(reference, alias)
        }
        Step::Key(_) | Step::Index(_) | Step::Members => false,
    })
}

fn keyed_by_alias(check: &Check, alias: &str) -> bool {
    all_paths(check).iter().any(|path| {
        path.steps.iter().any(|step| {
            matches!(step, Step::Ref(reference) if matches!(&reference.start, Start::Alias(name) if name == alias))
        })
    })
}

fn own_text(text: &str, alias: &str, one: bool) -> String {
    let marked = one && text.starts_with(&format!("{alias} is "));
    let text = text.to_string();
    if marked {
        format!("{MARK}{alias}{MARK}{}", &text[alias.len()..])
    } else {
        text
    }
}

fn under(name: &str, text: &str) -> String {
    match text
        .strip_prefix(MARK)
        .and_then(|rest| rest.split_once(MARK))
    {
        Some((_, after)) => format!("{name}{after}"),
        None => format!("{name}: {text}"),
    }
}

fn unmarked(text: &str) -> String {
    text.replace(MARK, "")
}

fn first_marked(texts: &[String]) -> Vec<String> {
    texts
        .iter()
        .enumerate()
        .map(|(k, text)| if k == 0 { text.clone() } else { unmarked(text) })
        .collect()
}

fn outside_quotes(text: &str) -> bool {
    text.replace("\\\\", "")
        .replace("\\\"", "")
        .matches('"')
        .count()
        .is_multiple_of(2)
}

fn lead_of(text: &str) -> String {
    if !crate::parts::is_item(text) {
        return String::new();
    }
    let cuts = text
        .match_indices(": ")
        .chain(text.match_indices(" is "))
        .map(|(at, _)| at)
        .filter(|at| *at > 0 && outside_quotes(&text[..*at]));
    match cuts.min() {
        Some(at) if text[..at].contains(" of ") => text[..at].to_string(),
        _ => String::new(),
    }
}

fn group_by_lead(texts: &[String]) -> Vec<Vec<String>> {
    let leads: Vec<String> = texts.iter().map(|text| lead_of(text)).collect();
    if leads.iter().all(String::is_empty) {
        return vec![texts.to_vec()];
    }
    let mut order: Vec<&String> = Vec::new();
    for lead in &leads {
        push_new(&mut order, lead);
    }
    order
        .into_iter()
        .map(|lead| {
            texts
                .iter()
                .zip(&leads)
                .filter(|(_, other)| *other == lead)
                .map(|(text, _)| text.clone())
                .collect()
        })
        .collect()
}

fn group_text(group: &[String]) -> String {
    let [first, rest @ ..] = group else {
        return String::new();
    };
    let lead = lead_of(first);
    let mut out = first.clone();
    for text in rest {
        let after = if lead.is_empty() {
            text.as_str()
        } else {
            text.strip_prefix(&format!("{lead}: ")).unwrap_or(text)
        };
        out.push_str(", and ");
        out.push_str(&unmarked(after));
    }
    out
}

fn cause_named(name: &str) -> Option<Cause> {
    [
        Cause::NotAnObject,
        Cause::Ambiguous,
        Cause::Unusable,
        Cause::Absent,
        Cause::Null,
        Cause::Value,
    ]
    .into_iter()
    .find(|cause| cause.name() == name)
}

fn same_names_by_place(inputs: &[Input]) -> Vec<Input> {
    let mut out: Vec<Input> = Vec::new();
    let mut done: Vec<&str> = Vec::new();
    for input in inputs {
        if done.contains(&input.name.as_str()) {
            continue;
        }
        done.push(&input.name);
        let mut group: Vec<&Input> = inputs.iter().filter(|i| i.name == input.name).collect();
        group.sort_by(|a, b| {
            crate::subjects::order(&a.value, &b.value).then_with(|| a.locations.cmp(&b.locations))
        });
        out.extend(group.into_iter().cloned());
    }
    out
}

fn reading_order(check: &Check, inputs: &[Input], aliases: &[&str]) -> Vec<Input> {
    let ordered = same_names_by_place(inputs);
    if !matches!(check, Check::Walk(_)) {
        return ordered;
    }
    let (through, rest): (Vec<Input>, Vec<Input>) = ordered
        .into_iter()
        .partition(|input| starts_at_alias(&input.name, aliases));
    through.into_iter().chain(rest).collect()
}

fn rooted_path(path: &Path) -> Path {
    Path {
        start: match &path.start {
            Start::Subject => path::root(false),
            Start::Own => path::root(true),
            other => other.clone(),
        },
        steps: path
            .steps
            .iter()
            .map(|step| match step {
                Step::Field(field) => Step::Field(Box::new(rooted_path(field))),
                other => other.clone(),
            })
            .collect(),
    }
}

fn rooted_side(side: &super::compare::Side) -> super::compare::Side {
    match side {
        super::compare::Side::Path(path) => super::compare::Side::Path(rooted_path(path)),
        other => other.clone(),
    }
}

fn rooted_right(right: &super::lists::Right) -> super::lists::Right {
    use super::lists::Right;
    match right {
        Right::Ref(path) => Right::Ref(rooted_path(path)),
        Right::Field(path) => Right::Field(rooted_path(path)),
        other => other.clone(),
    }
}

fn root_forms(check: &Check) -> Vec<(Check, bool)> {
    use super::lists::{Contains, In, Matches, Wanted};
    let form = match check {
        Check::Compare(c) => Check::Compare(super::compare::Compare {
            left: rooted_side(&c.left),
            right: rooted_side(&c.right),
            ..c.clone()
        }),
        Check::CompareTime(c) => Check::CompareTime(time::CompareTime {
            left: rooted_side(&c.left),
            right: rooted_side(&c.right),
            ..c.clone()
        }),
        Check::Equals(c) => Check::Equals(super::equals::Equals {
            path: rooted_path(&c.path),
            ..c.clone()
        }),
        Check::Range(c) => Check::Range(super::range::Range {
            path: rooted_path(&c.path),
            ..c.clone()
        }),
        Check::In(c) => Check::In(In {
            path: rooted_path(&c.path),
            values: rooted_right(&c.values),
            ..c.clone()
        }),
        Check::Contains(c) => Check::Contains(Contains {
            path: rooted_path(&c.path),
            wanted: match &c.wanted {
                Wanted::One(right) => Wanted::One(rooted_right(right)),
                Wanted::All(right) => Wanted::All(rooted_right(right)),
                Wanted::Some(right) => Wanted::Some(rooted_right(right)),
            },
            ..c.clone()
        }),
        Check::Matches(c) => Check::Matches(Matches {
            path: rooted_path(&c.path),
            patterns: rooted_right(&c.patterns),
            ..c.clone()
        }),
        Check::HasType(c) => Check::HasType(super::kinds::HasType {
            path: rooted_path(&c.path),
            ..c.clone()
        }),
        Check::NonEmptyString(c) => Check::NonEmptyString(super::kinds::NonEmptyString {
            path: rooted_path(&c.path),
            ..c.clone()
        }),
        Check::Empty(c) => Check::Empty(super::kinds::Empty {
            path: rooted_path(&c.path),
            ..c.clone()
        }),
        Check::Tally(t) => Check::Tally(Tally {
            left: rooted_tally_side(&t.left),
            right: t.right.as_ref().map(rooted_tally_side),
            ..t.clone()
        }),
        Check::Walk(w) => return vec![((*w.check).clone(), false)],
        Check::AnyOf(any) => {
            return any.options.iter().flatten().flat_map(root_forms).collect();
        }
        Check::Present(c) => Check::Present(super::present::Present {
            path: rooted_path(&c.path),
            ..c.clone()
        }),
        Check::For(_) => return Vec::new(),
    };
    vec![(form, true)]
}

fn rooted_tally_side(side: &Side) -> Side {
    match side {
        Side::Plain(plain) => Side::Plain(rooted_side(plain)),
        Side::Derived(derived) if derived.terms.len() == 1 => {
            Side::Derived(super::tally::Derived {
                terms: derived
                    .terms
                    .iter()
                    .map(|term| match term {
                        Term::Counted(counted) => Term::Counted(super::tally::Counted {
                            path: rooted_path(&counted.path),
                            ..counted.clone()
                        }),
                        other => other.clone(),
                    })
                    .collect(),
                ..derived.clone()
            })
        }
        other => other.clone(),
    }
}

fn counts_root(check: &Check, root: &Path) -> bool {
    let Check::Tally(tally) = check else {
        return false;
    };
    std::iter::once(&tally.left)
        .chain(tally.right.as_ref())
        .filter_map(|side| match side {
            Side::Derived(derived) if derived.terms.len() == 1 => Some(derived),
            _ => None,
        })
        .flat_map(|derived| derived.terms.iter())
        .any(|term| matches!(term, Term::Counted(counted) if counted.path == *root))
}

fn equals_kind_fault(check: &Check, root: &Path, read: &path::Read) -> Option<String> {
    let value = read
        .value
        .filter(|_| read.outcome == path::Outcome::Found)?;
    let (path, wanted, within) = match check {
        Check::Equals(equals) => (&equals.path, &equals.value, false),
        Check::Compare(super::compare::Compare {
            left: super::compare::Side::Path(path),
            cmp: super::compare::Cmp::Eq | super::compare::Cmp::Ne,
            ignoring: Some(_),
            ..
        }) => {
            return (path == root && !value.is_string())
                .then(|| super::message::isnt(&crate::name::name(root), value, "text"));
        }
        Check::Compare(super::compare::Compare {
            left: super::compare::Side::Path(path),
            right,
            cmp: super::compare::Cmp::Eq | super::compare::Cmp::Ne,
            within,
            ignoring: None,
        }) => match (right, within) {
            (_, Some(_)) => (path, &Value::Null, true),
            (super::compare::Side::Value(wanted), None) => (path, wanted, false),
            _ => return None,
        },
        _ => return None,
    };
    if path != root {
        return None;
    }
    if within {
        return (!value.is_number())
            .then(|| super::message::isnt(&crate::name::name(root), value, "a number"));
    }
    (!wanted.is_null()
        && !value.is_null()
        && crate::value::type_name(value) != crate::value::type_name(wanted))
    .then(|| {
        super::message::isnt(
            &crate::name::name(root),
            value,
            super::message::kind(wanted),
        )
    })
}

fn counted_kind(value: &Value, last: bool) -> Option<&'static str> {
    if !value.is_array() && !value.is_object() {
        Some("a list or an object")
    } else if value.is_object() && last {
        Some("a list")
    } else {
        None
    }
}

fn counted_root_fault(root: &Path, ctx: &Ctx) -> Option<(Cause, String)> {
    if !path::is_root(&root.start) {
        let read = path::read(root, ctx);
        let value = read
            .value
            .filter(|_| read.outcome == path::Outcome::Found)?;
        return counted_kind(value, true).map(|kind| {
            (
                Cause::Unusable,
                super::message::isnt(&crate::name::name(root), value, kind),
            )
        });
    }
    for end in 1..=root.steps.len() {
        if !matches!(root.steps[end - 1], Step::Key(_) | Step::Index(_)) {
            return None;
        }
        let prefix = Path {
            start: root.start.clone(),
            steps: root.steps[..end].to_vec(),
        };
        let last = end == root.steps.len();
        let read = path::read(&prefix, ctx);
        let name = crate::name::name(&prefix);
        match (read.outcome, read.value) {
            (path::Outcome::Absent, _) => {
                return Some((Cause::Absent, format!("{name} is missing")));
            }
            (path::Outcome::Null, _) => return Some((Cause::Null, format!("{name} is null"))),
            (path::Outcome::Found, Some(value)) if value.is_array() => return None,
            (path::Outcome::Found, Some(value)) => {
                if let Some(kind) = counted_kind(value, last) {
                    return Some((Cause::Unusable, super::message::isnt(&name, value, kind)));
                }
            }
            _ => return None,
        }
    }
    None
}

fn bound_key(path: &Path, ctx: &Ctx) -> bool {
    let start_bound = match &path.start {
        Start::Alias(name) => ctx.aliases.contains_key(name),
        Start::Part(part) => match &part.base {
            Start::Alias(name) => ctx.aliases.contains_key(name),
            _ => true,
        },
        Start::Params | Start::Input => true,
        Start::Subject | Start::Own => false,
    };
    start_bound
        && path.steps.iter().all(|step| match step {
            Step::Field(key) | Step::Ref(key) => {
                matches!(key.start, Start::Subject | Start::Own) || bound_key(key, ctx)
            }
            _ => true,
        })
}

fn root_rank(path: &Path) -> (u8, String) {
    match &path.start {
        Start::Input => (0, String::new()),
        Start::Params => (1, String::new()),
        Start::Alias(name) => (2, name.clone()),
        start if path::is_root(start) => (3, String::new()),
        Start::Part(part) => (4, part.name.clone()),
        _ => (5, String::new()),
    }
}

fn bound_alias(root: &Path, ctx: &Ctx) -> bool {
    match &root.start {
        Start::Alias(name) => ctx.aliases.contains_key(name),
        _ => true,
    }
}

fn sentence_roots_said(check: &Check, ctx: &Ctx) -> Vec<Clause> {
    sentence_roots_listed(check, ctx)
        .into_iter()
        .flat_map(super::message::unlisted)
        .collect()
}

fn sentence_roots_listed(check: &Check, ctx: &Ctx) -> Vec<Clause> {
    let nested = nested_whose(check, false);
    let mut said = sentence_root_clauses(&root_forms(check), ctx);
    said.extend(super::message::listed_root_clauses(&nested, ctx, false));
    said.extend(super::message::walked_root_clauses(&nested, ctx));
    said.extend(super::message::walked_root_clauses(&[check], ctx));
    if let Check::Walk(walk) = check {
        said.extend(super::message::walked_root_clauses(&[&*walk.check], ctx));
    }
    said
}

fn sentence_root_clauses(forms: &[(Check, bool)], ctx: &Ctx) -> Vec<Clause> {
    forms
        .iter()
        .flat_map(|form| {
            let mut faults: Vec<(Cause, String)> = Vec::new();
            for (cause, text) in sentence_root_faults(std::slice::from_ref(form), ctx) {
                if !faults.iter().any(|(_, seen)| *seen == text) {
                    faults.push((cause, text));
                }
            }
            let (check, _) = form;
            let mut named: Vec<String> = check
                .paths()
                .into_iter()
                .chain(walk::listed_refs(check))
                .flat_map(|root| {
                    std::iter::once(crate::name::name(root)).chain(root.steps.iter().filter_map(
                        |step| match step {
                            Step::Ref(key) => Some(crate::name::name(key)),
                            _ => None,
                        },
                    ))
                })
                .collect();
            named.sort_by_key(|name| std::cmp::Reverse(name.len()));
            faults
                .into_iter()
                .map(|(cause, text)| {
                    let name = named
                        .iter()
                        .find(|name| text.starts_with(name.as_str()))
                        .cloned()
                        .unwrap_or_else(|| text.clone());
                    Clause::root(&name, cause, text)
                })
                .collect::<Vec<Clause>>()
        })
        .collect()
}

fn sentence_root_flaw(forms: &[(Check, bool)], ctx: &Ctx) -> Option<(Cause, Vec<String>)> {
    let faults = sentence_root_faults(forms, ctx);
    let mut texts: Vec<String> = Vec::new();
    for (_, text) in &faults {
        push_new(&mut texts, text.clone());
    }
    Cause::worst(faults.into_iter().map(|(cause, _)| cause)).map(|cause| (cause, texts))
}

fn sentence_root_faults(forms: &[(Check, bool)], ctx: &Ctx) -> Vec<(Cause, String)> {
    let mut faults: Vec<(Cause, String)> = Vec::new();
    for (check, keyed_form) in forms {
        let mut roots: Vec<&Path> = check.paths();
        roots.extend(walk::listed_refs(check));
        let keys: Vec<&Path> = roots
            .iter()
            .flat_map(|root| {
                let keyed = *keyed_form
                    && (matches!(root.start, Start::Alias(_)) || counts_root(check, root));
                root.steps.iter().filter_map(move |step| match step {
                    Step::Ref(key) if matches!(key.start, Start::Params | Start::Input) => {
                        Some(&**key)
                    }
                    Step::Ref(key) if keyed && matches!(key.start, Start::Alias(_)) => Some(&**key),
                    Step::Field(key) if keyed && path::is_root(&key.start) => Some(&**key),
                    _ => None,
                })
            })
            .collect();
        if matches!(check, Check::Present(_)) {
            roots.clear();
        }
        roots.extend(keys.iter().copied());
        roots.retain(|root| bound_key(root, ctx));
        roots.sort_by_key(|root| (root_rank(root), crate::name::name(root)));
        roots.dedup();
        let mut found: Vec<(Cause, String)> = super::lists::input_key_fault(check, ctx)
            .into_iter()
            .map(|text| (Cause::NotAnObject, text))
            .collect();
        for root in roots {
            if counts_root(check, root) {
                if let Some(fault) = counted_root_fault(root, ctx) {
                    found.push(fault);
                    continue;
                }
                if path::is_root(&root.start)
                    || (!ctx.subject.value.is_array() && super::lists::walked(root, ctx).is_some())
                {
                    if super::walked_roots_on()
                        && let Check::Tally(tally) = check
                        && bound_alias(root, ctx)
                        && nested_whose(check, false).is_empty()
                        && root
                            .steps
                            .iter()
                            .all(|step| matches!(step, Step::Key(_) | Step::Index(_)))
                    {
                        found.extend(super::tally::counted_faults(tally, root, ctx));
                    }
                    continue;
                }
            }
            if unread_key(root, &keys, ctx).is_some() {
                continue;
            }
            let read = path::read(root, ctx);
            let part = matches!(&root.start, Start::Part(part) if !part.steps.is_empty());
            if super::lists::right_paths(check).contains(&root)
                && super::lists::walked_in(check, root, ctx).is_some()
            {
                if super::walked_roots_on()
                    && bound_alias(root, ctx)
                    && let Some(fault) = super::lists::walked_root_fault(check, root, ctx)
                    && fault.0 != Cause::Value
                {
                    found.push(fault);
                }
                continue;
            }
            if !(part && read.outcome.cause().is_some())
                && let Some(text) = super::message::root_kind_fault(check, root, ctx)
                    .or_else(|| equals_kind_fault(check, root, &read))
            {
                found.push((Cause::Unusable, text));
                continue;
            }
            if keys.contains(&root)
                && let Some(value) = read.value
                && read.outcome.cause().is_none()
                && !value.is_string()
            {
                found.push((
                    Cause::Unusable,
                    super::message::isnt(&crate::name::name(root), value, "text"),
                ));
                continue;
            }
            if let Some(cause) = read.outcome.cause() {
                let present = Check::Present(super::present::Present {
                    path: root.clone(),
                    missing: false,
                });
                let verdict = Verdict {
                    cause,
                    inputs: Vec::new(),
                };
                found.push((cause, super::message::message(&present, ctx, &verdict)));
            }
        }
        found.sort_by_key(|(cause, _)| *cause);
        faults.extend(found);
    }
    faults
}

fn unread_key<'p>(root: &'p Path, keys: &[&Path], ctx: &Ctx) -> Option<&'p Path> {
    root.steps.iter().find_map(|step| match step {
        Step::Ref(key)
            if keys.contains(&&**key)
                && matches!(
                    path::read(key, ctx).outcome,
                    crate::path::Outcome::Absent | crate::path::Outcome::Null
                ) =>
        {
            Some(&**key)
        }
        _ => None,
    })
}

fn nested_whose(check: &Check, counts_only: bool) -> Vec<&Check> {
    match check {
        Check::Tally(tally) => super::tally::tally_sides(tally)
            .into_iter()
            .flat_map(|side| match side {
                Side::Derived(derived) => derived
                    .terms
                    .iter()
                    .flat_map(|term| match term {
                        Term::Counted(counted) => counted.whose.iter().collect::<Vec<_>>(),
                        _ => Vec::new(),
                    })
                    .collect::<Vec<_>>(),
                Side::Plain(_) => Vec::new(),
            })
            .collect(),
        Check::Walk(walk) if !counts_only => walk.whose.iter().collect(),
        _ => Vec::new(),
    }
}

fn starts_at_alias(name: &str, aliases: &[&str]) -> bool {
    let name = name
        .strip_prefix("item ")
        .and_then(|rest| {
            let digits = rest.chars().take_while(char::is_ascii_digit).count();
            rest[digits..].strip_prefix(" of ").filter(|_| digits > 0)
        })
        .unwrap_or(name);
    aliases.iter().any(|alias| {
        name.strip_prefix(alias)
            .is_some_and(|rest| rest.is_empty() || rest.starts_with(['.', '[', ' ']))
    })
}

#[cfg(test)]
mod tests;
