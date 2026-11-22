use super::clause::{self, Clause, Kind};
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
    Member(String),
}

impl Seg {
    pub fn to_step(&self) -> Step {
        match self {
            Seg::Index(at) => Step::Index(*at),
            Seg::Key(key) | Seg::Member(key) => Step::Key(key.clone()),
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
    pub wants_object: bool,
    pub order: Vec<Seg>,
    pub path: String,
    pub item: String,
    pub said: String,
    pub rank: Vec<Rank>,
    pub cause: Cause,
    pub value: Value,
    pub location: Option<Location>,
    pub copies: Vec<(String, String)>,
    pub msg: String,
    pub seen: Option<(Value, Location)>,
    pub outcome: Option<Cause>,
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
        Seg::Key(key) | Seg::Member(key) => Rank::Text(key.clone()),
    }));
    rank
}

impl Failure {
    pub fn to_json(&self) -> Value {
        let mut locations: Vec<String> = self.location.iter().map(Location::render).collect();
        locations.extend(self.copies.iter().map(|(end, _)| end.clone()));
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
        if let Some(outcome) = self.outcome {
            entry["ergo/outcome"] = json!(outcome.name());
        }
        if let Some((value, location)) = &self.seen {
            let mut places = vec![location.render()];
            places.extend(self.copies.iter().map(|(_, item)| item.clone()));
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
        if let Some((Seg::Member(key), before)) = segs.split_last() {
            return member::named(key, &self.name_of(before, unaliased));
        }
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
            .filter(|(_, seg)| matches!(seg, Seg::Index(_) | Seg::Member(_)))
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
        let mut parts = vec![match &segs[*first] {
            Seg::Member(key) => member::named(key, &self.said_name(&segs[..*first], own_dot)),
            _ => self.said_name(&segs[..=*first], own_dot),
        }];
        for pair in indexes.windows(2) {
            let between = &segs[pair[0] + 1..pair[1]];
            let list = if between.is_empty() {
                "it".to_string()
            } else {
                plain(between)
            };
            match &segs[pair[1]] {
                Seg::Index(at) => parts.push(format!("item {} of {list}", at + 1)),
                Seg::Member(key) => parts.push(member::named(key, &list)),
                Seg::Key(_) => {}
            }
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
    let (path, member) = member::split(path);
    let path = &path;
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
            entry.val.array().is_some() && seg.map_or(!member, |seg| !matches!(seg, Seg::Index(_)))
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
    let stops_early = walked.is_empty() && member::stop_before_end(&trail).is_some();
    if member && !stops_early {
        let (next, found) = member::expand(entries, empty_ok);
        entries = next;
        raws.extend(found);
    }
    if walked.is_empty() && (!member || stops_early) {
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
    if member && !stops_early {
        walked.insert(total);
    }
    let mut marks = walked.clone();
    if member {
        marks.remove(&total);
    }
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
                    .filter(|at| **at >= inside && !(member && **at == total))
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
            wants_object: raw.kind == member::WANTS,
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
            outcome: None,
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
    pub parts: Vec<Clause>,
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

pub(super) fn named_side_of<'a>(
    check: &'a Check,
    ctx: &Ctx<'a>,
    keep: impl Fn(&Path) -> bool,
) -> Option<(&'a Path, path::Read<'a>)> {
    let sides = check.sides();
    let mut sides = sides.iter().map(|paths| {
        let kept: Vec<SidePath> = paths
            .iter()
            .copied()
            .filter(|side| keep(side.path))
            .collect();
        (kept.is_empty() && !paths.is_empty(), side_read(&kept, ctx))
    });
    let (left_left_out, left) = sides.next().unwrap_or((false, None));
    let right = sides.next().and_then(|(_, read)| read);
    let right_alone = left_left_out
        || left.as_ref().is_none_or(|(_, _, read)| *read)
            && right.as_ref().is_some_and(|(_, _, read)| !*read);
    let (path, read, _) = if right_alone { right } else { left }?;
    Some((path, read))
}

struct Judged {
    kept: bool,
    passed: bool,
    decided: bool,
    reached: bool,
    alone: Option<Cause>,
    failure: Option<(Failure, Clause)>,
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
                if let Some((failure, _)) = &mut out[at].failure {
                    failure
                        .copies
                        .push((item.end_location.render(), item.item.location.render()));
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
        Check::Compare(compare) if compare.ignoring.is_some() => {
            (!value.is_string()).then_some("text")
        }
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

pub(super) fn item_own(
    check: &Check,
    item: &WalkItem,
    walked: &Walked,
    outer: &Ctx,
) -> Option<Clause> {
    if focus_lost(item, check) {
        let mut at = outer.clone();
        at.subject = item.item.clone();
        at.label = None;
        let verdict = lost_verdict(item, &at);
        let text = message::message(&focus_check(item), &at, &verdict);
        let name = walked.item_name(&item.item_segs);
        return Some(super::tally::told(&name, verdict.cause, &text));
    }
    let focus = focus_ctx(item, outer);
    let name = walked.item_name(focus_segs(item, check));
    let paths: Vec<&Path> = check
        .paths()
        .into_iter()
        .chain(listed_refs(check))
        .collect();
    let keyed: Vec<Option<super::key_base::KeyBase>> = paths
        .iter()
        .map(|path| super::key_base::of_path(path, false, &focus))
        .collect();
    if keyed.iter().flatten().any(|found| found.off_object) {
        let text = message::isnt(&name, focus.subject.value, "an object");
        return Some(Clause::item(&name, Cause::NotAnObject, text, Vec::new()));
    }
    let rooted = !message::root_clauses(&[check], outer).is_empty()
        || !message::walked_root_clauses(&[check], outer).is_empty();
    let outside = |path: &Path| (reads_outside(path) || path.start == Start::Params) && rooted;
    let mut said: Vec<Clause> = Vec::new();
    let mut own_at = None;
    for (path, found) in paths.into_iter().zip(keyed) {
        match found {
            Some(found) => {
                said.extend(found.base.map(|(text, cause, _)| Clause::said(cause, text)))
            }
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
    let root_key = |path: &Path| {
        path.steps.iter().any(|step| {
            matches!(step, Step::Field(key) | Step::Ref(key)
                if !matches!(key.start, Start::Subject | Start::Own)
                    && (super::key_base::key_flaw(key, &focus).is_some()
                        || path::read(key, &focus).outcome != Outcome::Found))
        })
    };
    let blocked = |path: &Path| {
        outside(path) || root_key(path) || super::key_base::of_path(path, false, &focus).is_some()
    };
    let mut item = Clause::item(&name, Cause::Satisfied, String::new(), Vec::new());
    let alone = stood_in(check, &focus, blocked)
        .map(|alone| (run_check(&alone, &focus), alone))
        .filter(|(verdict, _)| verdict.cause.is_failure());
    let on_item = |path: &Path| {
        matches!(path.start, Start::Subject | Start::Own)
            && matches!(path.steps.first(), Some(Step::Key(_)))
    };
    let off_focus = |key_of_root: bool| {
        !focus.subject.value.is_object()
            && check
                .paths()
                .into_iter()
                .chain(listed_refs(check))
                .any(|path| {
                    let keyed = |step: &Step| {
                        matches!(step, Step::Field(key) | Step::Ref(key) if on_item(key))
                    };
                    if key_of_root {
                        blocked(path) && path.steps.iter().any(keyed)
                    } else {
                        on_item(path) && !blocked(path)
                    }
                })
    };
    if off_focus(true) || (alone.is_none() && off_focus(false)) {
        let text = message::isnt(&name, focus.subject.value, "an object");
        item = Clause::item(&name, Cause::NotAnObject, text, Vec::new());
    } else if let Some((verdict, alone)) = alone {
        let text = message::message(&alone, &focus, &verdict);
        item = super::tally::told(&name, verdict.cause, &text);
    } else if let Some((cause, text)) = own_list_fault(check, &focus, blocked) {
        item = super::tally::told(&name, cause, &text);
    }
    let at = own_at.unwrap_or(said.len());
    let after = said.split_off(at);
    let own = std::mem::take(&mut item.said);
    for clause in said.into_iter().chain(own).chain(after) {
        if !item.said.contains(&clause) {
            item.said.push(clause);
        }
    }
    item.cause = Cause::worst(
        item.said
            .iter()
            .map(|clause| clause.cause)
            .chain([item.cause]),
    )?;
    Some(item)
}

fn own_list_fault(
    check: &Check,
    focus: &Ctx,
    blocked: impl Fn(&Path) -> bool,
) -> Option<(Cause, String)> {
    let lists = super::lists::right_paths(check);
    if lists.is_empty() {
        return None;
    }
    if lists.into_iter().any(&blocked) {
        let faults = match roots_written_in(check, focus, blocked)? {
            Check::In(within) => super::lists::in_faults(&within, focus),
            Check::Contains(contains) => super::lists::contains_faults(&contains, focus),
            _ => Vec::new(),
        };
        return faults
            .into_iter()
            .next()
            .map(|(_, text)| (Cause::Unusable, text));
    }
    super::lists::field_walk_fault(check, focus).or_else(|| {
        super::lists::ref_faults(check, focus)
            .into_iter()
            .next()
            .map(|text| (Cause::Unusable, text))
    })
}

fn roots_written_in(check: &Check, focus: &Ctx, blocked: impl Fn(&Path) -> bool) -> Option<Check> {
    use super::lists::{Contains, In, Right, Wanted};
    let written = |right: &Right| match right {
        Right::Ref(list) if blocked(list) => {
            let read = path::read(list, focus);
            read.value
                .filter(|_| read.outcome == Outcome::Found)
                .filter(|value| value.as_array().is_some_and(|items| !items.is_empty()))
                .map(|value| Right::Written(value.clone()))
        }
        _ => None,
    };
    match check {
        Check::In(within)
            if blocked(&within.path)
                && message::root_kind_fault(check, &within.path, focus).is_some() =>
        {
            None
        }
        Check::In(within) => Some(Check::In(In {
            values: written(&within.values)?,
            ..within.clone()
        })),
        Check::Contains(contains) => {
            let wanted = match &contains.wanted {
                Wanted::All(right) => Wanted::All(written(right)?),
                Wanted::Some(right) => Wanted::Some(written(right)?),
                Wanted::One(_) => return None,
            };
            Some(Check::Contains(Contains {
                wanted,
                ..contains.clone()
            }))
        }
        _ => None,
    }
}

const STAND_IN_TIME: &str = "1970-01-01T00:00:00Z";

fn stood_in(check: &Check, focus: &Ctx, blocked: impl Fn(&Path) -> bool) -> Option<Check> {
    use super::compare::{Compare, Side};
    use super::lists::{Contains, In, Matches, Right, Wanted};
    if !check
        .paths()
        .into_iter()
        .chain(listed_refs(check))
        .any(&blocked)
    {
        return Some(check.clone());
    }
    let right_blocked = |right: &Right| {
        let mut paths = Vec::new();
        right.paths(&mut paths);
        paths.into_iter().any(&blocked)
    };
    let mixed = |list: &Path| {
        let kinds: std::collections::BTreeSet<&str> = path::read(list, focus)
            .value
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|value| !value.is_null())
            .map(message::kind)
            .collect();
        kinds.len() > 1
    };
    if let Check::In(within) = check
        && !blocked(&within.path)
        && let Some(stand_in) = super::lists::text_stand_in(check, focus)
    {
        return Some(stand_in);
    }
    let side_blocked = |side: &Side| side.paths().into_iter().any(&blocked);
    let own_side = |left: &Side, right: &Side| match (side_blocked(left), side_blocked(right)) {
        (false, true) => Some(left.clone()),
        (true, false) => Some(right.clone()),
        _ => None,
    };
    let own_list = |right: &Right| match right {
        Right::Field(list) | Right::Ref(list)
            if !blocked(list)
                && !mixed(list)
                && super::lists::walked_in(check, list, focus).is_none() =>
        {
            Some(Check::Contains(Contains {
                path: list.clone(),
                wanted: Wanted::One(Right::Written(Value::Null)),
                not: false,
            }))
        }
        _ => None,
    };
    match check {
        Check::Compare(compare) => {
            let own = own_side(&compare.left, &compare.right)?;
            Some(Check::Compare(Compare {
                left: own.clone(),
                right: own,
                ..compare.clone()
            }))
        }
        Check::CompareTime(compare) => {
            let own = own_side(&compare.left, &compare.right)?;
            Some(Check::CompareTime(super::time::CompareTime {
                left: own,
                right: Side::Value(Value::from(STAND_IN_TIME)),
                ..compare.clone()
            }))
        }
        Check::Contains(contains) if !blocked(&contains.path) => {
            let wanted = match &contains.wanted {
                _ if mixed(&contains.path) => return None,
                Wanted::One(right) if right_blocked(right) => {
                    Wanted::One(Right::Written(Value::Null))
                }
                Wanted::All(right) if right_blocked(right) => {
                    Wanted::All(Right::Written(Value::Array(vec![Value::Null])))
                }
                Wanted::Some(right) if right_blocked(right) => {
                    Wanted::Some(Right::Written(Value::Array(vec![Value::Null])))
                }
                _ => return None,
            };
            Some(Check::Contains(Contains {
                wanted,
                ..contains.clone()
            }))
        }
        Check::Contains(contains) => match &contains.wanted {
            Wanted::One(Right::Field(value)) if !blocked(value) => {
                let own = Side::Path(value.clone());
                Some(Check::Compare(Compare {
                    left: own.clone(),
                    right: own,
                    cmp: super::compare::Cmp::Eq,
                    within: None,
                    ignoring: None,
                }))
            }
            Wanted::All(list) | Wanted::Some(list) => own_list(list),
            Wanted::One(_) => None,
        },
        Check::In(within) if !blocked(&within.path) && right_blocked(&within.values) => {
            Some(Check::In(In {
                values: Right::Written(Value::Array(Vec::new())),
                ..within.clone()
            }))
        }
        Check::In(within) => own_list(&within.values),
        Check::Matches(matches) if !blocked(&matches.path) && right_blocked(&matches.patterns) => {
            Some(Check::Matches(Matches {
                patterns: Right::Written(Value::Array(vec![Value::from("x")])),
                ..matches.clone()
            }))
        }
        Check::Matches(matches) => own_list(&matches.patterns),
        Check::Tally(tally) => {
            let right = tally.right.as_ref()?;
            let blocked_side = |side: &super::tally::Side| {
                super::tally::side_paths(side).into_iter().any(&blocked)
            };
            let own = match (blocked_side(&tally.left), blocked_side(right)) {
                (false, true) => tally.left.clone(),
                (true, false) => right.clone(),
                _ => return None,
            };
            Some(Check::Tally(super::tally::Tally {
                left: own.clone(),
                right: Some(own),
                test: super::tally::Test::Compare {
                    cmp: super::compare::Cmp::Eq,
                    within: None,
                },
            }))
        }
        _ => None,
    }
}

fn before_key<'a>(path: &Path, at: &Ctx<'a>) -> Option<(Path, path::Read<'a>, Cause)> {
    let found = super::key_base::of_path(path, false, at)?;
    let cut = path.steps.iter().position(
        |step| matches!(step, Step::Ref(key) if super::key_base::key_flaw(key, at).is_some()),
    )?;
    let before = Path {
        start: path.start.clone(),
        steps: path.steps[..cut].to_vec(),
    };
    let read = path::read(&before, at);
    let outcome = Cause::worst([found.key_cause].into_iter().chain(read.outcome.cause()))?;
    Some((before, read, outcome))
}

fn judge(walk: &Walk, walked: &Walked, ctx: &Ctx) -> Vec<Judged> {
    let mut at = ctx.clone();
    let leaf_roots = message::root_clauses(&[&*walk.check], ctx);
    let leaf_walked = message::walked_root_clauses_with(&[&*walk.check], ctx, true);
    walked
        .items
        .iter()
        .map(|item| {
            at.subject = item.item.clone();
            at.label = None;
            let focus = focus_ctx(item, ctx);
            let verdicts: Vec<(&Check, Verdict, bool)> = walk
                .whose
                .iter()
                .map(|check| {
                    let (verdict, lost) = focus_verdict(check, item, &at, &focus);
                    (check, verdict, lost)
                })
                .collect();
            let failing = || verdicts.iter().filter(|(_, v, _)| v.cause.is_failure());
            let undecided = failing().next().is_some();
            let own = failing()
                .filter(|(check, _, _)| !check.flawed(ctx))
                .find_map(|(check, _, lost)| {
                    item_own(check, item, walked, ctx).map(|said| (*check, *lost, said))
                })
                .or_else(|| {
                    failing().find_map(|(check, verdict, _)| {
                        walked_root_said(check, ctx, verdict.cause)
                            .map(|said| (*check, false, said))
                    })
                });
            let kept = !verdicts.iter().any(|(_, v, _)| v.cause == Cause::Value);
            let leaf_check = walk.check.with_left(item.rest_path());
            let leaf = run_check(&leaf_check, &at);
            let passed = !undecided && kept && leaf.passed();
            let reached = kept
                && !leaf.passed()
                && (!undecided
                    || own.is_none()
                        && leaf.cause.is_failure()
                        && failing().all(|(check, _, _)| reads_focus(check)));
            let alone = reached.then_some(leaf.cause).filter(|cause| {
                super::lists::text_stand_in(&leaf_check, &at).is_some()
                    || leaf_roots.iter().any(|root| root.cause == *cause)
                        && !leaf_walked.iter().any(|root| root.cause == *cause)
            });
            let failure = if let Some((_, true, said)) = own {
                Some((
                    Failure {
                        wants_object: false,
                        msg: clause::text(std::slice::from_ref(&said)),
                        order: item.end_segs.clone(),
                        said: walked.item_name_dotted(&item.end_segs),
                        rank: rank_of(&walk.path.start, &item.end_segs),
                        path: walked.name_of(&item.end_segs, item.unaliased),
                        item: walked.name_of(&item.item_segs, item.unaliased),
                        cause: said.cause,
                        value: Value::Null,
                        location: Some(item.end_location.clone()),
                        copies: Vec::new(),
                        seen: Some((item.item.value.clone(), item.item.location.clone())),
                        outcome: None,
                    },
                    said,
                ))
            } else if let Some((check, false, said)) = own {
                let at = &focus;
                let item_segs = focus_segs(item, check);
                let named = named_side_of(check, at, |path| {
                    !reads_outside(path) && path.start != Start::Params
                });
                let (steps, read, outcome) = match named {
                    Some((path, read)) => match before_key(path, at) {
                        Some((before, read, outcome)) => (before.steps, Some(read), Some(outcome)),
                        None => (path.steps.clone(), Some(read), None),
                    },
                    None => (Vec::new(), None, None),
                };
                let mut order = item_segs.to_vec();
                order.extend(steps.iter().map(seg_of));
                let rank = rank_of(&walk.path.start, &order);
                let mut named_steps: Vec<Step> = item_segs.iter().map(Seg::to_step).collect();
                named_steps.extend(steps);
                let name = walked.name_of_steps(named_steps, item.unaliased);
                Some((
                    Failure {
                        wants_object: false,
                        msg: clause::text(std::slice::from_ref(&said)),
                        order,
                        path: name,
                        said: walked.item_name_dotted(item_segs),
                        rank,
                        item: walked.name_of(&item.item_segs, item.unaliased),
                        cause: said.cause,
                        value: read
                            .as_ref()
                            .and_then(|r| r.value.cloned())
                            .unwrap_or(Value::Null),
                        location: read.and_then(|r| r.location),
                        copies: Vec::new(),
                        seen: Some((item.item.value.clone(), item.item.location.clone())),
                        outcome,
                    },
                    said,
                ))
            } else if let Some((verdict, stand_in)) = alone
                .and_then(|_| super::lists::text_stand_in(&leaf_check, &at))
                .map(|stand_in| (run_check(&stand_in, &at), stand_in))
                .filter(|(verdict, _)| verdict.cause.is_failure())
            {
                let failure = Failure {
                    wants_object: false,
                    msg: message::prefixed(
                        &walked.item_name(&item.item_segs),
                        &message::message(&stand_in, &at, &verdict),
                    ),
                    order: item.end_segs.clone(),
                    said: walked.item_name_dotted(&item.end_segs),
                    rank: rank_of(&walk.path.start, &item.end_segs),
                    path: walked.name_of(&item.end_segs, item.unaliased),
                    item: walked.name_of(&item.item_segs, item.unaliased),
                    cause: verdict.cause,
                    value: item.shown(),
                    location: Some(item.end_location.clone()),
                    copies: Vec::new(),
                    seen: Some((item.item.value.clone(), item.item.location.clone())),
                    outcome: None,
                };
                let said = failure_clause(&failure);
                Some((failure, said))
            } else if !reached || alone.is_some() {
                None
            } else {
                let off = message::off_item(&leaf_check, ctx, leaf.cause);
                let walked_root = leaf_walked.iter().find(|root| root.cause == leaf.cause);
                let msg = if let Some(root) = walked_root {
                    root.text.clone()
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
                let failure = Failure {
                    wants_object: false,
                    msg,
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
                    outcome: None,
                };
                let said = walked_root
                    .cloned()
                    .unwrap_or_else(|| failure_clause(&failure));
                Some((failure, said))
            };
            Judged {
                kept,
                passed,
                decided: !undecided,
                reached,
                alone,
                failure,
            }
        })
        .collect()
}

fn walked_root_said(check: &Check, ctx: &Ctx, cause: Cause) -> Option<Clause> {
    message::walked_root_clauses(&[check], ctx)
        .into_iter()
        .find(|root| root.cause == cause)
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
        .find(|f| walked.items.is_empty() && !crate::parts::is_item(&f.item))
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
        let mut key_root = Vec::new();
        let texts: Vec<String> = if walked.failures.is_empty() {
            let keyed = super::key_base::of_path(&walk.path, true, &outer).is_some();
            let said = match cause {
                Cause::Absent => Some(format!("{} is missing", walked.name)),
                Cause::Null => Some(format!("{} is null", walked.name)),
                _ if keyed => Some(String::new()),
                _ => None,
            };
            match said {
                Some(said) => match super::key_base::of_path(&walk.path, true, &outer) {
                    Some(kb) => {
                        key_root.push(Clause::root(&kb.key_name, kb.key_cause, kb.key.clone()));
                        let mut found = Vec::new();
                        if let Some((text, base_cause, _)) = &kb.base {
                            found.push(text.clone());
                            cause = Cause::worst([cause, *base_cause]).unwrap_or(cause);
                            if let Some(first) = inputs.iter_mut().find(|i| i.name == walked.name)
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
                },
                None => walk_faults(walk, &outer),
            }
        } else {
            Vec::new()
        };
        let list = texts
            .into_iter()
            .map(|text| Clause::list(&walked.name, cause, text))
            .collect();
        let items = walked
            .failures
            .iter()
            .map(|f| walked_clause(&walked, f))
            .collect();
        let mut roots = key_root;
        once(&mut roots, whose_roots(walk, &outer, true));
        once(&mut roots, message::root_clauses(&[&*walk.check], &outer));
        let (cause, mut parts) = row_clauses(roots, list, items);
        and_walked_roots(walk, &outer, &mut parts);
        return Run {
            verdict: Verdict { cause, inputs },
            failed_items: walked.failures.iter().map(Failure::to_json).collect(),
            rich: walked.failures.iter().map(Failure::to_rich_json).collect(),
            message: Some(clause::text(&clause::shown(&parts))),
            parts,
        };
    }
    let judged = judge(walk, &walked, &outer);
    let judged = if walk.distinct {
        merged_copies(&walked, judged)
    } else {
        judged
    };
    let mut said: Vec<(&Failure, Clause)> = walked
        .failures
        .iter()
        .map(|f| (f, walked_clause(&walked, f)))
        .chain(
            judged
                .iter()
                .filter_map(|j| j.failure.as_ref().map(|(f, said)| (f, said.clone()))),
        )
        .collect();
    let fails: Vec<&Failure> = said.iter().map(|(f, _)| *f).collect();
    let settled = cause_of(walk, &walked, &judged, &fails);
    let rich: Vec<Value> = fails.iter().map(|f| f.to_rich_json()).collect();
    said.sort_by(|a, b| a.0.rank.cmp(&b.0.rank));
    let mut list = Vec::new();
    let roots = if settled == Cause::Satisfied && walk.quantifier == Quantifier::Some {
        Vec::new()
    } else {
        let mut roots = whose_roots(walk, &outer, settled != Cause::Satisfied);
        let flawed = walk.check.flawed(&outer) && roots.is_empty();
        let leaf = if flawed || !roots.is_empty() {
            message::root_clauses(&[&*walk.check], &outer)
        } else {
            let items: Vec<Clause> = said.iter().map(|(_, item)| item.clone()).collect();
            let alone: Vec<Cause> = judged.iter().filter_map(|j| j.alone).collect();
            let reached = judged.iter().any(|j| j.reached);
            leaf_roots(walk, &outer, &items, &alone, reached)
        };
        let up_front = !leaf.is_empty() || params_unreadable(&outer) && !roots.is_empty();
        if flawed {
            said.clear();
            if !through_a_list(&walk.path, &outer) {
                list = message::blocked_of(&walk.path, &outer)
                    .into_iter()
                    .map(|text| Clause::list(&walked.name, Cause::Unusable, text))
                    .collect();
            }
        } else if up_front && said.iter().all(|(_, item)| item.cause == Cause::Value) {
            said.retain(|(failure, _)| own_read_of_a_reached_item(&walked, failure));
        }
        once(&mut roots, leaf);
        roots
    };
    let (sorted, items): (Vec<&Failure>, Vec<Clause>) = said.into_iter().unzip();
    let (cause, parts) = if settled == Cause::Satisfied && roots.is_empty() {
        (settled, Vec::new())
    } else {
        let items_said = sorted
            .iter()
            .any(|f| !walked.failures.iter().any(|w| std::ptr::eq(w, *f)));
        let (cause, mut parts) = row_clauses(roots, list, items);
        let said_nothing = parts.is_empty();
        and_walked_roots(walk, &outer, &mut parts);
        match Cause::worst(parts.iter().map(|part| part.cause)) {
            Some(worst) if said_nothing || items_said => (worst, parts),
            Some(_) => (cause, parts),
            None => {
                let list = first_list(&walk.path, &outer);
                (settled, vec![Clause::list(&walked.name, settled, list)])
            }
        }
    };
    let failed_items = if cause == Cause::Satisfied {
        Vec::new()
    } else {
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
    Run {
        verdict: Verdict { cause, inputs },
        failed_items,
        rich,
        message: (!parts.is_empty()).then(|| clause::text(&clause::shown(&parts))),
        parts,
    }
}

fn whose_roots(walk: &Walk, outer: &Ctx, failing: bool) -> Vec<Clause> {
    let whose: Vec<&Check> = walk.whose.iter().collect();
    let mut roots = message::side_root_clauses(&whose, outer);
    if failing {
        once(&mut roots, message::root_clauses(&whose, outer));
    }
    roots
}

fn and_walked_roots(walk: &Walk, outer: &Ctx, parts: &mut Vec<Clause>) {
    let whose: Vec<&Check> = walk.whose.iter().collect();
    for root in message::walked_root_clauses(&whose, outer) {
        if !parts.iter().any(|said| said.text == root.text) {
            parts.insert(0, root);
        }
    }
}

fn leaf_roots(
    walk: &Walk,
    outer: &Ctx,
    items: &[Clause],
    alone: &[Cause],
    reached: bool,
) -> Vec<Clause> {
    if items
        .iter()
        .any(|item| item.kind == Kind::List && item.cause.is_failure())
    {
        return Vec::new();
    }
    message::root_clauses(&[&*walk.check], outer)
        .into_iter()
        .filter(|root| {
            alone.contains(&root.cause)
                || reached && items.iter().all(|item| root.cause <= item.cause)
                || items.iter().all(|item| item.cause == Cause::Value)
        })
        .collect()
}

fn once(roots: &mut Vec<Clause>, more: Vec<Clause>) {
    for root in more {
        if !roots.iter().any(|said| said.text == root.text) {
            roots.push(root);
        }
    }
}

fn own_read_of_a_reached_item(walked: &Walked, failure: &Failure) -> bool {
    !walked.items.is_empty() && walked.failures.iter().any(|own| std::ptr::eq(own, failure))
}

fn params_unreadable(ctx: &Ctx) -> bool {
    ctx.params.is_some_and(|p| !p.is_object() && !p.is_null())
}

fn walked_clause(walked: &Walked, failure: &Failure) -> Clause {
    match failure
        .order
        .iter()
        .rposition(|seg| matches!(seg, Seg::Index(_)))
    {
        Some(at) if !crate::parts::is_item(&failure.item) => Clause::item(
            &walked.item_name(&failure.order[..=at]),
            failure.cause,
            failure.msg.clone(),
            Vec::new(),
        ),
        _ => failure_clause(failure),
    }
}

fn row_clauses(roots: Vec<Clause>, list: Vec<Clause>, items: Vec<Clause>) -> (Cause, Vec<Clause>) {
    let mut parts = roots;
    parts.extend(list);
    parts.extend(items);
    let cause = Cause::worst(parts.iter().map(|part| part.cause)).unwrap_or(Cause::Value);
    (cause, parts)
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
    if !walk.flawed(ctx) && subject_is_not_an_object(walk, ctx) {
        let said = message::isnt(ctx.subject_label(), ctx.subject.value, "an object");
        return Run {
            verdict: Verdict {
                cause: Cause::NotAnObject,
                inputs: Vec::new(),
            },
            failed_items: Vec::new(),
            rich: Vec::new(),
            message: Some(said.clone()),
            parts: vec![Clause::said(Cause::NotAnObject, said)],
        };
    }
    read_row(walk, ctx)
}

fn failure_clause(failure: &Failure) -> Clause {
    crate::parts::said_clause(&failure.item, failure.cause, &failure.msg)
}

fn walk_faults(walk: &Walk, outer_ctx: &Ctx) -> Vec<String> {
    let mut faults = super::lists::input_key_fault_of(&path::step_refs(&walk.path), outer_ctx);
    faults.extend(message::key_faults_of(&walk.path, outer_ctx));
    if !through_a_list(&walk.path, outer_ctx) {
        faults.extend(message::blocked_of(&walk.path, outer_ctx));
    }
    if faults.is_empty() {
        vec!["the check is false".to_string()]
    } else {
        faults
    }
}

mod member;

#[cfg(test)]
mod tests;
