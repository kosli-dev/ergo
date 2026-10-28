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
        (Outcome::Found, Some(found)) => verdict(value::equal(found, &check.value)),
        (other, _) => other.cause().unwrap_or(Cause::Unusable),
    };
    Verdict {
        cause,
        inputs: read.inputs,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{Located, Location, Start, Step};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn cause(subject: Value, value: Value) -> Cause {
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
        let check = Equals {
            path: Path {
                start: Start::Subject,
                steps: vec![Step::Key("x".to_string())],
            },
            value,
        };
        run(&check, &ctx).cause
    }

    fn parsed(text: &str) -> Value {
        serde_json::from_str(text).unwrap()
    }

    #[test]
    fn passes_on_an_equal_value_and_fails_as_value_otherwise() {
        assert_eq!(cause(json!({"x": "a"}), json!("a")), Cause::Satisfied);
        assert_eq!(cause(json!({"x": "b"}), json!("a")), Cause::Value);
    }

    #[test]
    fn numbers_compare_by_value() {
        assert_eq!(cause(parsed(r#"{"x": 1.0}"#), json!(1)), Cause::Satisfied);
        assert_eq!(cause(json!({"x": 150}), parsed("1.5e2")), Cause::Satisfied);
    }

    #[test]
    fn a_value_of_another_type_fails_as_unusable() {
        assert_eq!(cause(json!({"x": "1"}), json!(1)), Cause::Unusable);
        assert_eq!(cause(json!({"x": [1]}), json!(1)), Cause::Unusable);
    }

    #[test]
    fn a_missing_field_fails_as_absent_even_against_null() {
        assert_eq!(cause(json!({}), json!("a")), Cause::Absent);
        assert_eq!(cause(json!({}), Value::Null), Cause::Absent);
    }

    #[test]
    fn a_null_field_passes_null_and_fails_anything_else_as_null() {
        assert_eq!(cause(json!({"x": null}), Value::Null), Cause::Satisfied);
        assert_eq!(cause(json!({"x": null}), json!("a")), Cause::Null);
    }

    #[test]
    fn a_field_that_was_read_fails_null_as_value() {
        assert_eq!(cause(json!({"x": 0}), Value::Null), Cause::Value);
        assert_eq!(cause(json!({"x": ""}), Value::Null), Cause::Value);
    }

    #[test]
    fn a_parent_that_cannot_hold_the_field_fails_with_its_outcome() {
        assert_eq!(cause(json!("s"), json!(1)), Cause::NotAnObject);
    }
}
