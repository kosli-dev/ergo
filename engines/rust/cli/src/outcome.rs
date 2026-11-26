//! Experimental: turns a report into outcome lines, the form a policy's examples write what they expect in.

use serde_json::{Map, Value};
use std::collections::BTreeSet;

/// One item of an outcome: a line, or a heading with the lines under it.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Item {
    /// A line on its own, like `compliant` or `released is met`.
    Line(String),
    /// A requirement heading, like `approved is not met`, with its check lines.
    Group(String, Vec<String>),
}

fn word_value(word: &str) -> Value {
    match serde_json::from_str::<Value>(word) {
        Ok(value @ (Value::Number(_) | Value::Bool(_) | Value::Null)) => value,
        _ => Value::String(word.to_string()),
    }
}

/// The shortest text that reads back as `id`, or `None` for an object or a list.
pub fn id_text(id: &Value) -> Option<String> {
    match id {
        Value::String(s) => {
            let word = !s.is_empty()
                && !s.starts_with('"')
                && !s.chars().any(|c| c.is_whitespace() || c.is_control());
            Some(if word && word_value(s) == *id {
                s.clone()
            } else {
                Value::String(s.clone()).to_string()
            })
        }
        Value::Number(_) | Value::Bool(_) | Value::Null => Some(id.to_string()),
        _ => None,
    }
}

/// Reads an id at the start of `text`, and gives it with the text after it.
pub fn read_id(text: &str) -> Option<(Value, &str)> {
    if text.starts_with('"') {
        let mut stream = serde_json::Deserializer::from_str(text).into_iter::<Value>();
        return match stream.next() {
            Some(Ok(value @ Value::String(_))) => Some((value, &text[stream.byte_offset()..])),
            _ => None,
        };
    }
    let end = text.find(char::is_whitespace).unwrap_or(text.len());
    (end > 0).then(|| (word_value(&text[..end]), &text[end..]))
}

/// The line for a report row, `None` for a passed row of a check Ergo adds, or why the line can't be written yet.
pub fn row_line(row: &Value) -> Result<Option<String>, String> {
    let check = row["check"].as_str().unwrap_or_default();
    let passed = row["passed"] == true;
    let not_yet = |what: &str| {
        Err(format!(
            "lines for {what} aren't supported yet, as for {check} in {}",
            row["requirement"].as_str().unwrap_or_default()
        ))
    };
    if check.starts_with('$') {
        return if passed {
            Ok(None)
        } else if check == "$applies" {
            not_yet("subjects out of scope")
        } else {
            not_yet("checks Ergo adds")
        };
    }
    if row["subject"].get("in").is_some() {
        return not_yet("child subjects");
    }
    let Some(id) = id_text(&row["subject"]["id"]) else {
        return not_yet("ids that are objects or lists");
    };
    let subject = row["subject"]["type"].as_str().unwrap_or_default();
    let line = match (passed, row["message"].as_str()) {
        (true, _) => format!("{subject} {id} passes {check}"),
        (false, Some(message)) if !message.is_empty() => {
            format!("{subject} {id} fails {check} because {message}")
        }
        (false, _) => format!("{subject} {id} fails {check}"),
    };
    Ok(Some(line))
}

fn scalar(text: &str) -> String {
    let reads_back = |source: String, want: Value| crate::yaml::parse(&source).ok() == Some(want);
    let plain = !text.chars().any(char::is_control)
        && reads_back(format!("- {text}\n"), Value::from(vec![text]))
        && reads_back(
            format!("{text}: 0\n"),
            Value::Object(Map::from_iter([(text.to_string(), Value::from(0))])),
        );
    if plain {
        text.to_string()
    } else if text.chars().any(char::is_control) {
        Value::from(text).to_string()
    } else {
        format!("'{}'", text.replace('\'', "''"))
    }
}

/// Writes items as a YAML list, quoting a line or a heading only when YAML would read it otherwise.
pub fn yaml(items: &[Item]) -> String {
    let mut out = String::new();
    for item in items {
        match item {
            Item::Line(line) => out.push_str(&format!("- {}\n", scalar(line))),
            Item::Group(heading, lines) => {
                out.push_str(&format!("- {}:\n", scalar(heading)));
                for line in lines {
                    out.push_str(&format!("    - {}\n", scalar(line)));
                }
            }
        }
    }
    out
}

/// The items as JSON, as YAML would read them.
pub fn to_json(items: &[Item]) -> Value {
    Value::Array(
        items
            .iter()
            .map(|item| match item {
                Item::Line(line) => Value::from(line.as_str()),
                Item::Group(heading, lines) => Value::Object(Map::from_iter([(
                    heading.clone(),
                    Value::from(lines.clone()),
                )])),
            })
            .collect(),
    )
}

/// The part of a report an example's lines cover.
#[derive(Debug, Default, PartialEq, Eq, Clone)]
pub struct Region {
    /// The whole policy, as `compliant` or `not compliant` covers it.
    pub compliant: bool,
    /// Whole requirements, as a requirement line or a heading with a status covers one.
    pub requirements: BTreeSet<String>,
    /// Checks, as requirement and check, as a check line covers one.
    pub checks: BTreeSet<(String, String)>,
}

/// The whole outcome of a report, as `ergo report --format outcome` prints it, or why a row can't be shown yet.
pub fn of(report: &Value) -> Result<Vec<Item>, String> {
    let whole = Region {
        compliant: true,
        ..Region::default()
    };
    items(report, &whole, true)
}

/// The items of a report inside `region`, leaving out the rows that can't be shown yet.
pub fn part(report: &Value, region: &Region) -> Vec<Item> {
    items(report, region, false).unwrap_or_default()
}

/// The words a requirement line puts after the requirement's name for a report status, like `is not met` for `not_met`.
pub fn status_words(status: &Value) -> Option<&'static str> {
    match status.as_str()? {
        "met" => Some("is met"),
        "not_met" => Some("is not met"),
        "not_applicable" => Some("is not applicable"),
        _ => None,
    }
}

fn items(report: &Value, region: &Region, strict: bool) -> Result<Vec<Item>, String> {
    let mut items = Vec::new();
    if region.compliant {
        items.push(Item::Line(
            if report["compliant"] == true {
                "compliant"
            } else {
                "not compliant"
            }
            .to_string(),
        ));
    }
    let rows = report["results"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or_default();
    let requirements = report["requirements"].as_object().into_iter().flatten();
    for (name, entry) in requirements {
        let whole = region.compliant || region.requirements.contains(name);
        let covers =
            |check: &str| whole || region.checks.contains(&(name.clone(), check.to_string()));
        if !whole && !region.checks.iter().any(|(r, _)| r == name) {
            continue;
        }
        let mut lines = Vec::new();
        for row in rows {
            if row["requirement"] != name.as_str()
                || !covers(row["check"].as_str().unwrap_or_default())
            {
                continue;
            }
            match row_line(row) {
                Ok(Some(line)) => lines.push(line),
                Ok(None) => {}
                Err(problem) if strict => return Err(problem),
                Err(_) => {}
            }
        }
        if !whole {
            items.push(Item::Group(name.clone(), lines));
            continue;
        }
        let Some(words) = status_words(&entry["status"]) else {
            return Err(format!("requirement {name} has no status"));
        };
        let heading = format!("{name} {words}");
        items.push(if lines.is_empty() {
            Item::Line(heading)
        } else {
            Item::Group(heading, lines)
        });
    }
    Ok(items)
}
