//! Experimental: builds the reports of a policy's examples with `ergo.rego`, run with `opa`.

use crate::examples::Example;
use serde_json::{Value, json};
use std::ffi::OsStr;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

struct Folder(PathBuf);

impl Folder {
    fn new() -> Result<Folder, String> {
        static MADE: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "ergo-test-{}-{}",
            std::process::id(),
            MADE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path)
            .map(|()| Folder(path))
            .map_err(|e| format!("can't make a folder for opa's data: {e}"))
    }
}

impl Drop for Folder {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Builds one report per example with the `ergo.rego` at `ergo_rego`, by running `opa` once on [QUERY] with [data] in a file of a new folder that it removes after, or says why it can't.
pub fn run(
    opa: &OsStr,
    ergo_rego: &str,
    policy: &Value,
    examples: &[Example],
) -> Result<Vec<Value>, String> {
    let unreadable = |problem: String| format!("can't read ergo.rego at {ergo_rego}: {problem}");
    let metadata = fs::metadata(ergo_rego).map_err(|e| unreadable(e.to_string()))?;
    if !metadata.is_file() {
        return Err(unreadable("it isn't a file".to_string()));
    }
    fs::File::open(ergo_rego).map_err(|e| unreadable(e.to_string()))?;
    let folder = Folder::new()?;
    let file = folder.0.join("data.json");
    fs::write(&file, data(policy, examples).to_string())
        .map_err(|e| format!("can't write opa's data in {}: {e}", file.display()))?;
    let output = Command::new(opa)
        .args(["eval", "--format", "raw", "-d", ergo_rego, "-d"])
        .arg(&file)
        .arg(QUERY)
        .output()
        .map_err(|e| {
            format!(
                "can't run {}: {e}; put opa on the PATH or set ERGO_OPA",
                opa.to_string_lossy()
            )
        })?;
    drop(folder);
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let first = stderr.lines().map(str::trim).find(|l| !l.is_empty());
        return Err(format!(
            "opa failed on ergo.rego at {ergo_rego}: {}",
            first.map_or_else(|| output.status.to_string(), str::to_string)
        ));
    }
    let printed = String::from_utf8(output.stdout).unwrap_or_default();
    reports(&printed, examples.len())
        .map_err(|problem| format!("{problem}, with ergo.rego at {ergo_rego}"))
}

/// The query `opa eval` runs: it compiles the policy once with `ergo.compile` and builds one report per example with `ergo.report`.
pub const QUERY: &str = "[reports | compiled := data.ergo.compile(data.ergo_cli_test.policy); reports := [data.ergo.report(e.input, compiled, e.params) | e := data.ergo_cli_test.examples[_]]][0]";

/// The data `opa` reads for [QUERY]: the policy, and each example's input and params in order, under `ergo_cli_test`.
pub fn data(policy: &Value, examples: &[Example]) -> Value {
    let examples: Vec<Value> = examples
        .iter()
        .map(|e| json!({"input": e.input, "params": e.params}))
        .collect();
    json!({"ergo_cli_test": {"policy": policy, "examples": examples}})
}

fn is_report(value: &Value) -> bool {
    let engine = &value["engine"];
    value["results"].is_array() && engine["name"].is_string() && engine["version"].is_string()
}

/// Reads what `opa eval --format raw` printed for [QUERY] as `count` reports, or says why it can't: each must be an object with a `results` list and an `engine` that has a `name` and a `version`.
pub fn reports(printed: &str, count: usize) -> Result<Vec<Value>, String> {
    let wrong =
        || format!("opa printed something that isn't a report for each of the {count} examples");
    let Ok(Value::Array(reports)) = serde_json::from_str::<Value>(printed) else {
        return Err(wrong());
    };
    if reports.len() != count || !reports.iter().all(is_report) {
        return Err(wrong());
    }
    Ok(reports)
}

/// The line that says which engine built `report`, like `engine: ergo-rego 0.5.1`.
pub fn engine_line(report: &Value) -> String {
    let engine = &report["engine"];
    format!(
        "engine: {} {}\n",
        engine["name"].as_str().unwrap_or_default(),
        engine["version"].as_str().unwrap_or_default()
    )
}

/// The problem a failed `$well_formed` row of `report` gives when `ergo.rego` doesn't support the policy's `ergo_spec`, like `policy ergo_spec: unsupported version v0.5, expected v0.6`.
pub fn unsupported_spec(report: &Value) -> Option<String> {
    let rows = report["results"].as_array()?;
    rows.iter()
        .filter(|row| row["check"] == "$well_formed" && row["passed"] != true)
        .flat_map(|row| row["inputs"].as_array().into_iter().flatten())
        .filter(|input| input["name"] == "policy ergo_spec")
        .flat_map(|input| input["value"].as_array().into_iter().flatten())
        .filter_map(Value::as_str)
        .find(|problem| problem.starts_with("unsupported version "))
        .map(|problem| format!("policy ergo_spec: {problem}"))
}
