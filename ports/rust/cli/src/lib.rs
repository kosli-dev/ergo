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

    /// The exit code: 2 for a wrong command line and 1 for a bad file.
    pub fn code(&self) -> i32 {
        match self {
            Failure::Usage(_) => 2,
            Failure::File(_) => 1,
        }
    }
}

/// The usage text.
pub const USAGE: &str =
    "Usage: ergo <command> --policy <file> --input <file> [--params <file>] [--compact]

Commands:
  report       print the report as JSON
  violations   print what failed in the report as JSON
  help         print this text

ergo --version prints the version.

Files can be .json, .yaml or .yml. Without --params the params are {}.
The output is pretty-printed with sorted keys; --compact prints one line.
";

/// What a run gives back.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// Text for stdout, exit code 0.
    Print(String),
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
    let report = ergo_engine::report(&input, &policy, &params);
    let value = match options.command {
        Command::Report => report,
        Command::Violations => ergo_engine::violations(&report),
    };
    Ok(Outcome::Print(output::render(&value, options.compact)))
}
