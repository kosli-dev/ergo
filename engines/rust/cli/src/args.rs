//! Reads the command line by hand.

use crate::Failure;
use std::collections::{BTreeMap, BTreeSet};

/// The two commands that print something built from the files.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Command {
    /// `ergo report`
    Report,
    /// `ergo violations`
    Violations,
}

/// How `ergo report` prints the report.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Format {
    /// As JSON, the default.
    Json,
    /// Experimental: as outcome lines in YAML, as a policy's examples write them.
    Outcome,
}

/// What the command line asks for.
#[derive(Debug, PartialEq, Eq)]
pub struct Options {
    /// The command to run.
    pub command: Command,
    /// Path of the policy file.
    pub policy: String,
    /// Path of the input file.
    pub input: String,
    /// Path of the params file, when given.
    pub params: Option<String>,
    /// Whether to print one line.
    pub compact: bool,
    /// Whether to exit non-zero when the report isn't compliant.
    pub fail: bool,
    /// How to print the report.
    pub format: Format,
}

/// Which engine builds the reports of `ergo test`.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Engine {
    /// The Rust engine in this command, the default.
    Rust,
    /// `ergo.rego`, run with `opa`.
    Rego,
}

/// What `ergo test` is asked to run.
#[derive(Debug, PartialEq, Eq)]
pub struct TestOptions {
    /// Path of the policy file that holds the examples.
    pub policy: String,
    /// Whether a warning fails the run.
    pub strict: bool,
    /// The engine that builds each example's report.
    pub engine: Engine,
    /// Path of `ergo.rego`, when `--ergo-rego` is given.
    pub ergo_rego: Option<String>,
}

/// The result of reading the command line.
#[derive(Debug, PartialEq, Eq)]
pub enum Parsed {
    /// Print the usage.
    Help,
    /// Print the version.
    Version,
    /// Run a command.
    Run(Options),
    /// Experimental: run a policy's examples.
    Test(TestOptions),
}

/// Reads the arguments after the program name.
pub fn parse(arguments: &[String]) -> Result<Parsed, Failure> {
    let usage = |m: String| Failure::Usage(m);
    let Some(first) = arguments.first() else {
        return Ok(Parsed::Help);
    };
    let command = match first.as_str() {
        "help" | "--help" | "-h" => return Ok(Parsed::Help),
        "--version" => return Ok(Parsed::Version),
        "report" => Some(Command::Report),
        "violations" => Some(Command::Violations),
        "test" => None,
        other => return Err(usage(format!("unknown command '{other}'"))),
    };
    let mut values: BTreeMap<&str, String> = BTreeMap::new();
    let mut switches = BTreeSet::new();
    let mut positional = Vec::new();
    let mut rest = arguments[1..].iter();
    while let Some(argument) = rest.next() {
        let (name, attached) = match argument.split_once('=') {
            Some((name, value)) if name.starts_with("--") => (name, Some(value.to_string())),
            _ => (argument.as_str(), None),
        };
        match name {
            "--help" | "-h" => return Ok(Parsed::Help),
            "--compact" | "--fail" | "--strict" => {
                if attached.is_some() {
                    return Err(usage(format!("{name} takes no value")));
                }
                switches.insert(name);
            }
            "--policy" | "--input" | "--params" | "--format" | "--engine" | "--ergo-rego" => {
                let value = match attached {
                    Some(value) => Some(value),
                    None => rest.next().filter(|v| !v.starts_with("--")).cloned(),
                };
                let Some(value) = value.filter(|v| !v.is_empty()) else {
                    return Err(usage(format!("{name} needs a value")));
                };
                if values.insert(name, value).is_some() {
                    return Err(usage(format!("{name} given twice")));
                }
            }
            other if other.starts_with("--") => {
                return Err(usage(format!("unknown flag '{other}'")));
            }
            other => positional.push(other.to_string()),
        }
    }
    let test_only = ["--engine", "--ergo-rego"];
    let Some(command) = command else {
        let report_only = values.keys().copied().filter(|v| !test_only.contains(v));
        let report_only = report_only.chain(switches.iter().copied().filter(|s| *s != "--strict"));
        if let Some(flag) = report_only.min() {
            return Err(usage(format!(
                "{flag} only goes with report and violations"
            )));
        }
        let mut positional = positional.into_iter();
        let policy = positional
            .next()
            .ok_or_else(|| usage("test needs a policy file".to_string()))?;
        if let Some(extra) = positional.next() {
            return Err(usage(format!("unexpected argument '{extra}'")));
        }
        let engine = match values.get("--engine").map(String::as_str) {
            None | Some("rust") => Engine::Rust,
            Some("rego") => Engine::Rego,
            Some(_) => return Err(usage("--engine must be rust or rego".to_string())),
        };
        let ergo_rego = values.remove("--ergo-rego");
        if ergo_rego.is_some() && engine != Engine::Rego {
            return Err(usage(
                "--ergo-rego only goes with --engine rego".to_string(),
            ));
        }
        return Ok(Parsed::Test(TestOptions {
            policy,
            strict: switches.contains("--strict"),
            engine,
            ergo_rego,
        }));
    };
    if let Some(extra) = positional.first() {
        return Err(usage(format!("unexpected argument '{extra}'")));
    }
    let test_flags = switches.iter().copied().filter(|s| *s == "--strict");
    let test_flags = test_flags.chain(test_only.into_iter().filter(|f| values.contains_key(f)));
    if let Some(flag) = test_flags.min() {
        return Err(usage(format!("{flag} only goes with test")));
    }
    let format = match values.get("--format").map(String::as_str) {
        None | Some("json") => Format::Json,
        Some("outcome") => Format::Outcome,
        Some(_) => return Err(usage("--format must be json or outcome".to_string())),
    };
    let compact = switches.contains("--compact");
    if format == Format::Outcome && command == Command::Violations {
        return Err(usage("--format outcome only goes with report".to_string()));
    }
    if format == Format::Outcome && compact {
        return Err(usage(
            "--compact can't go with --format outcome".to_string(),
        ));
    }
    Ok(Parsed::Run(Options {
        command,
        policy: values
            .remove("--policy")
            .ok_or_else(|| usage("--policy is missing".to_string()))?,
        input: values
            .remove("--input")
            .ok_or_else(|| usage("--input is missing".to_string()))?,
        params: values.remove("--params"),
        compact,
        fail: switches.contains("--fail"),
        format,
    }))
}
