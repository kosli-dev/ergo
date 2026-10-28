pub mod compare;
pub mod equals;
pub mod present;
pub mod range;
pub mod time;

use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path};
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
}

impl Input {
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
    pub value: Option<Value>,
    pub input: Input,
}

pub fn read_path(path: &Path, ctx: &Ctx) -> ReadPath {
    let read = path::read(path, ctx);
    let value = read.value.cloned();
    let input = Input {
        name: name::name(path),
        value: value.clone().unwrap_or(Value::Null),
        locations: read.location.iter().map(|l| l.render()).collect(),
        part: path::part_tag(path, ctx).map(|(name, id)| Part { name, id }),
    };
    ReadPath {
        outcome: read.outcome,
        value,
        input,
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Check {
    Present(present::Present),
    Compare(compare::Compare),
    CompareTime(time::CompareTime),
    Equals(equals::Equals),
    Range(range::Range),
}

pub fn run(check: &Check, ctx: &Ctx) -> Verdict {
    match check {
        Check::Present(check) => present::run(check, ctx),
        Check::Compare(check) => compare::run(check, ctx),
        Check::CompareTime(check) => time::run(check, ctx),
        Check::Equals(check) => equals::run(check, ctx),
        Check::Range(check) => range::run(check, ctx),
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
mod tests {
    use super::*;
    use crate::path::{Located, Location, PartStart, Step};
    use std::collections::BTreeMap;

    fn ctx<'a>(subject: &'a Value, input: &'a Value) -> Ctx<'a> {
        Ctx {
            subject: Located {
                value: subject,
                location: Location::input_root().key("s"),
            },
            input,
            params: None,
            aliases: BTreeMap::new(),
        }
    }

    fn present(path: Path, missing: bool) -> Check {
        Check::Present(present::Present { path, missing })
    }

    fn key(text: &str) -> Step {
        Step::Key(text.to_string())
    }

    #[test]
    fn run_gives_the_verdict_of_the_operator_the_check_holds() {
        let subject = json!({"x": 1});
        let input = json!({});
        let path = Path {
            start: path::Start::Subject,
            steps: vec![key("x")],
        };
        let found = run(&present(path.clone(), false), &ctx(&subject, &input));
        assert!(found.passed());
        let failed = run(&present(path, true), &ctx(&subject, &input));
        assert_eq!(failed.cause, Cause::Value);
        let equals = Check::Equals(equals::Equals {
            path: Path {
                start: path::Start::Subject,
                steps: vec![key("x")],
            },
            value: json!(1),
        });
        assert!(run(&equals, &ctx(&subject, &input)).passed());
    }

    #[test]
    fn an_input_read_through_a_part_is_tagged_with_the_alias_and_the_parts_id() {
        let subject = json!({"d": {"id": "c1", "x": 1}});
        let input = json!({});
        let start = path::Start::Part(Box::new(PartStart {
            name: "cov".into(),
            base: path::Start::Subject,
            steps: vec![key("d")],
            id: Some(vec![key("id")]),
        }));
        let verdict = run(
            &present(
                Path {
                    start,
                    steps: vec![key("x")],
                },
                false,
            ),
            &ctx(&subject, &input),
        );
        assert_eq!(
            verdict.inputs[0].to_json(),
            json!({"name": "cov.x", "value": 1, "locations": ["/s/d/x"], "part": {"name": "cov", "id": "c1"}})
        );
    }

    #[test]
    fn an_input_read_without_a_part_has_no_tag() {
        let subject = json!({"x": 1});
        let input = json!({});
        let path = Path {
            start: path::Start::Subject,
            steps: vec![key("x")],
        };
        let verdict = run(&present(path, false), &ctx(&subject, &input));
        assert!(verdict.inputs[0].to_json().get("part").is_none());
    }
}
