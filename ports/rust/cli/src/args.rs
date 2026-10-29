//! Reads the command line by hand.

use crate::Failure;

/// The two commands that print something built from the files.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Command {
    /// `ergo report`
    Report,
    /// `ergo violations`
    Violations,
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
}

/// The result of reading the command line.
#[derive(Debug, PartialEq, Eq)]
pub enum Parsed {
    /// Print the usage.
    Help,
    /// Run a command.
    Run(Options),
}

/// Reads the arguments after the program name.
pub fn parse(arguments: &[String]) -> Result<Parsed, Failure> {
    let usage = |m: String| Failure::Usage(m);
    let Some(first) = arguments.first() else {
        return Ok(Parsed::Help);
    };
    let command = match first.as_str() {
        "help" | "--help" | "-h" => return Ok(Parsed::Help),
        "report" => Command::Report,
        "violations" => Command::Violations,
        other => return Err(usage(format!("unknown command '{other}'"))),
    };
    let mut policy = None;
    let mut input = None;
    let mut params = None;
    let mut compact = false;
    let mut rest = arguments[1..].iter();
    while let Some(argument) = rest.next() {
        let (name, attached) = match argument.split_once('=') {
            Some((name, value)) if name.starts_with("--") => (name, Some(value.to_string())),
            _ => (argument.as_str(), None),
        };
        match name {
            "--help" | "-h" => return Ok(Parsed::Help),
            "--compact" => {
                if attached.is_some() {
                    return Err(usage("--compact takes no value".to_string()));
                }
                compact = true;
            }
            "--policy" | "--input" | "--params" => {
                let value = match attached {
                    Some(value) => Some(value),
                    None => rest.next().filter(|v| !v.starts_with("--")).cloned(),
                };
                let Some(value) = value.filter(|v| !v.is_empty()) else {
                    return Err(usage(format!("{name} needs a value")));
                };
                let slot = match name {
                    "--policy" => &mut policy,
                    "--input" => &mut input,
                    _ => &mut params,
                };
                if slot.replace(value).is_some() {
                    return Err(usage(format!("{name} given twice")));
                }
            }
            other if other.starts_with("--") => {
                return Err(usage(format!("unknown flag '{other}'")));
            }
            other => return Err(usage(format!("unexpected argument '{other}'"))),
        }
    }
    Ok(Parsed::Run(Options {
        command,
        policy: policy.ok_or_else(|| usage("--policy is missing".to_string()))?,
        input: input.ok_or_else(|| usage("--input is missing".to_string()))?,
        params,
        compact,
    }))
}
