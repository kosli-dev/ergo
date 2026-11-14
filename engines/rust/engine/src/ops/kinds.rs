use super::{Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::path::{Ctx, Path, step_refs};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    List,
    String,
    Number,
    Boolean,
    Object,
}

#[derive(Debug, Clone, PartialEq)]
pub struct HasType {
    pub path: Path,
    pub kind: Kind,
    pub not: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NonEmptyString {
    pub path: Path,
    pub not: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Empty {
    pub path: Path,
    pub not: bool,
}

impl HasType {
    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
    }
}

impl NonEmptyString {
    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
    }
}

impl Empty {
    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
    }
}

fn judged(path: &Path, ctx: &Ctx, decide: impl FnOnce(&Value) -> Cause) -> Verdict {
    let read = read_path(path, ctx);
    let cause = match (read.outcome.cause(), &read.value) {
        (Some(cause), _) => cause,
        (None, Some(found)) => decide(found),
        (None, None) => Cause::Unusable,
    };
    Verdict {
        cause,
        inputs: read.inputs,
    }
}

pub fn run_has_type(check: &HasType, ctx: &Ctx) -> Verdict {
    judged(&check.path, ctx, |found| {
        let has = matches!(
            (check.kind, found),
            (Kind::List, Value::Array(_))
                | (Kind::String, Value::String(_))
                | (Kind::Number, Value::Number(_))
                | (Kind::Boolean, Value::Bool(_))
                | (Kind::Object, Value::Object(_))
        );
        verdict(has != check.not)
    })
}

pub fn run_non_empty_string(check: &NonEmptyString, ctx: &Ctx) -> Verdict {
    judged(&check.path, ctx, |found| {
        let full = matches!(found, Value::String(s) if !s.is_empty());
        verdict(full != check.not)
    })
}

pub fn run_empty(check: &Empty, ctx: &Ctx) -> Verdict {
    judged(&check.path, ctx, |found| {
        let empty = match found {
            Value::String(s) => s.is_empty(),
            Value::Array(items) => items.is_empty(),
            _ => return Cause::Unusable,
        };
        verdict(empty != check.not)
    })
}

#[cfg(test)]
mod tests;
