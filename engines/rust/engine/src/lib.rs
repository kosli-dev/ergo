//! Builds an Ergo report from a policy, an input and params, all as JSON.
//!
//! The report says whether the input is compliant and why. Its shape is
//! described by `spec/report/schema.json`.
//!
//! ```
//! use ergo_policy_engine::{SPEC, report, violations};
//! use serde_json::json;
//!
//! let policy = json!({
//!     "ergo_spec": SPEC,
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
mod names;
mod ops;
mod path;
mod policy;
mod reading;
mod report;
mod subjects;
mod value;

pub use policy::SPEC;
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
mod tests;
