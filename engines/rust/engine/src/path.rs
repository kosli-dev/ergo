use crate::cause::Cause;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Start {
    Subject,
    Own,
    Input,
    Params,
    Alias(String),
    Part(Box<PartStart>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PartStart {
    pub name: String,
    pub base: Start,
    pub steps: Vec<Step>,
    pub id: Option<Vec<Step>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    Key(String),
    Index(u64),
    Ref(Box<Path>),
    Field(Box<Path>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Path {
    pub start: Start,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    Found,
    Null,
    Absent,
    Unusable,
    NotAnObject,
}

impl Outcome {
    pub fn cause(self) -> Option<Cause> {
        match self {
            Outcome::Found => None,
            Outcome::Null => Some(Cause::Null),
            Outcome::Absent => Some(Cause::Absent),
            Outcome::Unusable => Some(Cause::Unusable),
            Outcome::NotAnObject => Some(Cause::NotAnObject),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Root {
    Input,
    Params,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Location {
    pub root: Root,
    pub pointer: String,
}

fn escape_token(token: &str) -> String {
    token.replace('~', "~0").replace('/', "~1")
}

impl Location {
    pub fn input_root() -> Location {
        Location {
            root: Root::Input,
            pointer: String::new(),
        }
    }

    pub fn params_root() -> Location {
        Location {
            root: Root::Params,
            pointer: String::new(),
        }
    }

    pub fn key(&self, key: &str) -> Location {
        Location {
            root: self.root,
            pointer: format!("{}/{}", self.pointer, escape_token(key)),
        }
    }

    pub fn index(&self, index: u64) -> Location {
        Location {
            root: self.root,
            pointer: format!("{}/{}", self.pointer, index),
        }
    }

    pub fn render(&self) -> String {
        match self.root {
            Root::Input => self.pointer.clone(),
            Root::Params => format!("$params:{}", self.pointer),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Located<'a> {
    pub value: &'a Value,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct Ctx<'a> {
    pub subject: Located<'a>,
    pub input: &'a Value,
    pub params: Option<&'a Value>,
    pub aliases: BTreeMap<String, Located<'a>>,
    pub label: Option<String>,
    /// False only while a plain check of a subject that isn't a child subject
    /// runs: not a `for` line, a one-line `every` or `some`, a `count of` or
    /// a `sum of`, nor a `from` line. When it's true, a key read from an
    /// input that is a list, like `$input.k`, ends `Unusable`, and a path
    /// from such an input whose key can't be read ends with the key's
    /// outcome. When it's false, both end `NotAnObject`.
    pub item_by_item: bool,
    /// True while a line of an `any_of` option runs.
    pub in_option: bool,
}

impl<'a> Ctx<'a> {
    pub fn subject_label(&self) -> &str {
        self.label.as_deref().unwrap_or("the subject")
    }

    /// Returns a copy of this context with `item_by_item` set.
    #[must_use]
    pub fn item_by_item(&self) -> Ctx<'a> {
        Ctx {
            item_by_item: true,
            ..self.clone()
        }
    }
}

#[derive(Debug, Clone)]
pub struct Read<'a> {
    pub outcome: Outcome,
    pub value: Option<&'a Value>,
    pub location: Option<Location>,
    pub step_unreadable: bool,
}

pub const OUTER: &str = "$outer";

const ROOT_OWN: &str = ".";

pub fn root(own: bool) -> Start {
    Start::Part(Box::new(PartStart {
        name: if own {
            ROOT_OWN.to_string()
        } else {
            String::new()
        },
        base: Start::Alias(OUTER.to_string()),
        steps: Vec::new(),
        id: None,
    }))
}

pub fn is_root(start: &Start) -> bool {
    matches!(start, Start::Part(part)
        if (part.name.is_empty() || part.name == ROOT_OWN)
            && part.steps.is_empty()
            && part.base == Start::Alias(OUTER.to_string()))
}

pub fn names_the_subject(start: &Start) -> bool {
    matches!(start, Start::Part(part)
        if !part.name.is_empty()
            && part.name != ROOT_OWN
            && part.steps.is_empty()
            && part.base == Start::Alias(OUTER.to_string()))
}

pub fn is_root_own(start: &Start) -> bool {
    is_root(start) && matches!(start, Start::Part(part) if part.name == ROOT_OWN)
}

pub enum Resolved {
    Key(String),
    Index(u64),
}

fn ended<'a>(outcome: Outcome, location: Location) -> Read<'a> {
    Read {
        outcome,
        value: None,
        location: Some(location),
        step_unreadable: false,
    }
}

pub fn is_ref(path: &Path) -> bool {
    matches!(path.start, Start::Params | Start::Input)
        && path
            .steps
            .iter()
            .all(|step| matches!(step, Step::Key(_) | Step::Index(_)))
}

pub fn step_refs(path: &Path) -> Vec<Path> {
    path.steps
        .iter()
        .filter_map(|step| match step {
            Step::Ref(reference) if is_ref(reference) => Some((**reference).clone()),
            _ => None,
        })
        .collect()
}

pub fn resolve(step: &Step, ctx: &Ctx) -> Result<Resolved, Outcome> {
    match step {
        Step::Key(key) => Ok(Resolved::Key(key.clone())),
        Step::Index(index) => Ok(Resolved::Index(*index)),
        Step::Field(field) => {
            let read = read(field, ctx);
            if read.outcome != Outcome::Found {
                return Err(read.outcome);
            }
            match read.value {
                Some(Value::String(text)) => Ok(Resolved::Key(text.clone())),
                _ => Err(Outcome::Unusable),
            }
        }
        Step::Ref(reference) => {
            let read = read(reference, ctx);
            if reference.start == Start::Input
                && read.outcome == Outcome::NotAnObject
                && ctx.item_by_item
            {
                return Err(Outcome::Unusable);
            }
            if read.outcome != Outcome::Found {
                return Err(read.outcome);
            }
            match read.value {
                Some(Value::String(text)) => Ok(Resolved::Key(text.clone())),
                _ => Err(Outcome::Unusable),
            }
        }
    }
}

pub static ABSENT: Value = Value::Null;

fn found_or_absent<'a>(at: &Located<'a>) -> Result<(&'a Value, Location, bool), Read<'a>> {
    if std::ptr::eq(at.value, &ABSENT) {
        Err(ended(Outcome::Absent, at.location.clone()))
    } else {
        Ok((at.value, at.location.clone(), true))
    }
}

pub fn start_of<'a>(start: &Start, ctx: &Ctx<'a>) -> Result<(&'a Value, Location, bool), Read<'a>> {
    match start {
        Start::Subject | Start::Own => found_or_absent(&ctx.subject),
        Start::Input => Ok((ctx.input, Location::input_root(), true)),
        Start::Params => match ctx.params {
            Some(params) => Ok((params, Location::params_root(), false)),
            None => Err(ended(Outcome::Absent, Location::params_root())),
        },
        Start::Alias(name) => match ctx.aliases.get(name) {
            Some(found) => found_or_absent(found),
            None => Err(Read {
                outcome: Outcome::Absent,
                value: None,
                location: None,
                step_unreadable: false,
            }),
        },
        Start::Part(part) => start_of(&part.base, ctx),
    }
}

pub fn leading_steps(start: &Start) -> &[Step] {
    match start {
        Start::Part(part) => &part.steps,
        _ => &[],
    }
}

pub fn part_tag(path: &Path, ctx: &Ctx) -> Option<(String, Value)> {
    let Start::Part(part) = &path.start else {
        return None;
    };
    if part.steps.is_empty() {
        return None;
    }
    let id = match &part.id {
        None => Value::Null,
        Some(steps) => {
            let inside = Path {
                start: Start::Part(Box::new(PartStart {
                    id: None,
                    ..(**part).clone()
                })),
                steps: steps.clone(),
            };
            let read = read(&inside, ctx);
            match (read.outcome, read.value) {
                (Outcome::Found, Some(found)) => found.clone(),
                _ => Value::Null,
            }
        }
    };
    Some((part.name.clone(), id))
}

pub fn read<'a>(path: &Path, ctx: &Ctx<'a>) -> Read<'a> {
    let mut walked = walk(path, ctx);
    if !walked.step_unreadable
        && !(reads_a_list_input(path, ctx) && walked.outcome == Outcome::NotAnObject)
        && matches!(
            walked.outcome,
            Outcome::Absent | Outcome::Null | Outcome::Unusable | Outcome::NotAnObject
        )
    {
        let failed = leading_steps(&path.start)
            .iter()
            .chain(path.steps.iter())
            .filter(|step| matches!(step, Step::Ref(_)))
            .find_map(|step| resolve(step, ctx).err());
        if let Some(outcome) = failed {
            walked.outcome = outcome;
            walked.value = None;
            walked.step_unreadable = true;
        }
    }
    walked
}

fn reads_a_list_input(path: &Path, ctx: &Ctx) -> bool {
    path.start == Start::Input && ctx.input.is_array() && !ctx.item_by_item
}

fn walk<'a>(path: &Path, ctx: &Ctx<'a>) -> Read<'a> {
    let (mut value, mut location, from_subject) = match start_of(&path.start, ctx) {
        Ok(found) => found,
        Err(read) => return read,
    };
    let steps = leading_steps(&path.start).iter().chain(path.steps.iter());
    for (at, step) in steps.enumerate() {
        if at == 0 && reads_a_list_input(path, ctx) && matches!(step, Step::Ref(_)) {
            return ended(Outcome::NotAnObject, location);
        }
        let resolved = match resolve(step, ctx) {
            Ok(resolved) => resolved,
            Err(outcome) => {
                let mut stopped = ended(outcome, location);
                stopped.step_unreadable = true;
                return stopped;
            }
        };
        if at == 0 && from_subject && !value.is_object() && !matches!(resolved, Resolved::Index(_))
        {
            return ended(Outcome::NotAnObject, location);
        }
        match (resolved, value) {
            (Resolved::Index(_), Value::Null) if path.start != Start::Params => {
                return ended(Outcome::Null, location);
            }
            (_, Value::Null) if at > 0 => return ended(Outcome::Null, location),
            (_, Value::Null) => return ended(Outcome::Absent, location),
            (Resolved::Key(key), Value::Object(map)) => match map.get(&key) {
                Some(next) => {
                    location = location.key(&key);
                    value = next;
                }
                None => return ended(Outcome::Absent, location),
            },
            (Resolved::Index(index), Value::Array(items)) => {
                match usize::try_from(index).ok().and_then(|i| items.get(i)) {
                    Some(next) => {
                        location = location.index(index);
                        value = next;
                    }
                    None => return ended(Outcome::Absent, location),
                }
            }
            _ => return ended(Outcome::Unusable, location),
        }
    }
    let outcome = if value.is_null() {
        Outcome::Null
    } else {
        Outcome::Found
    };
    Read {
        outcome,
        value: Some(value),
        location: Some(location),
        step_unreadable: false,
    }
}

#[cfg(test)]
mod tests;
