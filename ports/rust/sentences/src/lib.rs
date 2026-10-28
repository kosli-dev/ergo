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
    print_from_condition, print_from_condition_with, print_from_with, print_path, print_term,
};
pub use rules::{check_problems, for_problems, from_problems};
pub use tree::*;

use parse::{Parser, trim};
use problems::{Kind, errors};

pub const NAME: &str = "ergo-sentences";

pub fn parse_path(line: &str) -> Result<Path, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .whole(parser.path(0, Side::Left))
        .ok_or_else(|| errors(text, Kind::Path))
}

pub fn parse_from(line: &str) -> Result<From, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .whole(parser.read_from_line(0))
        .ok_or_else(|| errors(text, Kind::From))
}

pub fn parse_check(line: &str) -> Result<Check, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .read_check()
        .map(|(check, _)| check)
        .ok_or_else(|| errors(text, Kind::Check))
}

pub fn parse_for(line: &str) -> Result<For, Vec<SyntaxError>> {
    let text = trim(line);
    let parser = Parser::new(text, false);
    parser
        .read_for(2)
        .map(|(line, _)| line)
        .ok_or_else(|| errors(text, Kind::For))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_itself() {
        assert_eq!(NAME, "ergo-sentences");
    }
}
