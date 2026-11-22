use super::compare::joined;
use super::kinds::{Empty, HasType, Kind, NonEmptyString};
use super::walk::{self, Options, Seg};
use super::{Check, Input, Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::lower::Scope;
use crate::path::{self, Ctx, Outcome, Path, Start, Step, is_ref, step_refs};
use crate::value;
use ergo_policy_sentences as tree;
use regex::Regex;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub enum Right {
    Written(Value),
    Ref(Path),
    Field(Path),
    Join(Vec<Right>),
}

impl Right {
    pub fn refs(&self) -> Vec<Path> {
        match self {
            Right::Written(_) => Vec::new(),
            Right::Ref(path) if is_ref(path) => std::iter::once(path.clone())
                .chain(step_refs(path))
                .collect(),
            Right::Ref(path) => step_refs(path),
            Right::Field(path) => step_refs(path),
            Right::Join(pieces) => pieces.iter().flat_map(Right::refs).collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct In {
    pub path: Path,
    pub values: Right,
    pub not: bool,
    pub ignoring: Option<super::compare::Ignoring>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Wanted {
    One(Right),
    All(Right),
    Some(Right),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Contains {
    pub path: Path,
    pub wanted: Wanted,
    pub not: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Matches {
    pub path: Path,
    pub patterns: Right,
    pub not: bool,
}

impl Right {
    /// Adds every path this right side reads, in the order it writes them.
    pub fn paths<'a>(&'a self, out: &mut Vec<&'a Path>) {
        match self {
            Right::Ref(path) | Right::Field(path) => out.push(path),
            Right::Join(pieces) => pieces.iter().for_each(|piece| piece.paths(out)),
            Right::Written(_) => {}
        }
    }

    pub(super) fn ref_paths(&self) -> Vec<&Path> {
        match self {
            Right::Ref(path) => vec![path],
            Right::Join(pieces) => pieces.iter().flat_map(Right::ref_paths).collect(),
            Right::Written(_) | Right::Field(_) => Vec::new(),
        }
    }

    fn shown_paths(&self) -> Vec<&Path> {
        match self {
            Right::Written(_) | Right::Ref(_) => Vec::new(),
            Right::Field(path) => vec![path],
            Right::Join(pieces) => pieces.iter().flat_map(Right::shown_paths).collect(),
        }
    }
}

impl In {
    pub fn paths(&self) -> Vec<&Path> {
        std::iter::once(&self.path)
            .chain(self.values.shown_paths())
            .collect()
    }

    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
            .into_iter()
            .chain(self.values.refs())
            .collect()
    }
}

impl Contains {
    pub fn paths(&self) -> Vec<&Path> {
        let right = match &self.wanted {
            Wanted::One(right) | Wanted::All(right) | Wanted::Some(right) => right,
        };
        std::iter::once(&self.path)
            .chain(right.shown_paths())
            .collect()
    }

    pub fn refs(&self) -> Vec<Path> {
        let right = match &self.wanted {
            Wanted::One(right) | Wanted::All(right) | Wanted::Some(right) => right,
        };
        step_refs(&self.path)
            .into_iter()
            .chain(right.refs())
            .collect()
    }
}

impl Matches {
    pub fn paths(&self) -> Vec<&Path> {
        std::iter::once(&self.path)
            .chain(self.patterns.shown_paths())
            .collect()
    }

    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
            .into_iter()
            .chain(self.patterns.refs())
            .collect()
    }
}

struct RightRead {
    outcome: Outcome,
    value: Option<Value>,
    inputs: Vec<Input>,
    forced: Option<Cause>,
}

pub struct Walked {
    pub name: String,
    pub value: Vec<Value>,
    pub locations: Vec<String>,
    pub cause: Option<Cause>,
    pub text: String,
    pub part: Option<super::Part>,
}

impl Walked {
    pub fn input(&self) -> Input {
        Input {
            name: self.name.clone(),
            value: Value::Array(self.value.clone()),
            locations: self.locations.clone(),
            part: self.part.clone(),
            state: Outcome::Found,
            null_at: None,
            worked: false,
        }
    }
}

fn broken_at(item: &walk::WalkItem) -> Option<(Vec<Seg>, Value, &'static str)> {
    let (rest, value, wants) = broken_in(item.item.value, &item.rest)?;
    let mut segs = item.item_segs.clone();
    segs.extend(rest);
    Some((segs, value, wants))
}

fn broken_in(start: &Value, order: &[Seg]) -> Option<(Vec<Seg>, Value, &'static str)> {
    let mut current = start;
    for (at, seg) in order.iter().enumerate() {
        let (holds, wants) = match seg {
            Seg::Key(_) | Seg::Member(_) => (current.is_object(), "an object"),
            Seg::Index(_) => (current.is_array(), "a list"),
        };
        if !holds && !current.is_null() {
            return Some((order[..at].to_vec(), current.clone(), wants));
        }
        current = match (current, seg) {
            (Value::Object(map), Seg::Key(key) | Seg::Member(key)) => map.get(key)?,
            (Value::Array(items), Seg::Index(index)) => items.get(usize::try_from(*index).ok()?)?,
            _ => return None,
        };
    }
    None
}

fn item_fault(
    walked: &walk::Walked,
    item: &walk::WalkItem,
    text: bool,
) -> Option<(Cause, Vec<Seg>, String)> {
    use super::message::{isnt, stated};
    match item.end {
        Some(Value::Null) => Some((
            Cause::Null,
            item.end_segs.clone(),
            stated(
                &walked.item_name(&item.end_segs),
                Cause::Null,
                &Value::Null,
                "",
            ),
        )),
        Some(value) if text && !value.is_string() => Some((
            Cause::Unusable,
            item.end_segs.clone(),
            isnt(&walked.item_name(&item.end_segs), value, "text"),
        )),
        Some(_) => None,
        None => match item.miss {
            Cause::Absent => Some((
                Cause::Absent,
                item.end_segs.clone(),
                stated(
                    &walked.item_name(&item.end_segs),
                    Cause::Absent,
                    &Value::Null,
                    "",
                ),
            )),
            Cause::NotAnObject => Some((
                Cause::Unusable,
                item.item_segs.clone(),
                isnt(
                    &walked.item_name(&item.item_segs),
                    item.item.value,
                    "an object",
                ),
            )),
            _ => broken_at(item).map(|(segs, value, wants)| {
                (
                    Cause::Unusable,
                    segs.clone(),
                    isnt(&walked.item_name(&segs), &value, wants),
                )
            }),
        },
    }
}

pub(super) fn starts_at_a_list(path: &Path, ctx: &Ctx) -> bool {
    !matches!(path.start, Start::Subject | Start::Own | Start::Params)
        && !path::is_root(&path.start)
        && path::start_of(&path.start, ctx).is_ok_and(|(value, _, _)| value.is_array())
        && matches!(
            path::leading_steps(&path.start)
                .iter()
                .chain(path.steps.iter())
                .next(),
            Some(Step::Key(_))
        )
}

pub fn walked(path: &Path, ctx: &Ctx) -> Option<Walked> {
    walked_from(path, ctx, true, false)
}

fn text_right(check: &super::Check) -> Option<&Path> {
    match check {
        super::Check::In(In {
            values: Right::Ref(path) | Right::Field(path),
            ignoring: Some(_),
            ..
        }) => Some(path),
        _ => None,
    }
}

fn text_walk(check: &super::Check, path: &Path, ctx: &Ctx) -> Option<Walked> {
    use super::message::{isnt, stated};
    if text_right(check) != Some(path) {
        return None;
    }
    if let Some(walk) = walked_from(path, ctx, true, true) {
        return Some(walk);
    }
    let read = read_path(path, ctx);
    let (Outcome::Found, Some(Value::Array(items)), Some(first)) =
        (read.outcome, read.value.as_ref(), read.inputs.first())
    else {
        return None;
    };
    let faults: Vec<(Cause, String)> = items
        .iter()
        .enumerate()
        .filter_map(|(at, item)| {
            let name = format!("item {} of {}", at + 1, first.name);
            match item {
                Value::String(_) => None,
                Value::Null => Some((Cause::Null, stated(&name, Cause::Null, item, ""))),
                other => Some((Cause::Unusable, isnt(&name, other, "text"))),
            }
        })
        .collect();
    let cause = Cause::worst(faults.iter().map(|f| f.0))?;
    Some(Walked {
        name: first.name.clone(),
        value: items.clone(),
        locations: first.locations.clone(),
        cause: Some(cause),
        text: super::message::joined(faults.into_iter().map(|f| f.1).collect()),
        part: first.part.clone(),
    })
}

pub(super) fn text_list_flawed(check: &super::Check, ctx: &Ctx) -> bool {
    let Some(list) = text_right(check) else {
        return false;
    };
    text_fault(check, list, ctx).is_some() || {
        let read = read_path(list, ctx);
        read.outcome == Outcome::Found && read.value.as_ref().is_some_and(|v| !v.is_array())
    }
}

pub(super) fn text_fault(check: &super::Check, path: &Path, ctx: &Ctx) -> Option<(Cause, String)> {
    text_walk(check, path, ctx).and_then(|walk| walk.cause.map(|cause| (cause, walk.text)))
}

pub(crate) fn text_unfit(check: &super::Check, name: &str, ctx: &Ctx) -> bool {
    text_right(check)
        .and_then(|list| text_walk(check, list, ctx))
        .is_some_and(|walk| walk.cause.is_some() && walk.name == name)
}

pub(super) fn text_stand_in(check: &super::Check, ctx: &Ctx) -> Option<super::Check> {
    let super::Check::In(within) = check else {
        return None;
    };
    let list = text_right(check)?;
    text_fault(check, list, ctx)?;
    let own = super::compare::Side::Path(within.path.clone());
    Some(super::Check::Compare(super::compare::Compare {
        left: own.clone(),
        right: own,
        cmp: super::compare::Cmp::Eq,
        within: None,
        ignoring: within.ignoring,
    }))
}

fn fault_walk(check: &super::Check, path: &Path, ctx: &Ctx) -> Option<Walked> {
    text_walk(check, path, ctx).or_else(|| walked(path, ctx))
}

fn walked_from(path: &Path, ctx: &Ctx, from_start: bool, text: bool) -> Option<Walked> {
    let simple = path
        .steps
        .iter()
        .all(|step| matches!(step, Step::Key(_) | Step::Index(_)));
    let params_that_arent_an_object = path.start == crate::path::Start::Params
        && ctx.params.is_some_and(|params| !params.is_object());
    let list_start = || starts_at_a_list(path, ctx);
    let walks = match path::read(path, ctx).outcome {
        Outcome::Unusable => true,
        Outcome::NotAnObject => from_start && list_start(),
        _ => false,
    };
    if !simple || params_that_arent_an_object || !walks {
        return None;
    }
    let walked = walk::walk(path, ctx, Options::default());
    if walked.unreadable.is_some() || !walked.walked.iter().any(|level| *level < walked.steps) {
        return None;
    }
    let base = match &path.start {
        Start::Part(part) => &part.base,
        start => start,
    };
    let start = path::start_of(base, ctx).ok().map(|(value, _, _)| value);
    let mut faults: Vec<(Cause, Vec<Seg>, String)> = walked
        .failures
        .iter()
        .map(|f| {
            if f.cause == Cause::Unusable
                && f.value.is_null()
                && let Some((segs, value, wants)) =
                    start.and_then(|start| broken_in(start, &f.order))
            {
                let text = super::message::isnt(&walked.item_name(&segs), &value, wants);
                return (Cause::Unusable, segs, text);
            }
            (f.cause, f.order.clone(), f.msg.clone())
        })
        .collect();
    faults.extend(
        walked
            .items
            .iter()
            .filter_map(|item| item_fault(&walked, item, text)),
    );
    faults.sort_by(|a, b| a.1.cmp(&b.1));
    let cause = Cause::worst(faults.iter().map(|f| f.0));
    let text = super::message::joined(faults.into_iter().map(|f| f.2).collect());
    Some(Walked {
        name: walked.name.clone(),
        value: walked.items.iter().map(walk::WalkItem::shown).collect(),
        locations: walked
            .items
            .iter()
            .map(|item| item.end_location.render())
            .collect(),
        cause,
        text,
        part: path::part_tag(path, ctx).map(|(name, id)| super::Part { name, id }),
    })
}

fn walked_read(walk: Walked, inputs: Vec<Input>) -> RightRead {
    RightRead {
        outcome: Outcome::Found,
        value: walk
            .cause
            .is_none()
            .then(|| Value::Array(walk.value.clone())),
        inputs,
        forced: walk.cause,
    }
}

fn read_list_right(check: &Check) -> Option<(&Right, bool)> {
    match check {
        Check::In(check) => Some((&check.values, true)),
        Check::Contains(check) => match &check.wanted {
            Wanted::One(right) => Some((right, false)),
            Wanted::All(right) | Wanted::Some(right) => Some((right, true)),
        },
        Check::Matches(check) => Some((&check.patterns, true)),
        _ => None,
    }
}

fn named(path: &Path) -> bool {
    path.steps.iter().any(|step| match step {
        Step::Field(_) => true,
        Step::Ref(reference) => matches!(reference.start, Start::Alias(_)),
        _ => false,
    })
}

pub(super) fn ref_inputs(check: &Check, ctx: &Ctx, params_too: bool) -> Vec<Input> {
    let Some((right, walks)) = read_list_right(check) else {
        return Vec::new();
    };
    right
        .ref_paths()
        .into_iter()
        .filter(|path| !named(path) && (params_too || matches!(path.start, Start::Input)))
        .flat_map(|path| read_right(&Right::Ref(path.clone()), ctx, walks).inputs)
        .collect()
}

pub(super) fn walked_right(check: &Check) -> Option<&Path> {
    match read_list_right(check) {
        Some((Right::Ref(path) | Right::Field(path), true)) => Some(path),
        _ => None,
    }
}

pub(super) fn named_refs(check: &Check) -> Vec<&Path> {
    read_list_right(check).map_or_else(Vec::new, |(right, _)| {
        right
            .ref_paths()
            .into_iter()
            .filter(|path| named(path))
            .collect()
    })
}

fn read_right(right: &Right, ctx: &Ctx, walks: bool) -> RightRead {
    read_right_as(right, ctx, walks, false)
}

fn read_right_as(right: &Right, ctx: &Ctx, walks: bool, text: bool) -> RightRead {
    match right {
        Right::Written(value) => RightRead {
            outcome: Outcome::Found,
            value: Some(value.clone()),
            inputs: Vec::new(),
            forced: None,
        },
        Right::Ref(path) | Right::Field(path) => {
            match walked_from(path, ctx, true, text).filter(|_| walks) {
                Some(walk) => {
                    let input = walk.input();
                    walked_read(walk, vec![input])
                }
                None => {
                    let read = read_path(path, ctx);
                    let outcome =
                        if matches!(right, Right::Ref(_)) && !walks && input_one_path(path, ctx) {
                            Outcome::NotAnObject
                        } else {
                            read.outcome
                        };
                    RightRead {
                        outcome,
                        value: read.value,
                        inputs: read.inputs,
                        forced: None,
                    }
                }
            }
        }
        Right::Join(pieces) => {
            let reads: Vec<RightRead> = pieces.iter().map(|p| read_right(p, ctx, walks)).collect();
            let inputs = reads
                .iter()
                .flat_map(|r| r.inputs.iter().cloned())
                .collect();
            let mut text = String::new();
            for read in &reads {
                match (read.outcome, &read.value) {
                    (Outcome::Found, Some(Value::String(piece))) => text.push_str(piece),
                    (Outcome::Found, _) => {
                        return RightRead {
                            outcome: Outcome::Found,
                            value: None,
                            inputs,
                            forced: None,
                        };
                    }
                    (outcome, _) => {
                        return RightRead {
                            outcome,
                            value: None,
                            inputs,
                            forced: None,
                        };
                    }
                }
            }
            RightRead {
                outcome: Outcome::Found,
                value: Some(Value::String(text)),
                inputs,
                forced: None,
            }
        }
    }
}

fn one_type<'a>(values: impl Iterator<Item = &'a Value>) -> Result<Option<&'static str>, ()> {
    let mut kind = None;
    for v in values.filter(|v| !v.is_null()) {
        let name = value::type_name(v);
        match kind {
            None => kind = Some(name),
            Some(seen) if seen != name => return Err(()),
            Some(_) => {}
        }
    }
    Ok(kind)
}

fn judged<F>(path: &Path, right: &Right, ctx: &Ctx, walks: bool, decide: F) -> Verdict
where
    F: FnOnce(&Value, &Outcome, Option<&Value>) -> Cause,
{
    judged_as(path, right, ctx, walks, false, decide)
}

fn judged_as<F>(
    path: &Path,
    right: &Right,
    ctx: &Ctx,
    walks: bool,
    text: bool,
    decide: F,
) -> Verdict
where
    F: FnOnce(&Value, &Outcome, Option<&Value>) -> Cause,
{
    let read = read_right_as(right, ctx, walks, text);
    let left = read_path(path, ctx);
    let inputs = left.inputs.into_iter().chain(read.inputs).collect();
    let cause = match (read.forced, read.outcome.cause(), &read.value) {
        (Some(forced), _, _) if text => Cause::worst(
            [
                Some(forced),
                text_side_cause(&left.outcome, left.value.as_ref()),
            ]
            .into_iter()
            .flatten(),
        )
        .unwrap_or(forced),
        (Some(cause), _, _) | (None, Some(cause), _) => cause,
        (None, None, Some(right_value)) => decide(right_value, &left.outcome, left.value.as_ref()),
        (None, None, None) => Cause::Unusable,
    };
    Verdict { cause, inputs }
}

fn text_side_cause(outcome: &Outcome, found: Option<&Value>) -> Option<Cause> {
    match left_cause(outcome, found) {
        Ok(Value::String(_)) => None,
        Ok(_) => Some(Cause::Unusable),
        Err(cause) => Some(cause),
    }
}

fn left_cause(outcome: &Outcome, found: Option<&Value>) -> Result<Value, Cause> {
    match (outcome.cause(), found) {
        (Some(cause), _) => Err(cause),
        (None, Some(v)) => Ok(v.clone()),
        (None, None) => Err(Cause::Unusable),
    }
}

fn ref_read(right: &Right, ctx: &Ctx) -> Option<Value> {
    match right {
        Right::Ref(path) => {
            if let Some(walk) = walked(path, ctx) {
                return walk.cause.is_none().then_some(Value::Array(walk.value));
            }
            let read = read_path(path, ctx);
            match read.outcome {
                Outcome::Found => read.value,
                _ => None,
            }
        }
        Right::Written(_) | Right::Field(_) | Right::Join(_) => None,
    }
}

fn usable_values(values: &Value, non_empty: bool) -> bool {
    match values {
        Value::Array(items) => (!non_empty || !items.is_empty()) && one_type(items.iter()).is_ok(),
        _ => false,
    }
}

fn usable_patterns(patterns: &Value) -> bool {
    match patterns {
        Value::Array(items) => items.iter().all(|p| compiled(p).is_some()),
        _ => false,
    }
}

impl In {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        ref_read(&self.values, ctx).is_some_and(|v| match self.ignoring {
            None => !usable_values(&v, false),
            Some(_) => !v.is_array(),
        })
    }
}

impl Contains {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        match &self.wanted {
            Wanted::One(_) => false,
            Wanted::All(right) | Wanted::Some(right) => {
                ref_read(right, ctx).is_some_and(|v| !usable_values(&v, true))
            }
        }
    }
}

impl Matches {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        ref_read(&self.patterns, ctx).is_some_and(|v| !usable_patterns(&v))
    }
}

fn text_items_cause(values: &[Value]) -> Option<Cause> {
    Cause::worst(values.iter().filter_map(|value| match value {
        Value::String(_) => None,
        Value::Null => Some(Cause::Null),
        _ => Some(Cause::Unusable),
    }))
}

fn in_text(
    check: &In,
    ignoring: super::compare::Ignoring,
    values: &[Value],
    outcome: &Outcome,
    found: Option<&Value>,
) -> Cause {
    if let Some(cause) = text_items_cause(values) {
        return Cause::worst(
            [Some(cause), text_side_cause(outcome, found)]
                .into_iter()
                .flatten(),
        )
        .unwrap_or(cause);
    }
    let text = match left_cause(outcome, found) {
        Ok(Value::String(text)) => text,
        Ok(_) => return Cause::Unusable,
        Err(cause) => return cause,
    };
    let text = ignoring.prepare(&text);
    let hit = values
        .iter()
        .any(|v| v.as_str().is_some_and(|w| ignoring.prepare(w) == text));
    verdict(hit != check.not)
}

pub fn run_in(check: &In, ctx: &Ctx) -> Verdict {
    judged_as(
        &check.path,
        &check.values,
        ctx,
        true,
        check.ignoring.is_some(),
        |values, outcome, found| {
            let Value::Array(values) = values else {
                return Cause::Unusable;
            };
            if let Some(ignoring) = check.ignoring {
                return in_text(check, ignoring, values, outcome, found);
            }
            let Ok(kind) = one_type(values.iter()) else {
                return Cause::Unusable;
            };
            let found = match left_cause(outcome, found) {
                Ok(v) => v,
                Err(cause) => return cause,
            };
            if values.is_empty() {
                return verdict(check.not);
            }
            if kind.is_some_and(|k| k != value::type_name(&found)) {
                return Cause::Unusable;
            }
            let Some(hit) = value::any_equal(values.iter().map(|v| value::equal(&found, v))) else {
                return Cause::Unusable;
            };
            verdict(hit != check.not)
        },
    )
}

pub fn run_contains(check: &Contains, ctx: &Ctx) -> Verdict {
    let (right, all) = match &check.wanted {
        Wanted::One(right) => (right, false),
        Wanted::All(right) | Wanted::Some(right) => (right, true),
    };
    judged(&check.path, right, ctx, all, |wanted, outcome, found| {
        let wanted: Vec<Value> = if all {
            match wanted {
                Value::Array(values) if !values.is_empty() => values.clone(),
                _ => return Cause::Unusable,
            }
        } else {
            vec![wanted.clone()]
        };
        if one_type(wanted.iter()).is_err() {
            return Cause::Unusable;
        }
        let items = match left_cause(outcome, found) {
            Ok(Value::Array(items)) => items,
            Ok(_) => return Cause::Unusable,
            Err(cause) => return cause,
        };
        if one_type(items.iter().chain(wanted.iter())).is_err() {
            return Cause::Unusable;
        }
        let held = wanted
            .iter()
            .map(|w| value::any_equal(items.iter().map(|item| value::equal(item, w))));
        let decided = match (&check.wanted, check.not) {
            (Wanted::Some(_), false) => value::any_equal(held),
            (Wanted::Some(_), true) => value::all_equal(held).map(|all| !all),
            (_, true) => value::any_equal(held).map(|any| !any),
            (_, false) => value::all_equal(held),
        };
        decided.map_or(Cause::Unusable, verdict)
    })
}

pub fn compiled(pattern: &Value) -> Option<Regex> {
    let text = ergo_policy_sentences::rust_pattern(pattern.as_str()?)?;
    Regex::new(&text).ok()
}

pub fn run_matches(check: &Matches, ctx: &Ctx) -> Verdict {
    judged(
        &check.path,
        &check.patterns,
        ctx,
        true,
        |patterns, outcome, found| {
            let Value::Array(patterns) = patterns else {
                return Cause::Unusable;
            };
            let Some(regexes) = patterns.iter().map(compiled).collect::<Option<Vec<_>>>() else {
                return Cause::Unusable;
            };
            let text = match left_cause(outcome, found) {
                Ok(Value::String(text)) => text,
                Ok(_) => return Cause::Unusable,
                Err(cause) => return cause,
            };
            let hit = regexes.iter().any(|r| r.is_match(&text));
            verdict(hit != check.not)
        },
    )
}

fn path_right(path: &tree::Path, scope: &Scope) -> Result<Right, Vec<String>> {
    scope.path(path).map(|p| {
        if matches!(p.start, Start::Params | Start::Input) {
            Right::Ref(p)
        } else {
            Right::Field(p)
        }
    })
}

fn list_right(list: &tree::List, scope: &Scope) -> Result<Right, Vec<String>> {
    match list {
        tree::List::Values(values) => {
            let mut read = Vec::new();
            let mut problems = Vec::new();
            for v in values {
                match scope.value(v) {
                    Ok(v) => read.push(v),
                    Err(found) => problems.extend(found),
                }
            }
            if problems.is_empty() {
                Ok(Right::Written(Value::Array(read)))
            } else {
                Err(problems)
            }
        }
        tree::List::Path(path) => path_right(path, scope),
    }
}

fn one_typed(right: Result<Right, Vec<String>>) -> Result<Right, Vec<String>> {
    match &right {
        Ok(Right::Written(Value::Array(values))) if one_type(values.iter()).is_err() => {
            Err(vec!["values of mixed types".to_string()])
        }
        _ => right,
    }
}

fn operand_right(operand: &tree::Operand, scope: &Scope) -> Option<Result<Right, Vec<String>>> {
    match operand {
        tree::Operand::Value(v) => Some(scope.value(v).map(Right::Written)),
        tree::Operand::Field(terms) => match terms.as_slice() {
            [tree::Term::Path(p)] => Some(path_right(p, scope)),
            _ => None,
        },
        tree::Operand::Joined(pieces) => {
            let mut rights = Vec::new();
            let mut problems = Vec::new();
            for piece in pieces {
                match operand_right(piece, scope) {
                    Some(Ok(right)) => rights.push(right),
                    Some(Err(found)) => problems.extend(found),
                    None => return None,
                }
            }
            Some(if problems.is_empty() {
                Ok(Right::Join(rights))
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
    let left = || scope.left_path(path);
    let contains = |wanted: Result<Wanted, Vec<String>>, not: bool| {
        joined(left(), wanted).map(|(path, wanted)| Check::Contains(Contains { path, wanted, not }))
    };
    Some(match phrase {
        tree::Phrase::OneOf { not, list } => joined(left(), one_typed(list_right(list, scope)))
            .map(|(path, values)| {
                Check::In(In {
                    path,
                    values,
                    not: *not,
                    ignoring: None,
                })
            }),
        tree::Phrase::Ignoring {
            phrase: inner,
            ignoring,
        } => match &**inner {
            tree::Phrase::OneOf { not, list } => {
                joined(left(), list_right(list, scope)).map(|(path, values)| {
                    Check::In(In {
                        path,
                        values,
                        not: *not,
                        ignoring: Some(super::compare::Ignoring::of(*ignoring)),
                    })
                })
            }
            _ => return None,
        },
        tree::Phrase::Contains { not, operand } => {
            contains(operand_right(operand, scope)?.map(Wanted::One), *not)
        }
        tree::Phrase::ContainsAll(list) => {
            contains(one_typed(list_right(list, scope)).map(Wanted::All), false)
        }
        tree::Phrase::ContainsNone(list) => {
            contains(one_typed(list_right(list, scope)).map(Wanted::All), true)
        }
        tree::Phrase::ContainsSome(list) => {
            contains(one_typed(list_right(list, scope)).map(Wanted::Some), false)
        }
        tree::Phrase::NotContainsAll(list) => {
            contains(one_typed(list_right(list, scope)).map(Wanted::Some), true)
        }
        tree::Phrase::Matches { not, list } => {
            joined(left(), list_right(list, scope)).map(|(path, patterns)| {
                Check::Matches(Matches {
                    path,
                    patterns,
                    not: *not,
                })
            })
        }
        tree::Phrase::Type(kind) | tree::Phrase::NotType(kind) => left().map(|path| {
            Check::HasType(HasType {
                path,
                kind: match kind {
                    tree::Type::List => Kind::List,
                    tree::Type::String => Kind::String,
                    tree::Type::Number => Kind::Number,
                    tree::Type::Boolean => Kind::Boolean,
                    tree::Type::Object => Kind::Object,
                },
                not: matches!(phrase, tree::Phrase::NotType(_)),
            })
        }),
        tree::Phrase::NonEmptyString | tree::Phrase::NotNonEmptyString => left().map(|path| {
            Check::NonEmptyString(NonEmptyString {
                path,
                not: matches!(phrase, tree::Phrase::NotNonEmptyString),
            })
        }),
        tree::Phrase::Empty { not } => left().map(|path| Check::Empty(Empty { path, not: *not })),
        _ => return None,
    })
}

fn right_text(right: &Right) -> String {
    match right {
        Right::Written(value) => super::message::print(value),
        Right::Ref(path) | Right::Field(path) => crate::name::name(path),
        Right::Join(pieces) => pieces
            .iter()
            .map(right_text)
            .collect::<Vec<_>>()
            .join(" followed by "),
    }
}

fn right_shown(right: &Right, ctx: &Ctx, walks: bool) -> Vec<Input> {
    match right {
        Right::Written(_) => Vec::new(),
        Right::Ref(path) | Right::Field(path) => match walked(path, ctx).filter(|_| walks) {
            Some(walk) if walk.cause.is_none() => vec![walk.input()],
            Some(_) => Vec::new(),
            None => read_path(path, ctx).inputs.into_iter().take(1).collect(),
        },
        Right::Join(pieces) => {
            let read = read_right(right, ctx, walks);
            match (read.outcome, read.value) {
                (Outcome::Found, Some(value)) => vec![Input {
                    name: right_text(right),
                    value,
                    locations: Vec::new(),
                    part: None,
                    state: Outcome::Found,
                    null_at: None,
                    worked: false,
                }],
                _ => pieces
                    .iter()
                    .flat_map(|p| right_shown(p, ctx, walks))
                    .collect(),
            }
        }
    }
}

pub fn right_inputs(check: &super::Check, ctx: &Ctx) -> Vec<Input> {
    match check {
        super::Check::In(c) => right_shown(&c.values, ctx, true),
        super::Check::Contains(c) => match &c.wanted {
            Wanted::One(right) => right_shown(right, ctx, false),
            Wanted::All(right) | Wanted::Some(right) => right_shown(right, ctx, true),
        },
        super::Check::Matches(c) => right_shown(&c.patterns, ctx, true),
        _ => Vec::new(),
    }
}

pub fn right_paths(check: &super::Check) -> Vec<&Path> {
    let mut out = Vec::new();
    match check {
        super::Check::In(c) => c.values.paths(&mut out),
        super::Check::Contains(c) => match &c.wanted {
            Wanted::One(right) | Wanted::All(right) | Wanted::Some(right) => right.paths(&mut out),
        },
        super::Check::Matches(c) => c.patterns.paths(&mut out),
        _ => {}
    }
    out
}

pub fn ref_faults(check: &super::Check, ctx: &Ctx) -> Vec<String> {
    let faults = match check {
        super::Check::In(c) => ref_fault(
            &c.values,
            ctx,
            |v| usable_values(v, false),
            |v| match v {
                Value::Array(_) => "a list of one kind of value".to_string(),
                _ => "a list".to_string(),
            },
        ),
        super::Check::Contains(c) => match &c.wanted {
            Wanted::All(right) | Wanted::Some(right) => ref_fault(
                right,
                ctx,
                |v| usable_values(v, true),
                |v| match v {
                    Value::Array(items) if items.is_empty() => {
                        "a list with at least one value".to_string()
                    }
                    Value::Array(_) => "a list of one kind of value".to_string(),
                    _ => "a list".to_string(),
                },
            ),
            Wanted::One(_) => Vec::new(),
        },
        super::Check::Matches(c) => ref_fault(&c.patterns, ctx, usable_patterns, |v| match v {
            Value::Array(_) => "a list of patterns".to_string(),
            _ => "a list".to_string(),
        }),
        _ => Vec::new(),
    };
    faults.into_iter().map(|(_, text)| text).collect()
}

fn kind_word(value: &Value) -> &'static str {
    super::message::kind(value)
}

fn kinds_of(values: &[Value]) -> String {
    let mut words: Vec<&str> = values
        .iter()
        .filter(|v| !v.is_null())
        .map(kind_word)
        .collect();
    words.sort_unstable();
    words.dedup();
    words.join(" or ")
}

fn list_of(values: &[Value]) -> String {
    let mut words: Vec<&str> = values
        .iter()
        .filter(|v| !v.is_null())
        .map(|v| match v {
            Value::String(_) => "text",
            Value::Number(_) => "numbers",
            Value::Bool(_) => "true or false values",
            Value::Array(_) => "lists",
            Value::Object(_) => "objects",
            Value::Null => "",
        })
        .collect();
    words.sort_unstable();
    words.dedup();
    format!("a list of {}", words.join(" or "))
}

fn ref_fault(
    right: &Right,
    ctx: &Ctx,
    usable: impl Fn(&Value) -> bool,
    kind: impl Fn(&Value) -> String,
) -> Vec<(String, String)> {
    let (Right::Ref(path) | Right::Field(path)) = right else {
        return Vec::new();
    };
    if let Some(walk) = walked(path, ctx) {
        let list = Value::Array(walk.value.clone());
        return if walk.cause.is_none() && !usable(&list) {
            vec![super::message::fault(&walk.name, &list, &kind(&list))]
        } else {
            Vec::new()
        };
    }
    let read = read_path(path, ctx);
    match (read.outcome, read.value, read.inputs.first()) {
        (Outcome::Found, Some(value), Some(first)) if !usable(&value) => {
            vec![super::message::fault(&first.name, &value, &kind(&value))]
        }
        _ => Vec::new(),
    }
}

fn right_value(right: &Right, ctx: &Ctx, walks: bool) -> Option<Value> {
    let read = read_right(right, ctx, walks);
    match (read.outcome, read.forced) {
        (Outcome::Found, None) => read.value,
        _ => None,
    }
}

fn rights_of(check: &super::Check) -> Vec<&Right> {
    match check {
        super::Check::In(c) => vec![&c.values],
        super::Check::Contains(c) => match &c.wanted {
            Wanted::One(_) => Vec::new(),
            Wanted::All(right) | Wanted::Some(right) => vec![right],
        },
        super::Check::Matches(c) => vec![&c.patterns],
        _ => Vec::new(),
    }
}

pub fn haystacks(check: &super::Check) -> Vec<&Path> {
    rights_of(check)
        .into_iter()
        .filter_map(|right| match right {
            Right::Ref(path) | Right::Field(path) => Some(path),
            _ => None,
        })
        .collect()
}

pub fn one_rights(check: &super::Check) -> Vec<&Path> {
    let mut out = Vec::new();
    if let super::Check::Contains(Contains {
        wanted: Wanted::One(right),
        ..
    }) = check
    {
        right.paths(&mut out);
    }
    out
}

pub(super) fn input_one_path(path: &Path, ctx: &Ctx) -> bool {
    path.start == Start::Input
        && ctx.input.is_array()
        && matches!(
            path.steps.first(),
            Some(Step::Key(_) | Step::Field(_) | Step::Ref(_))
        )
}

pub fn input_one_fault(check: &super::Check, ctx: &Ctx) -> Vec<String> {
    let mut paths: Vec<&Path> = match check {
        super::Check::CompareTime(_) if ctx.item_by_item => check.left_path().into_iter().collect(),
        super::Check::Compare(super::compare::Compare { left, right, .. })
        | super::Check::CompareTime(super::time::CompareTime { left, right, .. }) => [left, right]
            .into_iter()
            .flat_map(|side| match side {
                super::compare::Side::Join(pieces) => pieces.iter().collect(),
                side => vec![side],
            })
            .filter_map(|side| match side {
                super::compare::Side::Path(path) => Some(path),
                _ => None,
            })
            .collect(),
        super::Check::Tally(t) => [Some(&t.left), t.right.as_ref()]
            .into_iter()
            .flatten()
            .filter_map(|side| match side {
                super::tally::Side::Plain(super::compare::Side::Path(path)) => Some(path),
                _ => None,
            })
            .collect(),
        other => other.left_path().into_iter().collect(),
    };
    paths.extend(one_rights(check));
    paths.extend(
        right_paths(check)
            .into_iter()
            .filter(|path| walked_in(check, path, ctx).is_none()),
    );
    let keyed_by_input = |path: &&Path| {
        !ctx.item_by_item
            && path
                .steps
                .iter()
                .any(|step| matches!(step, Step::Ref(reference) if input_one_path(reference, ctx)))
    };
    if paths
        .iter()
        .any(|path| input_one_path(path, ctx) || keyed_by_input(path))
    {
        vec![super::message::isnt("$input", ctx.input, "an object")]
    } else {
        Vec::new()
    }
}

/// Returns `$input is [...], which isn't an object` when the input is a list
/// and the check reads `$input` with a key, like `m named by $input.k`.
pub fn input_key_fault(check: &super::Check, ctx: &Ctx) -> Vec<String> {
    input_key_fault_of(&check.refs(), ctx)
}

/// Returns `$input is [...], which isn't an object` when the input is a list
/// and one of the keys is read from it, like `$input.k`.
pub fn input_key_fault_of(refs: &[Path], ctx: &Ctx) -> Vec<String> {
    if refs.iter().any(|reference| input_one_path(reference, ctx)) {
        vec![super::message::isnt("$input", ctx.input, "an object")]
    } else {
        Vec::new()
    }
}

pub fn walked_in(check: &super::Check, path: &Path, ctx: &Ctx) -> Option<Walked> {
    if one_rights(check).contains(&path) {
        return None;
    }
    walked_from(
        path,
        ctx,
        right_paths(check).contains(&path),
        text_right(check) == Some(path),
    )
}

pub(super) fn walked_root_fault(
    check: &super::Check,
    path: &Path,
    ctx: &Ctx,
) -> Option<(Cause, String)> {
    let walk = walked_in(check, path, ctx)?;
    if let Some(cause) = walk.cause {
        return Some((cause, walk.text));
    }
    ref_faults(check, ctx)
        .into_iter()
        .next()
        .map(|text| (Cause::Unusable, text))
}

pub(super) fn field_walk_fault(check: &super::Check, ctx: &Ctx) -> Option<(Cause, String)> {
    rights_of(check).into_iter().find_map(|right| match right {
        Right::Field(path) => {
            walked(path, ctx).and_then(|walk| walk.cause.map(|cause| (cause, walk.text)))
        }
        _ => None,
    })
}

pub fn walk_fault(check: &super::Check, ctx: &Ctx) -> Option<(Cause, String)> {
    rights_of(check).into_iter().find_map(|right| match right {
        Right::Ref(path) | Right::Field(path) => {
            fault_walk(check, path, ctx).and_then(|walk| walk.cause.map(|cause| (cause, walk.text)))
        }
        _ => None,
    })
}

fn left_found(path: &Path, ctx: &Ctx) -> Option<(String, Value)> {
    let read = read_path(path, ctx);
    match (read.outcome, read.value, read.inputs.first()) {
        (Outcome::Found, Some(value), Some(first)) => Some((first.name.clone(), value)),
        _ => None,
    }
}

fn in_text_faults(check: &In, ctx: &Ctx) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = left_found(&check.path, ctx)
        .filter(|(_, found)| !found.is_string())
        .map(|(name, found)| super::message::fault(&name, &found, "text"))
        .into_iter()
        .collect();
    out.extend(ref_fault(&check.values, ctx, Value::is_array, |_| {
        "a list".to_string()
    }));
    out
}

pub fn in_faults(check: &In, ctx: &Ctx) -> Vec<(String, String)> {
    if check.ignoring.is_some() {
        return in_text_faults(check, ctx);
    }
    let mut out = Vec::new();
    if let (Some((name, found)), Some(Value::Array(values))) = (
        left_found(&check.path, ctx),
        right_value(&check.values, ctx, true),
    ) {
        let mixed = one_type(values.iter()).is_err();
        let fits = match one_type(values.iter()) {
            Ok(None) => true,
            Ok(Some(kind)) => kind == value::type_name(&found),
            Err(()) => false,
        };
        if !fits && !(mixed && matches!(check.values, Right::Field(_))) {
            out.push(super::message::fault(&name, &found, &kinds_of(&values)));
        }
    }
    out.extend(ref_fault(
        &check.values,
        ctx,
        |v| usable_values(v, false),
        |v| match v {
            Value::Array(_) => "a list of one kind of value".to_string(),
            _ => "a list".to_string(),
        },
    ));
    out
}

fn join_faults(check: &Contains, pieces: &[Right], ctx: &Ctx) -> Vec<(String, String)> {
    let mut out = Vec::new();
    if let Some((name, found)) = left_found(&check.path, ctx) {
        let text = [Value::String(String::new())];
        match &found {
            Value::Array(items) => {
                if one_type(items.iter().chain(text.iter())).is_err() {
                    out.push(super::message::fault(&name, &found, &list_of(&text)));
                }
            }
            _ => out.push(super::message::fault(&name, &found, "a list")),
        }
    }
    for piece in pieces {
        if let Right::Ref(path) | Right::Field(path) = piece
            && let Some((name, value)) = left_found(path, ctx)
            && !value.is_string()
        {
            out.push(super::message::fault(&name, &value, "text"));
        }
    }
    out
}

pub fn join_pieces(check: &super::Check) -> Vec<&Path> {
    match check {
        super::Check::Contains(Contains {
            wanted: Wanted::One(Right::Join(pieces)),
            ..
        }) => pieces
            .iter()
            .filter_map(|piece| match piece {
                Right::Ref(path) | Right::Field(path) => Some(path),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

pub fn contains_faults(check: &Contains, ctx: &Ctx) -> Vec<(String, String)> {
    if let Wanted::One(Right::Join(pieces)) = &check.wanted {
        return join_faults(check, pieces, ctx);
    }
    let (right, all) = match &check.wanted {
        Wanted::One(right) => (right, false),
        Wanted::All(right) | Wanted::Some(right) => (right, true),
    };
    let mut out = Vec::new();
    let wanted: Option<Vec<Value>> = right_value(right, ctx, all).and_then(|w| {
        if all {
            match w {
                Value::Array(values) => Some(values),
                _ => None,
            }
        } else {
            Some(vec![w])
        }
    });
    if let Some((name, found)) = left_found(&check.path, ctx) {
        match (&found, &wanted) {
            (Value::Array(items), Some(wanted)) => {
                let skipped = matches!(right, Right::Field(_))
                    && all
                    && !usable_values(&Value::Array(wanted.clone()), true);
                if !skipped && one_type(items.iter().chain(wanted.iter())).is_err() {
                    out.push(super::message::fault(&name, &found, &list_of(wanted)));
                }
            }
            (Value::Array(_), None) => {}
            _ => out.push(super::message::fault(&name, &found, "a list")),
        }
    }
    if all {
        out.extend(ref_fault(
            right,
            ctx,
            |v| usable_values(v, true),
            |v| match v {
                Value::Array(items) if items.is_empty() => {
                    "a list with at least one value".to_string()
                }
                Value::Array(_) => "a list of one kind of value".to_string(),
                _ => "a list".to_string(),
            },
        ));
    }
    out
}

pub fn matches_faults(check: &Matches, ctx: &Ctx) -> Vec<(String, String)> {
    let mut out = Vec::new();
    if let Some((name, found)) = left_found(&check.path, ctx)
        && !found.is_string()
    {
        out.push(super::message::fault(&name, &found, "text"));
    }
    out.extend(ref_fault(
        &check.patterns,
        ctx,
        usable_patterns,
        |v| match v {
            Value::Array(_) => "a list of patterns".to_string(),
            _ => "a list".to_string(),
        },
    ));
    out
}

#[cfg(test)]
mod tests;
