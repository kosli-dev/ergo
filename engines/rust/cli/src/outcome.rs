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

/// Whether two ids are the same: numbers by value, so `7.0` is `7`, and anything else as JSON values.
pub fn same_id(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(a), Value::Number(b)) => crate::number::same_value(a, b),
        _ => a == b,
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

/// A check line, read: `<subject> <id> passes <check>`, or `fails <check>` with an optional `because <message>`.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct CheckLine {
    /// The subject's name, as the policy writes it.
    pub subject: String,
    /// The subject's id.
    pub id: Value,
    /// Whether the line says `passes`.
    pub passes: bool,
    /// The check's name.
    pub check: String,
    /// The message after `because`, if the line has one.
    pub because: Option<String>,
    /// The type and id of each subject the line names after `in`, parent first.
    pub parents: Vec<(String, Value)>,
}

/// The subjects whose ids a row of `subject` carries under `in`, parent first, read from the `from` lines the report keeps in its `subjects`.
pub fn ancestors(report: &Value, subject: &str) -> Vec<String> {
    let subjects: Map<String, Value> = report["subjects"]
        .as_object()
        .into_iter()
        .flatten()
        .map(|(name, entry)| {
            (
                name.clone(),
                Value::Object(Map::from_iter([(
                    "from".to_string(),
                    entry["from"].clone(),
                )])),
            )
        })
        .collect();
    let policy = Value::Object(Map::from_iter([(
        "subjects".to_string(),
        Value::Object(subjects),
    )]));
    ergo_policy_engine::ancestors(&policy, subject)
}

fn longest_first<'a>(names: &[&'a str]) -> Vec<&'a str> {
    let mut names = names.to_vec();
    names.sort_by_key(|name| std::cmp::Reverse(name.len()));
    names
}

fn subject_at<'a>(text: &str, subjects: &[&'a str]) -> Option<&'a str> {
    longest_first(subjects)
        .into_iter()
        .find(|name| text.starts_with(&format!("{name} ")))
}

/// The names of a report's `subjects` or of a requirement's `checks`, leaving out Ergo's own.
pub fn names(map: &Value) -> Vec<&str> {
    map.as_object()
        .into_iter()
        .flat_map(|m| m.keys().map(String::as_str))
        .filter(|name| !name.starts_with('$'))
        .collect()
}

/// Reads a check line under `requirement`, with the longest of `subjects` it starts with, then an id, then for each ` in ` the longest of `subjects` that follows and an id, then `passes` or `fails`, and the longest of `checks` that the rest is or that is followed by ` because `. Gives why it can't be read otherwise.
pub fn read_check_line(
    text: &str,
    requirement: &str,
    subjects: &[&str],
    checks: &[&str],
) -> Result<CheckLine, String> {
    let not_yet = |what: &str| Err(format!("lines for {what} aren't supported yet"));
    let added = text.starts_with("fails $")
        || text.starts_with("passes $")
        || text.contains(" fails $")
        || text.contains(" passes $");
    let Some(subject) = subject_at(text, subjects) else {
        if added {
            return not_yet("checks Ergo adds");
        }
        return Err("it doesn't start with a subject of the policy".to_string());
    };
    let Some((id, mut rest)) = read_id(&text[subject.len() + 1..]) else {
        return Err(format!("it has no id after {subject}"));
    };
    let mut parents = Vec::new();
    while let Some(after) = rest.strip_prefix(" in ") {
        let Some(parent) = subject_at(after, subjects).or_else(|| {
            longest_first(subjects)
                .into_iter()
                .find(|name| after == *name)
        }) else {
            if added {
                return not_yet("checks Ergo adds");
            }
            return Err("it has no subject of the policy after in".to_string());
        };
        let Some((parent_id, after)) = read_id(after.get(parent.len() + 1..).unwrap_or_default())
        else {
            return Err(format!("it has no id after in {parent}"));
        };
        parents.push((parent.to_string(), parent_id));
        rest = after;
    }
    let (passes, rest) = if let Some(rest) = rest.strip_prefix(" passes ") {
        (true, rest)
    } else if let Some(rest) = rest.strip_prefix(" fails ") {
        (false, rest)
    } else if rest.starts_with(" is out of scope") || rest.starts_with(" is in scope") {
        return not_yet("subjects in or out of scope");
    } else if added {
        return not_yet("checks Ergo adds");
    } else {
        return Err("it needs passes or fails after the id".to_string());
    };
    let found = longest_first(checks).into_iter().find_map(|check| {
        if rest == check {
            Some((check, None))
        } else {
            let because = rest.strip_prefix(check)?.strip_prefix(" because ")?;
            (!passes).then(|| (check, Some(because.to_string())))
        }
    });
    let Some((check, because)) = found else {
        if rest.starts_with('$') {
            return not_yet("checks Ergo adds");
        }
        return Err(format!("it names no check of {requirement}"));
    };
    Ok(CheckLine {
        subject: subject.to_string(),
        id,
        passes,
        check: check.to_string(),
        because,
        parents,
    })
}

fn parents_of(row: &Value, report: &Value) -> Result<Vec<(String, Value)>, String> {
    let subject = &row["subject"];
    let kind = subject["type"].as_str().unwrap_or_default();
    let order = ancestors(report, kind);
    let given = match subject.get("in") {
        None => Map::new(),
        Some(Value::Object(given)) if !given.is_empty() => given.clone(),
        Some(_) => Map::from_iter([(String::new(), Value::Null)]),
    };
    if given.len() != order.len() || !order.iter().all(|name| given.contains_key(name)) {
        return Err(format!(
            "the in of a {kind} row doesn't name the subjects its from line is read inside, as for {} in {}",
            row["check"].as_str().unwrap_or_default(),
            row["requirement"].as_str().unwrap_or_default()
        ));
    }
    order
        .into_iter()
        .map(|name| {
            let id = given[&name].clone();
            match id_text(&id) {
                Some(_) => Ok((name, id)),
                None => Err(format!(
                    "lines for ids that are objects or lists aren't supported yet, as for {} in {}",
                    row["check"].as_str().unwrap_or_default(),
                    row["requirement"].as_str().unwrap_or_default()
                )),
            }
        })
        .collect()
}

fn row_parts(row: &Value, report: &Value) -> Result<Option<CheckLine>, String> {
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
    if id_text(&row["subject"]["id"]).is_none() {
        return not_yet("ids that are objects or lists");
    }
    let parents = parents_of(row, report)?;
    Ok(Some(CheckLine {
        subject: row["subject"]["type"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        id: row["subject"]["id"].clone(),
        passes: passed,
        check: check.to_string(),
        because: row["message"]
            .as_str()
            .filter(|message| !passed && !message.is_empty())
            .map(str::to_string),
        parents,
    }))
}

fn id_written(id: &Value, quoted: bool) -> String {
    match id {
        Value::String(_) if quoted => id.to_string(),
        id => id_text(id).unwrap_or_default(),
    }
}

/// The subject a check line names, with its id and each parent after `in`, like `artifact web in deployment d1`.
pub fn subject_words(subject: &str, id: &Value, parents: &[(String, Value)]) -> String {
    written_subject(subject, id, parents, false)
}

fn written_subject(subject: &str, id: &Value, parents: &[(String, Value)], quoted: bool) -> String {
    let mut text = format!("{subject} {}", id_written(id, quoted));
    for (parent, parent_id) in parents {
        text.push_str(&format!(" in {parent} {}", id_written(parent_id, quoted)));
    }
    text
}

fn write(line: &CheckLine, quoted: bool) -> String {
    let who = written_subject(&line.subject, &line.id, &line.parents, quoted);
    let check = &line.check;
    match (line.passes, &line.because) {
        (true, _) => format!("{who} passes {check}"),
        (false, Some(message)) => format!("{who} fails {check} because {message}"),
        (false, None) => format!("{who} fails {check}"),
    }
}

/// Whether two check lines say the same, with ids compared as [same_id] does.
pub fn same_line(a: &CheckLine, b: &CheckLine) -> bool {
    a.subject == b.subject
        && same_id(&a.id, &b.id)
        && a.passes == b.passes
        && a.check == b.check
        && a.because == b.because
        && a.parents.len() == b.parents.len()
        && a.parents
            .iter()
            .zip(&b.parents)
            .all(|((x, i), (y, j))| x == y && same_id(i, j))
}

/// The line for a report row as it is, with the parents the `from` lines in `report` give, `None` for a passed row of a check Ergo adds, or why the line can't be written yet.
pub fn row_line(row: &Value, report: &Value) -> Result<Option<String>, String> {
    Ok(row_parts(row, report)?.map(|line| write(&line, false)))
}

/// The line for a report row that reads back as that row against the names in `report`: it quotes an id that would read as part of a longer subject name, and leaves out a `because` that would read as part of a longer check name. `None` for a passed row of a check Ergo adds, or why no such line can be written.
pub fn line_for(row: &Value, report: &Value) -> Result<Option<String>, String> {
    let Some(line) = row_parts(row, report)? else {
        return Ok(None);
    };
    let requirement = row["requirement"].as_str().unwrap_or_default();
    let subjects = names(&report["subjects"]);
    let checks = names(&report["requirements"][requirement]["checks"]);
    let without_because = CheckLine {
        because: None,
        ..line.clone()
    };
    for (want, quoted) in [
        (&line, false),
        (&line, true),
        (&without_because, false),
        (&without_because, true),
    ] {
        let text = write(want, quoted);
        let read = read_check_line(&text, requirement, &subjects, &checks);
        if read.is_ok_and(|read| same_line(&read, want)) {
            return Ok(Some(text));
        }
    }
    Err(format!(
        "no line for {} and {} in {requirement} reads back as its row, because a longer subject or check name starts the same way",
        subject_words(&line.subject, &line.id, &line.parents),
        line.check
    ))
}

fn escaped(c: char) -> bool {
    c.is_control()
        || matches!(
            c,
            '\u{2028}' | '\u{2029}' | '\u{feff}' | '\u{fffe}' | '\u{ffff}'
        )
}

fn double_quoted(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            c if escaped(c) => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn scalar(text: &str) -> String {
    let reads_back = |source: String, want: Value| crate::yaml::parse(&source).ok() == Some(want);
    let needs_escapes = text.chars().any(escaped);
    let plain = !needs_escapes
        && reads_back(format!("- {text}\n"), Value::from(vec![text]))
        && reads_back(
            format!("{text}: 0\n"),
            Value::Object(Map::from_iter([(text.to_string(), Value::from(0))])),
        );
    if plain {
        text.to_string()
    } else if needs_escapes {
        double_quoted(text)
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

/// Reads a requirement line, like `released is met`, against the `requirements` of a policy or a report, and gives the requirement's name and the status words.
pub fn requirement_line<'a>(
    text: &'a str,
    requirements: &Value,
) -> Option<(&'a str, &'static str)> {
    ["is met", "is not met", "is not applicable"]
        .into_iter()
        .find_map(|words| {
            let name = text.strip_suffix(words)?.strip_suffix(' ')?;
            requirements.get(name).map(|_| (name, words))
        })
}

/// What a heading reads as: a requirement's name with its status words, a requirement's name on its own, or `None` when it names no requirement.
pub type Heading<'a> = Option<(&'a str, Option<&'static str>)>;

/// Reads a heading against `requirements`, or gives why it is written wrong when it is one requirement's name and also another's name with a status.
pub fn heading<'a>(text: &'a str, requirements: &Value) -> Result<Heading<'a>, String> {
    match (
        requirement_line(text, requirements),
        requirements.get(text).is_some(),
    ) {
        (Some((name, _)), true) => Err(format!(
            "the heading {text} could name the requirement {text} or the status of {name}: write the requirement's whole name and a status, like {text} is met, or for {name} write the line {text} and the heading {name}"
        )),
        (Some((name, words)), false) => Ok(Some((name, Some(words)))),
        (None, true) => Ok(Some((text, None))),
        (None, false) => Ok(None),
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
            match line_for(row, report) {
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
        let text = format!("{name} {words}");
        if strict && !lines.is_empty() && heading(&text, &report["requirements"]).is_err() {
            return Err(format!(
                "the heading {text}, for the status of {name}, would also name the requirement {text}, so it can't read back"
            ));
        }
        items.push(if lines.is_empty() {
            Item::Line(text)
        } else {
            Item::Group(text, lines)
        });
    }
    Ok(items)
}
