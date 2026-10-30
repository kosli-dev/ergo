//! Builds Ergo reports in a browser. The input, the policy and the params go in as JSON text and the report comes out as JSON text, so no number passes through a JavaScript number.

use serde_json::Value;
use wasm_bindgen::prelude::*;

/// Builds the report for `input`, `policy` and `params`, each given as JSON text, and returns it as JSON text. When one of them isn't valid JSON, the message says which.
pub fn report_text(input: &str, policy: &str, params: &str) -> Result<String, String> {
    let read = |what: &str, text: &str| {
        serde_json::from_str::<Value>(text).map_err(|e| format!("{what} valid JSON: {e}"))
    };
    let report = ergo_policy_engine::report(
        &read("the input isn't", input)?,
        &read("the policy isn't", policy)?,
        &read("the params aren't", params)?,
    );
    Ok(report.to_string())
}

#[wasm_bindgen(
    inline_js = "export function not_a_string(name, value) { return new TypeError(`${name} must be a string, not ${value === null ? 'null' : typeof value}`); }"
)]
extern "C" {
    fn not_a_string(name: &str, value: &JsValue) -> JsValue;
}

fn string(value: JsValue, name: &str) -> Result<String, JsValue> {
    value.as_string().ok_or_else(|| not_a_string(name, &value))
}

/// Builds the report for `input`, `policy` and `params`, each given as JSON text, and returns it as JSON text. Throws a `TypeError` when one of them isn't a string, and an `Error` when one of them isn't valid JSON, and the module stays usable. If the engine panics, the `wasm` profile aborts, which a caller sees as a `WebAssembly.RuntimeError: unreachable`, and then the module must not be called again. `initSync` and `init` give back the same instance, so load the module again, in a browser by reloading the page.
#[wasm_bindgen]
pub fn report(
    #[wasm_bindgen(unchecked_param_type = "string")] input: JsValue,
    #[wasm_bindgen(unchecked_param_type = "string")] policy: JsValue,
    #[wasm_bindgen(unchecked_param_type = "string")] params: JsValue,
) -> Result<String, JsValue> {
    let input = string(input, "input")?;
    let policy = string(policy, "policy")?;
    let params = string(params, "params")?;
    report_text(&input, &policy, &params).map_err(|message| JsError::new(&message).into())
}
