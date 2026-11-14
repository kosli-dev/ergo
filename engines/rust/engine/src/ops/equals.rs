use super::{Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::path::{self, Ctx, Outcome, Path};
use crate::value;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub struct Equals {
    pub path: Path,
    pub value: Value,
}

impl Equals {
    pub fn refs(&self) -> Vec<Path> {
        path::step_refs(&self.path)
    }
}

pub fn run(check: &Equals, ctx: &Ctx) -> Verdict {
    let read = read_path(&check.path, ctx);
    let cause = match (read.outcome, &read.value) {
        (Outcome::Null, _) => {
            if check.value.is_null() {
                Cause::Satisfied
            } else {
                Cause::Null
            }
        }
        (Outcome::Found, Some(found)) if check.value.is_null() || found.is_null() => Cause::Value,
        (Outcome::Found, Some(found))
            if value::type_name(found) != value::type_name(&check.value) =>
        {
            Cause::Unusable
        }
        (Outcome::Found, Some(found)) => {
            value::equal(found, &check.value).map_or(Cause::Unusable, verdict)
        }
        (other, _) => other.cause().unwrap_or(Cause::Unusable),
    };
    Verdict {
        cause,
        inputs: read.inputs,
    }
}

#[cfg(test)]
mod tests;
