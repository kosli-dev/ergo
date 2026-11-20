use super::clause::Clause;
use super::message;
use super::{Check, Input, SidePath, Verdict, read_path, run as run_check};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Located, Location, OUTER, Outcome, Path, Resolved, Start, Step};
use serde_json::{Value, json};
use std::collections::BTreeSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quantifier {
    Every,
    Some,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Walk {
    pub quantifier: Quantifier,
    pub path: Path,
    pub distinct: bool,
    pub whose: Vec<Check>,
    pub if_any: bool,
    pub check: Box<Check>,
    pub for_aliases: Vec<String>,
}

impl Walk {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        let outer = outer(ctx);
        self.whose
            .iter()
            .chain(std::iter::once(&*self.check))
            .any(|check| check.flawed(&outer))
    }

    pub fn refs(&self) -> Vec<Path> {
        let mut refs = path::step_refs(&self.path);
        for check in self.whose.iter().chain(std::iter::once(&*self.check)) {
            refs.extend(check.refs());
        }
        refs
    }

    pub fn walking_refs(&self) -> Vec<Path> {
        self.whose
            .iter()
            .chain(std::iter::once(&*self.check))
            .flat_map(Check::walking_refs)
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Seg {
    Index(u64),
    Key(String),
}

impl Seg {
    pub fn to_step(&self) -> Step {
        match self {
            Seg::Index(at) => Step::Index(*at),
            Seg::Key(key) => Step::Key(key.clone()),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Options {
    pub if_any: bool,
    pub empty_adds_nothing: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Failure {
    pub order: Vec<Seg>,
    pub path: String,
    pub item: String,
    pub said: String,
    pub rank: Vec<Rank>,
    pub cause: Cause,
    pub value: Value,
    pub location: Option<Location>,
    pub copies: Vec<String>,
    pub msg: String,
    pub seen: Option<(Value, Location)>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Rank {
    Index(u64),
    Text(String),
}

fn rank_of(start: &Start, segs: &[Seg]) -> Vec<Rank> {
    let mut rank = match start {
        Start::Subject | Start::Own => Vec::new(),
        Start::Alias(alias) => vec![Rank::Text(format!("${alias}"))],
        Start::Part(_) if path::is_root(start) => vec![Rank::Text("${\"alias\":\"\"".to_string())],
        Start::Part(part) => vec![Rank::Text(format!("${{\"alias\":\"{}\"", part.name))],
        Start::Params => vec![Rank::Text("$$params".to_string())],
        Start::Input => vec![Rank::Text("$$input".to_string())],
    };
    rank.extend(segs.iter().map(|seg| match seg {
        Seg::Index(at) => Rank::Index(*at),
        Seg::Key(key) => Rank::Text(key.clone()),
    }));
    rank
}

fn rank_of_path(path: &Path) -> Vec<Rank> {
    let segs: Vec<Seg> = path::leading_steps(&path.start)
        .iter()
        .chain(path.steps.iter())
        .map(|step| match step {
            Step::Index(at) => Seg::Index(*at),
            Step::Key(key) => Seg::Key(key.clone()),
            Step::Ref(_) | Step::Field(_) => Seg::Key(String::new()),
        })
        .collect();
    rank_of(&path.start, &segs)
}

impl Failure {
    pub fn to_json(&self) -> Value {
        let mut locations: Vec<String> = self.location.iter().map(Location::render).collect();
        locations.extend(self.copies.iter().cloned());
        json!({
            "path": self.path,
            "item": self.item,
            "cause": self.cause.name(),
            "value": self.value,
            "locations": locations,
        })
    }

    /// The failed item as `to_json` gives it, with what the row's `failures`
    /// also need: its text, and the item it sits in.
    pub fn to_rich_json(&self) -> Value {
        let mut entry = self.to_json();
        entry["ergo/text"] = json!(self.msg);
        if let Some((value, location)) = &self.seen {
            let mut places = vec![location.render()];
            places.extend(self.copies.iter().cloned());
            entry["ergo/item"] = json!({"value": value, "locations": places});
        }
        entry
    }
}

#[derive(Debug, Clone)]
pub struct WalkItem<'a> {
    pub item: Located<'a>,
    pub item_segs: Vec<Seg>,
    pub rest: Vec<Seg>,
    pub end: Option<&'a Value>,
    pub miss: Cause,
    pub end_location: Location,
    pub end_segs: Vec<Seg>,
    pub unaliased: bool,
}

impl WalkItem<'_> {
    pub fn shown(&self) -> Value {
        self.end.cloned().unwrap_or(Value::Null)
    }

    pub fn rest_path(&self) -> Path {
        Path {
            start: Start::Subject,
            steps: self.rest.iter().map(Seg::to_step).collect(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Walked<'a> {
    pub items: Vec<WalkItem<'a>>,
    pub failures: Vec<Failure>,
    pub walked: BTreeSet<usize>,
    pub steps: usize,
    pub name: String,
    pub unreadable: Option<Outcome>,
    start: Start,
    keeps_dot: bool,
}

impl Walked<'_> {
    pub fn walked_last(&self) -> bool {
        self.walked.contains(&self.steps)
    }

    pub fn name_of(&self, segs: &[Seg], unaliased: bool) -> String {
        self.name_of_steps(segs.iter().map(Seg::to_step).collect(), unaliased)
    }

    pub fn item_name(&self, segs: &[Seg]) -> String {
        self.item_name_with(segs, self.keeps_dot)
    }

    pub fn item_name_dotted(&self, segs: &[Seg]) -> String {
        self.item_name_with(segs, true)
    }

    fn item_name_with(&self, segs: &[Seg], own_dot: bool) -> String {
        let indexes: Vec<usize> = segs
            .iter()
            .enumerate()
            .filter(|(_, seg)| matches!(seg, Seg::Index(_)))
            .map(|(at, _)| at)
            .collect();
        let Some(first) = indexes.first() else {
            if let Start::Part(part) = &self.start
                && segs.len() < part.steps.len()
            {
                return format!("{} can't be read: {}", part.name, self.name_of(segs, true));
            }
            return self.said_name(segs, own_dot);
        };
        let plain = |segs: &[Seg]| {
            name::name(&Path {
                start: Start::Subject,
                steps: segs.iter().map(Seg::to_step).collect(),
            })
        };
        let mut parts = vec![self.said_name(&segs[..=*first], own_dot)];
        for pair in indexes.windows(2) {
            let Seg::Index(at) = &segs[pair[1]] else {
                continue;
            };
            let between = &segs[pair[0] + 1..pair[1]];
            parts.push(format!(
                "item {} of {}",
                at + 1,
                if between.is_empty() {
                    "it".to_string()
                } else {
                    plain(between)
                }
            ));
        }
        let tail = &segs[indexes[indexes.len() - 1] + 1..];
        if !tail.is_empty() {
            parts.push(plain(tail));
        }
        parts.join(": ")
    }

    fn said_name(&self, segs: &[Seg], own_dot: bool) -> String {
        let steps: Vec<Step> = segs.iter().map(Seg::to_step).collect();
        match &self.start {
            Start::Part(part)
                if steps.len() >= part.steps.len()
                    && !steps[..part.steps.len()]
                        .iter()
                        .any(|step| matches!(step, Step::Index(_))) =>
            {
                name::name(&named(&self.start, steps, false))
            }
            Start::Own if !own_dot => name::name(&Path {
                start: Start::Subject,
                steps,
            }),
            _ => name::name(&named(&self.start, steps, true)),
        }
    }

    pub fn name_of_steps(&self, steps: Vec<Step>, unaliased: bool) -> String {
        name::name(&named(&self.start, steps, unaliased))
    }
}

fn named(start: &Start, steps: Vec<Step>, unaliased: bool) -> Path {
    match start {
        Start::Part(part) if unaliased => Path {
            start: part.base.clone(),
            steps,
        },
        Start::Part(part) => Path {
            start: start.clone(),
            steps: steps.into_iter().skip(part.steps.len()).collect(),
        },
        _ => Path {
            start: start.clone(),
            steps,
        },
    }
}

#[derive(Clone)]
enum Val<'a> {
    Found(&'a Value),
    Absent,
    Unusable,
}

impl<'a> Val<'a> {
    fn gone(&self) -> bool {
        matches!(self, Val::Absent | Val::Found(Value::Null))
    }

    fn cause(&self) -> Cause {
        match self {
            Val::Absent => Cause::Absent,
            Val::Found(Value::Null) => Cause::Null,
            _ => Cause::Unusable,
        }
    }

    fn shown(&self) -> Value {
        match self {
            Val::Found(value) => (*value).clone(),
            _ => Value::Null,
        }
    }

    fn container(&self) -> bool {
        matches!(self, Val::Found(Value::Object(_) | Value::Array(_)))
    }

    fn array(&self) -> Option<&'a Vec<Value>> {
        match self {
            Val::Found(Value::Array(items)) => Some(items),
            _ => None,
        }
    }

    fn read(&self, seg: &Seg, location: &Location) -> (Val<'a>, Location) {
        match (self, seg) {
            (Val::Found(Value::Object(map)), Seg::Key(key)) => match map.get(key) {
                Some(next) => (Val::Found(next), location.key(key)),
                None => (Val::Absent, location.clone()),
            },
            (Val::Found(Value::Array(items)), Seg::Index(at)) => {
                match usize::try_from(*at).ok().and_then(|i| items.get(i)) {
                    Some(next) => (Val::Found(next), location.index(*at)),
                    None => (Val::Absent, location.clone()),
                }
            }
            _ if self.gone() => (Val::Absent, location.clone()),
            _ => (Val::Unusable, location.clone()),
        }
    }
}

#[derive(Clone)]
struct ItemAt<'a> {
    segs: Vec<Seg>,
    at: Located<'a>,
}

#[derive(Clone)]
struct Entry<'a> {
    segs: Vec<Seg>,
    val: Val<'a>,
    location: Location,
    item: Option<ItemAt<'a>>,
    rest: Vec<Seg>,
    unaliased: bool,
}

struct Raw {
    kind: &'static str,
    segs: Vec<Seg>,
    unaliased: bool,
    cause: Cause,
    value: Value,
    location: Location,
}

fn failed(entry: &Entry, cause: Cause, value: Value, kind: &'static str) -> Raw {
    Raw {
        kind,
        segs: entry.segs.clone(),
        unaliased: entry.unaliased,
        cause,
        value,
        location: entry.location.clone(),
    }
}

fn before_field(path: &Path, at: usize, ctx: &Ctx) -> Option<Outcome> {
    let upto = |end: usize| Path {
        start: path.start.clone(),
        steps: path.steps[..end].to_vec(),
    };
    let walks = (0..at).any(|end| {
        matches!(path.steps[end], Step::Key(_))
            && matches!(path::read(&upto(end), ctx).value, Some(Value::Array(_)))
    });
    if walks {
        return None;
    }
    if (1..at).any(|end| matches!(path::read(&upto(end), ctx).value, Some(Value::Null))) {
        return Some(Outcome::Null);
    }
    match path::read(&upto(at), ctx).outcome {
        Outcome::Found | Outcome::Null => None,
        outcome => Some(outcome),
    }
}

pub fn walk<'a>(path: &Path, ctx: &Ctx<'a>, options: Options) -> Walked<'a> {
    let leading = path::leading_steps(&path.start);
    let mut segs = Vec::new();
    for (at, step) in leading.iter().chain(path.steps.iter()).enumerate() {
        match path::resolve(step, ctx) {
            Ok(Resolved::Key(key)) => segs.push(Seg::Key(key)),
            Ok(Resolved::Index(at)) => segs.push(Seg::Index(at)),
            Err(outcome) => {
                let before = match step {
                    Step::Field(_) => at
                        .checked_sub(leading.len())
                        .and_then(|own| before_field(path, own, ctx).map(|outcome| (own, outcome))),
                    _ => None,
                };
                let failures = match before {
                    Some((own, Outcome::Null)) => {
                        let prefix = Path {
                            start: path.start.clone(),
                            steps: path.steps[..own].to_vec(),
                        };
                        walk(&prefix, ctx, Options::default()).failures
                    }
                    _ => Vec::new(),
                };
                let outcome = before.map_or(outcome, |(_, outcome)| outcome);
                return Walked {
                    items: Vec::new(),
                    failures,
                    walked: BTreeSet::new(),
                    steps: segs.len(),
                    name: name::name(path),
                    unreadable: Some(outcome),
                    start: path.start.clone(),
                    keeps_dot: false,
                };
            }
        }
    }
    let total = segs.len();
    let empty_ok = options.if_any || options.empty_adds_nothing;
    let (val, location) = match path::start_of(&path.start, ctx) {
        Ok((value, location, _)) => (Val::Found(value), location),
        Err(read) => (
            Val::Absent,
            read.location.unwrap_or_else(Location::input_root),
        ),
    };
    let mut entries = vec![Entry {
        segs: Vec::new(),
        val,
        location,
        item: None,
        rest: Vec::new(),
        unaliased: false,
    }];
    let mut trail = vec![(
        entries[0].segs.clone(),
        entries[0].val.clone(),
        entries[0].location.clone(),
    )];
    let mut walked = BTreeSet::new();
    let mut raws: Vec<Raw> = Vec::new();
    for level in 0..=total {
        let seg = segs.get(level);
        let walks_here = entries.iter().any(|entry| {
            entry.val.array().is_some() && seg.is_none_or(|seg| !matches!(seg, Seg::Index(_)))
        });
        if walks_here {
            walked.insert(level);
            let inside = path::leading_steps(&path.start).len();
            let aliased_away = level > 0 && level < inside;
            let mut next = Vec::new();
            for entry in entries {
                match entry.val.array() {
                    Some(items) => {
                        if items.is_empty() && !empty_ok {
                            raws.push(failed(&entry, Cause::Value, json!([]), "a list"));
                        }
                        for (at, value) in items.iter().enumerate() {
                            let mut item_segs = entry.segs.clone();
                            item_segs.push(Seg::Index(at as u64));
                            let location = entry.location.index(at as u64);
                            next.push(Entry {
                                segs: item_segs.clone(),
                                val: Val::Found(value),
                                location: location.clone(),
                                item: Some(ItemAt {
                                    segs: item_segs,
                                    at: Located { value, location },
                                }),
                                rest: Vec::new(),
                                unaliased: entry.unaliased || aliased_away,
                            });
                        }
                    }
                    None => raws.push(failed(
                        &entry,
                        entry.val.cause(),
                        entry.val.shown(),
                        "a list",
                    )),
                }
            }
            entries = next;
        }
        if let Some(seg) = seg {
            for entry in &mut entries {
                let (val, location) = entry.val.read(seg, &entry.location);
                entry.val = val;
                entry.location = location;
                entry.segs.push(seg.clone());
                entry.rest.push(seg.clone());
            }
            if entries.len() == 1 {
                trail.push((
                    entries[0].segs.clone(),
                    entries[0].val.clone(),
                    entries[0].location.clone(),
                ));
            }
        }
    }
    if walked.is_empty() {
        let stopped = trail
            .iter()
            .find(|(_, val, _)| !val.container())
            .or(trail.last());
        if let Some((stop_segs, val, location)) = stopped {
            raws.push(Raw {
                kind: if matches!(val.shown(), Value::Object(_)) {
                    "a list"
                } else {
                    "a list or an object"
                },
                segs: stop_segs.clone(),
                unaliased: false,
                cause: if val.gone() {
                    val.cause()
                } else {
                    Cause::Unusable
                },
                value: val.shown(),
                location: location.clone(),
            });
        }
    }
    let mut marks = walked.clone();
    let shown_path = match &path.start {
        Start::Part(part) => {
            let inside = part.steps.len();
            if walked.iter().any(|at| *at > 0 && *at < inside) {
                Path {
                    start: part.base.clone(),
                    steps: leading.iter().chain(path.steps.iter()).cloned().collect(),
                }
            } else {
                marks = walked
                    .iter()
                    .filter(|at| **at >= inside)
                    .map(|at| at - inside)
                    .collect();
                path.clone()
            }
        }
        _ => path.clone(),
    };
    let shown_name = name::marked_name(&shown_path, &marks);
    let items = entries
        .into_iter()
        .filter_map(|entry| {
            let item = entry.item?;
            let miss =
                if !item.at.value.is_object() && matches!(entry.rest.first(), Some(Seg::Key(_))) {
                    Cause::NotAnObject
                } else {
                    entry.val.cause()
                };
            let end = match entry.val {
                Val::Found(value) => Some(value),
                _ => None,
            };
            Some(WalkItem {
                item: item.at,
                item_segs: item.segs,
                rest: entry.rest,
                end,
                miss,
                end_location: entry.location,
                end_segs: entry.segs,
                unaliased: entry.unaliased,
            })
        })
        .collect();
    let mut walked_all = Walked {
        items,
        failures: Vec::new(),
        walked,
        steps: total,
        name: shown_name,
        unreadable: None,
        start: path.start.clone(),
        keeps_dot: path.start == Start::Own,
    };
    let mut failures: Vec<Failure> = raws
        .into_iter()
        .map(|raw| Failure {
            path: walked_all.name_of(&raw.segs, raw.unaliased),
            item: walked_all.name_of(&raw.segs, raw.unaliased),
            said: walked_all.item_name_dotted(&raw.segs),
            rank: rank_of(&path.start, &raw.segs),
            msg: message::stated(
                &walked_all.item_name(&raw.segs),
                raw.cause,
                &raw.value,
                raw.kind,
            ),
            order: raw.segs,
            cause: raw.cause,
            value: raw.value,
            location: Some(raw.location),
            copies: Vec::new(),
            seen: None,
        })
        .collect();
    failures.sort_by(|a, b| a.order.cmp(&b.order));
    walked_all.failures = failures;
    walked_all
}

#[derive(Debug, Clone, PartialEq)]
pub struct Run {
    pub verdict: Verdict,
    pub failed_items: Vec<Value>,
    pub rich: Vec<Value>,
    pub message: Option<String>,
    pub parts: Vec<String>,
}

/// The name of the first list a walk reads, as its inputs name it, like `xs`
/// for `every xs.ys.n is 1`.
pub fn first_list_name(walk: &Walk, ctx: &Ctx) -> Option<String> {
    let walked = self::walk(&walk.path, &outer(ctx), Options::default());
    walked
        .name
        .split_once("[]")
        .map(|(base, _)| base.to_string())
}

/// The names a walk's own list read goes by in the row's inputs, like
/// `xs[].v` and `xs.v` for `every xs.v is 1`.
pub fn walked_names(walk: &Walk, ctx: &Ctx) -> Vec<String> {
    let walked = self::walk(&walk.path, &outer(ctx), Options::default());
    vec![walked.name, name::name(&walk.path)]
}

fn outer<'a>(ctx: &Ctx<'a>) -> Ctx<'a> {
    let mut outer = ctx.clone();
    outer.aliases.insert(OUTER.to_string(), ctx.subject.clone());
    outer
}

pub(super) fn reads_outside(path: &Path) -> bool {
    matches!(path.start, Start::Alias(_) | Start::Part(_) | Start::Input)
}

pub(super) fn through_a_list(path: &Path, ctx: &Ctx) -> bool {
    (0..path.steps.len()).any(|at| {
        let before = Path {
            start: path.start.clone(),
            steps: path.steps[..at].to_vec(),
        };
        path::read(&before, ctx).value.is_some_and(Value::is_array)
    })
}

fn outside_inputs(walk: &Walk, ctx: &Ctx) -> Vec<Input> {
    let checks: Vec<&Check> = walk
        .whose
        .iter()
        .chain(std::iter::once(&*walk.check))
        .collect();
    outside_inputs_of(&checks, ctx)
        .into_iter()
        .filter(|input| {
            !walk.for_aliases.iter().any(|alias| {
                input
                    .name
                    .strip_prefix(alias.as_str())
                    .is_some_and(|rest| rest.starts_with(" named by "))
                    && checks.iter().any(|check| {
                        check.paths().into_iter().any(|path| {
                            matches!(&path.start, Start::Alias(name) if name == alias)
                                && has_root_field(path)
                                && name::name(path) == input.name
                        })
                    })
            })
        })
        .collect()
}

pub(super) fn outside_inputs_of(checks: &[&Check], ctx: &Ctx) -> Vec<Input> {
    let mut inputs = Vec::new();
    for check in checks {
        for path in check
            .paths()
            .into_iter()
            .chain(super::lists::named_refs(check))
            .filter(|p| {
                reads_outside(p)
                    || (matches!(p.start, Start::Params | Start::Subject | Start::Own)
                        && has_root_field(p))
            })
        {
            match listed_input(check, path, ctx) {
                Some(input) => inputs.push(input),
                None => inputs.extend(path_inputs(path, ctx, &[], true)),
            }
        }
        inputs.extend(super::lists::ref_inputs(check, ctx, false));
    }
    inputs
}

pub(super) fn listed_outside_inputs(checks: &[&Check], ctx: &Ctx) -> Vec<Input> {
    let mut inputs = Vec::new();
    for check in checks {
        for path in check.paths().into_iter().filter(|p| reads_outside(p)) {
            inputs.extend(listed_input(check, path, ctx));
        }
        inputs.extend(super::lists::ref_inputs(check, ctx, false));
    }
    inputs
}

pub(super) fn listed_input(check: &Check, path: &Path, ctx: &Ctx) -> Option<Input> {
    if matches!(path.start, Start::Params) {
        return None;
    }
    if super::lists::walked_right(check).is_some_and(|right| std::ptr::eq(right, path)) {
        if matches!(path.start, Start::Input) {
            return None;
        }
        return super::lists::walked(path, ctx).map(|walked| walked.input());
    }
    match check {
        Check::Tally(tally)
            if tally
                .counted_paths()
                .into_iter()
                .any(|counted| std::ptr::eq(counted, path))
                && super::lists::walked(path, ctx).is_some() =>
        {
            Some(super::tally::counted_list(path, ctx))
        }
        _ => None,
    }
}

fn hides(path: &Path, hidden: &[&str]) -> bool {
    matches!(&path.start, Start::Alias(name) if hidden.contains(&name.as_str()))
}

pub(super) fn cut_at(path: &Path, hidden: &[&str], fields_read_items: bool) -> Option<usize> {
    path.steps.iter().position(|step| match step {
        Step::Field(_) => fields_read_items,
        Step::Ref(reference) => hides(reference, hidden),
        _ => false,
    })
}

pub(super) fn has_root_field(path: &Path) -> bool {
    path.steps.iter().any(|step| {
        matches!(step, Step::Field(field)
            if path::is_root(&field.start) || path::names_the_subject(&field.start))
    })
}

fn field_input(field: &Path, ctx: &Ctx) -> Option<Input> {
    let mut input = read_path(field, ctx).inputs.into_iter().next()?;
    if path::names_the_subject(&field.start) {
        input.name = name::name(&Path {
            start: path::root(false),
            steps: field.steps.clone(),
        });
    }
    Some(input)
}

pub(super) fn path_inputs(
    path: &Path,
    ctx: &Ctx,
    hidden: &[&str],
    fields_read_items: bool,
) -> Vec<Input> {
    let mut at = ctx.clone();
    if !at.aliases.contains_key(OUTER) {
        at.aliases.insert(OUTER.to_string(), ctx.subject.clone());
    }
    if fields_read_items
        && (path::is_root(&path.start) || has_root_field(path))
        && !hides(path, hidden)
    {
        let mut inputs = if matches!(path.start, Start::Subject | Start::Own) {
            Vec::new()
        } else {
            path_inputs(path, &at, hidden, false)
        };
        inputs.extend(path.steps.iter().filter_map(|step| match step {
            Step::Field(field) => field_input(field, &at),
            _ => None,
        }));
        return inputs;
    }
    if hides(path, hidden) {
        return path
            .steps
            .iter()
            .filter_map(|step| match step {
                Step::Field(field)
                    if path::is_root(&field.start) || path::names_the_subject(&field.start) =>
                {
                    field_input(field, &at).map(|input| vec![input])
                }
                Step::Field(field) => Some(read_path(field, &at).inputs),
                _ => None,
            })
            .flatten()
            .collect();
    }
    match cut_at(path, hidden, fields_read_items) {
        None => read_path(path, ctx).inputs,
        Some(at) => {
            let before = Path {
                start: path.start.clone(),
                steps: path.steps[..at].to_vec(),
            };
            if through_a_list(&before, ctx) {
                Vec::new()
            } else {
                read_path(&before, ctx).inputs
            }
        }
    }
}

fn subject_is_not_an_object(walk: &Walk, ctx: &Ctx) -> bool {
    path_needs_an_object_subject(&walk.path, ctx)
}

pub(super) fn path_needs_an_object_subject(path: &Path, ctx: &Ctx) -> bool {
    if ctx.subject.value.is_object() {
        return false;
    }
    match &path.start {
        Start::Subject | Start::Own => !matches!(path.steps.first(), None | Some(Step::Index(_))),
        Start::Part(part) => {
            part.base == Start::Subject
                && !(part.steps.is_empty()
                    && (ctx.subject.value.is_array()
                        || matches!(path.steps.first(), None | Some(Step::Index(_)))))
        }
        _ => false,
    }
}

fn seg_of(step: &Step) -> Seg {
    match step {
        Step::Index(at) => Seg::Index(*at),
        Step::Key(key) => Seg::Key(key.clone()),
        _ => Seg::Key(String::new()),
    }
}

fn side_read<'a>(
    paths: &[SidePath<'a>],
    ctx: &Ctx<'a>,
) -> Option<(&'a Path, path::Read<'a>, bool)> {
    let mut first = None;
    for side in paths {
        let read = path::read(side.path, ctx);
        let is_read = read.outcome == Outcome::Found
            && (!side.needs_list || read.value.is_some_and(Value::is_array));
        if !is_read {
            return Some((side.path, read, false));
        }
        if first.is_none() {
            first = Some((side.path, read));
        }
    }
    first.map(|(path, read)| (path, read, true))
}

pub(super) fn named_side<'a>(
    check: &'a Check,
    ctx: &Ctx<'a>,
) -> Option<(&'a Path, path::Read<'a>)> {
    let sides = check.sides();
    let mut sides = sides.iter().map(|paths| side_read(paths, ctx));
    let left = sides.next().flatten();
    let right = sides.next().flatten();
    let right_alone = left.as_ref().is_none_or(|(_, _, read)| *read)
        && right.as_ref().is_some_and(|(_, _, read)| !*read);
    let (path, read, _) = if right_alone { right } else { left }?;
    Some((path, read))
}

struct Judged {
    kept: bool,
    passed: bool,
    decided: bool,
    failure: Option<Failure>,
}

fn merged_copies(walked: &Walked, judged: Vec<Judged>) -> Vec<Judged> {
    let mut out: Vec<Judged> = Vec::new();
    let mut seen: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
    for (item, j) in walked.items.iter().zip(judged) {
        let key = match item.end {
            Some(end) if j.kept && j.decided => crate::value::copy_key(end),
            _ => {
                out.push(j);
                continue;
            }
        };
        match seen.get(&key) {
            Some(&at) => {
                if let Some(failure) = &mut out[at].failure {
                    failure.copies.push(item.end_location.render());
                }
            }
            None => {
                seen.insert(key, out.len());
                out.push(j);
            }
        }
    }
    out
}

pub(super) fn reads_focus(check: &Check) -> bool {
    check
        .paths()
        .iter()
        .any(|path| matches!(path.start, Start::Subject | Start::Own))
}

pub(super) fn focus_ctx<'a>(item: &WalkItem<'a>, ctx: &Ctx<'a>) -> Ctx<'a> {
    let mut focus = ctx.clone();
    focus.label = None;
    focus.subject = match item.end {
        Some(end) if !item.rest.is_empty() => Located {
            value: end,
            location: item.end_location.clone(),
        },
        _ => item.item.clone(),
    };
    focus
}

pub(super) fn focus_lost(item: &WalkItem, check: &Check) -> bool {
    !item.rest.is_empty() && item.end.is_none() && reads_focus(check)
}

pub(super) fn focus_check(item: &WalkItem) -> Check {
    Check::Present(super::present::Present {
        path: item.rest_path(),
        missing: false,
    })
}

pub(super) fn focus_verdict(
    check: &Check,
    item: &WalkItem,
    at: &Ctx,
    focus: &Ctx,
) -> (Verdict, bool) {
    if focus_lost(item, check) {
        (lost_verdict(item, at), true)
    } else {
        (run_check(check, focus), false)
    }
}

pub(super) fn lost_verdict(item: &WalkItem, at: &Ctx) -> Verdict {
    Verdict {
        cause: path::read(&item.rest_path(), at)
            .outcome
            .cause()
            .unwrap_or(Cause::Unusable),
        inputs: Vec::new(),
    }
}

fn from_a_root(path: &Path) -> bool {
    matches!(
        path.start,
        Start::Alias(_) | Start::Part(_) | Start::Params | Start::Input
    ) && !path.steps.iter().any(|step| {
        matches!(step, Step::Field(field) if matches!(field.start, Start::Subject | Start::Own))
    })
}

pub(super) fn right_needs(check: &Check, value: &Value) -> Option<&'static str> {
    use super::compare::Cmp;
    match check {
        Check::Compare(compare) => match compare.cmp {
            Cmp::Gt | Cmp::Gte | Cmp::Lt | Cmp::Lte => (!value.is_number()).then_some("a number"),
            Cmp::StartsWith
            | Cmp::EndsWith
            | Cmp::NotStartsWith
            | Cmp::NotEndsWith
            | Cmp::AlphabeticallyBefore
            | Cmp::AlphabeticallyAfter
            | Cmp::AlphabeticallyOnOrBefore
            | Cmp::AlphabeticallyOnOrAfter => (!value.is_string()).then_some("text"),
            Cmp::Eq | Cmp::Ne => None,
        },
        Check::CompareTime(_) => super::time::read_time(value).is_none().then_some("a time"),
        Check::In(_) | Check::Contains(_) | Check::Matches(_) => {
            (!value.is_array()).then_some("a list")
        }
        _ => None,
    }
}

pub(super) fn listed_refs(check: &Check) -> Vec<&Path> {
    use super::lists::Wanted;
    match check {
        Check::In(check) => check.values.ref_paths(),
        Check::Matches(check) => check.patterns.ref_paths(),
        Check::Contains(check) => match &check.wanted {
            Wanted::One(right) | Wanted::All(right) | Wanted::Some(right) => right.ref_paths(),
        },
        _ => Vec::new(),
    }
}

fn root_alone(check: &Check, ctx: &Ctx, cause: Cause) -> Option<String> {
    check
        .paths()
        .into_iter()
        .chain(listed_refs(check))
        .filter(|path| from_a_root(path))
        .find_map(|path| {
            let listed = super::lists::right_paths(check)
                .contains(&path)
                .then(|| super::lists::walked_in(check, path, ctx))
                .flatten();
            if listed.is_some() {
                return super::lists::walked_root_fault(check, path, ctx)
                    .filter(|(found, _)| *found == cause)
                    .map(|(_, text)| text);
            }
            let read = path::read(path, ctx);
            let state = read.outcome.cause();
            if matches!(cause, Cause::Absent | Cause::Null | Cause::Unusable)
                && state == Some(cause)
            {
                let parts = message::null_key_parts(path, ctx);
                if !parts.is_empty() {
                    return Some(parts.join("; "));
                }
                return Some(message::root_text(path, ctx, cause));
            }
            let value = read.value.filter(|_| read.outcome == Outcome::Found)?;
            if cause != Cause::Unusable {
                return None;
            }
            message::root_kind_fault(check, path, ctx).or_else(|| {
                right_needs(check, value).map(|kind| message::isnt(&name::name(path), value, kind))
            })
        })
}

fn clash_named(said: String, item: &WalkItem, check: &Check, walked: &Path) -> String {
    if item.rest.is_empty() {
        return said;
    }
    let rest = name::name(&item.rest_path());
    let clashes = check
        .paths()
        .into_iter()
        .any(|path| from_a_root(path) && name::name(path) == rest);
    let cut = format!(": {rest} ");
    match said.find(&cut) {
        Some(at) if clashes => format!(
            "{}: {} {}",
            &said[..at],
            name::name(walked),
            &said[at + cut.len()..]
        ),
        _ => said,
    }
}

pub(super) fn focus_segs<'s>(item: &'s WalkItem, check: &Check) -> &'s [Seg] {
    if item.end.is_some() && reads_focus(check) {
        &item.end_segs
    } else {
        &item.item_segs
    }
}

#[allow(dead_code)]
pub(super) fn item_own(
    check: &Check,
    item: &WalkItem,
    walked: &Walked,
    outer: &Ctx,
) -> Option<Clause> {
    let focus = focus_ctx(item, outer);
    let name = walked.item_name(focus_segs(item, check));
    let paths: Vec<&Path> = check.paths().into_iter().chain(listed_refs(check)).collect();
    let keyed: Vec<Option<super::key_base::KeyBase>> = paths
        .iter()
        .map(|path| super::key_base::of_path(path, false, &focus))
        .collect();
    if keyed.iter().flatten().any(|found| found.off_object) {
        let text = message::isnt(&name, focus.subject.value, "an object");
        return Some(Clause::item(&name, Cause::NotAnObject, text, Vec::new()));
    }
    let outside = |path: &Path| reads_outside(path) || path.start == Start::Params;
    let mut said: Vec<Clause> = Vec::new();
    let mut own_at = None;
    for (path, found) in paths.into_iter().zip(keyed) {
        match found {
            Some(found) => said.extend(
                found
                    .base
                    .map(|(text, cause, _)| Clause::said(cause, text)),
            ),
            None if outside(path) => {
                said.extend(path.steps.iter().filter_map(|step| match step {
                    Step::Field(key) | Step::Ref(key)
                        if matches!(key.start, Start::Subject | Start::Own) =>
                    {
                        let (outcome, text, _) = super::key_base::key_flaw(key, &focus)?;
                        Some(Clause::said(outcome.cause()?, text))
                    }
                    _ => None,
                }));
            }
            None => {
                own_at.get_or_insert(said.len());
            }
        }
    }
    let mut item = Clause::item(&name, Cause::Satisfied, String::new(), Vec::new());
    if let Some(alone) = stood_in(check, |path| {
        outside(path) || super::key_base::of_path(path, false, &focus).is_some()
    }) {
        let verdict = run_check(&alone, &focus);
        if verdict.cause.is_failure() {
            let text = message::message(&alone, &focus, &verdict);
            item = super::tally::told(&name, verdict.cause, &text);
        }
    }
    let at = own_at.unwrap_or(said.len());
    item.said.splice(0..0, said.drain(..at));
    item.said.extend(said);
    item.cause = Cause::worst(
        item.said
            .iter()
            .map(|clause| clause.cause)
            .chain([item.cause]),
    )?;
    Some(item)
}

fn stood_in(check: &Check, blocked: impl Fn(&Path) -> bool) -> Option<Check> {
    use super::compare::{Compare, Side};
    if !check.paths().into_iter().chain(listed_refs(check)).any(&blocked) {
        return Some(check.clone());
    }
    let Check::Compare(compare) = check else {
        return None;
    };
    let blocked = |side: &Side| side.paths().into_iter().any(&blocked);
    let own = match (blocked(&compare.left), blocked(&compare.right)) {
        (false, true) => &compare.left,
        (true, false) => &compare.right,
        _ => return None,
    };
    Some(Check::Compare(Compare {
        left: own.clone(),
        right: own.clone(),
        ..compare.clone()
    }))
}

fn judge(walk: &Walk, walked: &Walked, ctx: &Ctx) -> Vec<Judged> {
    let mut at = ctx.clone();
    let whose: Vec<&Check> = walk.whose.iter().collect();
    let rooted = message::root_flaw(&whose, ctx).is_some();
    let alones: Vec<Option<Check>> = walk
        .whose
        .iter()
        .map(|check| {
            if rooted {
                super::tally::without_roots(check)
            } else {
                None
            }
        })
        .collect();
    walked
        .items
        .iter()
        .map(|item| {
            at.subject = item.item.clone();
            at.label = None;
            let focus = focus_ctx(item, ctx);
            let lost_check = focus_check(item);
            let verdicts: Vec<(&Check, Verdict, bool)> = walk
                .whose
                .iter()
                .zip(&alones)
                .map(|(check, alone)| alone.as_ref().unwrap_or(check))
                .map(|check| {
                    if focus_lost(item, check) {
                        (check, lost_verdict(item, &at), true)
                    } else {
                        (check, run_check(check, &focus), false)
                    }
                })
                .collect();
            let undecided = verdicts.iter().find(|(_, v, _)| v.cause.is_failure());
            let kept = !verdicts.iter().any(|(_, v, _)| v.cause == Cause::Value);
            let leaf_check = walk.check.with_left(item.rest_path());
            let leaf = run_check(&leaf_check, &at);
            let passed = undecided.is_none() && kept && leaf.passed();
            let failure = if let Some((_, verdict, true)) = undecided {
                Some(Failure {
                    msg: message::prefixed(
                        &walked.item_name(&item.item_segs),
                        &message::message(&lost_check, &at, verdict),
                    ),
                    order: item.end_segs.clone(),
                    said: walked.item_name_dotted(&item.end_segs),
                    rank: rank_of(&walk.path.start, &item.end_segs),
                    path: walked.name_of(&item.end_segs, item.unaliased),
                    item: walked.name_of(&item.item_segs, item.unaliased),
                    cause: verdict.cause,
                    value: Value::Null,
                    location: Some(item.end_location.clone()),
                    copies: Vec::new(),
                    seen: Some((item.item.value.clone(), item.item.location.clone())),
                })
            } else if let Some((check, _, _)) = undecided
                && !super::key_base::missing_keys(check, ctx).is_empty()
                && !matches!(
                    check
                        .paths()
                        .into_iter()
                        .find_map(|p| super::key_base::of_path(p, false, &focus)),
                    Some(super::key_base::KeyBase {
                        base: Some((_, Cause::Unusable, _)),
                        ..
                    })
                )
            {
                return Judged {
                    kept: false,
                    passed: false,
                    decided: true,
                    failure: None,
                };
            } else if let Some((check, verdict, _)) = undecided {
                let at = &focus;
                let keyed_base = (!super::key_base::missing_keys(check, ctx).is_empty())
                    .then(|| {
                        check
                            .paths()
                            .into_iter()
                            .find_map(|p| super::key_base::of_path(p, false, at))
                    })
                    .flatten()
                    .and_then(|kb| kb.base);
                let verdict = &match &keyed_base {
                    Some((_, cause, _)) => Verdict {
                        cause: *cause,
                        inputs: verdict.inputs.clone(),
                    },
                    None => verdict.clone(),
                };
                let item_segs = focus_segs(item, check);
                let named = named_side(check, at);
                let (steps, outside): (Vec<Step>, bool) = match &named {
                    Some((path, _)) => (
                        path.steps.clone(),
                        reads_outside(path) || path.start == Start::Params,
                    ),
                    None => (Vec::new(), false),
                };
                let mut order = item_segs.to_vec();
                let rank = match &named {
                    Some((path, _)) if outside => rank_of_path(path),
                    _ => {
                        let mut segs = order.clone();
                        segs.extend(steps.iter().map(seg_of));
                        rank_of(&walk.path.start, &segs)
                    }
                };
                let name = if outside {
                    named
                        .as_ref()
                        .map(|(path, _)| name::name(path))
                        .unwrap_or_default()
                } else {
                    order.extend(steps.iter().map(seg_of));
                    let mut named_steps: Vec<Step> = item_segs.iter().map(Seg::to_step).collect();
                    named_steps.extend(steps);
                    walked.name_of_steps(named_steps, item.unaliased)
                };
                let read = named.map(|(_, read)| read);
                let off = message::off_item(check, ctx, verdict.cause);
                let walked_root = super::lists::field_walk_fault(check, at)
                    .filter(|(cause, _)| *cause == verdict.cause)
                    .map(|(_, text)| text);
                let said = if let Some((text, _, _)) = &keyed_base {
                    message::prefixed(&walked.item_name(item_segs), text)
                } else if let Some(fault) = message::root_fault(check, ctx, verdict.cause) {
                    fault
                } else if let Some(text) = walked_root {
                    text
                } else if off.is_empty() {
                    message::prefixed(
                        &walked.item_name(item_segs),
                        &message::message(check, at, verdict),
                    )
                } else {
                    off.join(", and ")
                };
                Some(Failure {
                    msg: said,
                    order,
                    path: name,
                    said: walked.item_name_dotted(item_segs),
                    rank,
                    item: walked.name_of(&item.item_segs, item.unaliased),
                    cause: verdict.cause,
                    value: read
                        .as_ref()
                        .and_then(|r| r.value.cloned())
                        .unwrap_or(Value::Null),
                    location: read.and_then(|r| r.location),
                    copies: Vec::new(),
                    seen: Some((item.item.value.clone(), item.item.location.clone())),
                })
            } else if kept && !passed {
                let off = message::off_item(&leaf_check, ctx, leaf.cause);
                let said = if let Some(alone) = root_alone(&leaf_check, &at, leaf.cause) {
                    alone
                } else if !off.is_empty() {
                    off.join(", and ")
                } else {
                    clash_named(
                        message::prefixed(
                            &walked.item_name(&item.item_segs),
                            &message::message(&leaf_check, &at, &leaf),
                        ),
                        item,
                        &leaf_check,
                        &walk.path,
                    )
                };
                Some(Failure {
                    msg: said,
                    order: item.end_segs.clone(),
                    said: walked.item_name_dotted(&item.end_segs),
                    rank: rank_of(&walk.path.start, &item.end_segs),
                    path: walked.name_of(&item.end_segs, item.unaliased),
                    item: walked.name_of(&item.item_segs, item.unaliased),
                    cause: leaf.cause,
                    value: item.shown(),
                    location: Some(item.end_location.clone()),
                    copies: Vec::new(),
                    seen: Some((item.item.value.clone(), item.item.location.clone())),
                })
            } else {
                None
            };
            Judged {
                kept,
                passed: passed && !alones.iter().any(Option::is_some),
                decided: undecided.is_none(),
                failure,
            }
        })
        .collect()
}

fn cause_of(walk: &Walk, walked: &Walked, judged: &[Judged], fails: &[&Failure]) -> Cause {
    if walked.walked.is_empty() {
        return walked.failures.first().map_or(Cause::Value, |f| f.cause);
    }
    let worst = || Cause::worst(fails.iter().map(|f| f.cause)).unwrap_or(Cause::Value);
    match walk.quantifier {
        Quantifier::Every if fails.is_empty() => {
            if walk.if_any || judged.iter().any(|j| j.kept) {
                Cause::Satisfied
            } else {
                Cause::Value
            }
        }
        Quantifier::Every => worst(),
        Quantifier::Some if judged.iter().any(|j| j.passed) => Cause::Satisfied,
        Quantifier::Some if !fails.is_empty() => worst(),
        Quantifier::Some => Cause::Value,
    }
}

fn with_fields(inputs: &mut Vec<Input>, list: &str, path: &Path, ctx: &Ctx) {
    let fields: Vec<Input> = super::field_inputs(path, ctx)
        .into_iter()
        .filter(|field| !inputs.iter().any(|input| input.name == field.name))
        .collect();
    if let Some(at) = inputs.iter().position(|input| input.name == list) {
        inputs.splice(at + 1..at + 1, fields);
    }
}

/// How reading a walked list ended, from the failure that names the list
/// itself when it has no items.
pub fn list_state(walked: &Walked) -> crate::path::Outcome {
    walked
        .failures
        .iter()
        .find(|f| walked.items.is_empty() && !f.item.starts_with("item "))
        .map_or(crate::path::Outcome::Found, |f| match f.cause {
            Cause::Absent => crate::path::Outcome::Absent,
            Cause::Null => crate::path::Outcome::Null,
            Cause::Unusable => crate::path::Outcome::Unusable,
            Cause::NotAnObject => crate::path::Outcome::NotAnObject,
            _ => crate::path::Outcome::Found,
        })
}

fn read_row(walk: &Walk, ctx: &Ctx) -> Run {
    let outer = outer(ctx);
    let walked = self::walk(
        &walk.path,
        &outer,
        Options {
            if_any: walk.if_any,
            empty_adds_nothing: false,
        },
    );
    let outside = outside_inputs(walk, &outer);
    if let Some(outcome) = walked.unreadable {
        let mut inputs = vec![Input {
            name: walked.name.clone(),
            value: json!([]),
            locations: Vec::new(),
            part: None,
            state: outcome,
            null_at: None,
            worked: false,
        }];
        inputs.extend(outside);
        inputs.sort_by(|a, b| a.name.cmp(&b.name));
        inputs.dedup();
        with_fields(&mut inputs, &walked.name, &walk.path, ctx);
        let mut cause = outcome.cause().unwrap_or(Cause::Unusable);
        let parts: Vec<String> = if walked.failures.is_empty() {
            let keyed = super::key_base::of_path(&walk.path, true, &outer).is_some();
            let said = match cause {
                Cause::Absent => Some(format!("{} is missing", walked.name)),
                Cause::Null => Some(format!("{} is null", walked.name)),
                _ if keyed => Some(String::new()),
                _ => None,
            };
            match said {
                Some(said) => {
                    let mut parts = match super::key_base::of_path(&walk.path, true, &outer) {
                        Some(kb) => {
                            let mut found = vec![kb.key.clone()];
                            if let Some((text, base_cause, _)) = &kb.base {
                                found.push(text.clone());
                                cause = Cause::worst([cause, *base_cause]).unwrap_or(cause);
                                if let Some(first) =
                                    inputs.iter_mut().find(|i| i.name == walked.name)
                                    && let Some(state) =
                                        super::key_base::worse_state(first.state, *base_cause)
                                {
                                    first.state = state;
                                }
                            } else if !walk.if_any
                                && let Some(text) = super::key_base::empty_base(&walk.path, &outer)
                            {
                                found.push(text);
                            }
                            found
                        }
                        None => vec![said],
                    };
                    for root_cause in [Cause::Absent, Cause::Null, Cause::Unusable] {
                        if let Some(text) = root_alone(&walk.check, &outer, root_cause)
                            && !parts.contains(&text)
                        {
                            parts.push(text);
                        }
                    }
                    parts
                }
                None => walk_faults(walk, &outer),
            }
        } else {
            walked.failures.iter().map(|f| f.msg.clone()).collect()
        };
        return Run {
            verdict: Verdict { cause, inputs },
            failed_items: walked.failures.iter().map(Failure::to_json).collect(),
            rich: walked.failures.iter().map(Failure::to_rich_json).collect(),
            message: Some(message::joined(parts.clone())),
            parts,
        };
    }
    let judged = judge(walk, &walked, &outer);
    let judged = if walk.distinct {
        merged_copies(&walked, judged)
    } else {
        judged
    };
    let mut fails: Vec<&Failure> = walked.failures.iter().collect();
    fails.extend(judged.iter().filter_map(|j| j.failure.as_ref()));
    let cause = cause_of(walk, &walked, &judged, &fails);
    let mut sorted_msgs: Vec<String> = Vec::new();
    let rich: Vec<Value> = fails.iter().map(|f| f.to_rich_json()).collect();
    let failed_items = if cause == Cause::Satisfied {
        Vec::new()
    } else {
        let mut sorted = fails.clone();
        sorted.sort_by(|a, b| a.rank.cmp(&b.rank));
        sorted_msgs = sorted.iter().map(|f| f.msg.clone()).collect();
        sorted.iter().map(|f| f.to_json()).collect()
    };
    let tag = path::part_tag(&walk.path, &outer).map(|(name, id)| super::Part { name, id });
    let mut inputs = vec![Input {
        name: walked.name.clone(),
        value: Value::Array(walked.items.iter().map(WalkItem::shown).collect()),
        locations: walked
            .items
            .iter()
            .map(|item| item.end_location.render())
            .collect(),
        part: tag,
        state: list_state(&walked),
        null_at: None,
        worked: false,
    }];
    inputs.extend(outside);
    inputs.sort_by(|a, b| a.name.cmp(&b.name));
    inputs.dedup();
    with_fields(&mut inputs, &walked.name, &walk.path, ctx);
    let parts: Vec<String> = if cause == Cause::Satisfied {
        Vec::new()
    } else if sorted_msgs.is_empty() {
        vec![first_list(&walk.path, &outer)]
    } else {
        sorted_msgs
    };
    Run {
        verdict: Verdict { cause, inputs },
        failed_items,
        rich,
        message: (!parts.is_empty()).then(|| message::joined(parts.clone())),
        parts,
    }
}

fn in_a_for_line(ctx: &Ctx) -> bool {
    (ctx.label.is_none() || ctx.in_option) && ctx.aliases.keys().any(|name| name != OUTER)
}

fn first_list(path: &Path, ctx: &Ctx) -> String {
    message::first_list_text(path, ctx).unwrap_or_else(|| "the check is false".to_string())
}

pub fn walks_nothing(walk: &Walk, ctx: &Ctx) -> bool {
    let walked = self::walk(
        &walk.path,
        &outer(ctx),
        Options {
            if_any: walk.if_any,
            empty_adds_nothing: false,
        },
    );
    walked.unreadable.is_none() && walked.failures.is_empty() && walked.items.is_empty()
}

pub fn run(walk: &Walk, ctx: &Ctx) -> Run {
    let mut row = run_rows(walk, ctx);
    if !in_a_for_line(ctx) && row.verdict.cause != Cause::Satisfied {
        let outer_ctx = outer(ctx);
        let whose: Vec<&Check> = walk.whose.iter().collect();
        row.message = message::walked_roots_ahead(row.message.take(), &whose, &outer_ctx, &[]);
    }
    whose_keys_first(walk, ctx, &mut row);
    row
}

fn whose_keys_first(walk: &Walk, ctx: &Ctx, row: &mut Run) {
    let outer_ctx = outer(ctx);
    let keys: Vec<(Cause, String)> = walk
        .whose
        .iter()
        .flat_map(|check| super::key_base::missing_keys(check, &outer_ctx))
        .collect();
    if keys.is_empty()
        || row.verdict.cause == Cause::Unusable && row.failed_items.is_empty()
        || walk
            .whose
            .iter()
            .any(|check| !super::key_base::unusable_keys(check, &outer_ctx).is_empty())
    {
        return;
    }
    let said = row.message.clone().unwrap_or_default();
    let mut parts: Vec<String> = keys.iter().map(|(_, text)| text.clone()).collect();
    parts.extend(
        said.split("; ")
            .filter(|p| !p.is_empty() && !keys.iter().any(|(_, t)| t == p))
            .map(str::to_string),
    );
    let failed = row.verdict.cause.is_failure();
    row.verdict.cause = Cause::worst(
        keys.iter()
            .map(|(cause, _)| *cause)
            .chain(failed.then_some(row.verdict.cause)),
    )
    .unwrap_or(row.verdict.cause);
    row.message = Some(message::joined(parts));
}

fn run_rows(walk: &Walk, ctx: &Ctx) -> Run {
    let flawed = walk.flawed(ctx);
    if !flawed && subject_is_not_an_object(walk, ctx) {
        return Run {
            verdict: Verdict {
                cause: Cause::NotAnObject,
                inputs: Vec::new(),
            },
            failed_items: Vec::new(),
            rich: Vec::new(),
            message: Some(message::isnt(
                ctx.subject_label(),
                ctx.subject.value,
                "an object",
            )),
            parts: vec![message::isnt(
                ctx.subject_label(),
                ctx.subject.value,
                "an object",
            )],
        };
    }
    let mut row = read_row(walk, ctx);
    if flawed
        && !row.failed_items.is_empty()
        && walk
            .whose
            .iter()
            .any(|check| super::tally::without_roots(check).is_some())
    {
        let outer_ctx = outer(ctx);
        let whose: Vec<&Check> = walk.whose.iter().collect();
        if let Some((cause, text)) = message::root_flaw(&whose, &outer_ctx) {
            row.verdict.cause = Cause::worst([cause, row.verdict.cause]).unwrap_or(cause);
            row.message = Some(message::joined(message::with_roots(
                row.parts.clone(),
                &text,
            )));
            return row;
        }
    }
    if flawed {
        row.verdict.cause = Cause::Unusable;
        row.failed_items = Vec::new();
        let outer_ctx = outer(ctx);
        let faults = walk_faults(walk, &outer_ctx);
        let blocked = !through_a_list(&walk.path, &outer_ctx)
            && !message::blocked_of(&walk.path, &outer_ctx).is_empty();
        if !blocked && let Some((_, roots)) = list_beside_roots(walk, &outer_ctx) {
            let mut said = faults;
            said.extend(std::mem::take(&mut row.parts));
            row.parts = roots_then(roots, said);
            row.message = Some(message::joined(row.parts.clone()));
            return row;
        }
        row.parts = faults;
        let whose: Vec<&Check> = walk.whose.iter().collect();
        if let Some((_, text)) = message::root_flaw(&whose, &outer_ctx) {
            row.parts = message::with_roots(std::mem::take(&mut row.parts), &text);
        }
        row.message = Some(message::joined(row.parts.clone()));
        return row;
    }
    let outer_ctx = outer(ctx);
    let raw_cause = row.verdict.cause;
    let raw_parts = row.parts.clone();
    let beside = if raw_cause == Cause::Satisfied {
        None
    } else {
        list_beside_roots(walk, &outer_ctx)
    };
    let mut row = rooted_row(walk, ctx, &outer_ctx, row);
    if let Some((cause, roots)) = beside {
        row.verdict.cause = Cause::worst([cause, raw_cause]).unwrap_or(cause);
        row.parts = roots_then(roots, raw_parts);
        row.message = Some(message::joined(row.parts.clone()));
    }
    row
}

fn rooted_row(walk: &Walk, ctx: &Ctx, outer_ctx: &Ctx, mut row: Run) -> Run {
    let whose: Vec<&Check> = walk.whose.iter().collect();
    let unread = !row.verdict.cause.is_failure();
    let check_cause = unread
        .then(|| message::root_flaw(&[&*walk.check], outer_ctx))
        .flatten();
    let keyed =
        check_cause.is_some() && check_cause == message::key_cause(&[&*walk.check], outer_ctx);
    let flaw = message::root_flaw(&whose, outer_ctx)
        .or_else(|| (unread && !keyed).then_some(check_cause).flatten());
    let flaw = if unread {
        let mut keys = whose.clone();
        if keyed {
            keys.push(&*walk.check);
        }
        message::worse_key_cause(flaw, &keys, outer_ctx)
    } else {
        flaw
    };
    if let Some((cause, text)) = flaw {
        if row.verdict.cause != cause && row.verdict.cause.is_failure() {
            if !whose
                .iter()
                .any(|check| check.paths().into_iter().any(has_key_step))
            {
                row.verdict.cause = Cause::worst([cause, row.verdict.cause]).unwrap_or(cause);
            }
            if ctx.label.is_some() && !in_a_for_line(ctx) && !row.parts.is_empty() {
                let parts = message::with_roots(std::mem::take(&mut row.parts), &text);
                row.message = Some(message::joined(parts.clone()));
                row.parts = parts;
            }
            return row;
        }
        if row.verdict.cause == cause
            && cause.is_failure()
            && ctx.label.is_some()
            && !in_a_for_line(ctx)
            && !row.parts.is_empty()
            && row.parts.iter().any(|part| part.starts_with("item "))
        {
            let parts = message::with_roots(std::mem::take(&mut row.parts), &text);
            row.message = Some(message::joined(parts.clone()));
            row.parts = parts;
            return row;
        }
        let UpFront {
            cause,
            failed_items,
            message,
        } = read_up_front(
            row.verdict.cause,
            std::mem::take(&mut row.failed_items),
            cause,
            &text,
            None,
        );
        if let Some(message) = message {
            row.parts = vec![message.clone()];
            row.message = Some(message);
        }
        row.verdict.cause = cause;
        row.failed_items = failed_items;
    }
    row
}

fn list_beside_roots(walk: &Walk, outer_ctx: &Ctx) -> Option<(Cause, Vec<String>)> {
    let whose: Vec<&Check> = walk.whose.iter().collect();
    if params_unreadable(outer_ctx)
        || whose
            .iter()
            .any(|check| check.paths().into_iter().any(has_key_step))
    {
        return None;
    }
    let walked = self::walk(
        &walk.path,
        outer_ctx,
        Options {
            if_any: walk.if_any,
            empty_adds_nothing: false,
        },
    );
    let list_fails = walked.unreadable.is_some() || !walked.failures.is_empty();
    if !list_fails || !walked.own_failures() {
        return None;
    }
    message::root_flaw_texts(&whose, outer_ctx, &[])
}

impl Walked<'_> {
    pub(super) fn own_failures(&self) -> bool {
        self.failures
            .iter()
            .all(|f| !f.order.iter().any(|seg| matches!(seg, Seg::Index(_))))
    }
}

pub(super) fn params_unreadable(ctx: &Ctx) -> bool {
    ctx.params.is_some_and(|p| !p.is_object() && !p.is_null())
}

pub(super) fn has_key_step(path: &Path) -> bool {
    path.steps
        .iter()
        .any(|step| matches!(step, Step::Ref(_) | Step::Field(_)))
}

pub(super) fn roots_then(roots: Vec<String>, parts: Vec<String>) -> Vec<String> {
    let mut out = roots;
    for part in parts {
        if !out.contains(&part) {
            out.push(part);
        }
    }
    out
}

pub(super) struct UpFront {
    pub(super) cause: Cause,
    pub(super) failed_items: Vec<Value>,
    pub(super) message: Option<String>,
}

pub(super) fn read_up_front(
    row: Cause,
    failed_items: Vec<Value>,
    flaw: Cause,
    text: &str,
    said: Option<&str>,
) -> UpFront {
    if row == flaw {
        UpFront {
            cause: row,
            failed_items,
            message: Some(text.to_string()),
        }
    } else if !row.is_failure() {
        UpFront {
            cause: flaw,
            failed_items: Vec::new(),
            message: Some(text.to_string()),
        }
    } else {
        let message =
            said.map(|said| message::joined(message::with_roots(vec![said.to_string()], text)));
        UpFront {
            cause: row,
            failed_items,
            message,
        }
    }
}

fn walk_faults(walk: &Walk, outer_ctx: &Ctx) -> Vec<String> {
    let checks: Vec<&Check> = walk
        .whose
        .iter()
        .chain(std::iter::once(&*walk.check))
        .collect();
    let mut faults = super::lists::input_key_fault_of(&path::step_refs(&walk.path), outer_ctx);
    faults.extend(message::key_faults_of(&walk.path, outer_ctx));
    if !through_a_list(&walk.path, outer_ctx) {
        faults.extend(message::blocked_of(&walk.path, outer_ctx));
    }
    faults.extend(message::ref_fault_list(&checks, outer_ctx));
    if faults.is_empty() {
        vec!["the check is false".to_string()]
    } else {
        faults
    }
}

#[cfg(test)]
mod tests;
