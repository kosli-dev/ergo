pub mod any_of;
pub mod compare;
pub mod equals;
pub mod for_line;
pub mod kinds;
pub mod list_start;
pub mod lists;
pub mod message;
pub mod present;
pub mod range;
pub mod tally;
pub mod time;
pub mod walk;

use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path, Step};
use serde_json::{Map, Value, json};

#[derive(Debug, Clone, PartialEq)]
pub struct Part {
    pub name: String,
    pub id: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Input {
    pub name: String,
    pub value: Value,
    pub locations: Vec<String>,
    pub part: Option<Part>,
    pub state: Outcome,
    pub null_at: Option<String>,
}

impl Input {
    pub fn stopped_at(&self) -> &str {
        match (self.state, &self.null_at) {
            (Outcome::Null, Some(name)) => name,
            _ => &self.name,
        }
    }

    pub fn to_json(&self) -> Value {
        let mut entry = Map::new();
        entry.insert("name".to_string(), json!(self.name));
        entry.insert("value".to_string(), self.value.clone());
        entry.insert("locations".to_string(), json!(self.locations));
        if let Some(part) = &self.part {
            entry.insert(
                "part".to_string(),
                json!({"name": part.name, "id": part.id}),
            );
        }
        Value::Object(entry)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Verdict {
    pub cause: Cause,
    pub inputs: Vec<Input>,
}

impl Verdict {
    pub fn passed(&self) -> bool {
        self.cause == Cause::Satisfied
    }
}

pub struct ReadPath {
    pub outcome: Outcome,
    pub step_unreadable: bool,
    pub value: Option<Value>,
    pub inputs: Vec<Input>,
}

pub fn read_path(path: &Path, ctx: &Ctx) -> ReadPath {
    let read = path::read(path, ctx);
    let value = read.value.cloned();
    let mut inputs = vec![Input {
        name: name::name(path),
        value: value.clone().unwrap_or(Value::Null),
        locations: read.location.iter().map(|l| l.render()).collect(),
        part: path::part_tag(path, ctx).map(|(name, id)| Part { name, id }),
        state: read.outcome,
        null_at: null_step_name(path, ctx),
    }];
    inputs.extend(field_inputs(path, ctx));
    ReadPath {
        outcome: read.outcome,
        step_unreadable: read.step_unreadable,
        value,
        inputs,
    }
}

pub fn null_step_name(path: &Path, ctx: &Ctx) -> Option<String> {
    let read = path::read(path, ctx);
    if read.outcome != path::Outcome::Null || read.step_unreadable {
        return None;
    }
    (0..path.steps.len()).find_map(|at| {
        let prefix = Path {
            start: path.start.clone(),
            steps: path.steps[..at].to_vec(),
        };
        let read = path::read(&prefix, ctx);
        (read.outcome == path::Outcome::Null).then(|| name::name(&prefix))
    })
}

pub fn field_inputs(path: &Path, ctx: &Ctx) -> Vec<Input> {
    if ctx.aliases.contains_key(path::OUTER) {
        return Vec::new();
    }
    path.steps
        .iter()
        .filter_map(|step| match step {
            Step::Field(field) => {
                let found = path::read(field, ctx);
                Some(Input {
                    name: name::name(field),
                    value: found.value.cloned().unwrap_or(Value::Null),
                    locations: found.location.iter().map(|l| l.render()).collect(),
                    part: None,
                    state: found.outcome,
                    null_at: None,
                })
            }
            _ => None,
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq)]
pub enum Check {
    Present(present::Present),
    Compare(compare::Compare),
    CompareTime(time::CompareTime),
    Equals(equals::Equals),
    Range(range::Range),
    Tally(tally::Tally),
    Walk(Box<walk::Walk>),
    For(Box<for_line::For>),
    AnyOf(any_of::AnyOf),
    In(lists::In),
    Contains(lists::Contains),
    Matches(lists::Matches),
    HasType(kinds::HasType),
    NonEmptyString(kinds::NonEmptyString),
    Empty(kinds::Empty),
}

#[derive(Debug, Clone, Copy)]
pub struct SidePath<'a> {
    pub path: &'a Path,
    pub needs_list: bool,
}

impl Check {
    pub fn sides(&self) -> Vec<Vec<SidePath<'_>>> {
        fn plain(side: &compare::Side) -> Vec<SidePath<'_>> {
            side.paths()
                .into_iter()
                .map(|path| SidePath {
                    path,
                    needs_list: false,
                })
                .collect()
        }
        match self {
            Check::Compare(check) => vec![plain(&check.left), plain(&check.right)],
            Check::CompareTime(check) => vec![plain(&check.left), plain(&check.right)],
            Check::Tally(check) => check.sides(),
            other => other
                .left_path()
                .map(|path| {
                    vec![vec![SidePath {
                        path,
                        needs_list: false,
                    }]]
                })
                .unwrap_or_default(),
        }
    }

    pub fn left_path(&self) -> Option<&Path> {
        match self {
            Check::Present(check) => Some(&check.path),
            Check::Equals(check) => Some(&check.path),
            Check::Range(check) => Some(&check.path),
            Check::Compare(check) => match &check.left {
                compare::Side::Path(path) => Some(path),
                compare::Side::Value(_) | compare::Side::Join(_) => None,
            },
            Check::CompareTime(check) => match &check.left {
                compare::Side::Path(path) => Some(path),
                compare::Side::Value(_) | compare::Side::Join(_) => None,
            },
            Check::In(check) => Some(&check.path),
            Check::Contains(check) => Some(&check.path),
            Check::Matches(check) => Some(&check.path),
            Check::HasType(check) => Some(&check.path),
            Check::NonEmptyString(check) => Some(&check.path),
            Check::Empty(check) => Some(&check.path),
            Check::Tally(check) => check.paths().into_iter().next(),
            Check::Walk(_) | Check::For(_) | Check::AnyOf(_) => None,
        }
    }

    pub fn paths(&self) -> Vec<&Path> {
        match self {
            Check::Present(check) => vec![&check.path],
            Check::Equals(check) => vec![&check.path],
            Check::Range(check) => vec![&check.path],
            Check::Compare(check) => [&check.left, &check.right]
                .into_iter()
                .flat_map(compare::Side::paths)
                .collect(),
            Check::CompareTime(check) => [&check.left, &check.right]
                .into_iter()
                .flat_map(compare::Side::paths)
                .collect(),
            Check::Tally(check) => check.paths(),
            Check::AnyOf(check) => check.paths(),
            Check::In(check) => check.paths(),
            Check::Contains(check) => check.paths(),
            Check::Matches(check) => check.paths(),
            Check::HasType(check) => vec![&check.path],
            Check::NonEmptyString(check) => vec![&check.path],
            Check::Empty(check) => vec![&check.path],
            Check::Walk(_) | Check::For(_) => Vec::new(),
        }
    }

    pub fn with_left(&self, left: Path) -> Check {
        match self {
            Check::Present(check) => Check::Present(present::Present {
                path: left,
                ..check.clone()
            }),
            Check::Equals(check) => Check::Equals(equals::Equals {
                path: left,
                ..check.clone()
            }),
            Check::Range(check) => Check::Range(range::Range {
                path: left,
                ..check.clone()
            }),
            Check::Compare(check) => Check::Compare(compare::Compare {
                left: compare::Side::Path(left),
                ..check.clone()
            }),
            Check::CompareTime(check) => Check::CompareTime(time::CompareTime {
                left: compare::Side::Path(left),
                ..check.clone()
            }),
            Check::In(check) => Check::In(lists::In {
                path: left,
                ..check.clone()
            }),
            Check::Contains(check) => Check::Contains(lists::Contains {
                path: left,
                ..check.clone()
            }),
            Check::Matches(check) => Check::Matches(lists::Matches {
                path: left,
                ..check.clone()
            }),
            Check::HasType(check) => Check::HasType(kinds::HasType {
                path: left,
                ..check.clone()
            }),
            Check::NonEmptyString(check) => Check::NonEmptyString(kinds::NonEmptyString {
                path: left,
                ..check.clone()
            }),
            Check::Empty(check) => Check::Empty(kinds::Empty {
                path: left,
                ..check.clone()
            }),
            Check::Tally(_) | Check::Walk(_) | Check::For(_) | Check::AnyOf(_) => self.clone(),
        }
    }

    /// Returns true when the check reads its lists item by item: a `for`
    /// line, a one-line `every` or `some`, a `count of` or `sum of`, or an
    /// `any_of` with one of those among its options. It runs with
    /// [`Ctx::item_by_item`] set.
    #[must_use]
    pub fn reads_by_item(&self) -> bool {
        match self {
            Check::Walk(_) | Check::For(_) => true,
            Check::Tally(check) => check.counts(),
            Check::AnyOf(check) => check.options.iter().flatten().any(Check::reads_by_item),
            _ => false,
        }
    }

    pub fn refs(&self) -> Vec<Path> {
        match self {
            Check::Present(check) => check.refs(),
            Check::Equals(check) => check.refs(),
            Check::Range(check) => check.refs(),
            Check::Compare(check) => check.refs(),
            Check::CompareTime(check) => check.refs(),
            Check::Tally(check) => check.refs(),
            Check::Walk(check) => check.refs(),
            Check::For(check) => check.refs(),
            Check::AnyOf(check) => check.refs(),
            Check::In(check) => check.refs(),
            Check::Contains(check) => check.refs(),
            Check::Matches(check) => check.refs(),
            Check::HasType(check) => check.refs(),
            Check::NonEmptyString(check) => check.refs(),
            Check::Empty(check) => check.refs(),
        }
    }

    pub fn listed_refs(&self) -> Vec<(Path, bool)> {
        if let Check::AnyOf(check) = self {
            return check
                .options
                .iter()
                .flatten()
                .flat_map(Check::listed_refs)
                .collect();
        }
        let walking = self.walking_refs();
        let mut refs: Vec<(Path, bool)> = self
            .refs()
            .into_iter()
            .map(|reference| {
                let walks = walking.contains(&reference);
                (reference, walks)
            })
            .collect();
        refs.extend(self.read_refs());
        refs
    }

    fn read_refs(&self) -> Vec<(Path, bool)> {
        let own = |paths: Vec<&Path>, walks: bool| -> Vec<(Path, bool)> {
            paths
                .into_iter()
                .filter_map(|path| read_ref(path, walks))
                .collect()
        };
        match self {
            Check::Walk(check) => own(vec![&check.path], true)
                .into_iter()
                .chain(
                    check
                        .whose
                        .iter()
                        .chain(std::iter::once(&*check.check))
                        .flat_map(Check::read_refs),
                )
                .collect(),
            Check::For(check) => check
                .items
                .iter()
                .flat_map(|item| {
                    own(vec![&item.path], true)
                        .into_iter()
                        .chain(item.whose.iter().flat_map(Check::read_refs))
                })
                .chain(
                    check
                        .sentences
                        .iter()
                        .flat_map(|sentence| sentence.check.read_refs()),
                )
                .collect(),
            Check::AnyOf(check) => check
                .options
                .iter()
                .flatten()
                .flat_map(Check::read_refs)
                .collect(),
            Check::Tally(check) => {
                let counted = check.counted_paths();
                check
                    .paths()
                    .into_iter()
                    .filter_map(|path| {
                        let walks = counted.iter().any(|c| std::ptr::eq(*c, path));
                        read_ref(path, walks)
                    })
                    .chain(check.counted_whose().flat_map(Check::read_refs))
                    .collect()
            }
            Check::In(check) => own(check.paths(), false)
                .into_iter()
                .chain(named_prefixes(check.values.ref_paths()))
                .collect(),
            Check::Contains(check) => {
                let right = match &check.wanted {
                    lists::Wanted::One(right)
                    | lists::Wanted::All(right)
                    | lists::Wanted::Some(right) => right,
                };
                own(check.paths(), false)
                    .into_iter()
                    .chain(named_prefixes(right.ref_paths()))
                    .collect()
            }
            Check::Matches(check) => own(check.paths(), false)
                .into_iter()
                .chain(named_prefixes(check.patterns.ref_paths()))
                .collect(),
            _ => own(self.paths(), false),
        }
    }

    pub fn walking_refs(&self) -> Vec<Path> {
        match self {
            Check::Tally(check) => check.walking_refs(),
            Check::Walk(check) => check.walking_refs(),
            Check::For(check) => check.walking_refs(),
            Check::AnyOf(check) => check.walking_refs(),
            Check::In(check) => check.values.ref_paths().into_iter().cloned().collect(),
            Check::Matches(check) => check.patterns.ref_paths().into_iter().cloned().collect(),
            Check::Contains(check) => match &check.wanted {
                lists::Wanted::One(_) => Vec::new(),
                lists::Wanted::All(right) | lists::Wanted::Some(right) => {
                    right.ref_paths().into_iter().cloned().collect()
                }
            },
            _ => Vec::new(),
        }
    }

    pub fn flawed(&self, ctx: &Ctx) -> bool {
        match self {
            Check::AnyOf(check) => check.flawed(ctx),
            Check::Walk(check) => check.flawed(ctx),
            Check::In(check) => check.flawed(ctx),
            Check::Contains(check) => check.flawed(ctx),
            Check::Matches(check) => check.flawed(ctx),
            _ => false,
        }
    }
}

fn read_ref(path: &Path, walks: bool) -> Option<(Path, bool)> {
    if path::is_ref(path) {
        return Some((path.clone(), walks));
    }
    path::named_prefix(path).map(|prefix| (prefix, false))
}

fn named_prefixes(paths: Vec<&Path>) -> Vec<(Path, bool)> {
    paths
        .into_iter()
        .filter_map(path::named_prefix)
        .map(|prefix| (prefix, false))
        .collect()
}

pub struct Ran {
    pub verdict: Verdict,
    pub failed_items: Option<Vec<Value>>,
    pub message: Option<String>,
    pub parts: Option<Vec<String>>,
}

thread_local! {
    static WALKED_ROOTS: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

pub fn walked_roots_on() -> bool {
    WALKED_ROOTS.with(std::cell::Cell::get)
}

pub fn reading_walked_roots<T>(work: impl FnOnce() -> T) -> T {
    let was = WALKED_ROOTS.with(|on| on.replace(true));
    let out = work();
    WALKED_ROOTS.with(|on| on.set(was));
    out
}

pub fn run_full(check: &Check, ctx: &Ctx) -> Ran {
    if check.reads_by_item() && !ctx.item_by_item {
        return run_full(check, &ctx.item_by_item());
    }
    match check {
        Check::Walk(check) => {
            let run = walk::run(check, ctx);
            Ran {
                verdict: run.verdict,
                failed_items: Some(run.failed_items),
                message: run.message,
                parts: Some(run.parts),
            }
        }
        Check::For(check) => {
            let run = check.run(ctx);
            Ran {
                verdict: run.verdict,
                failed_items: Some(run.failed_items),
                message: run.message,
                parts: None,
            }
        }
        other => Ran {
            verdict: run(other, ctx),
            failed_items: None,
            message: None,
            parts: None,
        },
    }
}

pub fn run(check: &Check, ctx: &Ctx) -> Verdict {
    if check.reads_by_item() && !ctx.item_by_item {
        return run(check, &ctx.item_by_item());
    }
    match check {
        Check::Present(check) => present::run(check, ctx),
        Check::Compare(check) => compare::run(check, ctx),
        Check::CompareTime(check) => time::run(check, ctx),
        Check::Equals(check) => equals::run(check, ctx),
        Check::Range(check) => range::run(check, ctx),
        Check::Tally(check) => tally::run(check, ctx),
        Check::Walk(check) => walk::run(check, ctx).verdict,
        Check::For(check) => check.run(ctx).verdict,
        Check::AnyOf(check) => any_of::run(check, ctx),
        Check::In(check) => lists::run_in(check, ctx),
        Check::Contains(check) => lists::run_contains(check, ctx),
        Check::Matches(check) => lists::run_matches(check, ctx),
        Check::HasType(check) => kinds::run_has_type(check, ctx),
        Check::NonEmptyString(check) => kinds::run_non_empty_string(check, ctx),
        Check::Empty(check) => kinds::run_empty(check, ctx),
    }
}

pub fn verdict(passed: bool) -> Cause {
    if passed {
        Cause::Satisfied
    } else {
        Cause::Value
    }
}

#[cfg(test)]
mod tests;
