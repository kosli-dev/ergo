//! Builds Ergo reports in a browser. The input, the policy and the params go in as JSON text and the report comes out as JSON text, so no number passes through a JavaScript number.

use serde_json::Value;
use wasm_bindgen::prelude::*;

/// Builds the report for `input`, `policy` and `params`, each given as JSON text, and returns it as JSON text. When one of them isn't valid JSON, the message says which.
pub fn report_text(input: &str, policy: &str, params: &str) -> Result<String, String> {
    let read = |what: &str, text: &str| {
        serde_json::from_str::<Value>(text).map_err(|e| format!("{what} valid JSON: {e}"))
    };
    let report = ergo_engine::report(
        &read("the input isn't", input)?,
        &read("the policy isn't", policy)?,
        &read("the params aren't", params)?,
    );
    Ok(report.to_string())
}

/// Builds the report for `input`, `policy` and `params`, each given as JSON text, and returns it as JSON text. Throws when one of them isn't valid JSON.
#[wasm_bindgen]
pub fn report(input: &str, policy: &str, params: &str) -> Result<String, JsError> {
    report_text(input, policy, params).map_err(|message| JsError::new(&message))
}
