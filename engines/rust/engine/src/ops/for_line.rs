use super::tally::{Side, Tally, Term};
use super::time::{self, Time};
use super::walk::{self, Failure, Options, Seg, WalkItem};
use super::{Check, Input, Part, Verdict, run_full};
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

type SecondRoots = (Cause, Vec<String>, Vec<String>, Vec<String>);

pub struct Run {
    pub verdict: Verdict,
    pub failed_items: Vec<Value>,
    pub message: Option<String>,
}

fn all_paths(check: &Check) -> Vec<&Path> {
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

fn reads_alias(check: &Check, alias: &str) -> bool {
    all_paths(check).into_iter().any(|path| {
        matches!(&path.start, Start::Alias(name) if name == alias)
            || path.steps.iter().any(|step| match step {
                Step::Ref(reference) => {
                    matches!(&reference.start, Start::Alias(name) if name == alias)
                }
                _ => false,
            })
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
                Some(found)
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
    raw: Option<Value>,
    msg: Option<String>,
    bare: Option<String>,
    shared: bool,
    order: Vec<Seg>,
    name: String,
    said: String,
    path: String,
    cause: Cause,
    value: Value,
    location: Option<Location>,
}

impl Dead {
    fn shown(&self) -> &str {
        if self.said.is_empty() {
            &self.name
        } else {
            &self.said
        }
    }

    fn of_failure(failure: &Failure) -> Dead {
        Dead {
            bare: None,
            msg: None,
            shared: false,
            order: failure.order.clone(),
            name: failure.item.clone(),
            said: failure.said.clone(),
            path: failure.path.clone(),
            cause: failure.cause,
            value: failure.value.clone(),
            location: failure.location.clone(),
            raw: None,
        }
    }

    fn copy(&self) -> Dead {
        Dead {
            raw: self.raw.clone(),
            bare: self.bare.clone(),
            msg: self.msg.clone(),
            shared: self.shared,
            order: self.order.clone(),
            name: self.name.clone(),
            said: self.said.clone(),
            path: self.path.clone(),
            cause: self.cause,
            value: self.value.clone(),
            location: self.location.clone(),
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
            return Cands {
                live: Vec::new(),
                dead: walked.failures.iter().map(Dead::of_failure).collect(),
                list: empty_list(walked.name),
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
            state: crate::path::Outcome::Found,
            null_at: None,
        };
        let mut dead: Vec<Dead> = walked.failures.iter().map(Dead::of_failure).collect();
        let from_list = walked.failures.len();
        let mut live = Vec::new();
        let mut kept = 0;
        let mut at = outer.clone();
        for w in &walked.items {
            at.subject = w.item.clone();
            at.label = None;
            let focus = walk::focus_ctx(w, &outer);
            let read: Vec<(Verdict, bool)> = item
                .whose
                .iter()
                .map(|check| walk::focus_verdict(check, w, &at, &focus))
                .collect();
            let lost = read.iter().any(|(_, lost)| *lost);
            let verdicts: Vec<Verdict> = read.into_iter().map(|(verdict, _)| verdict).collect();
            let causes: Vec<Cause> = verdicts.iter().map(|v| v.cause).collect();
            let name = walked.name_of(&w.item_segs, w.unaliased);
            let undecided = Cause::worst(
                causes
                    .iter()
                    .copied()
                    .filter(|c| !matches!(c, Cause::Satisfied | Cause::Value)),
            );
            let first_alias = self.items[0].alias.as_str();
            let fault = item
                .whose
                .iter()
                .zip(&verdicts)
                .find(|(_, verdict)| !matches!(verdict.cause, Cause::Satisfied | Cause::Value))
                .and_then(|(check, verdict)| {
                    let text = (!lost)
                        .then(|| {
                            super::message::root_fault(check, &outer, verdict.cause).or_else(|| {
                                (verdict.cause == Cause::Unusable)
                                    .then(|| {
                                        check.paths().into_iter().find_map(|path| {
                                            super::message::reads_from_a_root(path)
                                                .then(|| {
                                                    super::message::root_kind_fault(
                                                        check, path, &outer,
                                                    )
                                                })
                                                .flatten()
                                        })
                                    })
                                    .flatten()
                            })
                        })
                        .flatten()?;
                    Some(if depth > 0 && !reads_alias(check, first_alias) {
                        format!("{FREE}{text}")
                    } else {
                        text
                    })
                });
            let own = |check: &Check, verdict: &Verdict| {
                let roots = super::message::root_flaw(&[check], &outer)
                    .map(|(_, text)| text)
                    .unwrap_or_default();
                super::message::message(check, &focus, verdict)
                    .split("; ")
                    .flat_map(|part| part.split(", and "))
                    .any(|part| !roots.split("; ").any(|root| root == part))
            };
            let undecided_whose = || {
                item.whose.iter().zip(&verdicts).filter(|(_, verdict)| {
                    !matches!(verdict.cause, Cause::Satisfied | Cause::Value)
                })
            };
            let why = undecided_whose()
                .find(|(check, verdict)| !lost && own(check, verdict))
                .map(|(check, verdict)| {
                    super::message::prefixed(
                        &walked.item_name_dotted(walk::focus_segs(w, check)),
                        &super::message::message(check, &focus, verdict),
                    )
                })
                .or_else(|| {
                    undecided_whose().next().map(|(check, verdict)| {
                        if !lost
                            && let Some(fault) =
                                super::message::root_fault(check, &outer, verdict.cause)
                        {
                            return fault;
                        }
                        if lost {
                            let lost_check = walk::focus_check(w);
                            let verdict = walk::lost_verdict(w, &at);
                            super::message::prefixed(
                                &walked.item_name_dotted(&w.item_segs),
                                &super::message::message(&lost_check, &at, &verdict),
                            )
                        } else {
                            super::message::prefixed(
                                &walked.item_name_dotted(walk::focus_segs(w, check)),
                                &super::message::message(check, &focus, verdict),
                            )
                        }
                    })
                });
            let dead_item = |cause: Cause| Dead {
                raw: (w.end.is_none() && !w.item.value.is_object()).then(|| w.item.value.clone()),
                bare: None,
                msg: if undecided.is_some() && depth == 0 && !matches!(item.how, How::Pick { .. }) {
                    why.clone()
                } else if undecided.is_some() && depth > 0 {
                    fault.clone()
                } else {
                    None
                },
                shared: false,
                order: w.item_segs.clone(),
                name: name.clone(),
                said: if !w.rest.is_empty() && w.item.value.is_object() && cause != Cause::Unusable
                {
                    walked.item_name_dotted(&w.end_segs)
                } else {
                    walked.item_name_dotted(&w.item_segs)
                },
                path: name.clone(),
                cause,
                value: w.shown(),
                location: Some(w.end_location.clone()),
            };
            if let Some(cause) = undecided {
                dead.push(dead_item(cause));
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
                Dead {
                    raw: None,
                    bare: None,
                    msg: None,
                    shared: false,
                    order: Vec::new(),
                    name: shown.clone(),
                    said: String::new(),
                    path: shown,
                    cause: Cause::Absent,
                    value: Value::Null,
                    location: None,
                }
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
                let key_name = crate::name::name(&sorted.path);
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
                        )),
                    },
                    Err(cause) => {
                        failed.push(sort_failure(&found, cause, Value::Null, location, &text))
                    }
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
                        raw: None,
                        bare: None,
                        msg: None,
                        shared: false,
                        order: found.order.clone(),
                        name: found.name.clone(),
                        said: found.said.clone(),
                        path: found.name.clone(),
                        cause: Cause::Ambiguous,
                        value: value.clone(),
                        location: location.clone(),
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
            }
        } else {
            Input {
                name: found.name.clone(),
                value: found.shown.clone(),
                locations: vec![found.location.render()],
                part: cands.list.part.clone(),
                state: crate::path::Outcome::Found,
                null_at: None,
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
        raw: None,
        bare: None,
        msg: Some(said),
        shared: false,
        order: found.order.clone(),
        name: found.name.clone(),
        said: found.said.clone(),
        path: found.name.clone(),
        cause,
        value,
        location,
    }
}

type SortRead<'a> = (Live<'a>, Result<Value, Cause>, Option<Location>, String);

struct Sfail {
    own: bool,
    one: bool,
    text: String,
    parts: Vec<String>,
    reads_last: bool,
    idx: usize,
    cause: Cause,
    inputs: Vec<Value>,
}

type Said = (Vec<Seg>, String, bool);

enum Named {
    Plain,
    Roots(Vec<String>),
    Ahead(Vec<String>),
}

struct Child {
    order: Vec<Seg>,
    entry: Dead,
    failed: Option<Outcome>,
    sfails: Vec<Sfail>,
    copies: Vec<String>,
}

struct Outcome {
    parts: Vec<String>,
    leaf: Vec<(String, bool)>,
    said: String,
    cause: Cause,
    assertions: Vec<Value>,
    inner: Vec<Dead>,
}

struct Level {
    cause: Cause,
    dead: Vec<Dead>,
    children: Vec<Child>,
}

struct Collect {
    lists: Vec<(usize, Input)>,
    seen: Vec<bool>,
    skip: Vec<String>,
    free: Vec<String>,
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
                        _ => Vec::new(),
                    }
                };
                vec![Dead {
                    raw: None,
                    bare: None,
                    msg: (!keyed.is_empty()).then(|| keyed.join(", and ")),
                    shared: !reads_path(&item.path, &self.items[0].alias),
                    order: Vec::new(),
                    name: shown.clone(),
                    said: String::new(),
                    path: shown,
                    cause,
                    value: Value::Null,
                    location: read.location,
                }]
            } else {
                Vec::new()
            };
            return Level {
                cause,
                dead,
                children: Vec::new(),
            };
        }
        let last = depth + 1 == self.items.len();
        let mut children = Vec::new();
        let mut passed = 0;
        for live in cands.live {
            let mut bound = ctx.clone();
            bound.aliases.insert(item.alias.clone(), live.at.clone());
            let entry = Dead {
                raw: None,
                bare: live.bare.clone(),
                msg: None,
                shared: false,
                order: live.order.clone(),
                name: live.name.clone(),
                said: live.said.clone(),
                path: live.name.clone(),
                cause: Cause::Satisfied,
                value: live.shown.clone(),
                location: Some(live.location.clone()),
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
                    }),
                    Vec::new(),
                )
            } else if last {
                self.try_sentences(&bound, collect, false)
            } else {
                let mut nested = self.level(depth + 1, &bound, collect);
                if nested.cause == Cause::Satisfied
                    && nested.children.is_empty()
                    && matches!(self.items[depth + 1].how, How::Every { if_any: true })
                    && let (Some(failed), sfails) = self.try_sentences(&bound, collect, true)
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
                        }],
                    };
                }
                if nested.cause == Cause::Satisfied {
                    (None, Vec::new())
                } else {
                    let assertions = self.aggregate(&nested.children);
                    let mut leaf: Vec<(String, bool)> = Vec::new();
                    let mut parts: Vec<String> =
                        match self.two_list_parts(&nested.children, &collect.skip) {
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
                                .map(|d| self.dead_text(d)),
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
                        }),
                        Vec::new(),
                    )
                }
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

    fn try_sentences(
        &self,
        ctx: &Ctx,
        collect: &mut Collect,
        skip_last: bool,
    ) -> (Option<Outcome>, Vec<Sfail>) {
        let alias = self.last_alias();
        let mut sfails = Vec::new();
        for (idx, sentence) in self.sentences.iter().enumerate() {
            if skip_last && sentence.reads_last {
                continue;
            }
            let ran = run_full(&sentence.check, ctx);
            let verdict = ran.verdict.clone();
            if !verdict.passed() {
                let own = sentence.reads_last && !reads_other(&sentence.check, alias);
                let walks = matches!(sentence.check, Check::Walk(_));
                let text = match (&ran.message, walks) {
                    (Some(said), true) => said.clone(),
                    _ => super::message::message(&sentence.check, ctx, &verdict),
                };
                let parts = match ran.parts {
                    Some(parts) if walks && !parts.is_empty() => {
                        let mut once: Vec<String> = Vec::new();
                        for part in parts {
                            if !once.contains(&part) {
                                once.push(part);
                            }
                        }
                        once
                    }
                    _ => vec![text.clone()],
                };
                let inputs: Vec<Value> =
                    reading_order(&sentence.check, &verdict.inputs, &self.alias_names())
                        .iter()
                        .filter(|input| !self.keyed_alias_input(&sentence.check, input))
                        .map(Input::to_json)
                        .collect();
                sfails.push(Sfail {
                    own,
                    one: inputs.len() == 1 && !keyed_by_alias(&sentence.check, alias),
                    text,
                    parts,
                    reads_last: sentence.reads_last,
                    idx,
                    cause: verdict.cause,
                    inputs,
                });
            }
        }
        let Some(cause) = Cause::worst(sfails.iter().map(|f| f.cause)) else {
            return (None, sfails);
        };
        let assertions = sfails
            .iter()
            .map(|f| {
                json!({
                    "assertion": self.sentences[f.idx].text,
                    "cause": f.cause.name(),
                    "inputs": f.inputs,
                })
            })
            .collect();
        let all_own = sfails.iter().all(|f| f.own);
        let two = self.items.len() > 1 && sfails.iter().any(|f| f.reads_last);
        let mut texts: Vec<String> = Vec::new();
        for f in &sfails {
            let lines: &[String] = if two {
                std::slice::from_ref(&f.text)
            } else {
                &f.parts
            };
            let free = !f.reads_last
                && !self
                    .items
                    .iter()
                    .any(|item| reads_alias(&self.sentences[f.idx].check, &item.alias));
            for line in lines {
                let text = if all_own {
                    own_text(line, alias, f.one)
                } else {
                    line.clone()
                };
                if free {
                    collect.free.extend(text.split("; ").map(str::to_string));
                }
                let text = unskipped(&text, &collect.skip);
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
                        json!({
                            "item": child.entry.name,
                            "cause": f.cause.name(),
                            "inputs": f.inputs,
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
        for path in paths {
            let own = walked.iter().find(|(p, _)| std::ptr::eq(*p, path));
            if matches!(path.start, Start::Params)
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
                    inputs.extend(walk::path_inputs(path, &outer_ctx(ctx), &hidden, true));
                }
                _ => {
                    let on_items = in_walk.contains(&std::ptr::from_ref(path));
                    let at = if matches!(path.start, Start::Part(_)) {
                        outer_ctx(ctx)
                    } else {
                        ctx.clone()
                    };
                    inputs.extend(walk::path_inputs(path, &at, &hidden, on_items));
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
        inputs
    }

    pub fn run(&self, ctx: &Ctx) -> Run {
        let (mut run, free, _, alone) = self.run_items(ctx, Vec::new());
        let said = run.message.clone();
        let (roots, ahead) = match self.rooted(&mut run, ctx) {
            Named::Plain => (Vec::new(), false),
            Named::Roots(texts) => (texts, false),
            Named::Ahead(texts) => (texts, true),
        };
        let failed = !run.failed_items.is_empty();
        let free: Vec<String> = if failed || alone {
            free.iter()
                .map(|text| unskipped(text, &roots))
                .filter(|text| !text.is_empty())
                .collect()
        } else {
            Vec::new()
        };
        let mut once: Vec<String> = Vec::new();
        for text in roots.into_iter().chain(free) {
            if !once.contains(&text) {
                once.push(text);
            }
        }
        if once.is_empty() {
            return run;
        }
        let second: Vec<String> = self
            .second_roots(ctx)
            .map(|(_, texts, _, _)| texts)
            .unwrap_or_default();
        let (items, hoisted) = if failed {
            let mut skip = once.clone();
            if let Some((_, _, raw, _)) = self.second_roots(ctx) {
                skip.extend(raw);
            }
            let (items, _, hoisted, _) = self.run_items(ctx, skip);
            (items.message, hoisted)
        } else if ahead && !alone {
            (said, Vec::new())
        } else {
            (None, Vec::new())
        };
        let mut ordered: Vec<String> = Vec::new();
        for text in once
            .iter()
            .filter(|text| !second.contains(text))
            .chain(hoisted.iter())
            .chain(once.iter().filter(|text| second.contains(text)))
        {
            if !ordered.contains(text) {
                ordered.push(text.clone());
            }
        }
        let once = ordered;
        let mut parts = once.clone();
        if let Some(items) = items {
            parts.extend(
                items
                    .split("; ")
                    .filter(|part| !part.is_empty() && !once.iter().any(|o| o == part))
                    .map(str::to_string),
            );
        }
        run.message = Some(super::message::joined(parts));
        run
    }

    fn rooted(&self, run: &mut Run, ctx: &Ctx) -> Named {
        let whose: Vec<&Check> = self
            .items
            .iter()
            .flat_map(|item| item.whose.iter())
            .chain(
                self.sentences
                    .iter()
                    .flat_map(|s| nested_whose(&s.check, false)),
            )
            .collect();
        let counted: Vec<&Check> = self
            .sentences
            .iter()
            .flat_map(|s| nested_whose(&s.check, true))
            .collect();
        let nested: Vec<&Check> = self
            .sentences
            .iter()
            .flat_map(|s| nested_whose(&s.check, false))
            .collect();
        let outer = outer_ctx(ctx);
        let outer_flaw = super::message::root_flaw_in_for(&whose, &outer, &counted, &nested);
        let forms: Vec<(Check, bool)> = self
            .sentences
            .iter()
            .flat_map(|s| root_forms(&s.check))
            .collect();
        let sentence_flaw = sentence_root_flaw(&forms, &outer);
        let read_first = self.reads_a_flawed_root(&outer);
        if read_first || outer_flaw.is_none() || list_failures(run.verdict.cause, &run.failed_items)
        {
            let flawed = read_first
                && whose
                    .iter()
                    .copied()
                    .chain(self.sentences.iter().map(|s| &s.check))
                    .any(|check| check.flawed(&outer));
            return self.read_roots_first(run, ctx, outer_flaw, sentence_flaw, flawed);
        }
        if let Some((cause, texts, _, _)) = self.second_roots(ctx) {
            let (cause, texts) = match &outer_flaw {
                None => (cause, texts),
                Some((outer_cause, outer_text)) => (
                    Cause::worst(vec![*outer_cause, cause]).unwrap_or(cause),
                    outer_text
                        .split("; ")
                        .map(str::to_string)
                        .chain(texts)
                        .collect(),
                ),
            };
            if matches!(run.verdict.cause, Cause::Satisfied | Cause::Value) {
                run.verdict.cause = cause;
                run.failed_items = Vec::new();
                return Named::Roots(texts);
            }
            if run.verdict.cause == cause {
                return Named::Roots(texts);
            }
        }
        let Some((cause, text)) = outer_flaw else {
            return Named::Plain;
        };
        let flawed = whose
            .iter()
            .copied()
            .chain(self.sentences.iter().map(|s| &s.check))
            .any(|check| check.flawed(&outer));
        if flawed && let Some(said) = run.message.clone() {
            return Named::Roots(super::message::with_roots(
                said.split("; ").map(str::to_string).collect(),
                &text,
            ));
        }
        let texts: Vec<String> = text.split("; ").map(str::to_string).collect();
        let row = run.verdict.cause;
        if row == cause {
            Named::Roots(texts)
        } else if matches!(row, Cause::Satisfied | Cause::Value) {
            run.verdict.cause = cause;
            run.failed_items = Vec::new();
            Named::Roots(texts)
        } else {
            run.verdict.cause = Cause::worst([cause, row]).unwrap_or(cause);
            Named::Ahead(texts)
        }
    }

    fn read_roots_first(
        &self,
        run: &mut Run,
        ctx: &Ctx,
        outer_flaw: Option<(Cause, String)>,
        sentence_flaw: Option<(Cause, Vec<String>)>,
        flawed: bool,
    ) -> Named {
        let mut causes: Vec<Cause> = Vec::new();
        let mut texts: Vec<String> = Vec::new();
        if let Some((cause, text)) = &outer_flaw {
            causes.push(*cause);
            texts.extend(text.split("; ").map(str::to_string));
        }
        if let Some((cause, sentence_texts)) = sentence_flaw {
            causes.push(cause);
            for text in sentence_texts {
                if !texts.contains(&text) {
                    texts.push(text);
                }
            }
        }
        let mut mode = Named::Plain;
        if let Some(cause) = Cause::worst(causes) {
            let row = run.verdict.cause;
            if list_failures(row, &run.failed_items) {
                run.verdict.cause = Cause::worst([cause, row]).unwrap_or(cause);
                mode = Named::Ahead(texts);
            } else if row == cause {
                mode = Named::Roots(texts);
            } else if matches!(row, Cause::Satisfied | Cause::Value) {
                run.verdict.cause = cause;
                run.failed_items = Vec::new();
                mode = Named::Roots(texts);
            } else {
                run.verdict.cause = Cause::worst([cause, row]).unwrap_or(cause);
                mode = Named::Ahead(texts);
            }
        }
        if let Some((second, second_texts, _, unread)) = self.second_roots(ctx)
            && !self.some_passed(run, ctx, &unread)
        {
            let row = run.verdict.cause;
            mode = match mode {
                Named::Roots(mut texts) => {
                    run.verdict.cause = Cause::worst([row, second]).unwrap_or(second);
                    texts.extend(second_texts);
                    Named::Roots(texts)
                }
                Named::Ahead(mut texts) => {
                    run.verdict.cause = Cause::worst([row, second]).unwrap_or(second);
                    texts.extend(second_texts);
                    Named::Ahead(texts)
                }
                Named::Plain if row == Cause::Satisfied => {
                    run.verdict.cause = second;
                    run.failed_items = Vec::new();
                    Named::Roots(second_texts)
                }
                Named::Plain if list_failures(row, &run.failed_items) => {
                    run.verdict.cause = Cause::worst([row, second]).unwrap_or(second);
                    Named::Ahead(second_texts)
                }
                Named::Plain if row == Cause::Value => {
                    run.verdict.cause = second;
                    run.failed_items = Vec::new();
                    Named::Roots(second_texts)
                }
                Named::Plain if row == second => Named::Roots(second_texts),
                Named::Plain => {
                    run.verdict.cause = Cause::worst([row, second]).unwrap_or(second);
                    Named::Ahead(second_texts)
                }
            };
        }
        if flawed {
            run.verdict.cause =
                Cause::worst([Cause::Unusable, run.verdict.cause]).unwrap_or(Cause::Unusable);
        }
        mode
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
            || super::message::root_flaw_in_for(&nested, outer, &[], &[]).is_some()
            || super::message::root_flaw_in_for(&whose, outer, &[], &[]).is_some()
    }

    fn some_passed(&self, run: &Run, ctx: &Ctx, unread: &[String]) -> bool {
        if !matches!(self.items[0].how, How::Some { .. }) || run.verdict.cause != Cause::Satisfied {
            return false;
        }
        let mut collect = Collect {
            lists: Vec::new(),
            seen: vec![false; self.items.len()],
            skip: Vec::new(),
            free: Vec::new(),
        };
        self.level(0, ctx, &mut collect)
            .children
            .iter()
            .any(|child| child.failed.is_none() && !unread.contains(&child.entry.name))
    }

    fn second_roots(&self, ctx: &Ctx) -> Option<SecondRoots> {
        let [first, second] = self.items.as_slice() else {
            return None;
        };
        let outer = outer_ctx(ctx);
        let forms: Vec<(Check, bool)> = self
            .sentences
            .iter()
            .flat_map(|s| root_forms(&s.check))
            .collect();
        let mut causes = Vec::new();
        let mut texts = Vec::new();
        let mut raw = Vec::new();
        let mut unread = Vec::new();
        for live in self.candidates(0, ctx).live {
            let mut bound = ctx.clone();
            bound.aliases.insert(first.alias.clone(), live.at.clone());
            let bound = outer_ctx(&bound);
            for cond in &second.whose {
                let Some((cause, text)) = super::message::root_flaw(&[cond], &bound) else {
                    continue;
                };
                if cause == Cause::NotAnObject {
                    continue;
                }
                let said = super::message::root_flaw(&[cond], &outer)
                    .map(|(_, said)| said)
                    .unwrap_or_default();
                let extra: Vec<&str> = text
                    .split("; ")
                    .filter(|part| !said.split("; ").any(|old| old == *part))
                    .collect();
                if !extra.is_empty() {
                    causes.push(cause);
                    texts.extend(extra.iter().map(|t| format!("{}: {t}", live.name)));
                    raw.extend(extra.iter().map(|t| (*t).to_string()));
                    unread.push(live.name.clone());
                }
            }
            for form in &forms {
                let Some((cause, found)) = sentence_root_flaw(std::slice::from_ref(form), &bound)
                else {
                    continue;
                };
                if cause == Cause::NotAnObject {
                    continue;
                }
                let said = sentence_root_flaw(std::slice::from_ref(form), &outer)
                    .map(|(_, said)| said)
                    .unwrap_or_default();
                let extra: Vec<&String> =
                    found.iter().filter(|part| !said.contains(part)).collect();
                if !extra.is_empty() {
                    causes.push(cause);
                    texts.extend(extra.iter().map(|t| format!("{}: {t}", live.name)));
                    raw.extend(extra.iter().map(|t| (*t).clone()));
                    unread.push(live.name.clone());
                }
            }
        }
        Cause::worst(causes).map(|cause| (cause, texts, raw, unread))
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

    fn unaliased_failures(&self, ctx: &Ctx) -> Option<(Cause, Vec<String>)> {
        let mut causes = Vec::new();
        let mut texts: Vec<String> = Vec::new();
        for sentence in &self.sentences {
            if self
                .items
                .iter()
                .any(|item| reads_alias(&sentence.check, &item.alias))
            {
                continue;
            }
            let ran = run_full(&sentence.check, ctx);
            let verdict = ran.verdict.clone();
            if verdict.passed() {
                continue;
            }
            causes.push(verdict.cause);
            let walks = matches!(sentence.check, Check::Walk(_));
            let lines = match (ran.message, ran.parts) {
                (_, Some(parts)) if walks && !parts.is_empty() => parts,
                (Some(said), _) if walks => vec![said],
                _ => vec![super::message::message(&sentence.check, ctx, &verdict)],
            };
            for line in lines {
                for text in line.split("; ") {
                    if !texts.iter().any(|t| t == text) {
                        texts.push(text.to_string());
                    }
                }
            }
        }
        Cause::worst(causes).map(|cause| (cause, texts))
    }

    fn run_items(&self, ctx: &Ctx, skip: Vec<String>) -> (Run, Vec<String>, Vec<String>, bool) {
        let (run, free, hoisted) = self.run_items_of(ctx, skip.clone());
        if run.verdict.cause != Cause::NotAnObject && !self.flawed(ctx) && self.none_kept(ctx) {
            if let Some(rest) = self.after_first() {
                let (mut reduced, free, hoisted, alone) = rest.run_items(ctx, skip);
                reduced.verdict.inputs = run.verdict.inputs;
                return (reduced, free, hoisted, alone);
            }
            if run.verdict.cause == Cause::Satisfied
                && let Some((cause, texts)) = self.unaliased_failures(ctx)
            {
                let mut run = run;
                run.verdict.cause = cause;
                run.message = Some(super::message::joined(texts.clone()));
                return (run, texts, hoisted, true);
            }
        }
        (run, free, hoisted, false)
    }

    fn run_items_of(&self, ctx: &Ctx, skip: Vec<String>) -> (Run, Vec<String>, Vec<String>) {
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
            return (
                Run {
                    verdict: Verdict {
                        cause: Cause::NotAnObject,
                        inputs: Vec::new(),
                    },
                    failed_items: Vec::new(),
                    message: None,
                },
                Vec::new(),
                Vec::new(),
            );
        }
        let mut collect = Collect {
            lists: Vec::new(),
            seen: vec![false; self.items.len()],
            skip,
            free: Vec::new(),
        };
        let level = self.level(0, ctx, &mut collect);
        let free = std::mem::take(&mut collect.free);
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
        let (failed, said, hoisted) = if let Some((_, listed)) = second {
            (listed, Vec::new(), Vec::new())
        } else if cause == Cause::Satisfied || flawed {
            (Vec::new(), Vec::new(), Vec::new())
        } else {
            self.failed_items(level)
        };
        let hoisted: Vec<String> = hoisted
            .iter()
            .map(|text| unskipped(text, &collect.skip))
            .filter(|text| !text.is_empty())
            .collect();
        let said: Vec<Said> = said
            .into_iter()
            .map(|(order, text, extra)| (order, unskipped(&text, &collect.skip), extra))
            .filter(|(_, text, _)| !text.is_empty())
            .collect();
        let message = if flawed
            || said.is_empty()
                && failed.is_empty()
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
            Some(super::message::for_empty(&listed, &outer, cause))
        } else {
            (!said.is_empty()).then(|| for_joined(said))
        };
        (
            Run {
                verdict: Verdict { cause, inputs },
                failed_items: failed,
                message,
            },
            free,
            hoisted,
        )
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
        Some((
            cause,
            dead.into_iter()
                .map(|d| d.json(Vec::new(), Vec::new()))
                .collect(),
        ))
    }

    fn strip(&self, text: &str) -> String {
        let mut out = text.to_string();
        for item in &self.items {
            let alias = &item.alias;
            out = out.replace(&format!(" of {alias}."), " of ");
            out = out.replace(&format!("of {alias}["), "of [");
            if let Some(rest) = out.strip_prefix(&format!("{alias}.")) {
                out = rest.to_string();
            }
            out = out.replace(&format!(", and {alias}."), ", and ");
            out = out.replace(&format!(": {alias}."), ": ");
        }
        out
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
        let kind = if matches!(dead.value, Value::Object(_)) {
            "a list"
        } else {
            "a list or an object"
        };
        let mut name = dead.shown().to_string();
        for item in &self.items {
            name = name.replace(&format!(" of {}.", item.alias), " of ");
        }
        if name.contains(" named by ") {
            name = self.strip(&name);
        }
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

    fn two_list_parts(&self, children: &[Child], skip: &[String]) -> Option<Vec<(String, bool)>> {
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
                    let text = unskipped(&text, skip);
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

    fn failed_items(&self, level: Level) -> (Vec<Value>, Vec<Said>, Vec<String>) {
        let mut said: Vec<Said> = level
            .dead
            .iter()
            .filter(|d| d.cause != Cause::Ambiguous)
            .map(|d| (d.order.clone(), self.dead_text(d).replace(FREE, ""), false))
            .collect();
        let ties: Vec<&Dead> = level
            .dead
            .iter()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        if let Some(first) = ties.first() {
            said.push((first.order.clone(), self.tie_text(&ties, 0), false));
        }
        let mut failed: Vec<(Vec<Seg>, Value)> = level
            .dead
            .iter()
            .map(|d| (d.order.clone(), d.json(Vec::new(), Vec::new())))
            .collect();
        let mut hoisted: Vec<Dead> = Vec::new();
        for child in level.children {
            for (text, extra) in self.child_texts(&child) {
                said.push((child.order.clone(), text, extra));
            }
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
            let inner = inner.iter().map(Dead::plain).collect();
            let mut json = entry.json(outcome.assertions, inner);
            if let Some(Value::Array(locations)) = json.get_mut("locations") {
                locations.extend(copies.into_iter().map(Value::String));
            }
            failed.push((order, json));
        }
        let hoisted_ties: Vec<&Dead> = hoisted
            .iter()
            .filter(|d| d.cause == Cause::Ambiguous)
            .collect();
        let mut first_said: Vec<Said> = Vec::new();
        if let Some(first) = hoisted_ties.first() {
            first_said.push((first.order.clone(), self.tie_text(&hoisted_ties, 1), false));
        }
        for entry in hoisted {
            if entry.cause != Cause::Ambiguous {
                first_said.push((
                    entry.order.clone(),
                    self.dead_text(&entry).replace(FREE, ""),
                    false,
                ));
            }
            failed.push((entry.order.clone(), entry.json(Vec::new(), Vec::new())));
        }
        failed.sort_by(|a, b| a.0.cmp(&b.0));
        said.sort_by(|a, b| a.0.cmp(&b.0));
        first_said.sort_by(|a, b| a.0.cmp(&b.0));
        let hoisted: Vec<String> = first_said.iter().map(|s| s.1.clone()).collect();
        first_said.extend(said);
        (
            failed.into_iter().map(|(_, v)| v).collect(),
            first_said,
            hoisted,
        )
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

fn nested_checks(check: &Check) -> Vec<&Check> {
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
        Step::Key(_) | Step::Index(_) => false,
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
    let text = unalias(text, alias);
    if marked {
        format!("{MARK}{alias}{MARK}{}", &text[alias.len()..])
    } else {
        text
    }
}

fn unalias(text: &str, alias: &str) -> String {
    let dotted = format!("{alias}.");
    let mut out = String::with_capacity(text.len());
    let mut at = 0;
    while let Some(found) = text[at..].find(&dotted) {
        let start = at + found;
        let before = text[..start].chars().next_back();
        let boundary =
            before.is_none_or(|c| !(c.is_alphanumeric() || matches!(c, '_' | '-' | '.' | '$')));
        out.push_str(&text[at..start]);
        if boundary && outside_quotes(&text[..start]) {
            at = start + dotted.len();
        } else {
            out.push_str(&dotted);
            at = start + dotted.len();
        }
    }
    out.push_str(&text[at..]);
    out
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

fn unskipped(text: &str, skip: &[String]) -> String {
    if skip.is_empty() {
        return text.to_string();
    }
    let skipped = |part: &str| skip.iter().any(|s| s == part);
    text.split("; ")
        .filter(|part| {
            let lead = lead_of(part);
            let after = if lead.is_empty() {
                *part
            } else {
                part.strip_prefix(&format!("{lead}: ")).unwrap_or(part)
            };
            !skipped(part) && !skipped(after)
        })
        .map(|part| {
            part.split(", and ")
                .filter(|piece| !skipped(piece))
                .collect::<Vec<_>>()
                .join(", and ")
        })
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("; ")
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

fn for_joined(said: Vec<Said>) -> String {
    let mut once: Vec<&Said> = Vec::new();
    for entry in &said {
        if !once.iter().any(|o| o.1 == entry.1) {
            once.push(entry);
        }
    }
    let mut counted: Vec<&str> = Vec::new();
    for entry in once.iter().filter(|e| !e.2) {
        if !counted.contains(&entry.1.as_str()) {
            counted.push(&entry.1);
        }
    }
    if counted.len() <= 3 {
        return once
            .iter()
            .map(|e| e.1.as_str())
            .collect::<Vec<_>>()
            .join("; ");
    }
    let shown: Vec<&str> = counted.iter().take(3).copied().collect();
    let mut kept: Vec<String> = once
        .iter()
        .filter(|e| {
            if e.2 {
                said.iter()
                    .any(|o| o.0 == e.0 && !o.2 && shown.contains(&o.1.as_str()))
            } else {
                shown.contains(&e.1.as_str())
            }
        })
        .map(|e| e.1.clone())
        .collect();
    kept.push(format!("and {} more", counted.len() - 3));
    kept.join("; ")
}

fn outside_quotes(text: &str) -> bool {
    text.replace("\\\\", "")
        .replace("\\\"", "")
        .matches('"')
        .count()
        .is_multiple_of(2)
}

fn lead_of(text: &str) -> String {
    if !text.starts_with("item ") {
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
        if !order.contains(&lead) {
            order.push(lead);
        }
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
            right,
            cmp: super::compare::Cmp::Eq | super::compare::Cmp::Ne,
            within,
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

fn sentence_root_flaw(forms: &[(Check, bool)], ctx: &Ctx) -> Option<(Cause, Vec<String>)> {
    let mut texts: Vec<String> = Vec::new();
    let mut causes: Vec<Cause> = Vec::new();
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
        let mut found: Vec<(Cause, String)> = Vec::new();
        for root in roots {
            if counts_root(check, root) {
                if let Some(fault) = counted_root_fault(root, ctx) {
                    found.push(fault);
                    continue;
                }
                if path::is_root(&root.start) {
                    continue;
                }
            }
            let read = path::read(root, ctx);
            let part = matches!(&root.start, Start::Part(part) if !part.steps.is_empty());
            if super::lists::right_paths(check).contains(&root)
                && !part
                && super::lists::walked_in(check, root, ctx).is_some()
            {
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
        for (cause, text) in found {
            causes.push(cause);
            if !texts.contains(&text) {
                texts.push(text);
            }
        }
    }
    Cause::worst(causes).map(|cause| (cause, texts))
}

fn list_failures(row: Cause, failed: &[Value]) -> bool {
    let empty = |f: &Value, key: &str| {
        f.get(key)
            .and_then(Value::as_array)
            .is_none_or(Vec::is_empty)
    };
    row != Cause::Satisfied
        && !failed.is_empty()
        && failed
            .iter()
            .all(|f| empty(f, "failed_assertions") && empty(f, "failed_items"))
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
mod tests {
    use crate::SPEC;
    use serde_json::{Value, json};

    fn row(for_line: &str, assertions: Value, subject: Value) -> Value {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": for_line, "assert": assertions}}}}
        });
        let mut subject = subject;
        subject["id"] = json!(1);
        let input = json!({"things": [subject]});
        let report = crate::report(
            &input,
            &policy,
            &json!({"k": "a", "list": ["x"], "kinds": "code", "need": {"b": 1}}),
        );
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap()
            .clone()
    }

    fn cause(for_line: &str, assertions: Value, subject: Value) -> String {
        row(for_line, assertions, subject)["cause"]
            .as_str()
            .unwrap()
            .to_string()
    }

    fn problems(for_line: &str) -> Value {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": for_line, "assert": "x exists"}}}}
        });
        let input = json!({"things": [{"id": 1, "xs": {"a": 1}, "x": "a", "ys": ["a"]}]});
        let report = crate::report(&input, &policy, &json!({}));
        let rows = report["results"].as_array().unwrap();
        assert!(rows.iter().all(|row| row["check"] != "c"));
        let well_formed = rows
            .iter()
            .find(|row| row["check"] == "$well_formed")
            .unwrap();
        well_formed["inputs"][2]["value"].clone()
    }

    #[test]
    fn a_for_item_that_names_its_own_alias_in_its_path_is_written_wrong() {
        assert_eq!(
            problems("every xs named by x as x"),
            json!(["for: unknown alias x"])
        );
    }

    #[test]
    fn a_for_item_that_names_a_later_alias_in_its_path_is_written_wrong() {
        assert_eq!(
            problems("every xs named by q as p, every ys as q"),
            json!(["for: unknown alias q"])
        );
    }

    #[test]
    fn a_for_item_that_names_its_own_alias_in_a_whose_is_written_wrong() {
        assert_eq!(
            problems("every xs whose v named by x is 1 as x"),
            json!(["for: unknown alias x"])
        );
    }

    #[test]
    fn a_for_item_that_names_an_earlier_alias_in_its_path_is_read() {
        let found = row(
            "every ys as y, every xs named by y as x",
            json!("x is 1"),
            json!({"xs": {"a": [1]}, "ys": ["a"]}),
        );
        assert_eq!(found["cause"], "satisfied");
    }

    fn items(row: &Value) -> Vec<String> {
        row["failed_items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["item"].as_str().unwrap().to_string())
            .collect()
    }

    fn names(row: &Value) -> Vec<String> {
        row["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["name"].as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn every_passes_when_all_items_pass_and_lists_the_failures_otherwise() {
        let line = "every xs as x";
        let sentence = json!("x.ok is true");
        let all = row(
            line,
            sentence.clone(),
            json!({"xs": [{"ok": true}, {"ok": true}]}),
        );
        assert_eq!(all["cause"], "satisfied");
        assert_eq!(all["failed_items"], json!([]));
        let some = row(line, sentence, json!({"xs": [{"ok": true}, {"ok": false}]}));
        assert_eq!(some["cause"], "value");
        assert_eq!(items(&some), ["item 2 of xs"]);
        assert_eq!(
            some["failed_items"][0]["failed_assertions"][0]["inputs"],
            json!([{"name": "x.ok", "value": false, "locations": ["/things/0/xs/1/ok"]}])
        );
    }

    #[test]
    fn an_item_whose_path_goes_on_into_a_value_that_is_not_an_object_fails_as_not_an_object() {
        for item in [json!("s"), json!(null), json!(3)] {
            let subject = json!({"xs": [item, {"t": "a"}]});
            assert_eq!(
                cause("every xs.t as t", json!("t is \"a\""), subject.clone()),
                "not_an_object"
            );
            assert_eq!(
                cause("some xs.t as t", json!("t is \"b\""), subject),
                "not_an_object"
            );
        }
    }

    #[test]
    fn an_object_item_whose_path_goes_on_into_a_text_still_fails_as_unusable() {
        let subject = json!({"xs": [{"meta": "text"}]});
        assert_eq!(
            cause("every xs.meta.k as k", json!("k is 1"), subject),
            "unusable"
        );
    }

    #[test]
    fn some_passes_with_one_passing_item_and_lists_nothing() {
        let subject = json!({"xs": [{"ok": false}, {"ok": true}]});
        let passing = row("some xs as x", json!("x.ok is true"), subject);
        assert_eq!(passing["cause"], "satisfied");
        assert_eq!(passing["failed_items"], json!([]));
        let failing = row(
            "some xs as x",
            json!("x.ok is true"),
            json!({"xs": [{"ok": false}]}),
        );
        assert_eq!(failing["cause"], "value");
        assert_eq!(items(&failing), ["item 1 of xs"]);
    }

    #[test]
    fn an_empty_list_fails_every_and_some_as_value_unless_if_any() {
        let subject = json!({"xs": []});
        assert_eq!(
            cause("every xs as x", json!("x is 1"), subject.clone()),
            "value"
        );
        assert_eq!(
            cause("some xs as x", json!("x is 1"), subject.clone()),
            "value"
        );
        assert_eq!(
            cause("every xs, if any, as x", json!("x is 1"), subject.clone()),
            "satisfied"
        );
        let listed = row("every xs as x", json!("x is 1"), subject);
        assert_eq!(items(&listed), ["xs"]);
        assert_eq!(listed["inputs"][0]["name"], "xs[]");
    }

    #[test]
    fn an_empty_list_a_for_line_tolerates_still_runs_the_sentences_that_dont_read_it() {
        let subject = json!({
            "approvers": [{"u": "ada", "subs": []}, {"u": "g", "state": "REJECTED"}],
            "commits": []
        });
        for line in [
            "some approvers as ap, every commits, if any, as c",
            "every approvers as ap, every commits, if any, as c",
        ] {
            let failed = row(line, json!("ap.state is \"APPROVED\""), subject.clone());
            assert_eq!(failed["cause"], "absent");
            assert_eq!(
                items(&failed),
                ["item 1 of approvers", "item 2 of approvers"]
            );
            assert_eq!(
                failed["message"],
                "item 1 of approvers: ap.state is missing; item 2 of approvers: ap.state is \"REJECTED\""
            );
        }
    }

    #[test]
    fn a_sentence_that_reads_the_alias_of_an_empty_list_a_for_line_tolerates_has_nothing_to_check()
    {
        let line = "some approvers as ap, every commits, if any, as c";
        let approved = json!({"approvers": [{"u": "ada", "state": "APPROVED"}], "commits": []});
        assert_eq!(
            cause(
                line,
                json!(["ap.state is \"APPROVED\"", "c.author does not equal ap.u"]),
                approved
            ),
            "satisfied"
        );
        let rejected = json!({"approvers": [{"u": "ada", "state": "REJECTED"}], "commits": []});
        assert_eq!(
            cause(
                line,
                json!("c.author does not equal ap.u"),
                rejected.clone()
            ),
            "satisfied"
        );
        assert_eq!(
            cause(
                line,
                json!(["ap.state is \"APPROVED\"", "c.author does not equal ap.u"]),
                rejected
            ),
            "value"
        );
    }

    #[test]
    fn an_empty_first_list_a_for_line_tolerates_still_runs_the_sentences_that_dont_read_it() {
        let approvers = json!([{"u": "ada"}, {"u": "g", "state": "REJECTED"}]);
        for line in [
            "every commits, if any, as c, some approvers as ap",
            "every commits, if any, as c, every approvers as ap",
        ] {
            let failed = row(
                line,
                json!(["c.author is ap.u", "ap.state is \"APPROVED\""]),
                json!({"approvers": approvers, "commits": []}),
            );
            assert_eq!(failed["cause"], "absent");
            assert_eq!(
                items(&failed),
                ["item 1 of approvers", "item 2 of approvers"]
            );
            assert_eq!(
                failed["message"],
                "item 1 of approvers: state is missing; item 2 of approvers: state is \"REJECTED\""
            );
            assert_eq!(names(&failed), ["approvers[]", "commits[]"]);
        }
        let filtered = row(
            "every commits whose n is 1, if any, as c, some approvers as ap",
            json!("ap.state is \"APPROVED\""),
            json!({"approvers": approvers, "commits": [{"n": 2}]}),
        );
        assert_eq!(filtered["cause"], "absent");
        assert_eq!(
            cause(
                "every commits, if any, as c, some approvers as ap",
                json!("c.author is ap.u"),
                json!({"approvers": [{"u": "ada"}], "commits": []})
            ),
            "satisfied"
        );
        assert_eq!(
            cause(
                "every commits, if any, as c, some approvers as ap",
                json!("c.author is ap.u"),
                json!({"commits": []})
            ),
            "satisfied"
        );
    }

    #[test]
    fn an_empty_list_a_one_item_for_line_tolerates_still_runs_the_sentences_that_dont_read_it() {
        for line in [
            "every xs, if any, as m",
            "every xs whose k is 1, if any, as m",
        ] {
            let failed = row(
                line,
                json!(["m.v is 1", "z is 1"]),
                json!({"xs": [], "z": 3}),
            );
            assert_eq!(failed["cause"], "value");
            assert_eq!(failed["message"], "z is 3");
            assert_eq!(failed["failed_items"], json!([]));
            assert_eq!(
                cause(
                    line,
                    json!(["m.v is 1", "z is 1"]),
                    json!({"xs": [], "z": 1})
                ),
                "satisfied"
            );
        }
        assert_eq!(
            row(
                "every commits, if any, as c, every c.files as f",
                json!(["f.n is 1", "z is 1"]),
                json!({"commits": [], "z": 3})
            )["message"],
            "z is 3"
        );
        let mixed = row(
            "every xs, if any, as m",
            json!(["w exists", "y is at least 1", "z is 1"]),
            json!({"xs": [], "z": 3, "y": "s"}),
        );
        assert_eq!(mixed["cause"], "unusable");
        assert_eq!(
            mixed["message"],
            "y is \"s\", which isn't a number; w is missing; z is 3"
        );
    }

    #[test]
    fn a_path_that_is_missing_null_or_not_a_list_fails_as_absent_null_or_unusable() {
        for (subject, wanted) in [
            (json!({}), "absent"),
            (json!({"xs": null}), "null"),
            (json!({"xs": "abc"}), "unusable"),
        ] {
            let found = row("every xs as x", json!("x is 1"), subject);
            assert_eq!(found["cause"], wanted);
            assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
            assert_eq!(names(&found), ["xs"]);
        }
    }

    #[test]
    fn a_subject_that_is_not_an_object_fails_as_not_an_object_with_nothing_listed() {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every xs as x", "assert": "x is 1"}}}}
        });
        let report = crate::report(&json!({"things": ["text"]}), &policy, &json!({}));
        let found = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(found["inputs"], json!([]));
        assert_eq!(found["failed_items"], json!([]));
    }

    #[test]
    fn a_for_line_over_the_subject_by_its_name_fails_as_not_an_object_on_a_subject_that_is_not_an_object_or_a_list()
     {
        for subject in [json!("text"), json!(3), json!(null)] {
            let policy = json!({
                "ergo_spec": SPEC,
                "subjects": {"thing": {"from": "every xs"}},
                "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every thing as k", "assert": "k is 1"}}}}
            });
            let report = crate::report(&json!({"xs": [subject]}), &policy, &json!({}));
            let found = report["results"]
                .as_array()
                .unwrap()
                .iter()
                .find(|row| row["check"] == "c")
                .unwrap();
            assert_eq!(found["cause"], "not_an_object");
            assert_eq!(found["inputs"], json!([]));
            assert_eq!(found["failed_items"], json!([]));
        }
    }

    #[test]
    fn a_failed_assertion_keeps_the_dot_of_a_field_named_like_the_subject() {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "every xs"}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every ys as k", "assert": ".thing is 1"}}}}
        });
        let input = json!({"xs": [{"thing": 2, "ys": [1]}]});
        let report = crate::report(&input, &policy, &json!({}));
        let found = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        assert_eq!(
            found["failed_items"][0]["failed_assertions"][0]["assertion"],
            ".thing is 1"
        );
    }

    #[test]
    fn a_whose_leaves_an_item_out_on_value_and_fails_the_check_when_it_cannot_decide() {
        let line = "every xs whose kind is \"code\" as x";
        let sentence = json!("x.ok is true");
        let left_out = row(
            line,
            sentence.clone(),
            json!({"xs": [{"kind": "doc", "ok": false}, {"kind": "code", "ok": true}]}),
        );
        assert_eq!(left_out["cause"], "satisfied");
        let none_left = row(
            line,
            sentence.clone(),
            json!({"xs": [{"kind": "doc", "ok": true}]}),
        );
        assert_eq!(none_left["cause"], "value");
        let undecided = row(
            line,
            sentence.clone(),
            json!({"xs": [{"ok": true}, {"kind": "code", "ok": true}]}),
        );
        assert_eq!(undecided["cause"], "absent");
        assert_eq!(items(&undecided), ["item 1 of xs"]);
        assert_eq!(undecided["failed_items"][0]["failed_assertions"], json!([]));
        let null = row(line, sentence, json!({"xs": [{"kind": null, "ok": true}]}));
        assert_eq!(null["cause"], "null");
    }

    #[test]
    fn an_item_that_ends_at_a_missing_value_fails_without_its_sentences_being_run() {
        let found = row(
            "every xs.title as t",
            json!("t is not \"WIP\""),
            json!({"xs": [{"title": "a"}, {}]}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(items(&found), ["item 2 of xs"]);
        assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
        assert_eq!(found["failed_items"][0]["value"], Value::Null);
        assert_eq!(found["inputs"][0]["name"], "xs[].title");
        assert_eq!(found["inputs"][0]["value"], json!(["a", null]));
    }

    #[test]
    fn an_alias_hides_a_field_of_the_subject_and_a_dot_reads_the_field() {
        let subject = json!({"xs": [{"ok": true}], "x": {"ok": false}});
        assert_eq!(
            cause("every xs as x", json!("x.ok is true"), subject.clone()),
            "satisfied"
        );
        assert_eq!(
            cause("every xs as x", json!(".x.ok is true"), subject),
            "value"
        );
    }

    #[test]
    fn a_bare_key_in_assert_is_a_subject_field_and_is_listed_sorted_with_the_list() {
        let found = row(
            "every xs as x",
            json!("x.a does not equal owner"),
            json!({"xs": [{"a": "bob"}], "owner": "ann"}),
        );
        assert_eq!(names(&found), ["owner", "xs[]"]);
    }

    #[test]
    fn a_bare_key_in_an_items_whose_is_the_items_field() {
        let found = row(
            "some xs whose role is \"qa\" as x",
            json!("x.at is before started"),
            json!({"xs": [{"role": "qa", "at": 1}], "started": 2}),
        );
        assert_eq!(found["cause"], "satisfied");
        assert_eq!(names(&found), ["started", "xs[]"]);
    }

    #[test]
    fn a_second_item_is_walked_for_each_item_of_the_first() {
        let line = "every ps as p, some p.ws whose s is \"A\" as w";
        let sentence = json!("w.n does not equal p.n");
        let subject = json!({"ps": [
            {"n": "ann", "ws": [{"n": "bob", "s": "A"}]},
            {"n": "eve", "ws": [{"n": "eve", "s": "A"}]}
        ]});
        let found = row(line, sentence, subject);
        assert_eq!(found["cause"], "value");
        assert_eq!(items(&found), ["item 2 of ps"]);
        let assertion = &found["failed_items"][0]["failed_assertions"][0];
        assert_eq!(assertion["assertion"], "w.n does not equal p.n");
        assert_eq!(assertion["items"][0]["item"], "item 1 of p.ws");
        assert_eq!(names(&found), ["p.ws[]", "ps[]"]);
    }

    #[test]
    fn a_sentence_that_does_not_read_the_second_alias_shows_its_inputs_directly() {
        let found = row(
            "every ps as p, every p.ws as w",
            json!(["p.n is 1", "w.n is 1"]),
            json!({"ps": [{"n": 2, "ws": [{"n": 1}]}]}),
        );
        let assertions = found["failed_items"][0]["failed_assertions"]
            .as_array()
            .unwrap();
        assert!(assertions[0].get("inputs").is_some());
        assert!(assertions[0].get("items").is_none());
    }

    #[test]
    fn a_failed_count_whose_whose_reads_a_part_lists_the_parts_value_with_its_location() {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id", "has": {"pa": "meta"}}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": {
                "for": "every groups as g",
                "assert": "count of items whose w is pa.w is 5"
            }}}}
        });
        let input = json!({"things": [{"id": "t", "groups": [1], "items": [{"w": 1}, {"w": 2}], "meta": {"w": 2}}]});
        let report = crate::report(&input, &policy, &json!({}));
        let found = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        let failed = &found["failed_items"][0]["failed_assertions"][0]["inputs"];
        for inputs in [failed, &found["inputs"]] {
            let part = inputs
                .as_array()
                .unwrap()
                .iter()
                .find(|i| i["name"] == "pa.w")
                .unwrap();
            assert_eq!(part["value"], json!(2));
            assert_eq!(part["locations"], json!(["/things/0/meta/w"]));
            assert_eq!(part["part"], json!({"id": null, "name": "pa"}));
        }
    }

    #[test]
    fn an_empty_second_list_is_listed_under_the_first_item() {
        let found = row(
            "every ps as p, every p.ws as w",
            json!("w is 1"),
            json!({"ps": [{"ws": []}]}),
        );
        assert_eq!(found["cause"], "value");
        assert_eq!(found["failed_items"][0]["failed_items"][0]["item"], "p.ws");
        assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
    }

    #[test]
    fn a_second_item_whose_whose_leaves_nothing_in_lists_the_first_item_with_no_sentences() {
        let found = row(
            "every xs as p, every ys whose k is 1 as q",
            json!("q.n is 1"),
            json!({"xs": [{"v": 1}], "ys": [{"k": 2}]}),
        );
        assert_eq!(found["cause"], "value");
        assert_eq!(items(&found), ["item 1 of xs"]);
        assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
    }

    #[test]
    fn a_failure_of_a_second_list_that_does_not_read_the_first_alias_is_listed_once() {
        let found = row(
            "some ps as p, every bs as b",
            json!("p.n is more than b.n"),
            json!({"ps": [{"n": 1}, {"n": 2}], "bs": "text"}),
        );
        assert_eq!(found["cause"], "unusable");
        assert_eq!(items(&found), ["bs"]);
        assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
    }

    #[test]
    fn a_picked_item_is_named_where_it_is_and_the_list_shows_only_it() {
        let found = row(
            "last of xs sorted by t as x",
            json!("x.ok is true"),
            json!({"xs": [{"t": 2, "ok": false}, {"t": 1, "ok": true}]}),
        );
        assert_eq!(found["cause"], "value");
        assert_eq!(items(&found), ["item 1 of xs"]);
        assert_eq!(names(&found), ["item 1 of xs"]);
    }

    #[test]
    fn a_pick_takes_the_position_from_the_start_or_the_end_in_the_order_of_the_field() {
        let subject = json!({"xs": [{"t": 3, "n": "c"}, {"t": 1, "n": "a"}, {"t": 2, "n": "b"}]});
        for (line, wanted) in [
            ("first of xs sorted by t as x", "a"),
            ("last of xs sorted by t as x", "c"),
            ("item 2 of xs sorted by t as x", "b"),
            ("item 2 from last of xs sorted by t as x", "b"),
            ("first of xs as x", "c"),
            ("last of xs as x", "b"),
        ] {
            assert_eq!(
                cause(line, json!(format!("x.n is \"{wanted}\"")), subject.clone()),
                "satisfied",
                "{line}"
            );
        }
    }

    #[test]
    fn a_pick_sorts_strings_alphabetically_by_code_point() {
        let subject = json!({"xs": [{"n": "adam"}, {"n": "Zoe"}]});
        assert_eq!(
            cause(
                "first of xs sorted by n alphabetically as x",
                json!("x.n is \"Zoe\""),
                subject.clone()
            ),
            "satisfied"
        );
        assert_eq!(
            cause(
                "first of xs sorted by n as x",
                json!("x.n is \"Zoe\""),
                subject.clone()
            ),
            "unusable"
        );
        assert_eq!(
            cause(
                "first of xs sorted by n alphabetically as x",
                json!("x.n is 1"),
                json!({"xs": [{"n": 1}]})
            ),
            "unusable"
        );
    }

    #[test]
    fn a_pick_sorts_numbers_times_and_dates_each_in_their_own_order() {
        assert_eq!(
            cause(
                "last of xs sorted by t as x",
                json!("x.t is \"2026-10-02T00:00:00Z\""),
                json!({"xs": [{"t": "2026-10-02T00:00:00Z"}, {"t": "2026-10-01T00:00:00Z"}]})
            ),
            "satisfied"
        );
        assert_eq!(
            cause(
                "last of xs sorted by t as x",
                json!("x.t is \"2026-10-02\""),
                json!({"xs": [{"t": "2026-10-02"}, {"t": "2026-09-30"}]})
            ),
            "satisfied"
        );
    }

    #[test]
    fn mixed_kinds_keep_the_first_kind_and_fail_the_others_as_unusable() {
        let found = row(
            "last of xs sorted by t as x",
            json!("x.t is 1"),
            json!({"xs": [{"t": 1}, {"t": "2026-10-02T00:00:00Z"}]}),
        );
        assert_eq!(found["cause"], "unusable");
        assert_eq!(items(&found), ["item 2 of xs"]);
        assert_eq!(found["failed_items"][0]["value"], "2026-10-02T00:00:00Z");
    }

    #[test]
    fn a_tie_at_the_picked_position_fails_every_tied_item_as_ambiguous() {
        let found = row(
            "last of xs sorted by t as x",
            json!("x.ok is true"),
            json!({"xs": [{"t": 2}, {"t": 2}, {"t": 1}]}),
        );
        assert_eq!(found["cause"], "ambiguous");
        assert_eq!(items(&found), ["item 1 of xs", "item 2 of xs"]);
        assert_eq!(found["failed_items"][0]["value"], 2);
    }

    #[test]
    fn a_tie_elsewhere_does_not_matter() {
        assert_eq!(
            cause(
                "last of xs sorted by t as x",
                json!("x.ok is true"),
                json!({"xs": [{"t": 1}, {"t": 1}, {"t": 3, "ok": true}]})
            ),
            "satisfied"
        );
    }

    #[test]
    fn a_missing_null_or_wrong_typed_sort_field_fails_the_item_and_nothing_is_picked() {
        for (field, wanted) in [
            (json!({}), "absent"),
            (json!({"t": null}), "null"),
            (json!({"t": "yesterday"}), "unusable"),
        ] {
            let found = row(
                "last of xs sorted by t as x",
                json!("x.ok is true"),
                json!({"xs": [{"t": 1}, field]}),
            );
            assert_eq!(found["cause"], wanted);
            assert_eq!(items(&found), ["item 2 of xs"]);
        }
    }

    #[test]
    fn a_position_past_the_end_fails_as_absent() {
        assert_eq!(
            cause("item 3 of xs as x", json!("x is 1"), json!({"xs": [1, 2]})),
            "absent"
        );
        assert_eq!(
            cause("first of xs as x", json!("x is 1"), json!({"xs": []})),
            "absent"
        );
        assert_eq!(
            cause("last of xs as x", json!("x is 1"), json!({"xs": []})),
            "absent"
        );
    }

    #[test]
    fn an_items_whose_reads_the_value_its_path_ends_at() {
        let line = "every rs.m whose s is \"A\" as m";
        assert_eq!(
            cause(
                line,
                json!("m.by exists"),
                json!({"rs": [{"m": {"s": "A", "by": "x"}}, {"s": "A", "m": {"s": "B"}}]})
            ),
            "satisfied"
        );
        let found = row(
            line,
            json!("m.by exists"),
            json!({"rs": [{"s": "A", "m": {"t": 1}}, {"m": {"s": "A", "t": 1}}]}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(
            found["message"],
            "item 1 of rs: m: s is missing; item 2 of rs: by is missing"
        );
    }

    #[test]
    fn an_items_whose_fails_as_absent_when_the_value_its_path_ends_at_is_missing() {
        let found = row(
            "every rs.m whose s is \"A\" as m",
            json!("m.by exists"),
            json!({"rs": [{"m": {"s": "A", "by": "x"}}, {"s": "A"}]}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(found["message"], "item 2 of rs: m is missing");
        assert_eq!(
            found["failed_items"],
            json!([{"path": "item 2 of rs", "item": "item 2 of rs", "cause": "absent", "value": null, "locations": ["/things/0/rs/1"], "failed_assertions": []}])
        );
    }

    #[test]
    fn an_items_whose_fails_as_not_an_object_when_the_value_its_path_ends_at_is_null() {
        let found = row(
            "every rs.m whose s is \"A\" as m",
            json!("m.by exists"),
            json!({"rs": [{"s": "A", "m": null}, {"m": {"s": "A", "by": "x"}}]}),
        );
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(
            found["message"],
            "item 1 of rs: m is null, which isn't an object"
        );
    }

    #[test]
    fn a_pick_sorts_by_a_field_of_the_value_its_path_ends_at() {
        let subject = json!({"rs": [
            {"t": 9, "m": {"s": "A", "by": "x", "t": 2}},
            {"t": 0, "m": {"s": "B", "by": "y", "t": 1}},
            {"t": 1, "m": {"s": "A", "by": "z", "t": 3}}
        ]});
        assert_eq!(
            cause(
                "first of rs.m whose s is \"A\" sorted by t as m",
                json!("m.by is \"x\""),
                subject.clone()
            ),
            "satisfied"
        );
        assert_eq!(
            cause(
                "last of rs.m sorted by t as m",
                json!("m.by is \"z\""),
                subject
            ),
            "satisfied"
        );
        let found = row(
            "last of rs.m sorted by t as m",
            json!("m.by exists"),
            json!({"rs": [{"t": 1, "m": {"t": "zz"}}, {"m": {"t": 1}}]}),
        );
        assert_eq!(found["cause"], "unusable");
        assert_eq!(
            found["message"],
            "item 1 of rs: m: t is \"zz\", which isn't a number, a time or a date"
        );
    }

    #[test]
    fn a_first_item_that_isnt_an_object_is_not_named_when_only_a_second_items_whose_failed_under_it()
     {
        let found = row(
            "every xs as x, every ys whose q is 1 as y",
            json!("y.q is 1"),
            json!({"xs": [{"n": 1}, 5], "ys": [{"q": 1}, "s"]}),
        );
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(
            found["message"],
            "item 2 of ys is \"s\", which isn't an object"
        );
    }

    #[test]
    fn a_value_past_the_list_that_isnt_an_object_is_named_after_its_item_and_the_rest_of_the_path()
    {
        let found = row(
            "every ys.z as z",
            json!("z.q is 1"),
            json!({"ys": [{"z": {"q": 1}}, {"z": "s"}, {}]}),
        );
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(
            found["message"],
            "item 2 of ys: z is \"s\", which isn't an object; item 3 of ys: z is missing"
        );
    }

    #[test]
    fn a_sort_on_a_value_that_isnt_an_object_names_the_item() {
        let found = row(
            "last of rs.m sorted by t as m",
            json!("m.by exists"),
            json!({"rs": [{"t": 1, "m": null}, {"m": {"t": 1}}]}),
        );
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(
            found["message"],
            "item 1 of rs is null, which isn't an object"
        );
    }

    #[test]
    fn a_pick_keeps_the_items_its_whose_keeps_before_sorting() {
        assert_eq!(
            cause(
                "item 2 from last of xs whose s is \"A\" sorted by t as x",
                json!("x.n is \"b\""),
                json!({"xs": [{"s": "A", "t": 1, "n": "a"}, {"s": "A", "t": 2, "n": "b"}, {"s": "B", "t": 3, "n": "c"}, {"s": "A", "t": 4, "n": "d"}]})
            ),
            "satisfied"
        );
        assert_eq!(
            cause(
                "item 2 from last of xs whose s is \"A\" sorted by t as x",
                json!("x.n is \"b\""),
                json!({"xs": [{"s": "A", "t": 1, "n": "a"}, {"s": "A", "t": 2, "n": "b"}, {"s": "B", "t": 3, "n": "c"}]})
            ),
            "value"
        );
    }

    #[test]
    fn a_whose_a_pick_cannot_decide_fails_the_check_and_nothing_is_picked() {
        let found = row(
            "first of xs whose s is \"A\" as x",
            json!("x.n is 1"),
            json!({"xs": [{"n": 1}, {"s": "A", "n": 1}]}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(items(&found), ["item 1 of xs"]);
    }

    #[test]
    fn a_path_named_by_a_for_alias_reads_the_key_the_item_holds() {
        let line = "every ks as k";
        let sentence = json!("m named by k is 1");
        let subject = json!({"ks": ["a", "b"], "m": {"a": 1, "b": 2}});
        let found = row(line, sentence.clone(), subject);
        assert_eq!(found["cause"], "value");
        assert_eq!(items(&found), ["item 2 of ks"]);
        assert_eq!(names(&found), ["ks[]", "m"]);
        let null = row(line, sentence.clone(), json!({"ks": [null], "m": {"a": 1}}));
        assert_eq!(null["cause"], "null");
        let number = row(line, sentence, json!({"ks": [5], "m": {"a": 1}}));
        assert_eq!(number["cause"], "unusable");
    }

    #[test]
    fn a_path_named_by_a_param_that_is_missing_fails_with_the_list_shown_as_empty() {
        let found = row(
            "every m named by $params.nope as x",
            json!("x is 1"),
            json!({"m": {"a": [1]}}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(found["failed_items"], json!([]));
        assert_eq!(found["inputs"][0]["value"], json!([]));
    }

    #[test]
    fn a_count_under_a_for_line_reads_the_alias_and_lists_the_number_then_the_list() {
        let found = row(
            "every xs as x",
            json!("count of x.fs is at least 1"),
            json!({"xs": [{"fs": ["a"]}, {"fs": []}]}),
        );
        assert_eq!(found["cause"], "value");
        let inputs = &found["failed_items"][0]["failed_assertions"][0]["inputs"];
        assert_eq!(inputs[0]["name"], "count of x.fs");
        assert_eq!(inputs[0]["value"], 0);
        assert_eq!(inputs[1]["name"], "x.fs[]");
    }

    #[test]
    fn a_failed_sentence_lists_each_value_it_read_in_the_order_it_reads_them() {
        let found = row(
            "every xs as x",
            json!("x.a is at least y"),
            json!({"xs": [{"a": 1}], "y": 5}),
        );
        let inputs = found["failed_items"][0]["failed_assertions"][0]["inputs"]
            .as_array()
            .unwrap();
        let names: Vec<&str> = inputs.iter().map(|i| i["name"].as_str().unwrap()).collect();
        assert_eq!(names, ["x.a", "y"]);
    }

    #[test]
    fn inputs_with_the_same_name_are_ordered_by_value_before_their_locations() {
        let found = row(
            "some approvals.approver as approver",
            json!(".approver equals approver"),
            json!({"approver": "", "approvals": [{"approver": "grace"}]}),
        );
        let inputs = found["failed_items"][0]["failed_assertions"][0]["inputs"]
            .as_array()
            .unwrap();
        let values: Vec<&str> = inputs
            .iter()
            .map(|i| i["value"].as_str().unwrap())
            .collect();
        assert_eq!(values, ["", "grace"]);
    }

    #[test]
    fn two_sentences_both_failing_are_listed_in_the_order_written() {
        let found = row(
            "every xs as x",
            json!(["x.b is 1", "x.a is 1"]),
            json!({"xs": [{"a": 2, "b": 2}]}),
        );
        let assertions: Vec<&str> = found["failed_items"][0]["failed_assertions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a["assertion"].as_str().unwrap())
            .collect();
        assert_eq!(assertions, ["x.b is 1", "x.a is 1"]);
    }

    #[test]
    fn a_whose_ref_that_is_not_a_list_fails_the_check_as_unusable_and_lists_the_items_it_cant_decide()
     {
        let found = row(
            "every xs whose kind is in $params.kinds as x",
            json!("x.ok is true"),
            json!({"xs": [{"kind": "code", "ok": false}]}),
        );
        assert_eq!(found["cause"], "unusable");
        assert_eq!(items(&found), ["item 1 of xs"]);
        assert_eq!(names(&found), ["xs[]"]);
        let usable = row(
            "every xs whose kind is in $params.list as x",
            json!("x.ok is true"),
            json!({"xs": [{"kind": "x", "ok": true}]}),
        );
        assert_eq!(usable["cause"], "satisfied");
    }

    #[test]
    fn a_second_path_whose_ref_step_cannot_be_read_fails_the_first_item_with_the_refs_cause() {
        let found = row(
            "every gs as g, every g.ss named by $params.nope as s",
            json!("s.ok is true"),
            json!({"gs": [{"ss": {"a": [{"ok": true}]}}]}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(items(&found), ["item 1 of gs"]);
        let inner = &found["failed_items"][0]["failed_items"][0];
        assert_eq!(inner["item"], "g.ss named by $params.nope");
        assert_eq!(inner["cause"], "absent");
        assert_eq!(inner["value"], Value::Null);
        assert_eq!(inner["locations"], json!(["/things/0/gs/0/ss"]));
        assert_eq!(found["inputs"][0]["name"], "g.ss named by $params.nope");
        assert_eq!(found["inputs"][0]["value"], json!([]));
    }

    #[test]
    fn a_second_item_reading_into_a_first_item_that_is_not_an_object_fails_it_as_not_an_object() {
        let found = row(
            "every ps as p, some p.as as w",
            json!("w.n does not equal p.n"),
            json!({"ps": [1, null, {"as": [{"n": "b"}], "n": "a"}]}),
        );
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(items(&found), ["item 1 of ps", "item 2 of ps"]);
        assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
        assert!(found["failed_items"][0].get("failed_items").is_none());
        assert_eq!(found["failed_items"][1]["value"], Value::Null);
    }

    #[test]
    fn a_path_named_by_an_alias_is_named_as_the_sentence_writes_it() {
        let found = row(
            "every ks as k",
            json!("m named by k is 1"),
            json!({"ks": ["b"], "m": {"b": 2}}),
        );
        assert_eq!(
            found["failed_items"][0]["failed_assertions"][0]["inputs"][0]["name"],
            "m named by k"
        );
    }

    #[test]
    fn a_walk_through_an_alias_adds_nothing_read_on_the_item_to_the_rows_inputs() {
        let found = row(
            "every xs as x",
            json!("every x.fs is a string"),
            json!({"xs": [null]}),
        );
        assert_eq!(found["cause"], "null");
        assert_eq!(names(&found), ["xs[]"]);
    }

    #[test]
    fn a_second_list_that_is_empty_in_one_item_and_missing_in_another_is_shown_by_its_walked_name()
    {
        let found = row(
            "every ms as m, every m.cs as c",
            json!("c.ok is true"),
            json!({"ms": [{"n": 1}, {"cs": []}]}),
        );
        assert_eq!(names(&found), ["m.cs[]", "ms[]"]);
    }

    #[test]
    fn a_sum_that_reads_no_alias_is_listed_with_the_row_and_one_that_does_is_not() {
        let found = row(
            "every xs as x",
            json!("x.t is at least p plus q"),
            json!({"xs": [{"t": 1}], "p": 1, "q": 1}),
        );
        assert_eq!(names(&found), ["p", "p plus q", "q", "xs[]"]);
        let aliased = row(
            "every xs as x",
            json!("x.t is at least x.u plus 1"),
            json!({"xs": [{"t": 1, "u": 1}]}),
        );
        assert_eq!(names(&aliased), ["xs[]"]);
    }

    #[test]
    fn a_walk_in_a_sentence_lists_its_own_list_unless_it_reads_through_an_alias() {
        let own = row(
            "every ks as k",
            json!("every rs.n is at least 1"),
            json!({"ks": ["a"], "rs": [{"n": 1}]}),
        );
        assert_eq!(names(&own), ["ks[]", "rs[].n"]);
        let through = row(
            "every ks as k",
            json!("some m named by k is at least 1"),
            json!({"ks": ["a"], "m": {"a": [1]}}),
        );
        assert_eq!(names(&through), ["ks[]", "m"]);
    }

    #[test]
    fn a_row_lists_the_params_value_a_sentence_compares_with() {
        let found = row(
            "every items as x",
            json!("x.v equals $params.k"),
            json!({"items": [{"v": 1}]}),
        );
        assert_eq!(names(&found), ["$params.k", "items[]"]);
    }

    #[test]
    fn a_row_lists_the_params_value_in_a_sentence_that_reads_no_alias() {
        let found = row(
            "every items as x",
            json!(["x.v exists", "n is $params.k"]),
            json!({"items": [{"v": 1}], "n": 1}),
        );
        assert_eq!(names(&found), ["$params.k", "items[]", "n"]);
    }

    #[test]
    fn a_row_lists_the_params_value_a_count_is_compared_with_and_the_count() {
        let found = row(
            "every items as x",
            json!("count of items is $params.k"),
            json!({"items": [{"v": 1}]}),
        );
        assert_eq!(names(&found), ["$params.k", "count of items", "items[]"]);
    }

    #[test]
    fn a_row_lists_the_count_on_the_right_of_a_sentence_that_reads_an_alias() {
        let found = row(
            "every items as x",
            json!("x.v is at most count of items"),
            json!({"items": [{"v": 1}]}),
        );
        assert_eq!(names(&found), ["count of items", "items[]"]);
    }

    #[test]
    fn a_row_lists_the_elapsed_time_of_a_sentence_that_reads_no_alias() {
        let found = row(
            "every items as x",
            json!("fc is days elapsed from fa to fb"),
            json!({"items": [{"v": 1}], "fa": "2026-10-01T00:00:00Z", "fb": "2026-10-02T00:00:00Z", "fc": 1}),
        );
        assert_eq!(
            names(&found),
            ["days elapsed from fa to fb", "fa", "fb", "fc", "items[]"]
        );
    }

    #[test]
    fn a_row_leaves_out_the_other_terms_of_a_plus_that_reads_an_alias() {
        let found = row(
            "every items as x",
            json!("x.v plus n is 5"),
            json!({"items": [{"v": 1}], "n": 4}),
        );
        assert_eq!(names(&found), ["items[]"]);
    }

    #[test]
    fn a_row_leaves_out_the_input_a_whose_on_the_for_line_reads() {
        let found = row(
            "every items whose v is at least $input.things as x",
            json!("x.v exists"),
            json!({"items": [{"v": 1}]}),
        );
        assert_eq!(names(&found), ["items[]"]);
    }

    #[test]
    fn a_row_leaves_out_the_params_of_a_walk_and_of_a_whose_on_the_for_line() {
        let found = row(
            "every items whose v is $params.k as x",
            json!("every items.v is at least $params.k"),
            json!({"items": [{"v": 1}]}),
        );
        assert_eq!(names(&found), ["items[]", "items[].v"]);
    }

    #[test]
    fn a_pick_that_starts_at_the_first_alias_is_one_entry_holding_every_value_picked() {
        let found = row(
            "every items as x, last of x.subs as y",
            json!("y.w is 1"),
            json!({"items": [{"subs": [{"w": 1}, {"w": 2}]}, {"subs": [{"w": 3}]}]}),
        );
        let inputs = found["inputs"].as_array().unwrap();
        let picked: Vec<&Value> = inputs.iter().filter(|i| i["name"] == "x.subs[]").collect();
        assert_eq!(picked.len(), 1);
        assert_eq!(picked[0]["value"], json!([{"w": 2}, {"w": 3}]));
        assert_eq!(
            picked[0]["locations"],
            json!(["/things/0/items/0/subs/1", "/things/0/items/1/subs/0"])
        );
        assert!(!names(&found).iter().any(|n| n.starts_with("item ")));
    }

    #[test]
    fn a_pick_that_finds_nothing_lists_the_list_it_looked_in_as_a_failure_of_its_own() {
        let found = row(
            "every items as x, last of x.subs as y",
            json!("y.w is 1"),
            json!({"items": [{"subs": [{"w": 1}]}, {"subs": []}]}),
        );
        assert_eq!(
            found["failed_items"][0]["failed_items"],
            json!([{"cause": "absent", "item": "x.subs", "path": "x.subs", "value": null, "locations": []}])
        );
        let past_the_end = row(
            "every items as x, item 2 of x.subs as y",
            json!("y.w is 1"),
            json!({"items": [{"subs": [{"w": 1}]}]}),
        );
        assert_eq!(
            past_the_end["failed_items"][0]["failed_items"][0]["item"],
            "x.subs"
        );
        assert_eq!(names(&past_the_end), ["items[]", "x.subs[]"]);
    }

    #[test]
    fn a_pick_that_starts_at_another_list_still_names_the_item_where_it_is() {
        let found = row(
            "every items as x, last of ps as y",
            json!("y.w is 1"),
            json!({"items": [{"v": 1}], "ps": [{"w": 1}, {"w": 2}]}),
        );
        assert_eq!(names(&found), ["item 2 of ps", "items[]"]);
    }

    #[test]
    fn an_empty_first_list_fails_as_the_second_items_pick_does_when_that_pick_fails() {
        let line = "every items as x, first of ps as y";
        let fails = |subject: Value, cause: &str| {
            let found = row(line, json!("y exists"), subject);
            assert_eq!(found["cause"], cause);
            assert_eq!(found["failed_items"], json!([]));
        };
        fails(json!({"items": []}), "absent");
        fails(json!({"items": [], "ps": null}), "null");
        fails(json!({"items": [], "ps": 5}), "unusable");
        fails(json!({"items": [], "ps": []}), "absent");
    }

    #[test]
    fn an_empty_first_list_still_fails_as_value_when_the_second_pick_works() {
        let found = row(
            "every items as x, first of ps as y",
            json!("y exists"),
            json!({"items": [], "ps": [1]}),
        );
        assert_eq!(found["cause"], "value");
    }

    #[test]
    fn an_empty_first_list_lists_the_items_a_second_pick_tied_on() {
        let found = row(
            "every items as x, first of ps sorted by t as y",
            json!("y exists"),
            json!({"items": [], "ps": [{"t": 1}, {"t": 1}]}),
        );
        assert_eq!(found["cause"], "ambiguous");
        assert_eq!(found["failed_items"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn a_first_pick_that_finds_nothing_keeps_its_own_cause_over_the_second_pick() {
        let found = row(
            "first of items as x, first of ps as y",
            json!("y exists"),
            json!({"items": [], "ps": 5}),
        );
        assert_eq!(found["cause"], "absent");
    }

    #[test]
    fn a_params_path_named_by_an_alias_lists_the_part_before_the_name() {
        let found = row(
            "every ks as k",
            json!("$params.need named by k exists"),
            json!({"ks": ["b"]}),
        );
        assert_eq!(names(&found), ["$params.need", "ks[]"]);
    }

    #[test]
    fn a_count_whose_list_does_not_start_at_an_alias_lists_that_list() {
        let found = row(
            "every cs as c",
            json!("count of ps whose n is c.a is at least 1"),
            json!({"cs": [{"a": 1}], "ps": [{"n": 1}]}),
        );
        assert_eq!(names(&found), ["cs[]", "ps[]"]);
    }

    #[test]
    fn an_item_read_beside_a_param_keeps_its_alias() {
        let found = row(
            "every cs as c",
            json!("c.a is in $params.list"),
            json!({"cs": [{"a": "y"}]}),
        );
        assert_eq!(
            found["message"],
            "item 1 of cs: c.a is \"y\", and $params.list is [\"x\"]"
        );
    }

    #[test]
    fn a_missing_param_in_an_inner_whose_is_named_once_with_no_item() {
        let found = row(
            "every ws as w",
            json!("every w.items whose lo is at least $params.p exists"),
            json!({"ws": [{"items": [{"hi": 2}, {"lo": 5}]}]}),
        );
        assert_eq!(found["message"], "$params.p is missing");
    }

    #[test]
    fn a_sentence_root_that_cant_be_read_fails_once_before_any_item_on_an_empty_list() {
        for (subject, cause, message) in [
            (json!({"xs": []}), "absent", "z is missing"),
            (json!({"xs": [], "z": null}), "null", "z is null"),
            (
                json!({"xs": [], "z": "s"}),
                "unusable",
                "z is \"s\", which isn't a number",
            ),
            (
                json!({"xs": [{"v": 1}, {"v": 2}], "z": "s"}),
                "unusable",
                "z is \"s\", which isn't a number",
            ),
        ] {
            let found = row(
                "every xs, if any, as m",
                json!("m.v is at least z"),
                subject,
            );
            assert_eq!(found["cause"], cause);
            assert_eq!(found["message"], message);
        }
    }

    #[test]
    fn a_sentence_root_that_cant_be_read_comes_before_an_empty_list_without_if_any() {
        let found = row(
            "every xs as m",
            json!("m.v is at least $params.missing"),
            json!({"xs": []}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(found["message"], "$params.missing is missing; xs is []");
    }

    #[test]
    fn a_sentence_root_named_by_the_lines_alias_is_read_for_each_item() {
        let found = row(
            "every ks as k",
            json!("m named by k is 1"),
            json!({"ks": ["a", "b"], "m": {"a": 1}}),
        );
        assert_eq!(found["cause"], "absent");
        assert_eq!(found["message"], "item 2 of ks: m named by k is missing");
    }

    #[test]
    fn a_param_key_that_isnt_text_doesnt_name_an_item_that_isnt_an_object() {
        let found = row(
            "every ws as w",
            json!("w.k named by $params.need is 1"),
            json!({"ws": [{"k": 1}, 2]}),
        );
        assert_eq!(
            found["message"],
            "$params.need is {\"b\": 1}, which isn't text"
        );
    }

    #[test]
    fn a_key_read_from_the_item_keeps_the_alias_and_names_an_item_that_isnt_an_object() {
        let found = row(
            "every ws as w",
            json!("w.k named by w.j is 1"),
            json!({"ws": [{"k": 1, "j": "k"}, 2]}),
        );
        assert_eq!(
            found["message"],
            "item 1 of ws: w is {\"j\": \"k\", \"k\": 1}, which isn't text; item 2 of ws: w is 2, which isn't text, and w is 2, which isn't an object"
        );
    }

    #[test]
    fn an_item_that_lacks_the_field_is_still_an_object() {
        let found = row(
            "every ws as w, last of w.items as i",
            json!("i.k named by i.j is 1"),
            json!({"ws": [{"items": [{"a": 1}]}]}),
        );
        assert_eq!(
            found["message"],
            "item 1 of ws: item 1 of items: i is {\"a\": 1}, which isn't text"
        );
    }

    #[test]
    fn a_failed_assertion_lists_the_alias_before_the_path_through_it() {
        let found = row(
            "every ts as ok",
            json!("every ok.fs.k is in ok"),
            json!({"ts": [{"fs": [{"k": 1}]}]}),
        );
        let names: Vec<&Value> = found["failed_items"][0]["failed_assertions"][0]["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|input| &input["name"])
            .collect();
        assert_eq!(names, [&json!("ok"), &json!("ok.fs[].k")]);
    }

    fn pr_row(
        has: Value,
        for_line: &str,
        assertions: Value,
        fields: Value,
        params: Value,
    ) -> (String, Value) {
        let mut subject = json!({"from": "prs", "identified_by": "id"});
        if !has.is_null() {
            subject["has"] = has;
        }
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"pr": subject},
            "requirements": {"r": {"subject": "pr", "checks": {"c": {"for": for_line, "assert": assertions}}}}
        });
        let mut pr = fields;
        pr["id"] = json!("p0");
        let report = crate::report(&json!({"prs": [pr]}), &policy, &params);
        let found = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        (
            found["cause"].as_str().unwrap().to_string(),
            found["message"].clone(),
        )
    }

    #[test]
    fn a_part_that_is_not_an_object_on_the_right_of_a_list_phrase_fails_as_unusable_and_names_the_part()
     {
        for assertion in [
            "m.v is in pl.z",
            "m.v matches pl.z",
            "pl.z contains m.v",
            "m.v is at least pl.z",
        ] {
            let (cause, message) = pr_row(
                json!({"pl": "c"}),
                "every xs as m",
                json!(assertion),
                json!({"c": [], "xs": [{"v": 1}]}),
                json!({}),
            );
            assert_eq!(cause, "unusable", "{assertion}");
            assert_eq!(message, "pl is [], which isn't an object", "{assertion}");
        }
    }

    #[test]
    fn a_part_that_is_a_list_of_objects_is_not_walked_on_the_right_of_a_list_phrase() {
        let fields = json!({"c": [{"z": 1}], "xs": [{"v": 1}]});
        for assertion in ["m.v is in pl.z", "pl.z contains m.v"] {
            let (cause, message) = pr_row(
                json!({"pl": "c"}),
                "every xs as m",
                json!(assertion),
                fields.clone(),
                json!({}),
            );
            assert_eq!(cause, "unusable", "{assertion}");
            assert_eq!(
                message, "pl is [{\"z\": 1}], which isn't an object",
                "{assertion}"
            );
        }
        let (cause, message) = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!("m.v matches pl.z"),
            fields,
            json!({}),
        );
        assert_eq!(cause, "unusable");
        assert_eq!(
            message,
            "pl is [{\"z\": 1}], which isn't an object; item 1 of xs: m.v is 1, which isn't text, and pl[].z is [1], which isn't a list of patterns"
        );
    }

    #[test]
    fn a_part_that_is_text_or_null_on_the_right_of_a_list_phrase_says_so() {
        for (part, cause, message) in [
            (json!("s"), "unusable", "pl is \"s\", which isn't an object"),
            (json!(null), "null", "pl is null"),
        ] {
            let found = pr_row(
                json!({"pl": "c"}),
                "every xs as m",
                json!("m.v is in pl.z"),
                json!({"c": part, "xs": [{"v": 1}]}),
                json!({}),
            );
            assert_eq!(found, (cause.to_string(), json!(message)));
        }
    }

    #[test]
    fn a_part_that_is_an_object_with_a_list_still_works_on_the_right_of_a_list_phrase() {
        let (cause, _) = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!("m.v is in pl.z"),
            json!({"c": {"z": [1]}, "xs": [{"v": 1}]}),
            json!({}),
        );
        assert_eq!(cause, "satisfied");
    }

    #[test]
    fn a_walk_through_a_field_of_the_subject_or_the_item_is_still_read_on_the_right_of_a_list_phrase()
     {
        let fields = json!({"ws": [{"z": 1}], "xs": [{"v": 1, "ws": [{"z": 1}]}]});
        for assertion in ["m.v is in ws.z", "m.v is in m.ws.z", "m.v is in .ws.z"] {
            let (cause, _) = pr_row(
                json!(null),
                "every xs as m",
                json!(assertion),
                fields.clone(),
                json!({}),
            );
            assert_eq!(cause, "satisfied", "{assertion}");
        }
    }

    #[test]
    fn params_that_are_not_an_object_make_a_for_line_unusable_even_when_its_items_are_not_objects()
    {
        for params in [json!([]), json!(3), json!("s"), json!(true)] {
            for (for_line, assertion) in [
                ("every xs as m", "m.v is at least 1"),
                ("every xs as m", "m.v is at least $params.n"),
                ("some xs as m", "m.v is 1"),
                (
                    "every xs whose k is 1 and whose v is in $params.l as m",
                    "m.v is 1",
                ),
            ] {
                for xs in [json!(["s", {"v": "x"}]), json!([null])] {
                    let (cause, _) = pr_row(
                        json!(null),
                        for_line,
                        json!(assertion),
                        json!({"xs": xs}),
                        params.clone(),
                    );
                    assert_eq!(cause, "unusable", "{params} {for_line} {assertion} {xs}");
                }
            }
        }
    }

    #[test]
    fn params_that_are_not_an_object_leave_the_items_messages_of_a_for_line_that_does_not_read_them()
     {
        let (cause, message) = pr_row(
            json!(null),
            "every xs as m",
            json!("m.v is at least 1"),
            json!({"xs": ["s", {"v": "x"}]}),
            json!(3),
        );
        assert_eq!(cause, "unusable");
        assert_eq!(
            message,
            "item 1 of xs is \"s\", which isn't an object; item 2 of xs: v is \"x\", which isn't a number"
        );
        let (_, message) = pr_row(
            json!(null),
            "every xs as m",
            json!("m.v is at least $params.n"),
            json!({"xs": [null, "s"]}),
            json!(3),
        );
        assert_eq!(message, "$params is 3, which isn't an object");
    }

    #[test]
    fn missing_or_empty_params_leave_items_that_are_not_objects_as_not_an_object() {
        for params in [json!(null), json!({})] {
            let (cause, _) = pr_row(
                json!(null),
                "every xs as m",
                json!("m.v is at least 1"),
                json!({"xs": ["s", {"v": "x"}]}),
                params,
            );
            assert_eq!(cause, "not_an_object");
        }
    }

    #[test]
    fn a_null_item_under_a_named_by_key_says_it_is_null_once_beside_the_item_that_is_not_text() {
        for for_line in ["every xs as m", "every xs, if any, as m"] {
            let (cause, message) = pr_row(
                json!(null),
                for_line,
                json!("m.k named by m.k is 1"),
                json!({"xs": [null, {"k": "a"}]}),
                json!({}),
            );
            assert_eq!(cause, "unusable");
            assert_eq!(
                message,
                "item 1 of xs: m is null; item 2 of xs: m is {\"k\": \"a\"}, which isn't text"
            );
        }
        let (_, message) = pr_row(
            json!(null),
            "every xs as m",
            json!(["m is $params.l", "m.v named by m.v is 1"]),
            json!({"xs": [null, {"k": "a"}]}),
            json!({}),
        );
        assert_eq!(
            message,
            "$params.l is missing; item 1 of xs: m is null; item 2 of xs: m is {\"k\": \"a\"}, which isn't text"
        );
    }

    const TIED: &str = "item 1 of xs: item 1 and item 2 of xs tie on v; item 2 of xs: item 1 and item 2 of xs tie on v";
    const TIE_LINE: &str = "every xs as p, first of xs whose k is p.k sorted by v as m";

    #[test]
    fn params_that_are_not_an_object_leave_a_tie_ambiguous_when_the_check_does_not_read_them() {
        for params in [
            json!(3),
            json!([]),
            json!("s"),
            json!(true),
            json!({}),
            json!(null),
        ] {
            let (cause, message) = pr_row(
                json!(null),
                TIE_LINE,
                json!("m.v is 1"),
                json!({"xs": [{"k": "a", "v": 1}, {"k": "a", "v": 1}]}),
                params,
            );
            assert_eq!(cause, "ambiguous");
            assert_eq!(message, TIED);
        }
    }

    #[test]
    fn params_that_are_not_an_object_are_named_before_a_tie_when_the_check_reads_them() {
        for (params, said) in [
            (json!(3), "$params is 3, which isn't an object"),
            (json!([]), "$params is [], which isn't an object"),
            (json!("s"), "$params is \"s\", which isn't an object"),
            (json!(true), "$params is true, which isn't an object"),
            (json!({}), "$params.n is missing"),
            (json!(null), "$params.n is missing"),
        ] {
            let (cause, message) = pr_row(
                json!(null),
                TIE_LINE,
                json!("m.v is at least $params.n"),
                json!({"xs": [{"k": "a", "v": 1}, {"k": "a", "v": 1}]}),
                params,
            );
            assert_eq!(cause, "ambiguous");
            assert_eq!(message, format!("{said}; {TIED}"));
        }
    }

    #[test]
    fn params_that_are_not_an_object_still_fail_a_check_without_a_tie_as_unusable() {
        for params in [json!(3), json!([]), json!("s"), json!(true)] {
            for assertion in ["m.v is at least 1", "m.v is at least $params.n"] {
                let (cause, _) = pr_row(
                    json!(null),
                    "every xs as m",
                    json!(assertion),
                    json!({"xs": ["s", null]}),
                    params.clone(),
                );
                assert_eq!(cause, "unusable");
            }
        }
    }

    #[test]
    fn a_part_that_holds_a_list_fails_a_count_of_whose_under_a_for_line_as_unusable() {
        for (part, shown) in [(json!([]), "[]"), (json!([{"z": 1}]), "[{\"z\": 1}]")] {
            for xs in [json!([{"v": 1, "ys": [{"v": 1}]}]), json!([])] {
                for assertion in [
                    "count of xs whose v is in pl.z is 0",
                    "count of m.ys whose v is in pl.z is 0",
                    "count of xs whose v is in pl.z is at least 0",
                ] {
                    let (cause, message) = pr_row(
                        json!({"pl": "c"}),
                        "every xs as m",
                        json!(assertion),
                        json!({"c": part, "xs": xs}),
                        json!({}),
                    );
                    assert_eq!(cause, "unusable");
                    assert!(
                        message
                            .as_str()
                            .unwrap()
                            .starts_with(&format!("pl is {shown}, which isn't an object")),
                        "{message}"
                    );
                }
            }
        }
    }

    #[test]
    fn a_part_that_is_text_null_missing_or_an_object_with_a_list_is_read_as_before_in_a_count_of_whose()
     {
        let xs = json!([{"v": 1}]);
        for (fields, cause, said) in [
            (
                json!({"c": "s", "xs": xs}),
                "unusable",
                "pl is \"s\", which isn't an object",
            ),
            (json!({"c": null, "xs": xs}), "null", "pl is null"),
            (json!({"xs": xs}), "absent", "pl.z is missing"),
            (
                json!({"c": {"z": [1]}, "xs": xs}),
                "value",
                "count of xs whose v is in pl.z is 1",
            ),
            (json!({"c": {"z": [2]}, "xs": xs}), "satisfied", ""),
        ] {
            let (found, message) = pr_row(
                json!({"pl": "c"}),
                "every xs as m",
                json!("count of xs whose v is in pl.z is 0"),
                fields,
                json!({}),
            );
            assert_eq!(found, cause);
            assert_eq!(message.as_str().unwrap_or(""), said);
        }
    }
}
