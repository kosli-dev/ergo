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
    pub whose: Vec<Check>,
    pub if_any: bool,
    pub check: Box<Check>,
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
    pub cause: Cause,
    pub value: Value,
    pub location: Option<Location>,
}

impl Failure {
    pub fn to_json(&self) -> Value {
        let locations: Vec<String> = self.location.iter().map(Location::render).collect();
        json!({
            "path": self.path,
            "item": self.item,
            "cause": self.cause.name(),
            "value": self.value,
            "locations": locations,
        })
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
}

impl Walked<'_> {
    pub fn walked_last(&self) -> bool {
        self.walked.contains(&self.steps)
    }

    pub fn name_of(&self, segs: &[Seg], unaliased: bool) -> String {
        self.name_of_steps(segs.iter().map(Seg::to_step).collect(), unaliased)
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
    segs: Vec<Seg>,
    unaliased: bool,
    cause: Cause,
    value: Value,
    location: Location,
}

fn failed(entry: &Entry, cause: Cause, value: Value) -> Raw {
    Raw {
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
                            raws.push(failed(&entry, Cause::Value, json!([])));
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
                    None => raws.push(failed(&entry, entry.val.cause(), entry.val.shown())),
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
    };
    let mut failures: Vec<Failure> = raws
        .into_iter()
        .map(|raw| Failure {
            path: walked_all.name_of(&raw.segs, raw.unaliased),
            item: walked_all.name_of(&raw.segs, raw.unaliased),
            order: raw.segs,
            cause: raw.cause,
            value: raw.value,
            location: Some(raw.location),
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
}

fn outer<'a>(ctx: &Ctx<'a>) -> Ctx<'a> {
    let mut outer = ctx.clone();
    outer.aliases.insert(OUTER.to_string(), ctx.subject.clone());
    outer
}

fn reads_outside(path: &Path) -> bool {
    matches!(path.start, Start::Alias(_) | Start::Part(_) | Start::Input)
}

fn through_a_list(path: &Path, ctx: &Ctx) -> bool {
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
}

pub(super) fn outside_inputs_of(checks: &[&Check], ctx: &Ctx) -> Vec<Input> {
    let mut inputs = Vec::new();
    for check in checks {
        for path in check.paths().into_iter().filter(|p| reads_outside(p)) {
            inputs.extend(path_inputs(path, ctx, &[], true));
        }
    }
    inputs
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

pub(super) fn path_inputs(
    path: &Path,
    ctx: &Ctx,
    hidden: &[&str],
    fields_read_items: bool,
) -> Vec<Input> {
    if hides(path, hidden) {
        return path
            .steps
            .iter()
            .filter_map(|step| match step {
                Step::Field(field) => Some(read_path(field, ctx).inputs),
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
        Start::Part(part) => part.base == Start::Subject,
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

fn named_side<'a>(check: &'a Check, ctx: &Ctx<'a>) -> Option<(&'a Path, path::Read<'a>)> {
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
    failure: Option<Failure>,
}

fn judge(walk: &Walk, walked: &Walked, ctx: &Ctx) -> Vec<Judged> {
    let mut at = ctx.clone();
    walked
        .items
        .iter()
        .map(|item| {
            at.subject = item.item.clone();
            let verdicts: Vec<(&Check, Verdict)> = walk
                .whose
                .iter()
                .map(|check| (check, run_check(check, &at)))
                .collect();
            let undecided = verdicts
                .iter()
                .find(|(_, v)| !matches!(v.cause, Cause::Satisfied | Cause::Value));
            let kept = !verdicts.iter().any(|(_, v)| v.cause == Cause::Value);
            let leaf = run_check(&walk.check.with_left(item.rest_path()), &at);
            let passed = undecided.is_none() && kept && leaf.passed();
            let failure = if let Some((check, verdict)) = undecided {
                let named = named_side(check, &at);
                let (steps, outside): (Vec<Step>, bool) = match &named {
                    Some((path, _)) => (
                        path.steps.clone(),
                        reads_outside(path) || path.start == Start::Params,
                    ),
                    None => (Vec::new(), false),
                };
                let mut order = item.item_segs.clone();
                let name = if outside {
                    named
                        .as_ref()
                        .map(|(path, _)| name::name(path))
                        .unwrap_or_default()
                } else {
                    order.extend(steps.iter().map(seg_of));
                    let mut named_steps: Vec<Step> =
                        item.item_segs.iter().map(Seg::to_step).collect();
                    named_steps.extend(steps);
                    walked.name_of_steps(named_steps, item.unaliased)
                };
                let read = named.map(|(_, read)| read);
                Some(Failure {
                    order,
                    path: name,
                    item: walked.name_of(&item.item_segs, item.unaliased),
                    cause: verdict.cause,
                    value: read
                        .as_ref()
                        .and_then(|r| r.value.cloned())
                        .unwrap_or(Value::Null),
                    location: read.and_then(|r| r.location),
                })
            } else if kept && !passed {
                Some(Failure {
                    order: item.end_segs.clone(),
                    path: walked.name_of(&item.end_segs, item.unaliased),
                    item: walked.name_of(&item.item_segs, item.unaliased),
                    cause: leaf.cause,
                    value: item.shown(),
                    location: Some(item.end_location.clone()),
                })
            } else {
                None
            };
            Judged {
                kept,
                passed,
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
        }];
        inputs.extend(outside);
        inputs.sort_by(|a, b| a.name.cmp(&b.name));
        inputs.dedup();
        with_fields(&mut inputs, &walked.name, &walk.path, ctx);
        return Run {
            verdict: Verdict {
                cause: outcome.cause().unwrap_or(Cause::Unusable),
                inputs,
            },
            failed_items: walked.failures.iter().map(Failure::to_json).collect(),
        };
    }
    let judged = judge(walk, &walked, &outer);
    let mut fails: Vec<&Failure> = walked.failures.iter().collect();
    fails.extend(judged.iter().filter_map(|j| j.failure.as_ref()));
    let cause = cause_of(walk, &walked, &judged, &fails);
    let failed_items = if cause == Cause::Satisfied {
        Vec::new()
    } else {
        let mut sorted = fails.clone();
        sorted.sort_by(|a, b| a.order.cmp(&b.order));
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
    }];
    inputs.extend(outside);
    inputs.sort_by(|a, b| a.name.cmp(&b.name));
    inputs.dedup();
    with_fields(&mut inputs, &walked.name, &walk.path, ctx);
    Run {
        verdict: Verdict { cause, inputs },
        failed_items,
    }
}

pub fn run(walk: &Walk, ctx: &Ctx) -> Run {
    let flawed = walk.flawed(ctx);
    if !flawed && subject_is_not_an_object(walk, ctx) {
        return Run {
            verdict: Verdict {
                cause: Cause::NotAnObject,
                inputs: Vec::new(),
            },
            failed_items: Vec::new(),
        };
    }
    let mut row = read_row(walk, ctx);
    if flawed {
        row.verdict.cause = Cause::Unusable;
        row.failed_items = Vec::new();
    }
    row
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ops::{equals::Equals, present::Present};
    use std::collections::BTreeMap;

    fn key(text: &str) -> Step {
        Step::Key(text.to_string())
    }

    fn at(start: Start, steps: &[&str]) -> Path {
        Path {
            start,
            steps: steps.iter().map(|s| key(s)).collect(),
        }
    }

    fn ctx<'a>(subject: &'a Value, input: &'a Value, params: Option<&'a Value>) -> Ctx<'a> {
        Ctx {
            subject: Located {
                value: subject,
                location: Location::input_root().key("s"),
            },
            input,
            params,
            aliases: BTreeMap::new(),
        }
    }

    fn walked(
        subject: Value,
        steps: &[&str],
        options: Options,
    ) -> (Vec<Value>, Vec<Value>, String) {
        let input = json!({});
        let context = ctx(&subject, &input, None);
        let result = walk(&at(Start::Subject, steps), &context, options);
        (
            result.items.iter().map(WalkItem::shown).collect(),
            result.failures.iter().map(Failure::to_json).collect(),
            result.name,
        )
    }

    fn every(steps: &[&str], whose: Vec<Check>, check: Check, if_any: bool) -> Walk {
        Walk {
            quantifier: Quantifier::Every,
            path: at(Start::Subject, steps),
            whose,
            if_any,
            check: Box::new(check),
        }
    }

    fn equals(value: Value) -> Check {
        Check::Equals(Equals {
            path: at(Start::Subject, &[]),
            value,
        })
    }

    fn present(missing: bool) -> Check {
        Check::Present(Present {
            path: at(Start::Subject, &[]),
            missing,
        })
    }

    fn row(walk: &Walk, subject: Value) -> Run {
        let input = json!({});
        let params = json!({});
        run(walk, &ctx(&subject, &input, Some(&params)))
    }

    #[test]
    fn a_walk_without_a_flawed_check_is_not_flawed_and_one_inside_an_any_of_is_asked_too() {
        let inner = every(&["ys"], vec![], equals(json!(1)), false);
        let wrapped = every(
            &["xs"],
            vec![Check::AnyOf(crate::ops::any_of::AnyOf {
                options: vec![vec![Check::Walk(Box::new(inner))]],
            })],
            equals(json!(1)),
            false,
        );
        let subject = json!({"xs": [{"ys": [1]}]});
        let input = json!({});
        assert!(!wrapped.flawed(&ctx(&subject, &input, None)));
        assert!(!Check::Walk(Box::new(wrapped)).flawed(&ctx(&subject, &input, None)));
    }

    #[test]
    fn the_last_list_is_walked_and_its_items_are_the_ends() {
        let (items, failures, name) = walked(
            json!({"xs": [{"a": 1}, {"a": 2}]}),
            &["xs", "a"],
            Options::default(),
        );
        assert_eq!(items, [json!(1), json!(2)]);
        assert!(failures.is_empty());
        assert_eq!(name, "xs[].a");
        let (items, _, name) = walked(json!({"xs": ["a", "b"]}), &["xs"], Options::default());
        assert_eq!(items, [json!("a"), json!("b")]);
        assert_eq!(name, "xs[]");
    }

    #[test]
    fn every_list_along_the_path_is_walked_and_named_with_brackets() {
        let (items, _, name) = walked(
            json!({"ps": [{"cs": [{"s": 1}, {"s": 2}]}, {"cs": [{"s": 3}]}]}),
            &["ps", "cs", "s"],
            Options::default(),
        );
        assert_eq!(items, [json!(1), json!(2), json!(3)]);
        assert_eq!(name, "ps[].cs[].s");
    }

    #[test]
    fn an_empty_list_fails_as_value_unless_if_any_or_a_tally_skips_it() {
        let subject = json!({"xs": []});
        let (_, failures, _) = walked(subject.clone(), &["xs", "a"], Options::default());
        assert_eq!(failures[0]["cause"], json!("value"));
        assert_eq!(failures[0]["path"], json!("xs"));
        assert_eq!(failures[0]["value"], json!([]));
        for options in [
            Options {
                if_any: true,
                empty_adds_nothing: false,
            },
            Options {
                if_any: false,
                empty_adds_nothing: true,
            },
        ] {
            let (items, failures, _) = walked(subject.clone(), &["xs", "a"], options);
            assert!(items.is_empty() && failures.is_empty());
        }
    }

    #[test]
    fn a_list_that_is_missing_null_or_not_a_list_fails_where_another_is_walked() {
        let (items, failures, _) = walked(
            json!({"ps": [{"cs": [{"s": 1}]}, {}, {"cs": null}, {"cs": "none"}]}),
            &["ps", "cs", "s"],
            Options::default(),
        );
        assert_eq!(items, [json!(1)]);
        let causes: Vec<&Value> = failures.iter().map(|f| &f["cause"]).collect();
        assert_eq!(
            causes,
            [&json!("absent"), &json!("null"), &json!("unusable")]
        );
        assert_eq!(failures[0]["path"], json!("ps[1].cs"));
        assert_eq!(failures[0]["locations"], json!(["/s/ps/1"]));
        assert_eq!(failures[1]["locations"], json!(["/s/ps/2/cs"]));
        assert_eq!(failures[2]["value"], json!("none"));
    }

    #[test]
    fn a_path_with_no_list_fails_once_where_it_stops_and_walks_nothing() {
        let (items, failures, name) =
            walked(json!({"x": {"y": 1}}), &["x", "y"], Options::default());
        assert!(items.is_empty());
        assert_eq!(name, "x.y");
        assert_eq!(failures.len(), 1);
        assert_eq!(failures[0]["path"], json!("x.y"));
        assert_eq!(failures[0]["cause"], json!("unusable"));
        assert_eq!(failures[0]["value"], json!(1));
        let (_, failures, _) = walked(json!({"x": null}), &["x", "y"], Options::default());
        assert_eq!(failures[0]["cause"], json!("null"));
        assert_eq!(failures[0]["path"], json!("x"));
        let (_, failures, _) = walked(json!({}), &["x", "y"], Options::default());
        assert_eq!(failures[0]["cause"], json!("absent"));
    }

    #[test]
    fn a_position_is_read_and_never_walked() {
        let input = json!({});
        let subject = json!({"xs": [[1, 2], [3]]});
        let context = ctx(&subject, &input, None);
        let path = Path {
            start: Start::Subject,
            steps: vec![key("xs"), Step::Index(0)],
        };
        let result = walk(&path, &context, Options::default());
        let shown: Vec<Value> = result.items.iter().map(WalkItem::shown).collect();
        assert_eq!(shown, [json!(1), json!(2)]);
        assert_eq!(result.name, "xs[0][]");
        assert_eq!(
            result.items[0].item_segs,
            [Seg::Key("xs".into()), Seg::Index(0), Seg::Index(0)]
        );
    }

    #[test]
    fn failures_are_in_path_order_with_positions_by_number() {
        let mut list = Vec::new();
        for at in 0..12 {
            list.push(if at == 2 || at == 10 {
                json!({"cs": null})
            } else {
                json!({"cs": [{"s": 1}]})
            });
        }
        let (_, failures, _) = walked(json!({"ps": list}), &["ps", "cs", "s"], Options::default());
        assert_eq!(failures[0]["path"], json!("ps[2].cs"));
        assert_eq!(failures[1]["path"], json!("ps[10].cs"));
    }

    #[test]
    fn an_unreadable_ref_step_walks_nothing_and_says_why() {
        let input = json!({});
        let subject = json!({"xs": [1]});
        let context = ctx(&subject, &input, None);
        let path = Path {
            start: Start::Subject,
            steps: vec![key("xs"), Step::Ref(Box::new(at(Start::Params, &["k"])))],
        };
        let result = walk(&path, &context, Options::default());
        assert_eq!(result.unreadable, Some(Outcome::Absent));
        assert!(result.items.is_empty());
        assert_eq!(result.name, "xs named by $params.k");
    }

    #[test]
    fn every_passes_when_each_item_passes_and_lists_nothing() {
        let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        let out = row(&walk, json!({"xs": [{"ok": true}, {"ok": true}]}));
        assert!(out.verdict.passed());
        assert!(out.failed_items.is_empty());
        assert_eq!(
            out.verdict.inputs[0].to_json(),
            json!({"name": "xs[].ok", "value": [true, true], "locations": ["/s/xs/0/ok", "/s/xs/1/ok"]})
        );
    }

    #[test]
    fn every_fails_with_value_and_lists_each_item_that_failed_in_path_order() {
        let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        let out = row(
            &walk,
            json!({"xs": [{"ok": false}, {"ok": true}, {"ok": false}]}),
        );
        assert_eq!(out.verdict.cause, Cause::Value);
        assert_eq!(
            out.failed_items,
            [
                json!({"path": "xs[0].ok", "item": "item 1 of xs", "cause": "value", "value": false, "locations": ["/s/xs/0/ok"]}),
                json!({"path": "xs[2].ok", "item": "item 3 of xs", "cause": "value", "value": false, "locations": ["/s/xs/2/ok"]}),
            ]
        );
    }

    #[test]
    fn a_value_missing_at_the_end_fails_the_item_as_absent_and_shows_null() {
        let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        let out = row(&walk, json!({"xs": [{"ok": true}, {}]}));
        assert_eq!(out.verdict.cause, Cause::Absent);
        assert_eq!(out.verdict.inputs[0].value, json!([true, null]));
        assert_eq!(out.failed_items[0]["value"], Value::Null);
        assert_eq!(out.failed_items[0]["locations"], json!(["/s/xs/1"]));
    }

    #[test]
    fn every_over_no_items_fails_as_value_unless_if_any() {
        let strict = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        let lenient = every(&["xs", "ok"], vec![], equals(json!(true)), true);
        let subject = json!({"xs": []});
        assert_eq!(row(&strict, subject.clone()).verdict.cause, Cause::Value);
        let out = row(&lenient, subject);
        assert!(out.verdict.passed());
        assert!(out.failed_items.is_empty());
    }

    #[test]
    fn an_item_that_is_not_an_object_misses_as_not_an_object_when_the_path_goes_on_into_it() {
        let input = json!({});
        let subject = json!({"xs": ["str", null, {"y": 1}, {"y": "s"}]});
        let context = ctx(&subject, &input, None);
        let result = walk(
            &at(Start::Subject, &["xs", "y"]),
            &context,
            Options::default(),
        );
        let misses: Vec<Option<Cause>> = result
            .items
            .iter()
            .map(|item| item.end.is_none().then_some(item.miss))
            .collect();
        assert_eq!(
            misses,
            [
                Some(Cause::NotAnObject),
                Some(Cause::NotAnObject),
                None,
                None
            ]
        );
        let ends = walk(&at(Start::Subject, &["xs"]), &context, Options::default());
        assert!(ends.items.iter().all(|item| item.end.is_some()));
    }

    #[test]
    fn every_and_some_fail_an_item_that_is_not_an_object_as_not_an_object() {
        let subject = json!({"xs": ["str", {"y": 1}]});
        let walk = every(&["xs", "y"], vec![], equals(json!(1)), false);
        let out = row(&walk, subject.clone());
        assert_eq!(out.verdict.cause, Cause::NotAnObject);
        assert_eq!(out.failed_items[0]["cause"], json!("not_an_object"));
        assert_eq!(out.failed_items[0]["item"], json!("item 1 of xs"));
        let mut some = walk.clone();
        some.quantifier = Quantifier::Some;
        assert!(row(&some, subject).verdict.passed());
    }

    #[test]
    fn every_fails_with_the_worst_cause_of_what_failed() {
        let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        let out = row(&walk, json!({"xs": [{"ok": false}, {}, {"ok": null}]}));
        assert_eq!(out.verdict.cause, Cause::Absent);
        let out = row(&walk, json!({"xs": [{"ok": false}, "s"]}));
        assert_eq!(out.verdict.cause, Cause::NotAnObject);
    }

    #[test]
    fn some_passes_when_one_item_passes_and_fails_with_the_first_cause_otherwise() {
        let mut walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        walk.quantifier = Quantifier::Some;
        let out = row(&walk, json!({"xs": [{"ok": false}, {"ok": true}]}));
        assert!(out.verdict.passed());
        assert!(out.failed_items.is_empty());
        let out = row(&walk, json!({"xs": [{"ok": false}, {}]}));
        assert_eq!(out.verdict.cause, Cause::Absent);
        assert_eq!(out.failed_items.len(), 2);
        let out = row(&walk, json!({"xs": []}));
        assert_eq!(out.verdict.cause, Cause::Value);
    }

    #[test]
    fn whose_leaves_out_an_item_that_fails_it_and_every_with_none_left_fails_as_value() {
        let whose = Check::Equals(Equals {
            path: at(Start::Subject, &["k"]),
            value: json!("a"),
        });
        let walk = every(&["xs", "ok"], vec![whose], equals(json!(true)), false);
        let subject = json!({"xs": [{"k": "a", "ok": true}, {"k": "b", "ok": false}]});
        let out = row(&walk, subject);
        assert!(out.verdict.passed());
        assert_eq!(out.verdict.inputs[0].value, json!([true, false]));
        let none = row(&walk, json!({"xs": [{"k": "b", "ok": false}]}));
        assert_eq!(none.verdict.cause, Cause::Value);
        assert!(none.failed_items.is_empty());
    }

    #[test]
    fn an_item_whose_cannot_decide_fails_the_check_with_its_cause_and_is_listed_by_the_whose_field()
    {
        let whose = Check::Equals(Equals {
            path: at(Start::Subject, &["k"]),
            value: json!("a"),
        });
        let walk = every(
            &["xs", "ok"],
            vec![whose.clone()],
            equals(json!(true)),
            false,
        );
        let subject = json!({"xs": [{"k": "a", "ok": true}, {"ok": true}]});
        let out = row(&walk, subject.clone());
        assert_eq!(out.verdict.cause, Cause::Absent);
        assert_eq!(
            out.failed_items,
            [
                json!({"path": "xs[1].k", "item": "item 2 of xs", "cause": "absent", "value": null, "locations": ["/s/xs/1"]})
            ]
        );
        let mut some = walk.clone();
        some.quantifier = Quantifier::Some;
        assert!(row(&some, subject).verdict.passed());
    }

    #[test]
    fn a_present_whose_that_finds_its_field_missing_leaves_the_item_out_and_does_not_undecide_it() {
        let whose = Check::Present(Present {
            path: at(Start::Subject, &["note"]),
            missing: false,
        });
        let walk = every(&["xs", "ok"], vec![whose], equals(json!(true)), false);
        let out = row(
            &walk,
            json!({"xs": [{"note": 1, "ok": true}, {"ok": false}]}),
        );
        assert!(out.verdict.passed());
    }

    #[test]
    fn a_subject_that_is_not_an_object_fails_a_walk_that_starts_at_it_with_nothing_read() {
        let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
        let out = row(&walk, json!("s"));
        assert_eq!(out.verdict.cause, Cause::NotAnObject);
        assert!(out.verdict.inputs.is_empty());
        assert!(out.failed_items.is_empty());
        let on_it = every(&[], vec![], equals(json!(1)), false);
        let out = row(&on_it, json!([1, 2]));
        assert_eq!(out.verdict.cause, Cause::Value);
        assert_eq!(out.verdict.inputs[0].name, "it[]");
    }

    #[test]
    fn a_ref_step_that_cannot_be_read_fails_with_its_cause_and_shows_an_empty_list() {
        let mut walk = every(&["xs"], vec![], equals(json!(1)), false);
        walk.path
            .steps
            .push(Step::Ref(Box::new(at(Start::Params, &["k"]))));
        let out = row(&walk, json!({"xs": [1]}));
        assert_eq!(out.verdict.cause, Cause::Absent);
        assert!(out.failed_items.is_empty());
        assert_eq!(
            out.verdict.inputs[0].to_json(),
            json!({"name": "xs named by $params.k", "value": [], "locations": []})
        );
    }

    #[test]
    fn a_path_read_from_outside_the_item_is_listed_once_and_params_are_not() {
        let input = json!({"staff": ["ann"]});
        let subject = json!({"xs": [{"n": "ann"}]});
        let params = json!({});
        let context = ctx(&subject, &input, Some(&params));
        let outside = Check::Compare(crate::ops::compare::Compare {
            left: crate::ops::compare::Side::Path(at(Start::Subject, &[])),
            right: crate::ops::compare::Side::Path(at(Start::Input, &["staff"])),
            cmp: crate::ops::compare::Cmp::Eq,
            within: None,
        });
        let walk = every(&["xs", "n"], vec![], outside, false);
        let out = run(&walk, &context);
        let names: Vec<&str> = out.verdict.inputs.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(names, ["$input.staff", "xs[].n"]);
    }

    #[test]
    fn the_inputs_of_a_walk_are_sorted_by_name_so_a_parent_that_sorts_first_comes_first() {
        let input = json!({"a": 1});
        let subject = json!({"xs": [{"n": 1}]});
        let params = json!({});
        let context = ctx(&subject, &input, Some(&params));
        let outside = Check::Compare(crate::ops::compare::Compare {
            left: crate::ops::compare::Side::Path(at(Start::Subject, &[])),
            right: crate::ops::compare::Side::Path(at(Start::Input, &["a"])),
            cmp: crate::ops::compare::Cmp::Eq,
            within: None,
        });
        let walk = every(&["xs", "n"], vec![], outside, false);
        let out = run(&walk, &context);
        let names: Vec<&str> = out.verdict.inputs.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(names, ["$input.a", "xs[].n"]);
    }

    #[test]
    fn present_inside_a_walk_reads_the_rest_of_the_path_on_each_item() {
        let walk = every(&["xs", "ok"], vec![], present(false), false);
        let out = row(&walk, json!({"xs": [{"ok": 1}, {}]}));
        assert_eq!(out.verdict.cause, Cause::Value);
        assert_eq!(out.failed_items.len(), 1);
        assert_eq!(out.failed_items[0]["path"], json!("xs[1].ok"));
    }

    #[test]
    fn a_walk_through_a_part_names_its_entry_with_the_part_and_tags_it() {
        let subject = json!({"d": {"items": [{"x": 1}]}});
        let input = json!({});
        let context = ctx(&subject, &input, None);
        let start = Start::Part(Box::new(path::PartStart {
            name: "lst".into(),
            base: Start::Subject,
            steps: vec![key("d"), key("items")],
            id: None,
        }));
        let path = Path {
            start,
            steps: vec![key("x")],
        };
        let walk = Walk {
            quantifier: Quantifier::Every,
            path,
            whose: vec![],
            if_any: false,
            check: Box::new(equals(json!(2))),
        };
        let out = run(&walk, &context);
        assert_eq!(
            out.verdict.inputs[0].to_json(),
            json!({"name": "lst[].x", "value": [1], "locations": ["/s/d/items/0/x"], "part": {"name": "lst", "id": null}})
        );
        assert_eq!(out.failed_items[0]["path"], json!("lst[0].x"));
    }

    #[test]
    fn a_walk_through_a_list_inside_a_part_is_named_with_the_full_path() {
        let subject = json!({"prs": [{"rs": [{"s": "ok"}]}]});
        let input = json!({});
        let context = ctx(&subject, &input, None);
        let start = Start::Part(Box::new(path::PartStart {
            name: "rs".into(),
            base: Start::Subject,
            steps: vec![key("prs"), key("rs")],
            id: None,
        }));
        let walk = Walk {
            quantifier: Quantifier::Every,
            path: Path {
                start,
                steps: vec![key("s")],
            },
            whose: vec![],
            if_any: false,
            check: Box::new(equals(json!("bad"))),
        };
        let out = run(&walk, &context);
        assert_eq!(out.verdict.inputs[0].name, "prs[].rs[].s");
        assert_eq!(out.failed_items[0]["path"], json!("prs[0].rs[0].s"));
    }
}
