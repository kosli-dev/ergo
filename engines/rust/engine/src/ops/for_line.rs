use super::tally::{Side, Tally, Term};
use super::time::{self, Time};
use super::walk::{self, Failure, Options, Seg, WalkItem};
use super::{Check, Input, Part, Verdict, run as run_check};
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
}

pub struct Run {
    pub verdict: Verdict,
    pub failed_items: Vec<Value>,
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
        .filter(|path| !matches!(path.start, Start::Subject))
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
                    Some(sorted) => match item_scope.path(&sorted.path) {
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
                whose: checks,
                alias: alias.clone(),
            });
        }
        bound = bound.with_for_alias(alias);
    }
    let mut problems: Vec<String> = problems
        .into_iter()
        .map(|problem| format!("for: {problem}"))
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
            Err(found) => problems.extend(found.into_iter().map(|p| format!("{place}{p}"))),
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
    order: Vec<Seg>,
    shown: Value,
    location: Location,
}

struct Dead {
    shared: bool,
    order: Vec<Seg>,
    name: String,
    path: String,
    cause: Cause,
    value: Value,
    location: Option<Location>,
}

impl Dead {
    fn of_failure(failure: &Failure) -> Dead {
        Dead {
            shared: false,
            order: failure.order.clone(),
            name: failure.item.clone(),
            path: failure.path.clone(),
            cause: failure.cause,
            value: failure.value.clone(),
            location: failure.location.clone(),
        }
    }

    fn copy(&self) -> Dead {
        Dead {
            shared: self.shared,
            order: self.order.clone(),
            name: self.name.clone(),
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
                dead: Vec::new(),
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
        };
        let mut dead: Vec<Dead> = walked.failures.iter().map(Dead::of_failure).collect();
        let from_list = walked.failures.len();
        let mut live = Vec::new();
        let mut kept = 0;
        let mut at = outer.clone();
        for w in &walked.items {
            at.subject = w.item.clone();
            let causes: Vec<Cause> = item
                .whose
                .iter()
                .map(|check| run_check(check, &at).cause)
                .collect();
            let name = walked.name_of(&w.item_segs, w.unaliased);
            let undecided = Cause::worst(
                causes
                    .iter()
                    .copied()
                    .filter(|c| !matches!(c, Cause::Satisfied | Cause::Value)),
            );
            let dead_item = |cause: Cause| Dead {
                shared: false,
                order: w.item_segs.clone(),
                name: name.clone(),
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
                    name,
                    order: w.item_segs.clone(),
                    shown: end.clone(),
                    location: w.end_location.clone(),
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
                    shared: false,
                    order: Vec::new(),
                    name: shown.clone(),
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
            let mut checks: Vec<(Live, Result<Value, Cause>, Option<Location>)> = Vec::new();
            for found in live {
                let holder = walked
                    .items
                    .iter()
                    .find(|w| w.item_segs == found.order)
                    .map(|w| w.item.clone())
                    .unwrap_or_else(|| found.at.clone());
                at.subject = holder;
                let read = path::read(&sorted.path, &at);
                let location = read.location.clone();
                let result = match (read.outcome.cause(), read.value) {
                    (Some(cause), _) => Err(cause),
                    (None, Some(value)) => Ok(value.clone()),
                    (None, None) => Err(Cause::Unusable),
                };
                checks.push((found, result, location));
            }
            let mut keys: Vec<(Live, Key, Value, Option<Location>)> = Vec::new();
            for (found, result, location) in checks {
                match result {
                    Ok(value) => match sort_key(&value, sorted.alphabetically) {
                        Some(key) => keys.push((found, key, value, location)),
                        None => failed.push(sort_failure(&found, Cause::Unusable, value, location)),
                    },
                    Err(cause) => failed.push(sort_failure(&found, cause, Value::Null, location)),
                }
            }
            if let Some(first) = keys.iter().map(|(_, k, _, _)| kind(k)).min() {
                let mut rest = Vec::new();
                for entry in keys {
                    if kind(&entry.1) == first {
                        rest.push(entry);
                    } else {
                        failed.push(sort_failure(&entry.0, Cause::Unusable, entry.2, entry.3));
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
                        shared: false,
                        order: found.order.clone(),
                        name: found.name.clone(),
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
            }
        } else {
            Input {
                name: found.name.clone(),
                value: found.shown.clone(),
                locations: vec![found.location.render()],
                part: None,
            }
        };
        cands.picked = true;
        cands.live = live;
    }
}

fn sort_failure(found: &Live, cause: Cause, value: Value, location: Option<Location>) -> Dead {
    Dead {
        shared: false,
        order: found.order.clone(),
        name: found.name.clone(),
        path: found.name.clone(),
        cause,
        value,
        location,
    }
}

struct Sfail {
    idx: usize,
    cause: Cause,
    inputs: Vec<Value>,
}

struct Child {
    order: Vec<Seg>,
    entry: Dead,
    failed: Option<Outcome>,
    sfails: Vec<Sfail>,
}

struct Outcome {
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
            let dead = if depth > 0 {
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
                vec![Dead {
                    shared: !reads_path(&item.path, &self.items[0].alias),
                    order: Vec::new(),
                    name: shown.clone(),
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
                shared: false,
                order: live.order.clone(),
                name: live.name.clone(),
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
            };
            let (outcome, sfails) = if into_non_object {
                (
                    Some(Outcome {
                        cause: Cause::NotAnObject,
                        assertions: Vec::new(),
                        inner: Vec::new(),
                    }),
                    Vec::new(),
                )
            } else if last {
                self.try_sentences(&bound)
            } else {
                let nested = self.level(depth + 1, &bound, collect);
                if nested.cause == Cause::Satisfied {
                    (None, Vec::new())
                } else {
                    let assertions = self.aggregate(&nested.children);
                    (
                        Some(Outcome {
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

    fn try_sentences(&self, ctx: &Ctx) -> (Option<Outcome>, Vec<Sfail>) {
        let mut sfails = Vec::new();
        for (idx, sentence) in self.sentences.iter().enumerate() {
            let verdict = run_check(&sentence.check, ctx);
            if !verdict.passed() {
                sfails.push(Sfail {
                    idx,
                    cause: verdict.cause,
                    inputs: reading_order(&sentence.check, &verdict.inputs, &self.alias_names())
                        .iter()
                        .map(Input::to_json)
                        .collect(),
                });
            }
        }
        match Cause::worst(sfails.iter().map(|f| f.cause)) {
            None => (None, sfails),
            Some(cause) => {
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
                (
                    Some(Outcome {
                        cause,
                        assertions,
                        inner: Vec::new(),
                    }),
                    sfails,
                )
            }
        }
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
            let (found, whose) = match &sentence.check {
                Check::Tally(tally) => tally_paths(tally, &hidden),
                other => (all_paths(other), Vec::new()),
            };
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
            if matches!(path.start, Start::Params) && in_walk.contains(&std::ptr::from_ref(path)) {
                continue;
            }
            match own {
                Some((_, if_any)) if !hides(path) && walk::cut_at(path, &hidden).is_none() => {
                    inputs.push(self.list_entry(path, *if_any, ctx));
                }
                _ if in_whose.contains(&std::ptr::from_ref(path)) => {
                    inputs.extend(walk::path_inputs(path, &outer_ctx(ctx), &hidden));
                }
                _ => inputs.extend(walk::path_inputs(path, ctx, &hidden)),
            }
        }
        for sentence in &self.sentences {
            if let Check::Tally(tally) = &sentence.check {
                inputs.extend(tally.unaliased_entries(ctx, &hidden));
            }
        }
        inputs
    }

    pub fn run(&self, ctx: &Ctx) -> Run {
        let first = &self.items[0];
        if walk::path_needs_an_object_subject(&first.path, ctx) {
            return Run {
                verdict: Verdict {
                    cause: Cause::NotAnObject,
                    inputs: Vec::new(),
                },
                failed_items: Vec::new(),
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
            .any(|check| check.flawed(&outer));
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
        let failed = if let Some((_, listed)) = second {
            listed
        } else if cause == Cause::Satisfied || flawed {
            Vec::new()
        } else {
            self.failed_items(level)
        };
        Run {
            verdict: Verdict { cause, inputs },
            failed_items: failed,
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
        Some((
            cause,
            dead.into_iter()
                .map(|d| d.json(Vec::new(), Vec::new()))
                .collect(),
        ))
    }

    fn failed_items(&self, level: Level) -> Vec<Value> {
        let mut failed: Vec<(Vec<Seg>, Value)> = level
            .dead
            .iter()
            .map(|d| (d.order.clone(), d.json(Vec::new(), Vec::new())))
            .collect();
        let mut hoisted: Vec<Dead> = Vec::new();
        for child in level.children {
            let Child {
                order,
                mut entry,
                failed: outcome,
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
            failed.push((order, entry.json(outcome.assertions, inner)));
        }
        for entry in hoisted {
            failed.push((entry.order.clone(), entry.json(Vec::new(), Vec::new())));
        }
        failed.sort_by(|a, b| a.0.cmp(&b.0));
        failed.into_iter().map(|(_, v)| v).collect()
    }

    fn shared_second(&self) -> bool {
        self.items.len() == 2 && !reads_path(&self.items[1].path, &self.items[0].alias)
    }
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
    let (through, rest): (Vec<Input>, Vec<Input>) = ordered.into_iter().partition(|input| {
        aliases.iter().any(|alias| {
            input
                .name
                .strip_prefix(alias)
                .is_some_and(|rest| rest.starts_with(['.', '[']))
        })
    });
    through.into_iter().chain(rest).collect()
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    fn row(for_line: &str, assertions: Value, subject: Value) -> Value {
        let policy = json!({
            "ergo_spec": "v0.3-dev",
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
            "ergo_spec": "v0.3-dev",
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
            "ergo_spec": "v0.3-dev",
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
            "ergo_spec": "v0.3-dev",
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
    fn a_whose_ref_that_is_not_a_list_fails_the_check_as_unusable_with_no_failed_items() {
        let found = row(
            "every xs whose kind is in $params.kinds as x",
            json!("x.ok is true"),
            json!({"xs": [{"kind": "code", "ok": false}]}),
        );
        assert_eq!(found["cause"], "unusable");
        assert_eq!(found["failed_items"], json!([]));
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
}
