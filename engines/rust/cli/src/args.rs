//! Reads the command line by hand.

use crate::Failure;
use crate::pretty::{Color, Show};
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
    /// Experimental: as text for a person at a terminal.
    Pretty,
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
    /// The engine that builds the report.
    pub engine: Engine,
    /// Path of `ergo.rego`, when `--ergo-rego` is given.
    pub ergo_rego: Option<String>,
    /// Which rows `--format pretty` lists.
    pub show: Show,
    /// Whether to colour `--format pretty`.
    pub color: Color,
}

/// Which engine builds the reports.
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
    /// Which example lines are listed on a terminal.
    pub show: Show,
    /// Whether to colour the lines on a terminal.
    pub color: Color,
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
            "--policy" | "--input" | "--params" | "--format" | "--engine" | "--ergo-rego"
            | "--show" | "--color" => {
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
    let engine = match values.get("--engine").map(String::as_str) {
        None | Some("rust") => Engine::Rust,
        Some("rego") => Engine::Rego,
        Some(_) => return Err(usage("--engine must be rust or rego".to_string())),
    };
    let show = match values.get("--show").map(String::as_str) {
        None | Some("failed") => Show::Failed,
        Some("all") => Show::All,
        Some(_) => return Err(usage("--show must be failed or all".to_string())),
    };
    let color = match values.get("--color").map(String::as_str) {
        None | Some("auto") => Color::Auto,
        Some("always") => Color::Always,
        Some("never") => Color::Never,
        Some(_) => return Err(usage("--color must be auto, always or never".to_string())),
    };
    let ergo_rego = values.remove("--ergo-rego");
    if ergo_rego.is_some() && engine != Engine::Rego {
        return Err(usage(
            "--ergo-rego only goes with --engine rego".to_string(),
        ));
    }
    let Some(command) = command else {
        let shared = ["--engine", "--show", "--color"];
        let report_only = values.keys().copied().filter(|v| !shared.contains(v));
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
        return Ok(Parsed::Test(TestOptions {
            policy,
            strict: switches.contains("--strict"),
            engine,
            ergo_rego,
            show,
            color,
        }));
    };
    if let Some(extra) = positional.first() {
        return Err(usage(format!("unexpected argument '{extra}'")));
    }
    if switches.contains("--strict") {
        return Err(usage("--strict only goes with test".to_string()));
    }
    let format = match values.get("--format").map(String::as_str) {
        None | Some("json") => Format::Json,
        Some("outcome") => Format::Outcome,
        Some("pretty") => Format::Pretty,
        Some(_) => {
            return Err(usage(
                "--format must be json, outcome or pretty".to_string(),
            ));
        }
    };
    let compact = switches.contains("--compact");
    for (name, wanted) in [("outcome", Format::Outcome), ("pretty", Format::Pretty)] {
        if format == wanted && command == Command::Violations {
            return Err(usage(format!("--format {name} only goes with report")));
        }
        if format == wanted && compact {
            return Err(usage(format!("--compact can't go with --format {name}")));
        }
    }
    for flag in ["--show", "--color"] {
        if format != Format::Pretty && values.contains_key(flag) {
            return Err(usage(format!(
                "{flag} only goes with --format pretty and test"
            )));
        }
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
        engine,
        ergo_rego,
        show,
        color,
    }))
}
