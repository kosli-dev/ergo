//! Reads a policy, an input or params from a JSON or YAML file.

use crate::args::StdinFormat;
use crate::{Failure, yaml};
use serde_json::Value;
use std::fs;
use std::io::Read;
use std::path::Path;

/// How a message names where `what` was read from: `the policy file policy.yaml`, or `the policy on standard input` for the path `-`.
pub fn name(what: &str, path: &str) -> String {
    if path == "-" && what == "params" {
        "standard input as params".to_string()
    } else if path == "-" {
        format!("the {what} on standard input")
    } else {
        format!("the {what} file {path}")
    }
}

/// The keys written twice in one mapping of the YAML `text`, as [yaml::repeated_keys] gives them, and none for text that isn't valid YAML.
pub fn repeated_keys_in(text: &str) -> Vec<Vec<String>> {
    yaml::repeated_keys(text).unwrap_or_default()
}

/// Reads all of standard input, from `reader`, as text, and refuses it when `is_terminal` says nobody is piping anything in. `what` is `policy`, `input` or `params` and goes into the error message.
pub fn read_stdin_from(
    what: &str,
    is_terminal: bool,
    reader: &mut dyn Read,
) -> Result<String, Failure> {
    if is_terminal {
        return Err(Failure::File(
            "standard input is a terminal; pipe the input in".to_string(),
        ));
    }
    let mut text = String::new();
    reader
        .read_to_string(&mut text)
        .map_err(|e| Failure::File(format!("can't read the {what} on standard input: {e}")))?;
    Ok(text)
}

/// Reads `text`, which came from standard input, as JSON or YAML as `format` says.
pub fn parse_stdin(what: &str, text: &str, format: StdinFormat) -> Result<Value, Failure> {
    parse_text(&name(what, "-"), text, matches!(format, StdinFormat::Yaml))
}

/// The keys written twice in one mapping of the YAML file at `path`, as [yaml::repeated_keys] gives them, and none for a JSON file or a file that can't be read.
pub fn repeated_keys(path: &str) -> Vec<Vec<String>> {
    let yaml = Path::new(path).extension().is_some_and(|e| {
        matches!(
            e.to_string_lossy().to_ascii_lowercase().as_str(),
            "yaml" | "yml"
        )
    });
    if !yaml {
        return Vec::new();
    }
    fs::read_to_string(path)
        .ok()
        .and_then(|text| yaml::repeated_keys(&text).ok())
        .unwrap_or_default()
}

/// Reads the file at `path` as JSON or YAML, by its extension. `what` is `policy`, `input` or `params` and goes into the error message.
pub fn load(what: &str, path: &str) -> Result<Value, Failure> {
    let extension = Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_ascii_lowercase());
    let is_yaml = match extension.as_deref() {
        Some("json") => false,
        Some("yaml" | "yml") => true,
        _ => {
            return Err(Failure::File(format!(
                "the {what} file {path} must end in .json, .yaml or .yml"
            )));
        }
    };
    let text = fs::read_to_string(path)
        .map_err(|e| Failure::File(format!("can't read the {what} file {path}: {e}")))?;
    parse_text(&name(what, path), &text, is_yaml)
}

fn parse_text(name: &str, text: &str, is_yaml: bool) -> Result<Value, Failure> {
    let parsed = if is_yaml {
        yaml::parse(text).map_err(|e| match e {
            yaml::Error::Invalid(m) => ("isn't valid YAML", m),
            yaml::Error::NotJson(m) => ("is valid YAML that JSON can't hold", m),
            yaml::Error::Refused(m) => ("can't be read", m),
        })
    } else {
        serde_json::from_str(text).map_err(|e| ("isn't valid JSON", e.to_string()))
    };
    parsed.map_err(|(problem, message)| {
        Failure::File(format!(
            "{name} {problem}: {}",
            message.lines().next().unwrap_or("")
        ))
    })
}
