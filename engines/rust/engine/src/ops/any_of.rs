use super::{Check, Input, Verdict, run_full};
use crate::cause::Cause;
use crate::path::{self, Ctx, Path, Start};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub struct AnyOf {
    pub names: Vec<String>,
    pub options: Vec<Vec<Check>>,
}

impl AnyOf {
    pub fn refs(&self) -> Vec<Path> {
        self.checks().flat_map(Check::refs).collect()
    }

    pub fn walking_refs(&self) -> Vec<Path> {
        self.checks().flat_map(Check::walking_refs).collect()
    }

    pub fn paths(&self) -> Vec<&Path> {
        self.checks().flat_map(Check::paths).collect()
    }

    pub fn flawed(&self, ctx: &Ctx) -> bool {
        self.checks().any(|check| check.flawed(ctx))
    }

    fn checks(&self) -> impl Iterator<Item = &Check> {
        self.options.iter().flatten()
    }
}

fn answers_presence(check: &Check, verdict: &Verdict) -> bool {
    matches!(check, Check::Present(present) if !present.missing) && verdict.cause == Cause::Value
}

pub fn run(check: &AnyOf, ctx: &Ctx) -> Verdict {
    let mut inputs: Vec<Input> = Vec::new();
    let mut options: Vec<Cause> = Vec::new();
    let in_option = Ctx {
        in_option: true,
        ..ctx.clone()
    };
    for option in &check.options {
        let mut causes = Vec::new();
        let mut field_missing = false;
        for line in option {
            let ran = run_full(line, &in_option).verdict;
            field_missing |= answers_presence(line, &ran);
            causes.push(ran.cause);
            inputs.extend(ran.inputs);
        }
        options.push(if field_missing {
            Cause::Value
        } else {
            Cause::worst(causes).unwrap_or(Cause::Satisfied)
        });
    }
    let cause = if check.flawed(ctx) {
        Cause::Unusable
    } else if options.contains(&Cause::Satisfied) {
        Cause::Satisfied
    } else {
        Cause::worst(options).unwrap_or(Cause::Value)
    };
    let inputs = tag_like_parts(check, ctx, crate::subjects::merge_inputs(inputs));
    Verdict { cause, inputs }
}

fn tag_like_parts(check: &AnyOf, ctx: &Ctx, mut inputs: Vec<Input>) -> Vec<Input> {
    let mut parts: Vec<(String, String, Value)> = Vec::new();
    for path in check.checks().flat_map(Check::paths) {
        if let Start::Part(part) = &path.start
            && let Some((name, id)) = path::part_tag(path, ctx)
        {
            let own = crate::name::name(&Path {
                start: Start::Subject,
                steps: part.steps.clone(),
            });
            if !parts.iter().any(|found| found.0 == name && found.2 == id) {
                parts.push((name, own, id));
            }
        }
    }
    for input in &mut inputs {
        if input.part.is_some() {
            continue;
        }
        let matching: Vec<&(String, String, Value)> = parts
            .iter()
            .filter(|(_, own, _)| {
                input
                    .name
                    .strip_prefix(own.as_str())
                    .is_some_and(|rest| rest.is_empty() || rest.starts_with(['.', '[']))
            })
            .collect();
        if let [(name, _, id)] = matching.as_slice() {
            input.part = Some(super::Part {
                name: name.clone(),
                id: id.clone(),
            });
        }
    }
    inputs
}

#[cfg(test)]
mod tests;
