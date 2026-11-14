use super::{Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::path::{self, Ctx, Outcome, Path, Start, Step};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Present {
    pub path: Path,
    pub missing: bool,
}

impl Present {
    pub fn refs(&self) -> Vec<Path> {
        path::step_refs(&self.path)
    }
}

pub fn run(check: &Present, ctx: &Ctx) -> Verdict {
    let read = read_path(&check.path, ctx);
    let no_params = check.path.start == Start::Params && ctx.params.is_none();
    let key_unreadable = check
        .path
        .steps
        .iter()
        .any(|step| matches!(step, Step::Field(_)) && path::resolve(step, ctx).is_err());
    let cause = match read.outcome {
        outcome if read.step_unreadable => outcome.cause().unwrap_or(Cause::Unusable),
        Outcome::Null if key_unreadable && super::message::stops_at_a_null(&check.path, ctx) => {
            Cause::Null
        }
        Outcome::Absent | Outcome::Null if key_unreadable => Cause::Absent,
        Outcome::Found => verdict(!check.missing),
        Outcome::Absent | Outcome::Null if no_params => Cause::Absent,
        Outcome::Absent | Outcome::Null => verdict(check.missing),
        other => other.cause().unwrap_or(Cause::Unusable),
    };
    Verdict {
        cause,
        inputs: read.inputs,
    }
}

#[cfg(test)]
mod tests;
