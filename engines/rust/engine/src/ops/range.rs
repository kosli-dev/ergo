use super::{Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::path::{self, Ctx, Outcome, Path};
use crate::value;
use serde_json::{Number, Value};

#[derive(Debug, Clone, PartialEq)]
pub struct Range {
    pub path: Path,
    pub min: Number,
    pub max: Number,
    pub outside: bool,
}

impl Range {
    pub fn refs(&self) -> Vec<Path> {
        path::step_refs(&self.path)
    }
}

pub fn run(check: &Range, ctx: &Ctx) -> Verdict {
    let read = read_path(&check.path, ctx);
    let cause = match (read.outcome, &read.value) {
        (Outcome::Found, Some(Value::Number(n))) => value::between(&check.min, n, &check.max)
            .map_or(Cause::Unusable, |inside| verdict(inside != check.outside)),
        (Outcome::Found, _) => Cause::Unusable,
        (other, _) => other.cause().unwrap_or(Cause::Unusable),
    };
    Verdict {
        cause,
        inputs: read.inputs,
    }
}

#[cfg(test)]
mod tests;
