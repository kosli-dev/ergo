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
}

impl Range {
    pub fn refs(&self) -> Vec<Path> {
        path::step_refs(&self.path)
    }
}

pub fn run(check: &Range, ctx: &Ctx) -> Verdict {
    let read = read_path(&check.path, ctx);
    let cause = match (read.outcome, &read.value) {
        (Outcome::Found, Some(Value::Number(n))) => {
            value::between(&check.min, n, &check.max).map_or(Cause::Unusable, verdict)
        }
        (Outcome::Found, _) => Cause::Unusable,
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

    fn number(text: &str) -> Number {
        match serde_json::from_str::<Value>(text).unwrap() {
            Value::Number(n) => n,
            _ => panic!("{text} isn't a number"),
        }
    }

    fn cause(subject: &str, min: &str, max: &str) -> Cause {
        let input = json!({"things": [serde_json::from_str::<Value>(subject).unwrap()]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: None,
            aliases: BTreeMap::new(),
        };
        let check = Range {
            path: Path {
                start: Start::Subject,
                steps: vec![Step::Key("x".to_string())],
            },
            min: number(min),
            max: number(max),
        };
        run(&check, &ctx).cause
    }

    #[test]
    fn passes_inside_the_range_bounds_included() {
        assert_eq!(cause(r#"{"x": 2}"#, "1", "3"), Cause::Satisfied);
        assert_eq!(cause(r#"{"x": 1}"#, "1", "3"), Cause::Satisfied);
        assert_eq!(cause(r#"{"x": 3.0}"#, "1", "3"), Cause::Satisfied);
        assert_eq!(cause(r#"{"x": 2}"#, "1.5", "2e1"), Cause::Satisfied);
    }

    #[test]
    fn fails_as_value_outside_the_range() {
        assert_eq!(cause(r#"{"x": 0.5}"#, "1", "3"), Cause::Value);
        assert_eq!(cause(r#"{"x": 4}"#, "1", "3"), Cause::Value);
        assert_eq!(cause(r#"{"x": -2}"#, "-1", "1"), Cause::Value);
    }

    #[test]
    fn fails_as_unusable_on_anything_but_a_number() {
        assert_eq!(cause(r#"{"x": "2"}"#, "1", "3"), Cause::Unusable);
        assert_eq!(cause(r#"{"x": true}"#, "1", "3"), Cause::Unusable);
        assert_eq!(cause(r#"{"x": [2]}"#, "1", "3"), Cause::Unusable);
    }

    #[test]
    fn fails_with_the_path_outcome_when_it_is_not_found() {
        assert_eq!(cause(r#"{}"#, "1", "3"), Cause::Absent);
        assert_eq!(cause(r#"{"x": null}"#, "1", "3"), Cause::Null);
        assert_eq!(cause(r#""s""#, "1", "3"), Cause::NotAnObject);
    }
}
