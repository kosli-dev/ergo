#![doc = include_str!("../README.md")]
#![warn(missing_docs)]

mod error;
mod numbers;
mod parse;
mod print;
mod problems;
mod rules;
mod tree;
mod words;

pub use error::SyntaxError;
pub use numbers::rust_pattern;
pub use print::{
    print_assertion, print_check, print_condition, print_for, print_for_item, print_from,
    print_from_condition, print_from_condition_with, print_left_term, print_path, print_term,
};
pub use rules::{check_problems, for_problems, from_problems};
pub use tree::*;

use parse::{FromRead, Parser, trim};
use problems::{Kind, errors};

/// Reads a path, like `x.y[1]` or `item 2 of xs`.
///
/// Whitespace at both ends is dropped. It returns the `SyntaxError`s `ergo.rego` gives for the same line when the line is not a path.
///
/// ```
/// use ergo_sentences::parse_path;
///
/// assert!(parse_path("x.y[1]").is_ok());
/// assert!(parse_path("x.y[").is_err());
/// ```
pub fn parse_path(line: &str) -> Result<Path, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .whole(parser.path(0, Side::Left))
        .ok_or_else(|| errors(text, Kind::Path))
}

/// Reads a `from` line, like `every items whose x is 1`.
///
/// It accepts what the `from-line` rule of `spec/sentences.abnf` accepts and nothing else. Whitespace at both ends is dropped. It returns the `SyntaxError`s `ergo.rego` gives for the same line when the line does not read.
///
/// ```
/// use ergo_sentences::parse_from;
///
/// assert!(parse_from("every items whose x is 1").is_ok());
/// assert!(parse_from("every").is_err());
/// ```
pub fn parse_from(line: &str) -> Result<FromLine, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .whole(parser.read_from_line(0))
        .map(FromRead::build)
        .ok_or_else(|| errors(text, Kind::From))
}

/// Reads a check sentence, like `approvals is at least 2`.
///
/// It accepts what the `check` rule of `spec/sentences.abnf` accepts and nothing else. Whitespace at both ends is dropped. It returns the `SyntaxError`s `ergo.rego` gives for the same line when the line does not read.
///
/// ```
/// use ergo_sentences::parse_check;
///
/// assert!(parse_check("approvals is at least 2").is_ok());
/// let errors = parse_check("x is \"a").unwrap_err();
/// assert_eq!(errors[0].message, "unclosed quote at column 6");
/// ```
pub fn parse_check(line: &str) -> Result<Check, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .read_check()
        .map(|(check, _)| check)
        .ok_or_else(|| errors(text, Kind::Check))
}

/// Reads a `for` line, like `every xs as x, last of ys as y`.
///
/// It accepts what the `for-line` rule of `spec/sentences.abnf` accepts and nothing else. Whitespace at both ends is dropped. It returns the `SyntaxError`s `ergo.rego` gives for the same line when the line does not read.
///
/// ```
/// use ergo_sentences::parse_for;
///
/// assert!(parse_for("every xs as x").is_ok());
/// assert!(parse_for("every xs").is_err());
/// ```
pub fn parse_for(line: &str) -> Result<ForLine, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .read_for(2)
        .map(|(line, _)| line)
        .ok_or_else(|| errors(text, Kind::For))
}
