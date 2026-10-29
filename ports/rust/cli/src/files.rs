//! Reads a policy, an input or params from a JSON or YAML file.

use crate::{Failure, yaml};
use serde_json::Value;
use std::fs;
use std::path::Path;

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
    let parsed = if is_yaml {
        yaml::parse(&text).map_err(|e| match e {
            yaml::Error::Invalid(m) => ("isn't valid YAML", m),
            yaml::Error::NotJson(m) => ("is valid YAML that JSON can't hold", m),
            yaml::Error::Refused(m) => ("can't be read", m),
        })
    } else {
        serde_json::from_str(&text).map_err(|e| ("isn't valid JSON", e.to_string()))
    };
    parsed.map_err(|(problem, message)| {
        Failure::File(format!(
            "the {what} file {path} {problem}: {}",
            message.lines().next().unwrap_or("")
        ))
    })
}
