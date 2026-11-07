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
mod tests {
    use super::*;
    use crate::ops::{equals::Equals, present::Present};
    use crate::path::{Located, Location, Start, Step};
    use serde_json::{Value, json};
    use std::collections::BTreeMap;

    fn path(key: &str) -> Path {
        Path {
            start: Start::Subject,
            steps: vec![Step::Key(key.to_string())],
        }
    }

    fn exists(key: &str) -> Check {
        Check::Present(Present {
            path: path(key),
            missing: false,
        })
    }

    fn is(key: &str, value: Value) -> Check {
        Check::Equals(Equals {
            path: path(key),
            value,
        })
    }

    fn verdict(options: Vec<Vec<Check>>, subject: Value) -> Verdict {
        let input = json!({"s": subject});
        let ctx = Ctx {
            label: None,
            subject: Located {
                value: &input["s"],
                location: Location::input_root().key("s"),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        run(
            &AnyOf {
                names: Vec::new(),
                options,
            },
            &ctx,
        )
    }

    #[test]
    fn it_passes_when_every_check_of_one_option_passes_whatever_the_others_do() {
        let options = vec![
            vec![is("x", json!(2))],
            vec![is("x", json!(1)), exists("y")],
        ];
        let found = verdict(options, json!({"x": 1, "y": 0}));
        assert_eq!(found.cause, Cause::Satisfied);
    }

    #[test]
    fn it_fails_with_the_first_cause_among_its_options_in_the_order_of_causes() {
        let options = vec![vec![is("x", json!(2))], vec![is("z", json!(1))]];
        let found = verdict(options, json!({"x": 1}));
        assert_eq!(found.cause, Cause::Absent);
    }

    #[test]
    fn an_option_whose_field_is_missing_settles_as_value_not_as_the_cause_of_another_check() {
        let options = vec![vec![exists("x"), is("z", json!(1))]];
        let found = verdict(options, json!({"y": 1}));
        assert_eq!(found.cause, Cause::Value);
    }

    #[test]
    fn a_present_check_that_asks_for_a_missing_field_does_not_settle_its_option_as_value() {
        let options = vec![vec![Check::Present(Present {
            path: path("x"),
            missing: true,
        })]];
        assert_eq!(verdict(options, json!({"x": 1})).cause, Cause::Value,);
        let options = vec![vec![is("z", json!(1)), exists("x")]];
        assert_eq!(verdict(options, json!({"x": 1})).cause, Cause::Absent);
    }

    #[test]
    fn every_path_any_option_reads_is_listed_once_sorted_by_name() {
        let options = vec![
            vec![is("y", json!(1)), exists("x")],
            vec![is("x", json!(1))],
        ];
        let found = verdict(options, json!({"x": 1, "y": 2}));
        let names: Vec<&str> = found.inputs.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(names, ["x", "y"]);
    }

    #[test]
    fn it_has_no_left_path_of_its_own_and_gives_the_paths_of_all_its_checks() {
        let check = Check::AnyOf(AnyOf {
            names: Vec::new(),
            options: vec![vec![exists("x")], vec![is("y", json!(1))]],
        });
        assert!(check.left_path().is_none());
        assert_eq!(check.paths().len(), 2);
        assert_eq!(check.with_left(path("z")), check);
    }
}
