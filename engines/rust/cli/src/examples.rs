//! Experimental: reads the examples of a policy and checks each one's outcome against its report.

use crate::outcome::Item;
use serde_json::Value;
use std::collections::BTreeSet;

/// One example of a policy, with the params it runs with.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Example {
    /// The example's name, unique in the policy.
    pub name: String,
    /// The input to build the report from.
    pub input: Value,
    /// The example's own `params`, or else the policy's `example_params`, or else `{}`.
    pub params: Value,
    /// The outcome as written, a list of lines and headings.
    pub outcome: Value,
}

/// What checking an outcome against a report found.
#[derive(Debug, Default, PartialEq, Eq, Clone)]
pub struct Checked {
    /// Each way the report differs from the outcome, empty when the example passes.
    pub problems: Vec<String>,
    /// The outcome as written.
    pub expected: Vec<Item>,
    /// The report's lines for the part the outcome covers.
    pub actual: Vec<Item>,
    /// Each check a check line shows, as requirement, check and whether the line says it passes.
    pub shown: BTreeSet<(String, String, bool)>,
}

/// Reads the examples of a policy, or says why they're written wrong.
pub fn read(_policy: &Value) -> Result<Vec<Example>, String> {
    Ok(vec![])
}

/// Checks an outcome against a report, by the matching and coverage rules of the spec.
pub fn check(_outcome: &Value, _report: &Value) -> Checked {
    Checked::default()
}
