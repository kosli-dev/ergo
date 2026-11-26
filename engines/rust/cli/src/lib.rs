//! The command-line tool behind the `ergo` binary: reads a policy, an input and params from JSON or YAML files and prints the report or the violations.

pub mod args;
pub mod examples;
pub mod files;
pub mod number;
pub mod opa;
pub mod outcome;
pub mod output;
pub mod yaml;

use args::{Command, Engine, Format, Parsed};
use std::ffi::{OsStr, OsString};

/// Why a run failed. The message is one line and names the problem and the file.
#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    /// The command line is wrong.
    Usage(String),
    /// A file can't be read or parsed, or a policy's examples are written wrong.
    File(String),
    /// The output asked for can't show something in the report yet.
    Unsupported(String),
    /// With `--fail`, the policy is written wrong and the output asked for can't show the report.
    WrittenWrong(String),
    /// Experimental: `ergo test --engine rego` can't read `ergo.rego` or run `opa`, `opa` failed or printed something that isn't a report, or `ergo.rego` doesn't support the policy's `ergo_spec`.
    Engine(String),
}

/// The environment variables `ergo` reads. An empty one counts as not set.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Environment {
    /// `ERGO_REGO`: the path of `ergo.rego` for `ergo test --engine rego` when `--ergo-rego` isn't given.
    pub ergo_rego: Option<String>,
    /// `ERGO_OPA`: the `opa` command to run, in place of the `opa` on the PATH.
    pub opa: Option<OsString>,
}

impl Environment {
    /// Reads `ERGO_REGO` and `ERGO_OPA` from the process's environment.
    pub fn read() -> Environment {
        let read = |name| std::env::var_os(name).filter(|v| !v.is_empty());
        Environment {
            ergo_rego: read("ERGO_REGO").map(|v| v.to_string_lossy().into_owned()),
            opa: read("ERGO_OPA"),
        }
    }
}

impl Failure {
    /// The text to print on stderr.
    pub fn message(&self) -> &str {
        match self {
            Failure::Usage(m)
            | Failure::File(m)
            | Failure::Unsupported(m)
            | Failure::WrittenWrong(m)
            | Failure::Engine(m) => m,
        }
    }

    /// The exit code: 3 when, with `--fail`, the policy is written wrong, and 2 for a wrong command line, a bad file and output that can't be written alike.
    pub fn code(&self) -> i32 {
        match self {
            Failure::WrittenWrong(_) => 3,
            _ => 2,
        }
    }
}

/// The usage text.
pub const USAGE: &str =
    "Usage: ergo <command> --policy <file> --input <file> [--params <file>] [--compact] [--fail]
       ergo report --format outcome --policy <file> --input <file> [--params <file>] [--fail]
       ergo test <policy file> [--strict] [--engine rust|rego] [--ergo-rego <file>]

Commands:
  report       print the report as JSON
  violations   print what failed in the report as JSON
  test         experimental: run the examples in a policy
  help         print this text

ergo --version prints the version and the commit it was built from.

Files can be .json, .yaml or .yml. Without --params the params are {}.
The output is pretty-printed with sorted keys; --compact prints one line.

Experimental: --format outcome prints the report as outcome lines in YAML,
ready to paste into an example. test --strict also fails when no example
shows a check failing, or none shows it passing.

test --engine rego builds each report with ergo.rego through opa, in place
of the Rust engine. The path of ergo.rego is --ergo-rego, or ERGO_REGO when
that flag isn't given. opa is the one on the PATH, or ERGO_OPA when it's set.

Exit codes:
  0  the output was printed: the policy is met, or --fail isn't given
  1  with --fail, a check failed; with test, an example failed, or --strict and a warning
  2  the command line is wrong, a file can't be read, or the output couldn't be written
  3  with --fail, the policy is written wrong or has no requirements
";

/// What a run gives back.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// Text for stdout, exit code 0.
    Print(String),
    /// Text for stdout, then a non-zero exit code: 1 when a check failed and 3 when the policy is written wrong or has no requirements.
    PrintAndFail(String, u8),
}

/// The exit code `--fail` gives a report: 3 when a `$well_formed` row failed or no check ran, 0 when it's compliant, and 1 otherwise.
pub fn fail_code(report: &serde_json::Value) -> u8 {
    let written_wrong = report["results"].as_array().is_none_or(|rows| {
        rows.is_empty()
            || rows
                .iter()
                .any(|row| row["check"] == "$well_formed" && row["passed"] != true)
    });
    if written_wrong {
        3
    } else if report["compliant"] == true {
        0
    } else {
        1
    }
}

/// Runs the tool for the given arguments, without the program name, as if no environment variable were set.
pub fn run(arguments: &[String]) -> Result<Outcome, Failure> {
    run_in(arguments, &Environment::default())
}

fn test(options: args::TestOptions, environment: &Environment) -> Result<Outcome, Failure> {
    let ergo_rego = match (options.engine, options.ergo_rego, &environment.ergo_rego) {
        (Engine::Rust, _, None) => None,
        (Engine::Rust, _, Some(_)) => {
            return Err(Failure::Usage(
                "ERGO_REGO is set, and it only goes with --engine rego".to_string(),
            ));
        }
        (Engine::Rego, Some(path), _) => Some(path),
        (Engine::Rego, None, Some(path)) => Some(path.clone()),
        (Engine::Rego, None, None) => {
            return Err(Failure::Usage(
                "--engine rego needs the path of ergo.rego, in --ergo-rego or ERGO_REGO"
                    .to_string(),
            ));
        }
    };
    let policy = files::load("policy", &options.policy)?;
    let written_wrong = |problem| {
        Failure::File(format!(
            "the examples in the policy file {} are written wrong: {problem}",
            options.policy
        ))
    };
    examples::repeated(&files::repeated_keys(&options.policy)).map_err(written_wrong)?;
    let examples = examples::read(&policy).map_err(written_wrong)?;
    let (engine, reports) = match ergo_rego {
        None => (
            String::new(),
            examples
                .iter()
                .map(|e| ergo_policy_engine::report(&e.input, &policy, &e.params))
                .collect(),
        ),
        Some(ergo_rego) => {
            let opa = environment.opa.as_deref().unwrap_or(OsStr::new("opa"));
            let reports = opa::run(opa, &ergo_rego, &policy, &examples).map_err(Failure::Engine)?;
            if let Some(problem) = reports.iter().find_map(opa::unsupported_spec) {
                return Err(Failure::Engine(format!(
                    "the ergo.rego at {ergo_rego} refuses the policy file {}: {problem}",
                    options.policy
                )));
            }
            (opa::engine_line(&reports[0]), reports)
        }
    };
    let (text, code) = examples::results(&policy, &examples, &reports, options.strict);
    let text = format!("{engine}{text}");
    Ok(match code {
        0 => Outcome::Print(text),
        code => Outcome::PrintAndFail(text, code),
    })
}

/// Runs the tool for the given arguments, without the program name, with the environment variables in `environment`.
pub fn run_in(arguments: &[String], environment: &Environment) -> Result<Outcome, Failure> {
    let options = match args::parse(arguments)? {
        Parsed::Help => return Ok(Outcome::Print(USAGE.to_string())),
        Parsed::Version => {
            return Ok(Outcome::Print(format!(
                "ergo {} (commit {})\n",
                env!("CARGO_PKG_VERSION"),
                env!("ERGO_BUILD_COMMIT")
            )));
        }
        Parsed::Run(options) => options,
        Parsed::Test(options) => return test(options, environment),
    };
    let policy = files::load("policy", &options.policy)?;
    let input = files::load("input", &options.input)?;
    let params = match &options.params {
        Some(path) => files::load("params", path)?,
        None => serde_json::json!({}),
    };
    let report = ergo_policy_engine::report(&input, &policy, &params);
    let code = if options.fail { fail_code(&report) } else { 0 };
    let text = match (options.command, options.format) {
        (_, Format::Outcome) => {
            outcome::yaml(&outcome::of(&report, &policy).map_err(|problem| match code {
                3 => Failure::WrittenWrong(format!(
                    "the policy file {} is written wrong, so the report can't be shown as an outcome: {problem}",
                    options.policy
                )),
                _ => Failure::Unsupported(problem),
            })?)
        }
        (Command::Report, Format::Json) => output::render(&report, options.compact),
        (Command::Violations, Format::Json) => {
            output::render(&ergo_policy_engine::violations(&report), options.compact)
        }
    };
    Ok(match code {
        0 => Outcome::Print(text),
        code => Outcome::PrintAndFail(text, code),
    })
}
