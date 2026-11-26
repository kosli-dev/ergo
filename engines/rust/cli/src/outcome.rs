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
    /// The subject's id, or `None` for a row of a check Ergo adds, which has none.
    pub id: Option<Value>,
    /// Whether the line says `passes`.
    pub passes: bool,
    /// The check's name.
    pub check: String,
    /// The message after `because`, if the line has one.
    pub because: Option<String>,
    /// The type and id of each subject the line names after `in`, parent first.
    pub parents: Vec<(String, Value)>,
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

/// The names of a policy's `subjects` or of a requirement's `checks`, leaving out Ergo's own.
pub fn names(map: &Value) -> Vec<&str> {
    map.as_object()
        .into_iter()
        .flat_map(|m| m.keys().map(String::as_str))
        .filter(|name| !name.starts_with('$'))
        .collect()
}

/// The checks Ergo adds whose rows have no id, so their lines have none: `$min_subjects`, `$unique_ids`, `$unique_ancestor_ids` and `$well_formed`.
pub const ADDED: [&str; 4] = [
    "$min_subjects",
    "$unique_ids",
    "$unique_ancestor_ids",
    "$well_formed",
];

const APPLIES: &str = "$applies";

const SCOPE_WORDS: &str = "a subject in or out of scope is written with is in scope or is out of scope, not with passes or fails";

type Parents = Vec<(String, Value)>;

fn read_parents<'t>(mut rest: &'t str, subjects: &[&str]) -> Result<(Parents, &'t str), String> {
    let mut parents = Vec::new();
    while let Some(after) = rest.strip_prefix(" in ") {
        let Some(parent) = subject_at(after, subjects).or_else(|| {
            longest_first(subjects)
                .into_iter()
                .find(|name| after == *name)
        }) else {
            return Err("it has no subject of the policy after in".to_string());
        };
        let Some((parent_id, after)) = read_id(after.get(parent.len() + 1..).unwrap_or_default())
        else {
            return Err(format!("it has no id after in {parent}"));
        };
        parents.push((parent.to_string(), parent_id));
        rest = after;
    }
    Ok((parents, rest))
}

fn verb(rest: &str) -> Option<(bool, &str)> {
    if let Some(rest) = rest.strip_prefix(" passes ") {
        Some((true, rest))
    } else {
        rest.strip_prefix(" fails ").map(|rest| (false, rest))
    }
}

fn check_named<'a>(
    rest: &str,
    passes: bool,
    checks: &[&'a str],
) -> Option<(&'a str, Option<String>)> {
    longest_first(checks).into_iter().find_map(|check| {
        if rest == check {
            Some((check, None))
        } else {
            let because = rest.strip_prefix(check)?.strip_prefix(" because ")?;
            (!passes).then(|| (check, Some(because.to_string())))
        }
    })
}

fn names_applies(rest: &str) -> bool {
    rest == APPLIES || rest.starts_with(&format!("{APPLIES} "))
}

fn read_with_id(
    text: &str,
    requirement: &str,
    subjects: &[&str],
    checks: &[&str],
) -> Result<CheckLine, String> {
    let Some(subject) = subject_at(text, subjects) else {
        return Err("it doesn't start with a subject of the policy".to_string());
    };
    let Some((id, rest)) = read_id(&text[subject.len() + 1..]) else {
        return Err(format!("it has no id after {subject}"));
    };
    let (parents, rest) = read_parents(rest, subjects)?;
    let line = |passes: bool, check: &str, because: Option<&str>| CheckLine {
        subject: subject.to_string(),
        id: Some(id.clone()),
        passes,
        check: check.to_string(),
        because: because.map(str::to_string),
        parents: parents.clone(),
    };
    if rest == " is in scope" {
        return Ok(line(true, APPLIES, None));
    }
    if rest.starts_with(" is in scope ") {
        return Err("is in scope has nothing after it".to_string());
    }
    if let Some(after) = rest.strip_prefix(" is out of scope") {
        if after.is_empty() {
            return Ok(line(false, APPLIES, None));
        }
        if let Some(because) = after.strip_prefix(" because ") {
            return Ok(line(false, APPLIES, Some(because)));
        }
    }
    let Some((passes, rest)) = verb(rest) else {
        return Err("it needs passes or fails after the id".to_string());
    };
    if names_applies(rest) {
        return Err(SCOPE_WORDS.to_string());
    }
    let Some((check, because)) = check_named(rest, passes, checks) else {
        return Err(format!("it names no check of {requirement}"));
    };
    Ok(line(passes, check, because.as_deref()))
}

fn read_without_id(text: &str, own: &str, subjects: &[&str]) -> Result<CheckLine, String> {
    let spaced = format!(" {text}");
    let (subject, parents, rest) = if verb(&spaced).is_some() {
        (own, Vec::new(), spaced.as_str())
    } else {
        let Some(subject) = subject_at(text, subjects) else {
            return Err("it doesn't start with a subject of the policy".to_string());
        };
        let (parents, rest) = read_parents(&text[subject.len()..], subjects)?;
        if verb(rest).is_some() && parents.is_empty() && subject == own {
            return Err(format!(
                "the row of a check Ergo adds for {own} itself has no subject to name, so its line starts with passes or fails"
            ));
        }
        (subject, parents, rest)
    };
    let Some((passes, rest)) = verb(rest) else {
        return Err("a line for a check Ergo adds has no id, so passes or fails comes right after the subject and its parents".to_string());
    };
    if names_applies(rest) {
        return Err(SCOPE_WORDS.to_string());
    }
    let Some((check, because)) = check_named(rest, passes, &ADDED) else {
        return Err("it names no check Ergo adds".to_string());
    };
    Ok(CheckLine {
        subject: subject.to_string(),
        id: None,
        passes,
        check: check.to_string(),
        because,
        parents,
    })
}

fn names_a_check_ergo_adds(text: &str) -> bool {
    let head = text.find(" because ").map_or(text, |at| &text[..at]);
    ["passes ", "fails "].into_iter().any(|verb| {
        ADDED.iter().chain([&APPLIES]).any(|name| {
            let said = format!("{verb}{name}");
            head.starts_with(&said) || head.contains(&format!(" {said}"))
        })
    })
}

/// Reads a line under `requirement`, whose subject is `own`, against the policy's `subjects` and the requirement's `checks`. A check line is the longest of `subjects` it starts with, then an id, then for each ` in ` the longest of `subjects` that follows and an id, then `passes` or `fails`, and the longest of `checks` that the rest is or that is followed by ` because `. A scope line has `is in scope`, `is out of scope` or `is out of scope because <message>` in place of `passes` or `fails` and a check, and reads as the check `$applies`. A line for a check Ergo adds ([ADDED]) has no id, and starts with `passes` or `fails` when its row is for `own` and has no `in`. Gives why it can't be read otherwise.
pub fn read_check_line(
    text: &str,
    requirement: &str,
    own: &str,
    subjects: &[&str],
    checks: &[&str],
) -> Result<CheckLine, String> {
    let with_id = read_with_id(text, requirement, subjects, checks);
    if with_id.is_ok() {
        return with_id;
    }
    let without_id = read_without_id(text, own, subjects);
    if without_id.is_ok() || (names_a_check_ergo_adds(text) && with_id != Err(SCOPE_WORDS.into())) {
        return without_id;
    }
    with_id
}

fn parents_of(row: &Value, policy: &Value) -> Result<Vec<(String, Value)>, String> {
    let subject = &row["subject"];
    let kind = subject["type"].as_str().unwrap_or_default();
    let order = ergo_policy_engine::ancestors(policy, kind);
    let given = match subject.get("in") {
        None => Some(Map::new()),
        Some(Value::Object(given)) if !given.is_empty() => Some(given.clone()),
        Some(_) => None,
    };
    let added = row["check"].as_str().is_some_and(|c| ADDED.contains(&c));
    if added && subject.get("in").is_none() {
        return Ok(Vec::new());
    }
    let Some(given) = given.filter(|given| {
        given.len() == order.len() && order.iter().all(|name| given.contains_key(name))
    }) else {
        return Err(format!(
            "the in of a {kind} row doesn't name the subjects its from line is read inside, as for {} in {}",
            row["check"].as_str().unwrap_or_default(),
            row["requirement"].as_str().unwrap_or_default()
        ));
    };
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

fn row_parts(row: &Value, policy: &Value) -> Result<CheckLine, String> {
    let check = row["check"].as_str().unwrap_or_default();
    let requirement = row["requirement"].as_str().unwrap_or_default();
    let passed = row["passed"] == true;
    let not_yet = |what: &str| {
        Err(format!(
            "lines for {what} aren't supported yet, as for {check} in {requirement}"
        ))
    };
    let id = &row["subject"]["id"];
    let added = ADDED.contains(&check);
    if check.starts_with('$') && check != APPLIES && !added {
        return not_yet("this check");
    }
    if added && !id.is_null() {
        return not_yet("a row of a check Ergo adds that has an id");
    }
    if !added && id_text(id).is_none() {
        return not_yet("ids that are objects or lists");
    }
    let parents = parents_of(row, policy)?;
    let subject = row["subject"]["type"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    if check == APPLIES && !passed && row["cause"] != "value" {
        return Err(format!(
            "lines for an $applies row that failed with {}, not value, aren't supported yet, as for {} in {requirement}",
            row["cause"].as_str().unwrap_or("no cause"),
            subject_words(&subject, Some(id), &parents)
        ));
    }
    Ok(CheckLine {
        subject,
        id: (!added).then(|| id.clone()),
        passes: passed,
        check: check.to_string(),
        because: row["message"]
            .as_str()
            .filter(|message| !passed && !message.is_empty())
            .map(str::to_string),
        parents,
    })
}

fn same_row_of(a: &Value, b: &Value) -> bool {
    let ids = |a: &Value, b: &Value| (a.is_null() && b.is_null()) || same_id(a, b);
    if a["check"] != b["check"] {
        return false;
    }
    let (a, b) = (&a["subject"], &b["subject"]);
    let same_in = match (a.get("in"), b.get("in")) {
        (None, None) => true,
        (Some(Value::Object(x)), Some(Value::Object(y))) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(name, id)| y.get(name).is_some_and(|other| ids(id, other)))
        }
        _ => false,
    };
    a["type"] == b["type"] && ids(&a["id"], &b["id"]) && same_in
}

fn left_out(row: &Value) -> bool {
    row["passed"] == true && row["check"].as_str().is_some_and(|c| c.starts_with('$'))
}

fn id_written(id: &Value, quoted: bool) -> String {
    match id {
        Value::String(_) if quoted => id.to_string(),
        id => id_text(id).unwrap_or_default(),
    }
}

/// The subject a check line names, with its id, if it has one, and each parent after `in`, like `artifact web in deployment d1`.
pub fn subject_words(subject: &str, id: Option<&Value>, parents: &[(String, Value)]) -> String {
    written_subject(subject, id, parents, None, false)
}

fn written_subject(
    subject: &str,
    id: Option<&Value>,
    parents: &[(String, Value)],
    own: Option<&str>,
    quoted: bool,
) -> String {
    let mut text = match id {
        Some(id) => format!("{subject} {}", id_written(id, quoted)),
        None if parents.is_empty() && own == Some(subject) => String::new(),
        None => subject.to_string(),
    };
    for (parent, parent_id) in parents {
        text.push_str(&format!(" in {parent} {}", id_written(parent_id, quoted)));
    }
    text
}

fn write(line: &CheckLine, own: &str, quoted: bool) -> String {
    let who = written_subject(
        &line.subject,
        line.id.as_ref(),
        &line.parents,
        Some(own),
        quoted,
    );
    let check = &line.check;
    let said = match (check == APPLIES, line.passes, &line.because) {
        (true, true, _) => "is in scope".to_string(),
        (true, false, Some(message)) => format!("is out of scope because {message}"),
        (true, false, None) => "is out of scope".to_string(),
        (false, true, _) => format!("passes {check}"),
        (false, false, Some(message)) => format!("fails {check} because {message}"),
        (false, false, None) => format!("fails {check}"),
    };
    if who.is_empty() {
        said
    } else {
        format!("{who} {said}")
    }
}

fn same_ids(a: Option<&Value>, b: Option<&Value>) -> bool {
    match (a, b) {
        (Some(a), Some(b)) => same_id(a, b),
        (None, None) => true,
        _ => false,
    }
}

/// Whether two check lines say the same, with ids compared as [same_id] does.
pub fn same_line(a: &CheckLine, b: &CheckLine) -> bool {
    a.subject == b.subject
        && same_ids(a.id.as_ref(), b.id.as_ref())
        && a.passes == b.passes
        && a.check == b.check
        && a.because == b.because
        && a.parents.len() == b.parents.len()
        && a.parents
            .iter()
            .zip(&b.parents)
            .all(|((x, i), (y, j))| x == y && same_id(i, j))
}

/// The line for a report row as it is, with the parents the `from` lines in `policy` give, `None` for a passed row of a check Ergo adds, a subject in scope included, or why the line can't be written yet.
pub fn row_line(row: &Value, policy: &Value) -> Result<Option<String>, String> {
    if left_out(row) {
        return Ok(None);
    }
    let own = own_subject(row, policy);
    Ok(Some(write(&row_parts(row, policy)?, own, false)))
}

/// The line for any report row, even one `--format outcome` leaves out, like a subject in scope: the one that reads back as the row, as [line_for] gives it, or else the row's line as it is, or why it can't be written yet.
pub fn said(row: &Value, policy: &Value) -> Result<String, String> {
    let line = row_parts(row, policy)?;
    Ok(read_back(row, policy, &line)
        .unwrap_or_else(|_| write(&line, own_subject(row, policy), false)))
}

fn own_subject<'a>(row: &Value, policy: &'a Value) -> &'a str {
    let requirement = row["requirement"].as_str().unwrap_or_default();
    policy["requirements"][requirement]["subject"]
        .as_str()
        .unwrap_or_default()
}

/// The line for a report row that reads back as that row against the subject and check names in `policy`: it quotes an id that would read as part of a longer subject name, and leaves out a `because` that would read as part of a longer check name. `None` for a passed row of a check Ergo adds, a subject in scope included, or why no such line can be written.
pub fn line_for(row: &Value, policy: &Value) -> Result<Option<String>, String> {
    if left_out(row) {
        return Ok(None);
    }
    read_back(row, policy, &row_parts(row, policy)?).map(Some)
}

fn read_back(row: &Value, policy: &Value, line: &CheckLine) -> Result<String, String> {
    let requirement = row["requirement"].as_str().unwrap_or_default();
    let own = own_subject(row, policy);
    let subjects = names(&policy["subjects"]);
    let checks = names(&policy["requirements"][requirement]["checks"]);
    let without_because = CheckLine {
        because: None,
        ..line.clone()
    };
    for (want, quoted) in [
        (line, false),
        (line, true),
        (&without_because, false),
        (&without_because, true),
    ] {
        let text = write(want, own, quoted);
        let read = read_check_line(&text, requirement, own, &subjects, &checks);
        if read.is_ok_and(|read| same_line(&read, want)) {
            return Ok(text);
        }
    }
    Err(format!(
        "no line for {} and {} in {requirement} reads back as its row, because a longer subject or check name starts the same way",
        subject_words(&line.subject, line.id.as_ref(), &line.parents),
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

/// The whole outcome of a report made from `policy`, as `ergo report --format outcome` prints it, or why a row can't be shown yet.
pub fn of(report: &Value, policy: &Value) -> Result<Vec<Item>, String> {
    let whole = Region {
        compliant: true,
        ..Region::default()
    };
    items(report, policy, &whole, true)
}

/// The items of a report made from `policy` inside `region`, leaving out the rows that can't be shown yet.
pub fn part(report: &Value, policy: &Value, region: &Region) -> Vec<Item> {
    items(report, policy, region, false).unwrap_or_default()
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

fn items(
    report: &Value,
    policy: &Value,
    region: &Region,
    strict: bool,
) -> Result<Vec<Item>, String> {
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
    let written_wrong = rows
        .iter()
        .find(|row| row["check"] == "$well_formed" && row["passed"] != true);
    if let (true, Some(row)) = (strict, written_wrong) {
        return Err(format!(
            "requirement {} is written wrong: {}",
            row["requirement"].as_str().unwrap_or_default(),
            row["message"].as_str().unwrap_or_default()
        ));
    }
    let requirements = report["requirements"].as_object().into_iter().flatten();
    for (name, entry) in requirements {
        let whole = region.compliant || region.requirements.contains(name);
        let covers =
            |check: &str| whole || region.checks.contains(&(name.clone(), check.to_string()));
        if !whole && !region.checks.iter().any(|(r, _)| r == name) {
            continue;
        }
        let mut lines = Vec::new();
        let mut said_before: Vec<(&Value, String)> = Vec::new();
        for row in rows {
            if row["requirement"] != name.as_str()
                || !covers(row["check"].as_str().unwrap_or_default())
            {
                continue;
            }
            if let (true, Ok(text)) = (strict, said(row, policy)) {
                let twin = said_before
                    .iter()
                    .find(|(other, said)| *said != text && same_row_of(other, row));
                if let Some((other, said)) = twin {
                    return Err(format!(
                        "the rows of {} in {name} for {} don't all say the same, so no line agrees with every one of them: {said}, and {text}",
                        row["check"].as_str().unwrap_or_default(),
                        row_parts(other, policy).map_or(String::new(), |line| subject_words(
                            &line.subject,
                            line.id.as_ref(),
                            &line.parents
                        ))
                    ));
                }
                said_before.push((row, text));
            }
            match line_for(row, policy) {
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
