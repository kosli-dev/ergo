//! Experimental: turns a report into outcome lines, the form a policy's examples write what they expect in.

use serde_json::Value;

/// One item of an outcome: a line, or a heading with the lines under it.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Item {
    /// A line on its own, like `compliant` or `released is met`.
    Line(String),
    /// A requirement heading, like `approved is not met`, with its check lines.
    Group(String, Vec<String>),
}

/// The shortest text that reads back as `id`, or `None` for an object or a list.
pub fn id_text(_id: &Value) -> Option<String> {
    None
}

/// Reads an id at the start of `text`, and gives it with the text after it.
pub fn read_id(_text: &str) -> Option<(Value, &str)> {
    None
}

/// The line for a report row, `None` for a passed row of a check Ergo adds, or why the line can't be written yet.
pub fn row_line(_row: &Value) -> Result<Option<String>, String> {
    Ok(None)
}

/// Writes items as a YAML list, quoting a line or a heading only when YAML would read it otherwise.
pub fn yaml(_items: &[Item]) -> String {
    String::new()
}

/// The items as JSON, as YAML would read them.
pub fn to_json(_items: &[Item]) -> Value {
    Value::Null
}
