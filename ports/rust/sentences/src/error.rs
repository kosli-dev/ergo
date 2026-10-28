#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct SyntaxError {
    pub column: Option<usize>,
    pub message: String,
}

impl SyntaxError {
    pub(crate) fn new(message: String) -> Self {
        let column = column_of(&message);
        SyntaxError { column, message }
    }
}

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
