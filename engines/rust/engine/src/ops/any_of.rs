use super::{Check, Input, Verdict, run_full};
use crate::cause::Cause;
use crate::path::{self, Ctx, Path, Start};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub struct AnyOf {
    pub names: Vec<String>,
    pub texts: Vec<Vec<String>>,
    pub options: Vec<Vec<Check>>,
}

/// One line of an option that didn't pass, as its `failures` entry needs it.
pub struct LineRun {
    pub check: Check,
    pub at: usize,
    pub text: String,
    pub cause: Cause,
    pub inputs: Vec<Input>,
    pub said: super::message::Said,
}

/// What one option of an `any_of` gives, with its lines that didn't pass.
pub struct OptionRun {
    pub name: String,
    pub cause: Cause,
    pub count: usize,
    pub lines: Vec<LineRun>,
}

/// Runs each option of `check` line by line, for the row's `failures`.
pub fn option_runs(check: &AnyOf, ctx: &Ctx) -> Vec<OptionRun> {
    check
        .options
        .iter()
        .enumerate()
        .map(|(at, option)| {
            let mut causes = Vec::new();
            let mut field_missing = false;
            let mut lines = Vec::new();
            for (k, line) in option.iter().enumerate() {
                let ran = run_full(line, ctx);
                field_missing |= answers_presence(line, &ran.verdict);
                causes.push(ran.verdict.cause);
                if ran.verdict.passed() {
                    continue;
                }
                let said = match super::message::ran_said(&ran) {
                    Some(said) if matches!(line, Check::Walk(_)) => said,
                    _ => super::message::option_line_said(
                        line,
                        ctx,
                        ran.message.clone(),
                        &ran.verdict,
                    ),
                };
                lines.push(LineRun {
                    check: line.clone(),
                    at: k,
                    text: check
                        .texts
                        .get(at)
                        .and_then(|t| t.get(k))
                        .cloned()
                        .unwrap_or_default(),
                    cause: ran.verdict.cause,
                    inputs: ran.verdict.inputs,
                    said,
                });
            }
            OptionRun {
                name: check.names.get(at).cloned().unwrap_or_default(),
                cause: if field_missing {
                    Cause::Value
                } else {
                    Cause::worst(causes).unwrap_or(Cause::Satisfied)
                },
                count: option.len(),
                lines,
            }
        })
        .collect()
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
    for option in &check.options {
        let mut causes = Vec::new();
        let mut field_missing = false;
        for line in option {
            let ran = run_full(line, ctx).verdict;
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
