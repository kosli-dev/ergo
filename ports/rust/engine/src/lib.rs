pub mod cause;
pub mod checks;
pub mod lower;
pub mod name;
pub mod ops;
pub mod path;
pub mod policy;
pub mod reading;
pub mod report;
pub mod subjects;
pub mod value;

use policy::{Policy, Problems};
use report::Evaluation;
use serde_json::Value;
use std::collections::BTreeMap;

pub fn report_with(
    input: &Value,
    policy: &Value,
    params: &Value,
    extra_problems: &BTreeMap<String, Problems>,
) -> Value {
    let read = Policy::read(policy);
    let reading = reading::Reading::of(&read);
    let evaluations: BTreeMap<String, Evaluation> = read
        .requirements
        .iter()
        .map(|(name, requirement)| {
            (
                name.clone(),
                subjects::find_subjects(&reading, &read, name, requirement, input, params),
            )
        })
        .collect();
    report::assemble_with(&read, &reading, extra_problems, &evaluations, input, params)
}

pub fn report(input: &Value, policy: &Value, params: &Value) -> Value {
    report_with(input, policy, params, &BTreeMap::new())
}

pub fn violations(report: &Value) -> Value {
    report::violations(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn report_and_violations_work_from_json_alone() {
        let policy = json!({
            "ergo_spec": "v0.2",
            "subjects": {"thing": {"from": "things"}},
            "requirements": {"s": {"subject": "thing", "require": "most", "checks": {"c": "x exists"}}}
        });
        let report = report(&json!({}), &policy, &Value::Null);
        assert_eq!(report["compliant"], json!(false));
        let violations = violations(&report);
        assert_eq!(violations.as_array().unwrap().len(), 1);
        assert_eq!(violations[0]["check"], json!("$well_formed"));
    }

    #[test]
    fn the_same_policy_gives_the_same_report_whatever_order_it_was_written_in() {
        let a: Value = serde_json::from_str(r#"{"requirements": {"b": {"subject": "t", "checks": {"y": "x exists", "x": "x exists"}}, "a": {"subject": "t", "checks": {"c": "x exists"}}}, "subjects": {"t": {"from": "t"}, "u": null}, "ergo_spec": "v0.2"}"#).unwrap();
        let b: Value = serde_json::from_str(r#"{"ergo_spec": "v0.2", "subjects": {"u": null, "t": {"from": "t"}}, "requirements": {"a": {"checks": {"c": "x exists"}, "subject": "t"}, "b": {"checks": {"x": "x exists", "y": "x exists"}, "subject": "t"}}}"#).unwrap();
        let input = json!({"t": []});
        assert_eq!(
            report(&input, &a, &Value::Null).to_string(),
            report(&input, &b, &Value::Null).to_string()
        );
    }

    #[test]
    fn extra_problems_reach_the_report() {
        let policy = json!({
            "ergo_spec": "v0.2",
            "subjects": {"thing": {"from": "things"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        });
        let mut problems = Problems::new();
        policy::add_problem(&mut problems, "checks.c".to_string(), "doesn't parse");
        let extra = BTreeMap::from([("s".to_string(), problems)]);
        let report = report_with(&json!({}), &policy, &Value::Null, &extra);
        assert_eq!(
            report["results"][0]["inputs"][2]["value"],
            json!(["doesn't parse"])
        );
    }
}
