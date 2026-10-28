use super::{Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::path::{Ctx, Outcome, Path, Start};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Present {
    pub path: Path,
    pub missing: bool,
}

pub fn run(check: &Present, ctx: &Ctx) -> Verdict {
    let read = read_path(&check.path, ctx);
    let no_params = check.path.start == Start::Params && ctx.params.is_none();
    let cause = match read.outcome {
        Outcome::Found => verdict(!check.missing),
        Outcome::Absent | Outcome::Null if no_params => Cause::Absent,
        Outcome::Absent | Outcome::Null => verdict(check.missing),
        other => other.cause().unwrap_or(Cause::Unusable),
    };
    Verdict {
        cause,
        inputs: vec![read.input],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{Located, Location, Step};
    use serde_json::{Value, json};
    use std::collections::BTreeMap;

    fn check(steps: &[&str], start: Start, missing: bool) -> Present {
        Present {
            path: Path {
                start,
                steps: steps.iter().map(|s| Step::Key(s.to_string())).collect(),
            },
            missing,
        }
    }

    fn run_on(subject: &Value, params: Option<&Value>, check: &Present) -> Verdict {
        let input = json!({"things": [subject]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params,
            aliases: BTreeMap::new(),
        };
        run(check, &ctx)
    }

    #[test]
    fn any_value_counts_as_present_false_included() {
        let v = run_on(
            &json!({"x": false}),
            None,
            &check(&["x"], Start::Subject, false),
        );
        assert_eq!(v.cause, Cause::Satisfied);
        assert_eq!(v.inputs[0].locations, vec!["/things/0/x"]);
    }

    #[test]
    fn a_missing_field_fails_present_as_value_and_passes_missing() {
        let subject = json!({"y": 1});
        assert_eq!(
            run_on(&subject, None, &check(&["x"], Start::Subject, false)).cause,
            Cause::Value
        );
        assert_eq!(
            run_on(&subject, None, &check(&["x"], Start::Subject, true)).cause,
            Cause::Satisfied
        );
    }

    #[test]
    fn a_null_field_counts_as_missing() {
        let subject = json!({"x": null});
        assert_eq!(
            run_on(&subject, None, &check(&["x"], Start::Subject, false)).cause,
            Cause::Value
        );
        assert_eq!(
            run_on(&subject, None, &check(&["x"], Start::Subject, true)).cause,
            Cause::Satisfied
        );
    }

    #[test]
    fn a_field_that_is_there_fails_missing_as_value() {
        let v = run_on(
            &json!({"x": ""}),
            None,
            &check(&["x"], Start::Subject, true),
        );
        assert_eq!(v.cause, Cause::Value);
    }

    #[test]
    fn without_params_a_params_path_fails_both_as_absent() {
        let subject = json!({});
        assert_eq!(
            run_on(&subject, None, &check(&["flag"], Start::Params, false)).cause,
            Cause::Absent
        );
        assert_eq!(
            run_on(&subject, None, &check(&["flag"], Start::Params, true)).cause,
            Cause::Absent
        );
    }

    #[test]
    fn params_without_the_field_fail_present_as_value() {
        let params = json!({});
        let v = run_on(
            &json!({}),
            Some(&params),
            &check(&["flag"], Start::Params, false),
        );
        assert_eq!(v.cause, Cause::Value);
    }

    #[test]
    fn a_field_on_a_subject_that_is_not_an_object_fails_both_as_not_an_object() {
        let subject = json!("s");
        assert_eq!(
            run_on(&subject, None, &check(&["x"], Start::Subject, false)).cause,
            Cause::NotAnObject
        );
        assert_eq!(
            run_on(&subject, None, &check(&["x"], Start::Subject, true)).cause,
            Cause::NotAnObject
        );
    }

    #[test]
    fn a_step_past_a_string_fails_both_as_unusable() {
        let subject = json!({"x": "a"});
        assert_eq!(
            run_on(&subject, None, &check(&["x", "y"], Start::Subject, false)).cause,
            Cause::Unusable
        );
        assert_eq!(
            run_on(&subject, None, &check(&["x", "y"], Start::Subject, true)).cause,
            Cause::Unusable
        );
    }
}
