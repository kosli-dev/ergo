//! Builds an Ergo report from a policy, an input and params, all as JSON.
//!
//! The report says whether the input is compliant and why. Its shape is
//! described by `spec/report/schema.json`.
//!
//! ```
//! use ergo_policy_engine::{report, violations};
//! use serde_json::json;
//!
//! let policy = json!({
//!     "ergo_spec": "v0.4-dev",
//!     "subjects": {"deployment": {"from": "deployments"}},
//!     "requirements": {
//!         "approved": {
//!             "subject": "deployment",
//!             "checks": {"has approvals": "approvals is at least 2"}
//!         }
//!     }
//! });
//! let input = json!({"deployments": [{"approvals": 1}]});
//!
//! let report = report(&input, &policy, &json!({}));
//! assert_eq!(report["compliant"], json!(false));
//! assert_eq!(violations(&report).as_array().unwrap().len(), 1);
//! ```

#![warn(missing_docs)]

mod cause;
mod checks;
mod lower;
mod name;
mod ops;
mod path;
mod policy;
mod reading;
mod report;
mod subjects;
mod value;

use policy::{Policy, Problems};
use report::Evaluation;
use serde_json::Value;
use std::collections::BTreeMap;

fn report_with(
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
    sorted(report::assemble_with(
        &read,
        &reading,
        extra_problems,
        &evaluations,
        input,
        params,
    ))
}

fn sorted(value: Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut entries: Vec<(String, Value)> = map.into_iter().collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            Value::Object(entries.into_iter().map(|(k, v)| (k, sorted(v))).collect())
        }
        Value::Array(items) => Value::Array(items.into_iter().map(sorted).collect()),
        Value::Number(number) => Value::Number(value::plain_number(&number)),
        other => other,
    }
}

/// Builds the report for `policy` applied to `input`.
///
/// `params` holds the values a policy reads as `$params`. Pass `Value::Null`
/// or an empty object when the policy has none. The report is a JSON object
/// that follows `spec/report/schema.json`. A policy that can't be read still
/// gives a report, and says what is wrong with it.
///
/// Every number in the report is written plain: no exponent and no trailing
/// zeros, so `1.50` is `1.5` and `1e2` is `100`. The same policy, input and
/// params always give the same report, byte for byte, whatever order the
/// policy was written in.
pub fn report(input: &Value, policy: &Value, params: &Value) -> Value {
    report_with(input, policy, params, &BTreeMap::new())
}

/// Lists what failed in a report made by [`report`].
///
/// It returns a JSON array with one entry for each failed check. The array is
/// empty when the report is compliant. Numbers are written plain, as in the
/// report, and the same report always gives the same bytes.
pub fn violations(report: &Value) -> Value {
    sorted(report::violations(report))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn report_and_violations_work_from_json_alone() {
        let policy = json!({
            "ergo_spec": "v0.4-dev",
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
        let a: Value = serde_json::from_str(r#"{"requirements": {"b": {"subject": "t", "checks": {"y": "x exists", "x": "x exists"}}, "a": {"subject": "t", "checks": {"c": "x exists"}}}, "subjects": {"t": {"from": "t"}, "u": null}, "ergo_spec": "v0.4-dev"}"#).unwrap();
        let b: Value = serde_json::from_str(r#"{"ergo_spec": "v0.4-dev", "subjects": {"u": null, "t": {"from": "t"}}, "requirements": {"a": {"checks": {"c": "x exists"}, "subject": "t"}, "b": {"checks": {"x": "x exists", "y": "x exists"}, "subject": "t"}}}"#).unwrap();
        let input = json!({"t": []});
        assert_eq!(
            report(&input, &a, &Value::Null).to_string(),
            report(&input, &b, &Value::Null).to_string()
        );
    }

    #[test]
    fn extra_problems_reach_the_report() {
        let policy = json!({
            "ergo_spec": "v0.4-dev",
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
    fn plain_everywhere(value: &Value, at: &str) {
        match value {
            Value::Number(number) => {
                let text = number.to_string();
                assert!(
                    !text.contains(['e', 'E']) && !(text.contains('.') && text.ends_with('0')),
                    "{at}: {text}"
                );
                assert!(text != "-0", "{at}: {text}");
            }
            Value::Array(items) => items
                .iter()
                .enumerate()
                .for_each(|(i, item)| plain_everywhere(item, &format!("{at}/{i}"))),
            Value::Object(map) => map
                .iter()
                .for_each(|(k, item)| plain_everywhere(item, &format!("{at}/{k}"))),
            _ => {}
        }
    }

    #[test]
    fn no_number_in_the_report_or_the_violations_keeps_a_written_form() {
        let input: Value = serde_json::from_str(
            r#"{"items": [{"id": 1.0, "x": 1.50, "y": -0.0, "z": 1e2, "w": 2.5e-3, "l": [1.0, 2.50], "n": -0}, {"id": 1, "x": 100.0}]}"#,
        )
        .unwrap();
        let params: Value = serde_json::from_str(r#"{"k": [1.50, 2.0], "m": 1e1}"#).unwrap();
        let policy: Value = serde_json::from_str(
            r#"{"ergo_spec": "v0.4-dev",
                "subjects": {"d": {"from": "items", "identified_by": "id"}},
                "requirements": {"r": {"subject": "d", "min_subjects": 2.0,
                    "checks": {"a": "x is 1.50", "b": "y is 0.0", "c": "z is at least 1e2",
                               "e": "x is between 1.0 and 2.50", "g": "count of l is 2.0",
                               "h": "x is in $params.k", "i": "w is $params.m"}}}}"#,
        )
        .unwrap();
        let report = report(&input, &policy, &params);
        plain_everywhere(&report, "report");
        plain_everywhere(&violations(&report), "violations");
        assert!(!report["results"].as_array().unwrap().is_empty());
    }
}
