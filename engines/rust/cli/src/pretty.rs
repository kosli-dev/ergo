//! Experimental: shows a report for a person at a terminal.

use serde_json::{Map, Value};

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

/// What `--color` says.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Color {
    /// Colour when stdout is a terminal and `NO_COLOR` isn't set, the default.
    Auto,
    /// Always colour.
    Always,
    /// Never colour.
    Never,
}

/// Whether to write colour codes: `--color always` and `--color never` decide, and `auto` colours a terminal when `no_color` is false.
pub fn color_on(choice: Color, terminal: bool, no_color: bool) -> bool {
    match choice {
        Color::Always => true,
        Color::Never => false,
        Color::Auto => terminal && !no_color,
    }
}

/// The locale a program runs in: the first of `LC_ALL`, `LC_CTYPE` and `LANG` that `get` gives a non-empty value for.
pub fn locale(get: impl Fn(&str) -> Option<String>) -> Option<String> {
    ["LC_ALL", "LC_CTYPE", "LANG"]
        .into_iter()
        .find_map(|name| get(name).filter(|value| !value.is_empty()))
}

/// Whether `locale` names UTF-8, so glyphs can be written.
pub fn utf8(locale: Option<&str>) -> bool {
    locale.is_some_and(|locale| {
        let locale = locale.to_ascii_lowercase();
        locale.contains("utf-8") || locale.contains("utf8")
    })
}

/// The mark that starts a line.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Mark {
    /// Something passed or is met, in green.
    Pass,
    /// Something failed, in red.
    Fail,
    /// A warning, in yellow.
    Warn,
    /// Something that isn't judged, like a subject out of scope, dim.
    Skip,
    /// The verdict line, in bold.
    Therefore,
}

/// `text` with every control character written as a visible `\u{..}` escape: C0 (including newline, return and tab), DEL and C1.
pub fn escape(text: &str) -> String {
    text.chars()
        .map(|c| {
            if c.is_control() {
                format!("\\u{{{:x}}}", c as u32)
            } else {
                c.to_string()
            }
        })
        .collect()
}

const RESET: &str = "\x1b[0m";

fn paint(text: &str, code: &str, on: bool) -> String {
    if on {
        format!("\x1b[{code}m{text}{RESET}")
    } else {
        text.to_string()
    }
}

impl Style {
    fn glyph(&self, mark: Mark) -> &'static str {
        match (mark, self.glyphs) {
            (Mark::Pass, true) => "✓",
            (Mark::Pass, false) => "ok",
            (Mark::Fail, true) => "✗",
            (Mark::Fail, false) => "FAIL",
            (Mark::Warn, true) => "⚠",
            (Mark::Warn, false) => "warn",
            (Mark::Skip, true) => "–",
            (Mark::Skip, false) => "-",
            (Mark::Therefore, true) => "∴",
            (Mark::Therefore, false) => "->",
        }
    }

    /// `text` after the mark, dressed in the mark's colour: the whole line for everything but a pass, which only colours its mark.
    pub fn line(&self, mark: Mark, text: &str) -> String {
        let glyph = self.glyph(mark);
        let text = &escape(text);
        let whole = |code| paint(&format!("{glyph} {text}"), code, self.color);
        match mark {
            Mark::Pass => format!("{} {text}", paint(glyph, "32", self.color)),
            Mark::Fail => whole("31"),
            Mark::Warn => whole("33"),
            Mark::Skip => whole("2"),
            Mark::Therefore => whole("1"),
        }
    }
}

struct Row {
    requirement: String,
    check: String,
    passed: bool,
    cause: Option<String>,
    subject: String,
    message: Option<String>,
}

fn read_row(
    index: usize,
    row: &Value,
    policy: &Value,
    requirements: &Map<String, Value>,
) -> Result<Row, String> {
    let number = index + 1;
    let text = |field: &str| {
        row[field]
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| format!("the {field} of row {number} is missing or isn't text"))
    };
    let requirement = text("requirement")?;
    if !requirements.contains_key(&requirement) {
        return Err(format!(
            "the requirement {requirement} of row {number} isn't in the report's requirements"
        ));
    }
    let check = text("check")?;
    let passed = row["passed"]
        .as_bool()
        .ok_or_else(|| format!("the passed of row {number} is missing or isn't true or false"))?;
    if row["subject"]["type"].as_str().is_none() {
        return Err(format!("the subject of row {number} has no type"));
    }
    let subject = crate::outcome::row_subject_words(row, policy);
    let message = match &row["message"] {
        Value::Null => None,
        Value::String(message) => Some(message.clone()),
        _ => return Err(format!("the message of row {number} isn't text")),
    };
    Ok(Row {
        requirement,
        check,
        passed,
        cause: row["cause"].as_str().map(str::to_string),
        subject,
        message,
    })
}

fn describe(status: &str) -> (Mark, String) {
    match status {
        "met" => (Mark::Pass, "is met".to_string()),
        "not_applicable" => (Mark::Skip, "is not applicable".to_string()),
        "not_met" => (Mark::Fail, "is not met".to_string()),
        other => (Mark::Fail, format!("has status {other:?}")),
    }
}

fn plural(n: usize) -> &'static str {
    if n == 1 { "" } else { "s" }
}

fn row_line(row: &Row) -> (Mark, String) {
    match (row.check.as_str(), row.passed) {
        ("$applies", true) => (Mark::Pass, format!("{} is in scope", row.subject)),
        ("$applies", false) if out_of_scope(row) => (
            Mark::Skip,
            match &row.message {
                Some(message) => format!("{} is out of scope ({message})", row.subject),
                None => format!("{} is out of scope", row.subject),
            },
        ),
        (check, true) => (Mark::Pass, format!("{} passes {check}", row.subject)),
        (check, false) => (Mark::Fail, format!("{} fails {check}", row.subject)),
    }
}

fn out_of_scope(row: &Row) -> bool {
    row.check == "$applies" && !row.passed && row.cause.as_deref() == Some("value")
}

/// Shows `report`, made for `policy`, as text, or says what it can't read.
pub fn render(report: &Value, policy: &Value, style: &Style) -> Result<String, String> {
    let compliant = report["compliant"]
        .as_bool()
        .ok_or("the report's compliant is missing or isn't true or false")?;
    let requirements = report["requirements"]
        .as_object()
        .ok_or("the report has no requirements object")?;
    let results = report["results"]
        .as_array()
        .ok_or("the report has no results list")?;
    let mut statuses = Vec::new();
    for (name, entry) in requirements {
        let status = entry["status"]
            .as_str()
            .ok_or_else(|| format!("the status of requirement {name} is missing or isn't text"))?;
        let (mark, words) = describe(status);
        statuses.push((name, mark, words));
    }
    statuses.sort_by_key(|(_, mark, _)| *mark != Mark::Fail);
    let rows = results
        .iter()
        .enumerate()
        .map(|(index, row)| read_row(index, row, policy, requirements))
        .collect::<Result<Vec<_>, _>>()?;
    let mut out = String::new();
    for (name, mark, words) in &statuses {
        out.push_str(&style.line(*mark, &format!("{name} {words}")));
        out.push('\n');
        for row in rows.iter().filter(|row| row.requirement == **name) {
            let shown = match style.show {
                Show::All => true,
                Show::Failed => *mark == Mark::Fail && !row.passed && !out_of_scope(row),
            };
            if !shown {
                continue;
            }
            let (row_mark, text) = row_line(row);
            out.push_str(&format!("    {}\n", style.line(row_mark, &text)));
            if row_mark == Mark::Fail
                && let Some(message) = &row.message
            {
                out.push_str(&format!("      because {}\n", escape(message)));
            }
        }
    }
    let skipped = rows.iter().filter(|row| out_of_scope(row)).count();
    let passed = rows.iter().filter(|row| row.passed).count();
    let failed = rows.len() - passed - skipped;
    let gap = if out.is_empty() { "" } else { "\n" };
    out.push_str(&format!(
        "{gap}  {} row{}: {passed} passed, {failed} failed, {skipped} out of scope\n\n",
        rows.len(),
        plural(rows.len())
    ));
    let verdict = if compliant {
        "compliant"
    } else {
        "not compliant"
    };
    out.push_str(&style.line(Mark::Therefore, verdict));
    out.push('\n');
    Ok(out)
}

#[cfg(test)]
mod tests;
