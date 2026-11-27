//! Experimental: shows a report for a person at a terminal.

use serde_json::Value;

/// Which rows `--show` lists.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Show {
    /// Only the rows that failed, the default.
    Failed,
    /// Every row.
    All,
}

/// How the text is dressed: with ANSI colours or not, with glyphs or plain words, and which rows to list.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct Style {
    /// Whether to write ANSI colour codes.
    pub color: bool,
    /// Whether to write `✓`, `✗`, `⚠`, `–` and `∴`, and not `ok`, `FAIL`, `warn`, `-` and `->`.
    pub glyphs: bool,
    /// Which rows to list.
    pub show: Show,
}

/// Shows `report` as text, or says what it can't read.
pub fn render(report: &Value, style: &Style) -> Result<String, String> {
    let _ = (report, style);
    Err("todo".to_string())
}

#[cfg(test)]
mod tests;
