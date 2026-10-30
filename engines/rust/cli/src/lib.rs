//! The command-line tool behind the `ergo` binary: reads a policy, an input and params from JSON or YAML files and prints the report or the violations.

pub mod args;
pub mod files;
pub mod number;
pub mod output;
pub mod yaml;

use args::{Command, Parsed};

/// Why a run failed. The message is one line and names the problem and the file.
#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    /// The command line is wrong.
    Usage(String),
    /// A file can't be read or parsed.
    File(String),
}

impl Failure {
    /// The text to print on stderr.
    pub fn message(&self) -> &str {
        match self {
            Failure::Usage(m) | Failure::File(m) => m,
        }
    }

    /// The exit code: 2, for a wrong command line and for a bad file alike.
    pub fn code(&self) -> i32 {
        match self {
            Failure::Usage(_) | Failure::File(_) => 2,
        }
    }
}

/// The usage text.
pub const USAGE: &str =
    "Usage: ergo <command> --policy <file> --input <file> [--params <file>] [--compact] [--fail]

Commands:
  report       print the report as JSON
  violations   print what failed in the report as JSON
  help         print this text

ergo --version prints the version.

Files can be .json, .yaml or .yml. Without --params the params are {}.
The output is pretty-printed with sorted keys; --compact prints one line.

Exit codes:
  0  the output was printed: the policy is met, or --fail isn't given
  1  with --fail, a check failed
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

/// Runs the tool for the given arguments, without the program name.
pub fn run(arguments: &[String]) -> Result<Outcome, Failure> {
    let options = match args::parse(arguments)? {
        Parsed::Help => return Ok(Outcome::Print(USAGE.to_string())),
        Parsed::Version => {
            return Ok(Outcome::Print(format!(
                "ergo {}\n",
                env!("CARGO_PKG_VERSION")
            )));
        }
        Parsed::Run(options) => options,
    };
    let policy = files::load("policy", &options.policy)?;
    let input = files::load("input", &options.input)?;
    let params = match &options.params {
        Some(path) => files::load("params", path)?,
        None => serde_json::json!({}),
    };
    let report = ergo_policy_engine::report(&input, &policy, &params);
    let code = if options.fail { fail_code(&report) } else { 0 };
    let value = match options.command {
        Command::Report => report,
        Command::Violations => ergo_policy_engine::violations(&report),
    };
    let text = output::render(&value, options.compact);
    Ok(match code {
        0 => Outcome::Print(text),
        code => Outcome::PrintAndFail(text, code),
    })
}
