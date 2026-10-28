mod error;
mod parse;
mod print;
mod problems;
mod tree;
mod words;

pub use error::SyntaxError;
pub use print::{print_condition, print_from, print_from_condition, print_path, print_term};
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_itself() {
        assert_eq!(NAME, "ergo-sentences");
    }
}
