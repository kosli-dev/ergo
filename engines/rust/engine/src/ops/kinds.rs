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
}

#[derive(Debug, Clone, PartialEq)]
pub struct NonEmptyString {
    pub path: Path,
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
        verdict(matches!(
            (check.kind, found),
            (Kind::List, Value::Array(_))
                | (Kind::String, Value::String(_))
                | (Kind::Number, Value::Number(_))
                | (Kind::Boolean, Value::Bool(_))
                | (Kind::Object, Value::Object(_))
        ))
    })
}

pub fn run_non_empty_string(check: &NonEmptyString, ctx: &Ctx) -> Verdict {
    judged(&check.path, ctx, |found| {
        verdict(matches!(found, Value::String(s) if !s.is_empty()))
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
mod tests {
    use super::*;
    use crate::path::{Located, Location, Start, Step};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn x() -> Path {
        Path {
            start: Start::Subject,
            steps: vec![Step::Key("x".to_string())],
        }
    }

    fn on(subject: Value, run: impl Fn(&Ctx) -> Verdict) -> Cause {
        let input = json!({"things": [subject]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        run(&ctx).cause
    }

    fn has(kind: Kind, subject: Value) -> Cause {
        on(subject, |ctx| {
            run_has_type(&HasType { path: x(), kind }, ctx)
        })
    }

    fn non_empty(subject: Value) -> Cause {
        on(subject, |ctx| {
            run_non_empty_string(&NonEmptyString { path: x() }, ctx)
        })
    }

    fn empty(not: bool, subject: Value) -> Cause {
        on(subject, |ctx| run_empty(&Empty { path: x(), not }, ctx))
    }

    #[test]
    fn has_type_passes_on_its_type_and_fails_any_other_as_value() {
        for (kind, good, bad) in [
            (Kind::List, json!([]), json!({})),
            (Kind::String, json!(""), json!(1)),
            (Kind::Number, json!(1.5), json!("1")),
            (Kind::Boolean, json!(false), json!(0)),
            (Kind::Object, json!({}), json!([])),
        ] {
            assert_eq!(has(kind, json!({"x": good})), Cause::Satisfied, "{kind:?}");
            assert_eq!(has(kind, json!({"x": bad})), Cause::Value, "{kind:?}");
        }
    }

    #[test]
    fn has_type_fails_with_the_path_outcome_when_nothing_was_read() {
        assert_eq!(has(Kind::String, json!({})), Cause::Absent);
        assert_eq!(has(Kind::String, json!({"x": null})), Cause::Null);
        assert_eq!(has(Kind::String, json!("s")), Cause::NotAnObject);
    }

    #[test]
    fn a_non_empty_string_has_a_character_and_anything_else_fails_as_value() {
        assert_eq!(non_empty(json!({"x": " "})), Cause::Satisfied);
        assert_eq!(non_empty(json!({"x": ""})), Cause::Value);
        assert_eq!(non_empty(json!({"x": 1})), Cause::Value);
        assert_eq!(non_empty(json!({"x": ["a"]})), Cause::Value);
        assert_eq!(non_empty(json!({})), Cause::Absent);
        assert_eq!(non_empty(json!({"x": null})), Cause::Null);
    }

    #[test]
    fn empty_takes_strings_and_lists() {
        assert_eq!(empty(false, json!({"x": ""})), Cause::Satisfied);
        assert_eq!(empty(false, json!({"x": []})), Cause::Satisfied);
        assert_eq!(empty(false, json!({"x": "a"})), Cause::Value);
        assert_eq!(empty(true, json!({"x": [1]})), Cause::Satisfied);
        assert_eq!(empty(true, json!({"x": "a"})), Cause::Satisfied);
        assert_eq!(empty(true, json!({"x": []})), Cause::Value);
    }

    #[test]
    fn empty_fails_anything_else_as_unusable_and_nothing_read_with_the_outcome() {
        for v in [json!(0), json!(false), json!({})] {
            assert_eq!(empty(false, json!({"x": v.clone()})), Cause::Unusable);
            assert_eq!(empty(true, json!({"x": v})), Cause::Unusable);
        }
        assert_eq!(empty(false, json!({})), Cause::Absent);
        assert_eq!(empty(true, json!({"x": null})), Cause::Null);
    }
}
