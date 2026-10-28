/// Why a line did not read, in the words `ergo.rego` uses.
///
/// ```text
/// unclosed quote at column 14
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct SyntaxError {
    /// The place in the trimmed line, counted in characters from 1. It is only set when the message names a column.
    pub column: Option<usize>,
    /// What is wrong.
    pub message: String,
}

impl SyntaxError {
    pub(crate) fn new(message: String) -> Self {
        let column = column_of(&message);
        SyntaxError { column, message }
    }
}

impl std::fmt::Display for SyntaxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for SyntaxError {}

fn column_of(message: &str) -> Option<usize> {
    let rest = [
        "unclosed quote at column ",
        "invalid string at column ",
        "nothing after the path at column ",
    ]
    .iter()
    .find_map(|prefix| message.strip_prefix(prefix))?;
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok()
}
