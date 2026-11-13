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
            Seg::Key(_) => (current.is_object(), "an object"),
            Seg::Index(_) => (current.is_array(), "a list"),
        };
        if !holds && !current.is_null() {
            return Some((order[..at].to_vec(), current.clone(), wants));
        }
        current = match (current, seg) {
            (Value::Object(map), Seg::Key(key)) => map.get(key)?,
            (Value::Array(items), Seg::Index(index)) => items.get(usize::try_from(*index).ok()?)?,
            _ => return None,
        };
    }
    None
}

fn item_fault(walked: &walk::Walked, item: &walk::WalkItem) -> Option<(Cause, Vec<Seg>, String)> {
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
    walked_from(path, ctx, true)
}

fn walked_from(path: &Path, ctx: &Ctx, from_start: bool) -> Option<Walked> {
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
            .filter_map(|item| item_fault(&walked, item)),
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
    match right {
        Right::Written(value) => RightRead {
            outcome: Outcome::Found,
            value: Some(value.clone()),
            inputs: Vec::new(),
            forced: None,
        },
        Right::Ref(path) | Right::Field(path) => match walked(path, ctx).filter(|_| walks) {
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
        },
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
    let read = read_right(right, ctx, walks);
    let left = read_path(path, ctx);
    let inputs = left.inputs.into_iter().chain(read.inputs).collect();
    let cause = match (read.forced.or(read.outcome.cause()), &read.value) {
        (Some(cause), _) => cause,
        (None, Some(right_value)) => decide(right_value, &left.outcome, left.value.as_ref()),
        (None, None) => Cause::Unusable,
    };
    Verdict { cause, inputs }
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
        ref_read(&self.values, ctx).is_some_and(|v| !usable_values(&v, false))
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

pub fn run_in(check: &In, ctx: &Ctx) -> Verdict {
    judged(
        &check.path,
        &check.values,
        ctx,
        true,
        |values, outcome, found| {
            let Value::Array(values) = values else {
                return Cause::Unusable;
            };
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
                })
            }),
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
    fn of<'a>(right: &'a Right, out: &mut Vec<&'a Path>) {
        match right {
            Right::Ref(path) | Right::Field(path) => out.push(path),
            Right::Join(pieces) => pieces.iter().for_each(|piece| of(piece, out)),
            Right::Written(_) => {}
        }
    }
    let mut out = Vec::new();
    match check {
        super::Check::In(c) => of(&c.values, &mut out),
        super::Check::Contains(c) => match &c.wanted {
            Wanted::One(right) | Wanted::All(right) | Wanted::Some(right) => of(right, &mut out),
        },
        super::Check::Matches(c) => of(&c.patterns, &mut out),
        _ => {}
    }
    out
}

pub fn ref_faults(check: &super::Check, ctx: &Ctx) -> Vec<String> {
    match check {
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
    }
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
) -> Vec<String> {
    let (Right::Ref(path) | Right::Field(path)) = right else {
        return Vec::new();
    };
    if let Some(walk) = walked(path, ctx) {
        let list = Value::Array(walk.value.clone());
        return if walk.cause.is_none() && !usable(&list) {
            vec![super::message::isnt(&walk.name, &list, &kind(&list))]
        } else {
            Vec::new()
        };
    }
    let read = read_path(path, ctx);
    match (read.outcome, read.value, read.inputs.first()) {
        (Outcome::Found, Some(value), Some(first)) if !usable(&value) => {
            vec![super::message::isnt(&first.name, &value, &kind(&value))]
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
    fn of<'a>(right: &'a Right, out: &mut Vec<&'a Path>) {
        match right {
            Right::Ref(path) | Right::Field(path) => out.push(path),
            Right::Join(pieces) => pieces.iter().for_each(|piece| of(piece, out)),
            Right::Written(_) => {}
        }
    }
    let mut out = Vec::new();
    if let super::Check::Contains(Contains {
        wanted: Wanted::One(right),
        ..
    }) = check
    {
        of(right, &mut out);
    }
    out
}

fn input_one_path(path: &Path, ctx: &Ctx) -> bool {
    path.start == Start::Input
        && ctx.input.is_array()
        && matches!(
            path.steps.first(),
            Some(Step::Key(_) | Step::Field(_) | Step::Ref(_))
        )
}

pub fn input_one_fault(check: &super::Check, ctx: &Ctx) -> Vec<String> {
    let mut paths: Vec<&Path> = match check {
        super::Check::Compare(c) => [&c.left, &c.right]
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
    if paths.iter().any(|path| input_one_path(path, ctx)) {
        vec![super::message::isnt("$input", ctx.input, "an object")]
    } else {
        Vec::new()
    }
}

pub fn walked_in(check: &super::Check, path: &Path, ctx: &Ctx) -> Option<Walked> {
    if one_rights(check).contains(&path) {
        return None;
    }
    walked_from(path, ctx, right_paths(check).contains(&path))
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
            walked(path, ctx).and_then(|walk| walk.cause.map(|cause| (cause, walk.text)))
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

pub fn in_faults(check: &In, ctx: &Ctx) -> Vec<String> {
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
            out.push(super::message::isnt(&name, &found, &kinds_of(&values)));
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

fn join_faults(check: &Contains, pieces: &[Right], ctx: &Ctx) -> Vec<String> {
    let mut out = Vec::new();
    if let Some((name, found)) = left_found(&check.path, ctx) {
        let text = [Value::String(String::new())];
        match &found {
            Value::Array(items) => {
                if one_type(items.iter().chain(text.iter())).is_err() {
                    out.push(super::message::isnt(&name, &found, &list_of(&text)));
                }
            }
            _ => out.push(super::message::isnt(&name, &found, "a list")),
        }
    }
    for piece in pieces {
        if let Right::Ref(path) | Right::Field(path) = piece
            && let Some((name, value)) = left_found(path, ctx)
            && !value.is_string()
        {
            out.push(super::message::isnt(&name, &value, "text"));
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

pub fn contains_faults(check: &Contains, ctx: &Ctx) -> Vec<String> {
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
                    out.push(super::message::isnt(&name, &found, &list_of(wanted)));
                }
            }
            (Value::Array(_), None) => {}
            _ => out.push(super::message::isnt(&name, &found, "a list")),
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

pub fn matches_faults(check: &Matches, ctx: &Ctx) -> Vec<String> {
    let mut out = Vec::new();
    if let Some((name, found)) = left_found(&check.path, ctx)
        && !found.is_string()
    {
        out.push(super::message::isnt(&name, &found, "text"));
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
mod tests {
    use super::*;
    use crate::path::{Located, Location, Step};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn key_path(start: Start, keys: &[&str]) -> Path {
        Path {
            start,
            steps: keys.iter().map(|k| Step::Key(k.to_string())).collect(),
        }
    }

    fn x() -> Path {
        key_path(Start::Subject, &["x"])
    }

    fn on(subject: Value, params: Option<Value>, run: impl Fn(&Ctx) -> Verdict) -> Verdict {
        let input = json!({"things": [subject]});
        let ctx = Ctx {
            label: None,
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: params.as_ref(),
            aliases: BTreeMap::new(),
        };
        run(&ctx)
    }

    fn is_in(subject: Value, values: Right, not: bool) -> Cause {
        let check = In {
            path: x(),
            values,
            not,
        };
        on(subject, None, |ctx| run_in(&check, ctx)).cause
    }

    fn written(values: Value) -> Right {
        Right::Written(values)
    }

    #[test]
    fn in_passes_on_one_of_the_values_by_value() {
        let values = written(json!([1, 2]));
        assert_eq!(
            is_in(
                serde_json::from_str(r#"{"x": 1.0}"#).unwrap(),
                values.clone(),
                false
            ),
            Cause::Satisfied
        );
        assert_eq!(is_in(json!({"x": 3}), values.clone(), false), Cause::Value);
        assert_eq!(is_in(json!({"x": "1"}), values, false), Cause::Unusable);
    }

    #[test]
    fn not_in_passes_on_none_of_the_values_and_on_an_empty_list() {
        let values = written(json!(["prod", "staging"]));
        assert_eq!(
            is_in(json!({"x": "dev"}), values.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(
            is_in(json!({"x": "prod"}), values.clone(), true),
            Cause::Value
        );
        assert_eq!(is_in(json!({"x": 5}), values, true), Cause::Unusable);
        assert_eq!(
            is_in(json!({"x": 5}), written(json!([])), true),
            Cause::Satisfied
        );
        assert_eq!(
            is_in(json!({"x": 5}), written(json!([])), false),
            Cause::Value
        );
    }

    #[test]
    fn a_missing_or_null_field_fails_in_even_when_the_values_hold_null() {
        let values = written(json!(["a", null]));
        assert_eq!(is_in(json!({}), values.clone(), false), Cause::Absent);
        assert_eq!(
            is_in(json!({"x": null}), values.clone(), false),
            Cause::Null
        );
        assert_eq!(is_in(json!({"x": "a"}), values, false), Cause::Satisfied);
    }

    #[test]
    fn values_read_from_a_field_that_are_not_one_list_of_one_type_fail_as_unusable_first() {
        let field = Right::Field(key_path(Start::Subject, &["ys"]));
        assert_eq!(
            is_in(json!({"ys": "a"}), field.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(json!({"x": "a", "ys": ["a", 1]}), field.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(json!({"ys": ["a", 1]}), field.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(json!({"x": "a"}), field.clone(), false),
            Cause::Absent
        );
        assert_eq!(
            is_in(json!({"x": "a", "ys": ["b", "a"]}), field, false),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_field_and_a_ref_on_the_right_are_both_inputs() {
        let field = In {
            path: x(),
            values: Right::Field(key_path(Start::Subject, &["ys"])),
            not: false,
        };
        let names = |v: Verdict| v.inputs.into_iter().map(|i| i.name).collect::<Vec<_>>();
        assert_eq!(
            names(on(json!({"x": "a", "ys": ["a"]}), None, |ctx| run_in(
                &field, ctx
            ))),
            ["x", "ys"]
        );
        let reference = In {
            path: x(),
            values: Right::Ref(key_path(Start::Params, &["k"])),
            not: false,
        };
        let v = on(json!({"x": "a"}), Some(json!({"k": ["a"]})), |ctx| {
            run_in(&reference, ctx)
        });
        assert_eq!(v.cause, Cause::Satisfied);
        assert_eq!(names(v), ["x", "$params.k"]);
    }

    #[test]
    fn a_ref_that_is_missing_or_null_fails_with_its_outcome_whatever_the_field_holds() {
        let check = In {
            path: x(),
            values: Right::Ref(key_path(Start::Params, &["k"])),
            not: false,
        };
        assert_eq!(
            on(json!({}), Some(json!({})), |ctx| run_in(&check, ctx)).cause,
            Cause::Absent
        );
        assert_eq!(
            on(json!({"x": 1}), Some(json!({"k": null})), |ctx| run_in(
                &check, ctx
            ))
            .cause,
            Cause::Null
        );
    }

    #[test]
    fn a_ref_after_in_contains_and_matches_is_listed_after_the_field_whatever_the_cause() {
        let ref_k = || Right::Ref(key_path(Start::Params, &["k"]));
        let names = |v: Verdict| v.inputs.into_iter().map(|i| i.name).collect::<Vec<_>>();
        let subjects_and_params = [
            (json!({"x": "a"}), json!({"k": ["a"]})),
            (json!({"x": "a"}), json!({"k": "text"})),
            (json!({"x": ["a"]}), json!({})),
            (json!({"x": ["a"]}), json!({"k": null})),
            (json!({}), json!({"k": ["a"]})),
            (json!({"x": null}), json!({"k": ["a"]})),
        ];
        for (subject, params) in subjects_and_params {
            let in_check = In {
                path: x(),
                values: ref_k(),
                not: false,
            };
            let contains_check = Contains {
                path: x(),
                wanted: Wanted::All(ref_k()),
                not: false,
            };
            let matches_check = Matches {
                path: x(),
                patterns: ref_k(),
                not: false,
            };
            let verdicts = [
                on(subject.clone(), Some(params.clone()), |ctx| {
                    run_in(&in_check, ctx)
                }),
                on(subject.clone(), Some(params.clone()), |ctx| {
                    run_contains(&contains_check, ctx)
                }),
                on(subject.clone(), Some(params.clone()), |ctx| {
                    run_matches(&matches_check, ctx)
                }),
            ];
            for verdict in verdicts {
                assert_eq!(names(verdict), ["x", "$params.k"]);
            }
        }
    }

    fn contains(subject: Value, wanted: Wanted, not: bool) -> Cause {
        let check = Contains {
            path: x(),
            wanted,
            not,
        };
        on(subject, None, |ctx| run_contains(&check, ctx)).cause
    }

    #[test]
    fn includes_and_excludes_need_a_list() {
        let one = Wanted::One(written(json!("a")));
        assert_eq!(
            contains(json!({"x": ["b", "a"]}), one.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["b"]}), one.clone(), false),
            Cause::Value
        );
        assert_eq!(contains(json!({"x": []}), one.clone(), false), Cause::Value);
        assert_eq!(
            contains(json!({"x": []}), one.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": "abc"}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": {"a": "a"}}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(contains(json!({}), one.clone(), true), Cause::Absent);
        assert_eq!(contains(json!({"x": null}), one, false), Cause::Null);
    }

    #[test]
    fn items_and_values_of_more_than_one_type_fail_as_unusable_leaving_null_aside() {
        let one = Wanted::One(written(json!(1)));
        assert_eq!(
            contains(json!({"x": ["1", 1]}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": ["1"]}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": [1, null]}), one.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(contains(json!({"x": [2]}), one, true), Cause::Satisfied);
    }

    #[test]
    fn contains_all_of_and_none_of_take_every_value() {
        let all = Wanted::All(written(json!(["b", "a"])));
        assert_eq!(
            contains(json!({"x": ["a", "c", "b"]}), all.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["a"]}), all.clone(), false),
            Cause::Value
        );
        assert_eq!(
            contains(json!({"x": ["c"]}), all.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(contains(json!({"x": ["c", "a"]}), all, true), Cause::Value);
    }

    #[test]
    fn contains_a_joined_string_looks_for_the_pieces_put_together() {
        let joined = || {
            Wanted::One(Right::Join(vec![
                written(json!("x")),
                Right::Field(key_path(Start::Subject, &["y"])),
            ]))
        };
        assert_eq!(
            contains(json!({"x": ["x1", "b"], "y": "1"}), joined(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["x1", "b"], "y": "1"}), joined(), true),
            Cause::Value
        );
        assert_eq!(
            contains(json!({"x": ["a"], "y": "1"}), joined(), true),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["a"], "y": 1}), joined(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": ["a"]}), joined(), false),
            Cause::Absent
        );
        assert_eq!(
            contains(json!({"x": "a", "y": null}), joined(), false),
            Cause::Null
        );
        assert_eq!(
            contains(json!({"x": "a", "y": "1"}), joined(), false),
            Cause::Unusable
        );
    }

    #[test]
    fn contains_some_of_needs_one_value_and_not_all_of_needs_one_missing() {
        let some = Wanted::Some(written(json!(["b", "a"])));
        assert_eq!(
            contains(json!({"x": ["a", "c"]}), some.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["c"]}), some.clone(), false),
            Cause::Value
        );
        assert_eq!(
            contains(json!({"x": []}), some.clone(), false),
            Cause::Value
        );
        assert_eq!(
            contains(json!({"x": ["a", "c"]}), some.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": []}), some.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["b", "a", "c"]}), some, true),
            Cause::Value
        );
    }

    #[test]
    fn contains_some_of_and_not_all_of_never_pass_on_a_field_that_cannot_be_read_as_a_list() {
        let some = Wanted::Some(written(json!(["a"])));
        for not in [false, true] {
            assert_eq!(
                contains(json!({"x": "a"}), some.clone(), not),
                Cause::Unusable
            );
            assert_eq!(
                contains(json!({"x": ["a", 1]}), some.clone(), not),
                Cause::Unusable
            );
            assert_eq!(contains(json!({}), some.clone(), not), Cause::Absent);
            assert_eq!(contains(json!({"x": null}), some.clone(), not), Cause::Null);
        }
    }

    #[test]
    fn a_field_of_values_for_contains_some_of_fails_as_unusable_when_empty_or_not_a_list() {
        let field = || Wanted::Some(Right::Field(key_path(Start::Subject, &["ys"])));
        for ys in [json!([]), json!("a"), json!(["a", 1])] {
            for not in [false, true] {
                assert_eq!(
                    contains(json!({"x": ["a"], "ys": ys.clone()}), field(), not),
                    Cause::Unusable,
                    "{ys}"
                );
            }
        }
    }

    #[test]
    fn values_read_as_an_empty_list_a_non_list_or_mixed_types_fail_as_unusable() {
        let field = || Wanted::All(Right::Field(key_path(Start::Subject, &["ys"])));
        for ys in [json!([]), json!("a"), json!(["a", 1])] {
            assert_eq!(
                contains(json!({"x": ["a"], "ys": ys.clone()}), field(), true),
                Cause::Unusable,
                "{ys}"
            );
            assert_eq!(
                contains(json!({"ys": ys.clone()}), field(), false),
                Cause::Unusable,
                "{ys}"
            );
        }
    }

    #[test]
    fn one_value_that_is_a_list_is_looked_for_as_a_list() {
        let one = Wanted::One(Right::Field(key_path(Start::Subject, &["y"])));
        assert_eq!(
            contains(json!({"x": [["a"]], "y": ["a"]}), one.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["a"], "y": ["a"]}), one, false),
            Cause::Unusable
        );
    }

    fn matches(text: Value, patterns: Value, not: bool) -> Cause {
        let check = Matches {
            path: x(),
            patterns: written(patterns),
            not,
        };
        on(json!({"x": text}), None, |ctx| run_matches(&check, ctx)).cause
    }

    #[test]
    fn a_pattern_matches_anywhere_unless_anchored() {
        assert_eq!(
            matches(json!("my_svc_x"), json!(["z", "^b", "svc_"]), false),
            Cause::Satisfied
        );
        assert_eq!(matches(json!("a"), json!(["z", "^b"]), false), Cause::Value);
        assert_eq!(matches(json!("bob"), json!(["^b"]), true), Cause::Value);
        assert_eq!(matches(json!("a"), json!(["^b"]), true), Cause::Satisfied);
        assert_eq!(matches(json!("a"), json!([]), false), Cause::Value);
        assert_eq!(matches(json!("a"), json!([]), true), Cause::Satisfied);
    }

    #[test]
    fn matching_works_as_re2_does() {
        assert_eq!(
            matches(json!("a\nb"), json!(["^a.b$"]), false),
            Cause::Value
        );
        assert_eq!(matches(json!("a\n"), json!(["a$"]), false), Cause::Value);
        assert_eq!(
            matches(json!("abc"), json!(["(?i)^A"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("été"), json!([r"^\p{L}+$"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("\u{212a}"), json!(["(?i)^k$"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("a+b"), json!([r"\Qa+b\E"]), false),
            Cause::Satisfied
        );
    }

    #[test]
    fn digit_word_space_and_boundary_classes_are_ascii_as_in_re2() {
        assert_eq!(matches(json!("٣"), json!([r"^\d$"]), false), Cause::Value);
        assert_eq!(matches(json!("٣"), json!([r"^[\d]$"]), false), Cause::Value);
        assert_eq!(
            matches(json!("٣"), json!([r"^\D$"]), false),
            Cause::Satisfied
        );
        assert_eq!(matches(json!("é"), json!([r"^\w$"]), false), Cause::Value);
        assert_eq!(
            matches(json!("\u{b}"), json!([r"^\s$"]), false),
            Cause::Value
        );
        assert_eq!(
            matches(json!("\u{a0}"), json!([r"^\s$"]), false),
            Cause::Value
        );
        assert_eq!(
            matches(json!("aé"), json!([r"a\b"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("é"), json!(["^[[:alpha:]]$"]), false),
            Cause::Value
        );
    }

    #[test]
    fn a_pattern_that_cannot_be_used_fails_as_unusable() {
        assert_eq!(matches(json!("a"), json!(["("]), false), Cause::Unusable);
        assert_eq!(matches(json!("a"), json!([1]), false), Cause::Unusable);
        assert_eq!(matches(json!("a"), json!("a"), false), Cause::Unusable);
        assert_eq!(
            matches(json!("a"), json!(["a", r"a\Z"]), true),
            Cause::Unusable
        );
    }

    #[test]
    fn matching_anything_but_a_string_fails_as_unusable() {
        assert_eq!(matches(json!(1), json!(["1"]), false), Cause::Unusable);
        assert_eq!(matches(json!(["a"]), json!(["a"]), true), Cause::Unusable);
    }

    #[test]
    fn a_whole_ref_is_listed_in_refs_and_a_params_path_with_a_field_step_only_by_its_ref_steps() {
        let k = key_path(Start::Params, &["k"]);
        assert_eq!(Right::Ref(k.clone()).refs(), vec![k.clone()]);
        let named = Path {
            start: Start::Params,
            steps: vec![Step::Key("lists".into()), Step::Ref(Box::new(k.clone()))],
        };
        assert_eq!(Right::Ref(named).refs(), vec![k.clone()]);
        let by_field = Path {
            start: Start::Params,
            steps: vec![
                Step::Key("lists".into()),
                Step::Field(Box::new(key_path(Start::Subject, &["y"]))),
            ],
        };
        assert!(Right::Ref(by_field).refs().is_empty());
        assert!(
            Right::Field(key_path(Start::Subject, &["ys"]))
                .refs()
                .is_empty()
        );
        assert!(written(json!(["a"])).refs().is_empty());
    }

    fn lowered(sentence: &str) -> Option<Result<Check, Vec<String>>> {
        let check = tree::parse_check(sentence).unwrap();
        match &check.assertions[0] {
            tree::Assertion::Plain { path, phrase } => {
                lower_phrase(path, phrase, &Scope::new().on_subject())
            }
            other => panic!("{sentence} isn't a plain assertion: {other:?}"),
        }
    }

    fn lowered_check(sentence: &str) -> Check {
        lowered(sentence).unwrap().unwrap()
    }

    #[test]
    fn one_of_reads_into_in_with_written_values_a_ref_or_a_field() {
        match lowered_check("x is not one of \"a\", \"b\"") {
            Check::In(c) => {
                assert!(c.not);
                assert_eq!(c.values, written(json!(["a", "b"])));
            }
            other => panic!("{other:?}"),
        }
        assert!(matches!(
            lowered_check("x is in $params.k"),
            Check::In(In {
                values: Right::Ref(_),
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is in $input.k"),
            Check::In(In {
                values: Right::Ref(_),
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is in ys"),
            Check::In(In {
                values: Right::Field(_),
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is in $params.lists named by $params.k"),
            Check::In(In {
                values: Right::Ref(_),
                ..
            })
        ));
    }

    #[test]
    fn each_contains_phrase_reads_into_contains() {
        for (sentence, all, not) in [
            ("x contains \"a\"", false, false),
            ("x does not contain $params.v", false, true),
            ("x contains all of \"a\", \"b\"", true, false),
            ("x contains none of ys", true, true),
        ] {
            match lowered_check(sentence) {
                Check::Contains(c) => {
                    assert_eq!(matches!(c.wanted, Wanted::All(_)), all, "{sentence}");
                    assert_eq!(c.not, not, "{sentence}");
                }
                other => panic!("{sentence}: {other:?}"),
            }
        }
    }

    #[test]
    fn contains_some_of_and_does_not_contain_all_of_read_into_contains_some() {
        for (sentence, not) in [
            ("x contains some of \"a\", \"b\"", false),
            ("x does not contain all of ys", true),
        ] {
            match lowered_check(sentence) {
                Check::Contains(c) => {
                    assert!(matches!(c.wanted, Wanted::Some(_)), "{sentence}");
                    assert_eq!(c.not, not, "{sentence}");
                }
                other => panic!("{sentence}: {other:?}"),
            }
        }
    }

    #[test]
    fn is_not_a_type_and_is_not_a_non_empty_string_read_into_their_checks() {
        assert!(matches!(
            lowered_check("x is not a list"),
            Check::HasType(HasType {
                kind: Kind::List,
                not: true,
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is not an object"),
            Check::HasType(HasType {
                kind: Kind::Object,
                not: true,
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is not a non-empty string"),
            Check::NonEmptyString(NonEmptyString { not: true, .. })
        ));
    }

    #[test]
    fn matches_type_non_empty_string_and_empty_read_into_their_checks() {
        assert!(matches!(
            lowered_check("x does not match \"^a\""),
            Check::Matches(Matches { not: true, .. })
        ));
        assert!(matches!(
            lowered_check("x is an object"),
            Check::HasType(HasType {
                kind: Kind::Object,
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is a non-empty string"),
            Check::NonEmptyString(_)
        ));
        assert!(matches!(
            lowered_check("x is not empty"),
            Check::Empty(Empty { not: true, .. })
        ));
    }

    #[test]
    fn a_phrase_compare_reads_or_a_count_on_the_right_is_not_read_here() {
        for sentence in [
            "x is 1",
            "x is at least 2",
            "x exists",
            "x contains count of ys",
        ] {
            assert!(lowered(sentence).is_none(), "{sentence}");
        }
    }

    #[test]
    fn written_values_of_mixed_types_are_written_wrong_leaving_null_aside() {
        for sentence in [
            "x is one of \"a\", 1",
            "x is not one of true, 1e2",
            "x contains all of true, 1",
            "x contains none of \"a\", false",
        ] {
            assert_eq!(
                lowered(sentence).unwrap().unwrap_err(),
                ["values of mixed types"],
                "{sentence}"
            );
        }
        assert!(lowered("x is one of \"a\", null").unwrap().is_ok());
        assert!(lowered("x contains all of 1, 2").unwrap().is_ok());
    }

    fn flawed_with(check: &Check, params: Value) -> bool {
        let input = json!({"things": [{"x": "a"}]});
        let ctx = Ctx {
            label: None,
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: Some(&params),
            aliases: BTreeMap::new(),
        };
        check.flawed(&ctx)
    }

    #[test]
    fn a_ref_that_reads_the_wrong_kind_of_value_is_a_flaw_and_a_missing_one_is_not() {
        let in_list = lowered_check("x is in $params.l");
        assert!(flawed_with(&in_list, json!({"l": "a"})));
        assert!(flawed_with(&in_list, json!({"l": ["a", 1]})));
        assert!(!flawed_with(&in_list, json!({"l": []})));
        assert!(!flawed_with(&in_list, json!({"l": ["a"]})));
        assert!(!flawed_with(&in_list, json!({})));
        assert!(!flawed_with(&in_list, json!({"l": null})));
        let all = lowered_check("x contains all of $params.l");
        assert!(flawed_with(&all, json!({"l": []})));
        assert!(flawed_with(&all, json!({"l": "a"})));
        assert!(!flawed_with(&all, json!({"l": ["a"]})));
        let one = lowered_check("x contains $params.v");
        assert!(!flawed_with(&one, json!({"v": [1, "a"]})));
        let patterns = lowered_check("x matches $params.p");
        assert!(flawed_with(&patterns, json!({"p": ["("]})));
        assert!(flawed_with(&patterns, json!({"p": "a"})));
        assert!(!flawed_with(&patterns, json!({"p": ["^a"]})));
    }

    #[test]
    fn a_written_list_or_a_field_on_the_right_is_never_a_flaw() {
        assert!(!flawed_with(
            &lowered_check("x is one of \"a\", \"b\""),
            json!({})
        ));
        assert!(!flawed_with(&lowered_check("x is in ys"), json!({})));
    }

    fn deps_name() -> Right {
        Right::Field(key_path(Start::Subject, &["deps", "name"]))
    }

    fn params_deps_name() -> Right {
        Right::Ref(key_path(Start::Params, &["deps", "name"]))
    }

    fn with_deps(deps: Value) -> Value {
        json!({"x": "click", "deps": deps})
    }

    #[test]
    fn a_field_that_walks_a_list_of_objects_compares_with_what_it_reads_from_each_item() {
        let deps = json!([{"name": "click"}, {"name": "jinja2"}]);
        assert_eq!(
            is_in(with_deps(deps.clone()), deps_name(), false),
            Cause::Satisfied
        );
        assert_eq!(
            is_in(json!({"x": "attrs", "deps": deps}), deps_name(), false),
            Cause::Value
        );
    }

    #[test]
    fn a_walk_fails_every_row_as_absent_when_an_item_has_no_value() {
        let deps = json!([{"name": "click"}, {}]);
        assert_eq!(
            is_in(with_deps(deps.clone()), deps_name(), false),
            Cause::Absent
        );
        assert_eq!(is_in(with_deps(deps), deps_name(), true), Cause::Absent);
    }

    #[test]
    fn a_walk_fails_as_null_when_an_item_has_a_null_value() {
        let deps = json!([{"name": null}]);
        assert_eq!(is_in(with_deps(deps), deps_name(), false), Cause::Null);
    }

    #[test]
    fn a_walk_fails_as_value_when_the_list_is_empty_even_after_is_not_in() {
        assert_eq!(is_in(with_deps(json!([])), deps_name(), true), Cause::Value);
        assert_eq!(
            is_in(with_deps(json!([])), deps_name(), false),
            Cause::Value
        );
    }

    #[test]
    fn a_walk_fails_as_unusable_when_an_item_is_not_an_object_or_the_values_have_more_than_one_type()
     {
        assert_eq!(
            is_in(with_deps(json!(["click"])), deps_name(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(
                with_deps(json!([{"name": "click"}, {"name": 3}])),
                deps_name(),
                false
            ),
            Cause::Unusable
        );
    }

    #[test]
    fn a_path_that_meets_no_list_is_read_as_before() {
        assert_eq!(
            is_in(with_deps(json!("text")), deps_name(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(with_deps(json!(null)), deps_name(), false),
            Cause::Null
        );
        assert_eq!(
            is_in(json!({"x": "click"}), deps_name(), false),
            Cause::Absent
        );
    }

    #[test]
    fn a_ref_that_walks_a_list_of_objects_reads_the_params_the_same_way() {
        let check = In {
            path: x(),
            values: params_deps_name(),
            not: false,
        };
        let params = Some(json!({"deps": [{"name": "click"}, {"name": "jinja2"}]}));
        assert_eq!(
            on(json!({"x": "click"}), params.clone(), |ctx| run_in(
                &check, ctx
            ))
            .cause,
            Cause::Satisfied
        );
        assert_eq!(
            on(json!({"x": "attrs"}), params, |ctx| run_in(&check, ctx)).cause,
            Cause::Value
        );
        assert_eq!(
            on(
                json!({"x": "click"}),
                Some(json!({"deps": [{"name": "click"}, {}]})),
                |ctx| run_in(&check, ctx)
            )
            .cause,
            Cause::Absent
        );
    }

    #[test]
    fn a_walk_names_the_path_with_brackets_and_lists_where_each_value_was_read() {
        let input = json!({"things": [with_deps(json!([{"name": "click"}, {}]))]});
        let ctx = Ctx {
            label: None,
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        let walk = walked(&key_path(Start::Subject, &["deps", "name"]), &ctx).unwrap();
        assert_eq!(walk.name, "deps[].name");
        assert_eq!(walk.value, vec![json!("click"), Value::Null]);
        assert_eq!(
            walk.locations,
            vec!["/things/0/deps/0/name", "/things/0/deps/1"]
        );
        assert_eq!(walk.cause, Some(Cause::Absent));
        assert_eq!(walk.text, "item 2 of deps: name is missing");
    }

    fn position_walk(w: Value) -> Walked {
        steps_walk(w, vec![Step::Index(0)])
    }

    fn steps_walk(w: Value, after_x: Vec<Step>) -> Walked {
        let input = json!({"things": [{"x": "a", "w": w}]});
        let ctx = Ctx {
            label: None,
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        let mut steps = vec![Step::Key("w".into()), Step::Key("X".into())];
        steps.extend(after_x);
        let path = Path {
            start: Start::Subject,
            steps,
        };
        walked(&path, &ctx).unwrap()
    }

    #[test]
    fn a_position_on_a_value_that_is_not_a_list_fails_as_unusable_and_names_the_value() {
        for (held, shown) in [
            (json!("ab"), "\"ab\""),
            (json!(3), "3"),
            (json!({"y": 1}), "{\"y\": 1}"),
            (json!(true), "true"),
        ] {
            let walk = position_walk(json!([{"X": ["a"]}, {"X": held}]));
            assert_eq!(walk.cause, Some(Cause::Unusable));
            assert_eq!(
                walk.text,
                format!("item 2 of w: X is {shown}, which isn't a list")
            );
        }
    }

    #[test]
    fn a_position_on_a_missing_or_null_value_fails_as_absent_like_the_rego_engine() {
        for held in [json!({}), json!({"X": null})] {
            let walk = position_walk(json!([{"X": ["a"]}, held]));
            assert_eq!(walk.cause, Some(Cause::Absent));
            assert_eq!(walk.text, "item 2 of w: item 1 of X is missing");
        }
    }

    #[test]
    fn a_position_on_lists_in_every_item_walks_without_a_fault() {
        let walk = position_walk(json!([{"X": ["a"]}, {"X": ["b"]}]));
        assert_eq!(walk.cause, None);
    }

    #[test]
    fn a_position_after_a_position_fails_as_unusable_and_names_the_value_that_is_not_a_list() {
        let steps = || vec![Step::Index(0), Step::Index(0)];
        let walk = steps_walk(json!([{"X": [["a"]]}, {"X": ["x"]}]), steps());
        assert_eq!(walk.cause, Some(Cause::Unusable));
        assert_eq!(
            walk.text,
            "item 2 of w: item 1 of X is \"x\", which isn't a list"
        );
        let walk = steps_walk(json!([{"X": [["a"]]}, {"X": "x"}]), steps());
        assert_eq!(walk.cause, Some(Cause::Unusable));
        assert_eq!(walk.text, "item 2 of w: X is \"x\", which isn't a list");
        let walk = steps_walk(json!([{"X": [["a"]]}, {"X": [["b"]]}]), steps());
        assert_eq!(walk.cause, None);
    }

    #[test]
    fn a_key_after_a_position_fails_as_unusable_when_another_item_holds_no_object_there() {
        let key = |name: &str| Step::Key(name.into());
        let walk = steps_walk(
            json!([{"X": [{"k": ["a"]}]}, {"X": ["x"]}]),
            vec![Step::Index(0), key("k")],
        );
        assert_eq!(walk.cause, Some(Cause::Unusable));
        let walk = steps_walk(
            json!([{"X": [{"k": [["a"]]}]}, {"X": [{"k": "s"}]}]),
            vec![Step::Index(0), key("k"), Step::Index(0)],
        );
        assert_eq!(walk.cause, Some(Cause::Unusable));
        let walk = steps_walk(
            json!([{"X": [{"k": ["a"]}]}, {"X": [{"k": ["b"]}]}]),
            vec![Step::Index(0), key("k")],
        );
        assert_eq!(walk.cause, None);
    }
}
