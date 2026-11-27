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
    fn new(label: &str) -> Result<Folder, String> {
        static MADE: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "ergo-{label}-{}-{}",
            std::process::id(),
            MADE.fetch_add(1, Ordering::Relaxed)
        ));
        let mut builder = fs::DirBuilder::new();
        #[cfg(unix)]
        std::os::unix::fs::DirBuilderExt::mode(&mut builder, 0o700);
        builder
            .create(&path)
            .map(|()| Folder(path))
            .map_err(|e| format!("can't make a folder for opa's data: {e}"))
    }
}

impl Drop for Folder {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Why the `ergo.rego` that was named can't be given to `opa`.
#[derive(Debug, PartialEq, Eq)]
pub enum PathProblem {
    /// The path holds a `:`, which `opa` reads as a prefix.
    Colon(String),
    /// The file can't be read.
    Unreadable(String),
}

impl PathProblem {
    /// The problem in words.
    pub fn message(self) -> String {
        match self {
            PathProblem::Colon(m) | PathProblem::Unreadable(m) => m,
        }
    }
}

/// Checks that the `ergo.rego` at `ergo_rego` can be given to `opa`: no `:` in the path, and a file that can be opened.
pub fn check_path(ergo_rego: &str) -> Result<(), PathProblem> {
    if ergo_rego.contains(':') {
        return Err(PathProblem::Colon(format!(
            "the path of ergo.rego ({ergo_rego}) holds a ':', which opa reads as a prefix; move the file"
        )));
    }
    let unreadable = |problem: String| {
        PathProblem::Unreadable(format!("can't read ergo.rego at {ergo_rego}: {problem}"))
    };
    let metadata = fs::metadata(ergo_rego).map_err(|e| unreadable(e.to_string()))?;
    if !metadata.is_file() {
        return Err(unreadable("it isn't a file".to_string()));
    }
    fs::File::open(ergo_rego).map_err(|e| unreadable(e.to_string()))?;
    Ok(())
}

/// The entry point of `names` that `opa` said is undefined in `stderr`, or `None`. Blank output names none, because an `ergo.report` that is undefined for the input prints nothing too.
pub fn missing_entry_point(names: &[&str], stderr: &str) -> Option<String> {
    let undefined = |name: &str| {
        let wanted = format!("data.{name}");
        stderr.lines().any(|line| {
            line.contains("undefined")
                && line.match_indices(&wanted).any(|(at, _)| {
                    !line[at + wanted.len()..]
                        .chars()
                        .next()
                        .is_some_and(|c| c.is_alphanumeric() || matches!(c, '_' | '.' | '['))
                })
        })
    };
    names
        .iter()
        .find(|name| undefined(name))
        .map(|name| (*name).to_string())
}

/// The message for an `ergo.rego` at `ergo_rego` that has no `entry_point`, which says what `ergo test` needs when the entry point is `ergo.compile`.
pub fn no_entry_point(ergo_rego: &str, entry_point: &str) -> String {
    let message = format!("the ergo.rego at {ergo_rego} has no {entry_point}");
    if entry_point == "ergo.compile" {
        format!("{message}; ergo test needs it, and OPA.md calls it experimental")
    } else {
        message
    }
}

fn eval(
    opa: &OsStr,
    ergo_rego: &str,
    data: &Value,
    query: &str,
    label: &str,
    names: &[&str],
) -> Result<String, String> {
    check_path(ergo_rego).map_err(PathProblem::message)?;
    let folder = Folder::new(label)?;
    if folder.0.to_string_lossy().contains(':') {
        return Err(format!(
            "the temp folder ({}) holds a ':', which opa reads as a prefix; move the file",
            folder.0.display()
        ));
    }
    let file = folder.0.join("data.json");
    write_private(&file, &data.to_string())
        .map_err(|e| format!("can't write opa's data in {}: {e}", file.display()))?;
    let output = Command::new(opa)
        .args(["eval", "--format", "raw", "-d", ergo_rego, "-d"])
        .arg(&file)
        .arg(query)
        .output()
        .map_err(|e| {
            format!(
                "can't run {}: {e}; put opa on the PATH or set ERGO_OPA",
                opa.to_string_lossy()
            )
        })?;
    drop(folder);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if let Some(missing) = missing_entry_point(names, &stderr) {
        return Err(no_entry_point(ergo_rego, &missing));
    }
    if !output.status.success() {
        let first = stderr.lines().map(str::trim).find(|l| !l.is_empty());
        return Err(format!(
            "opa failed on ergo.rego at {ergo_rego}: {}",
            first.map_or_else(|| output.status.to_string(), str::to_string)
        ));
    }
    Ok(String::from_utf8(output.stdout).unwrap_or_default())
}

/// Builds one report per example with the `ergo.rego` at `ergo_rego`, by running `opa` once on [QUERY] with [data] in a file of a new folder that it removes after, or says why it can't.
pub fn run(
    opa: &OsStr,
    ergo_rego: &str,
    policy: &Value,
    examples: &[Example],
) -> Result<Vec<Value>, String> {
    let printed = eval(
        opa,
        ergo_rego,
        &data(policy, examples),
        QUERY,
        "test",
        &["ergo.compile", "ergo.report"],
    )?;
    reports(&printed, examples.len())
        .map_err(|problem| format!("{problem}, with ergo.rego at {ergo_rego}"))
}

/// Builds the report of `input` and `params` for `policy`, and its violations when `violations` is set, with the `ergo.rego` at `ergo_rego`, by running `opa` once on [REPORT_QUERY] or [VIOLATIONS_QUERY], or says why it can't.
pub fn report_of(
    opa: &OsStr,
    ergo_rego: &str,
    policy: &Value,
    input: &Value,
    params: &Value,
    violations: bool,
) -> Result<(Value, Option<Value>), String> {
    let (query, label, names): (&str, &str, &[&str]) = if violations {
        (
            VIOLATIONS_QUERY,
            "violations",
            &["ergo.report", "ergo.violations"],
        )
    } else {
        (REPORT_QUERY, "report", &["ergo.report"])
    };
    let printed = eval(
        opa,
        ergo_rego,
        &one_data(policy, input, params),
        query,
        label,
        names,
    )?;
    one_report(&printed, violations)
        .map_err(|problem| format!("{problem}, with ergo.rego at {ergo_rego}"))
}

/// The query `opa eval` runs for `ergo report`: the report `ergo.report` builds from the policy, the input and the params.
pub const REPORT_QUERY: &str = "{\"report\": data.ergo.report(data.ergo_cli.input, data.ergo_cli.policy, data.ergo_cli.params)}";

/// The query `opa eval` runs for `ergo violations`: [REPORT_QUERY]'s report and `ergo.violations` of it.
pub const VIOLATIONS_QUERY: &str = "[x | report := data.ergo.report(data.ergo_cli.input, data.ergo_cli.policy, data.ergo_cli.params); x := {\"report\": report, \"violations\": data.ergo.violations(report)}][0]";

/// The data `opa` reads for [REPORT_QUERY] and [VIOLATIONS_QUERY]: the policy, the input and the params, under `ergo_cli`.
pub fn one_data(policy: &Value, input: &Value, params: &Value) -> Value {
    json!({"ergo_cli": {"policy": policy, "input": input, "params": params}})
}

/// Reads what `opa eval --format raw` printed for [REPORT_QUERY], or for [VIOLATIONS_QUERY] when `violations` is set, as the report and its violations, or says why it can't.
pub fn one_report(printed: &str, violations: bool) -> Result<(Value, Option<Value>), String> {
    let wrong = |reason: &str| format!("opa printed something that isn't a report: {reason}");
    let Ok(Value::Object(mut printed)) = serde_json::from_str::<Value>(printed) else {
        return Err("opa printed something that isn't a report".to_string());
    };
    let report = printed
        .remove("report")
        .ok_or_else(|| wrong("report is missing"))?;
    if let Some(problem) = report_problem(&report, "report", "report: ") {
        return Err(wrong(&problem));
    }
    let violations = match (violations, printed.remove("violations")) {
        (false, _) => None,
        (true, Some(found)) if found.is_array() => Some(found),
        (true, Some(_)) => return Err(wrong("violations isn't a list")),
        (true, None) => return Err(wrong("violations is missing")),
    };
    Ok((report, violations))
}

fn write_private(path: &std::path::Path, text: &str) -> std::io::Result<()> {
    use std::io::Write;
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    options.open(path)?.write_all(text.as_bytes())
}

/// The query `opa eval` runs for `ergo test`: it compiles the policy once with `ergo.compile`, an entry point that OPA.md calls experimental, and builds one report per example with `ergo.report`. It is the only place the CLI uses `ergo.compile`.
pub const QUERY: &str = "[reports | compiled := data.ergo.compile(data.ergo_cli_test.policy); reports := [data.ergo.report(e.input, compiled, e.params) | e := data.ergo_cli_test.examples[_]]][0]";

/// The data `opa` reads for [QUERY]: the policy, and each example's input and params in order, under `ergo_cli_test`.
pub fn data(policy: &Value, examples: &[Example]) -> Value {
    let examples: Vec<Value> = examples
        .iter()
        .map(|e| json!({"input": e.input, "params": e.params}))
        .collect();
    json!({"ergo_cli_test": {"policy": policy, "examples": examples}})
}

fn report_problem(value: &Value, subject: &str, prefix: &str) -> Option<String> {
    if !value.is_object() {
        return Some(format!("{subject} isn't an object"));
    }
    let engine = &value["engine"];
    let problem = if !value["results"].is_array() {
        "results isn't a list"
    } else if !engine["name"].is_string() {
        "engine.name isn't text"
    } else if !engine["version"].is_string() {
        "engine.version isn't text"
    } else {
        return None;
    };
    Some(format!("{prefix}{problem}"))
}

/// Reads what `opa eval --format raw` printed for [QUERY] as `count` reports, or says why it can't: each must be an object with a `results` list and an `engine` that has a `name` and a `version`.
pub fn reports(printed: &str, count: usize) -> Result<Vec<Value>, String> {
    let wrong =
        || format!("opa printed something that isn't a report for each of the {count} examples");
    let Ok(Value::Array(reports)) = serde_json::from_str::<Value>(printed) else {
        return Err(wrong());
    };
    if reports.len() != count {
        return Err(wrong());
    }
    for (i, report) in reports.iter().enumerate() {
        let subject = format!("report {}", i + 1);
        if let Some(problem) = report_problem(report, &subject, &format!("{subject}: ")) {
            return Err(format!("{}: {problem}", wrong()));
        }
    }
    Ok(reports)
}

/// The line that says which engine built `report`, like `engine: ergo-rego 0.5.1`.
pub fn engine_line(report: &Value) -> String {
    let engine = &report["engine"];
    format!(
        "engine: {} {}\n",
        crate::pretty::escape(engine["name"].as_str().unwrap_or_default()),
        crate::pretty::escape(engine["version"].as_str().unwrap_or_default())
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
