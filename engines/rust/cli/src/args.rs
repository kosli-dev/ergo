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

/// How a file read from standard input is written, from `--stdin-format`.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum StdinFormat {
    /// `--stdin-format json`
    Json,
    /// `--stdin-format yaml`
    Yaml,
}

/// What the command line asks for.
#[derive(Debug, PartialEq, Eq)]
pub struct Options {
    /// The command to run.
    pub command: Command,
    /// Path of the policy file, or `-` for standard input.
    pub policy: String,
    /// Path of the input file, or `-` for standard input.
    pub input: String,
    /// Path of the params file, when given, or `-` for standard input.
    pub params: Option<String>,
    /// How standard input is written, when one of the paths is `-`.
    pub stdin_format: Option<StdinFormat>,
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
    /// Path of the policy file that holds the examples, or `-` for standard input.
    pub policy: String,
    /// How standard input is written, when the policy is `-`.
    pub stdin_format: Option<StdinFormat>,
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
            | "--show" | "--color" | "--stdin-format" => {
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
    let stdin_format = match values.get("--stdin-format").map(String::as_str) {
        None => None,
        Some("json") => Some(StdinFormat::Json),
        Some("yaml") => Some(StdinFormat::Yaml),
        Some(_) => return Err(usage("--stdin-format must be json or yaml".to_string())),
    };
    let ergo_rego = values.remove("--ergo-rego");
    if ergo_rego.is_some() && engine != Engine::Rego {
        return Err(usage(
            "--ergo-rego only goes with --engine rego".to_string(),
        ));
    }
    let Some(command) = command else {
        let shared = ["--engine", "--show", "--color", "--stdin-format"];
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
        check_stdin(usize::from(policy == "-"), stdin_format)?;
        return Ok(Parsed::Test(TestOptions {
            policy,
            stdin_format,
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
    let policy = values
        .remove("--policy")
        .ok_or_else(|| usage("--policy is missing".to_string()))?;
    let input = values
        .remove("--input")
        .ok_or_else(|| usage("--input is missing".to_string()))?;
    let params = values.remove("--params");
    let dashes = [Some(&policy), Some(&input), params.as_ref()]
        .into_iter()
        .flatten()
        .filter(|v| *v == "-")
        .count();
    check_stdin(dashes, stdin_format)?;
    Ok(Parsed::Run(Options {
        command,
        policy,
        input,
        params,
        stdin_format,
        compact,
        fail: switches.contains("--fail"),
        format,
        engine,
        ergo_rego,
        show,
        color,
    }))
}

fn check_stdin(dashes: usize, format: Option<StdinFormat>) -> Result<(), Failure> {
    let usage = |m: &str| Err(Failure::Usage(m.to_string()));
    match (dashes, format) {
        (0, None) | (1, Some(_)) => Ok(()),
        (0, Some(_)) => usage("--stdin-format only goes with a value of -"),
        (1, None) => usage("--stdin-format json or yaml is needed when a value is -"),
        _ => usage("only one of --policy, --input and --params can be read from standard input"),
    }
}
