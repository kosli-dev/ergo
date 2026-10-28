pub mod any_of;
pub mod compare;
pub mod equals;
pub mod for_line;
pub mod kinds;
pub mod lists;
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
    }];
    if !ctx.aliases.contains_key(path::OUTER) {
        for step in &path.steps {
            if let Step::Field(field) = step {
                let found = path::read(field, ctx);
                inputs.push(Input {
                    name: name::name(field),
                    value: found.value.cloned().unwrap_or(Value::Null),
                    locations: found.location.iter().map(|l| l.render()).collect(),
                    part: None,
                });
            }
        }
    }
    ReadPath {
        outcome: read.outcome,
        step_unreadable: read.step_unreadable,
        value,
        inputs,
    }
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
    NotYet,
}

impl Check {
    pub fn left_path(&self) -> Option<&Path> {
        match self {
            Check::Present(check) => Some(&check.path),
            Check::Equals(check) => Some(&check.path),
            Check::Range(check) => Some(&check.path),
            Check::Compare(check) => match &check.left {
                compare::Side::Path(path) => Some(path),
                compare::Side::Value(_) => None,
            },
            Check::CompareTime(check) => match &check.left {
                compare::Side::Path(path) => Some(path),
                compare::Side::Value(_) => None,
            },
            Check::In(check) => Some(&check.path),
            Check::Contains(check) => Some(&check.path),
            Check::Matches(check) => Some(&check.path),
            Check::HasType(check) => Some(&check.path),
            Check::NonEmptyString(check) => Some(&check.path),
            Check::Empty(check) => Some(&check.path),
            Check::Tally(check) => check.paths().into_iter().next(),
            Check::Walk(_) | Check::For(_) | Check::AnyOf(_) | Check::NotYet => None,
        }
    }

    pub fn paths(&self) -> Vec<&Path> {
        fn side(side: &compare::Side) -> Option<&Path> {
            match side {
                compare::Side::Path(path) => Some(path),
                compare::Side::Value(_) => None,
            }
        }
        match self {
            Check::Present(check) => vec![&check.path],
            Check::Equals(check) => vec![&check.path],
            Check::Range(check) => vec![&check.path],
            Check::Compare(check) => [&check.left, &check.right]
                .into_iter()
                .filter_map(side)
                .collect(),
            Check::CompareTime(check) => [&check.left, &check.right]
                .into_iter()
                .filter_map(side)
                .collect(),
            Check::Tally(check) => check.paths(),
            Check::AnyOf(check) => check.paths(),
            Check::In(check) => check.paths(),
            Check::Contains(check) => check.paths(),
            Check::Matches(check) => check.paths(),
            Check::HasType(check) => vec![&check.path],
            Check::NonEmptyString(check) => vec![&check.path],
            Check::Empty(check) => vec![&check.path],
            Check::Walk(_) | Check::For(_) | Check::NotYet => Vec::new(),
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
            Check::NonEmptyString(_) => Check::NonEmptyString(kinds::NonEmptyString { path: left }),
            Check::Empty(check) => Check::Empty(kinds::Empty {
                path: left,
                ..check.clone()
            }),
            Check::Tally(_) | Check::Walk(_) | Check::For(_) | Check::AnyOf(_) | Check::NotYet => {
                self.clone()
            }
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
            Check::NotYet => Vec::new(),
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

pub struct Ran {
    pub verdict: Verdict,
    pub failed_items: Option<Vec<Value>>,
}

pub fn run_full(check: &Check, ctx: &Ctx) -> Ran {
    match check {
        Check::Walk(check) => {
            let run = walk::run(check, ctx);
            Ran {
                verdict: run.verdict,
                failed_items: Some(run.failed_items),
            }
        }
        Check::For(check) => {
            let run = check.run(ctx);
            Ran {
                verdict: run.verdict,
                failed_items: Some(run.failed_items),
            }
        }
        other => Ran {
            verdict: run(other, ctx),
            failed_items: None,
        },
    }
}

pub fn run(check: &Check, ctx: &Ctx) -> Verdict {
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
        Check::NotYet => Verdict {
            cause: Cause::Unusable,
            inputs: Vec::new(),
        },
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
    fn a_check_the_engine_cannot_run_yet_fails_as_unusable_and_reads_nothing() {
        let subject = json!({"x": 1});
        let input = json!({});
        let verdict = run(&Check::NotYet, &ctx(&subject, &input));
        assert_eq!(verdict.cause, Cause::Unusable);
        assert!(verdict.inputs.is_empty());
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
    fn a_field_step_gives_the_field_as_an_entry_after_the_path_and_null_where_it_is_missing() {
        let input = json!({});
        let path = |subject: &Value| {
            let path = Path {
                start: path::Start::Subject,
                steps: vec![
                    key("values"),
                    Step::Field(Box::new(Path {
                        start: path::Start::Subject,
                        steps: vec![key("key")],
                    })),
                ],
            };
            read_path(&path, &ctx(subject, &input)).inputs
        };
        let found = path(&json!({"key": "k1", "values": {"k1": 5}}));
        assert_eq!(
            found.iter().map(Input::to_json).collect::<Vec<_>>(),
            [
                json!({"name": "values named by key", "value": 5, "locations": ["/s/values/k1"]}),
                json!({"name": "key", "value": "k1", "locations": ["/s/key"]}),
            ]
        );
        let missing = path(&json!({"values": {"k1": 5}}));
        assert_eq!(
            missing[1].to_json(),
            json!({"name": "key", "value": null, "locations": ["/s"]})
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
