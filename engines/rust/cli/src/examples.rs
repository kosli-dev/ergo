//! Experimental: reads the examples of a policy and checks each one's outcome against its report.

use crate::outcome::{self, Item, Region};
use serde_json::{Value, json};
use std::collections::BTreeSet;

/// One example of a policy, with the params it runs with.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Example {
    /// The example's name, unique in the policy.
    pub name: String,
    /// The input to build the report from.
    pub input: Value,
    /// The example's own `params`, or else the policy's `example_params`, or else `{}`.
    pub params: Value,
    /// The outcome as written, a list of lines and headings.
    pub outcome: Value,
}

/// What checking an outcome against a report found.
#[derive(Debug, Default, PartialEq, Eq, Clone)]
pub struct Checked {
    /// Each way the report differs from the outcome, empty when the example passes.
    pub problems: Vec<String>,
    /// The outcome as written.
    pub expected: Vec<Item>,
    /// The report's lines for the part the outcome covers.
    pub actual: Vec<Item>,
    /// Each check a check line shows, as requirement, check and whether the line says it passes.
    pub shown: BTreeSet<(String, String, bool)>,
}

/// Reads the examples of a policy, or says why they're written wrong.
pub fn read(policy: &Value) -> Result<Vec<Example>, String> {
    let list = match &policy["examples"] {
        Value::Null => &Vec::new(),
        Value::Array(list) => list,
        _ => return Err("examples isn't a list".to_string()),
    };
    if list.is_empty() {
        return Err("the policy has no examples".to_string());
    }
    let shared = policy.get("example_params").cloned().unwrap_or(json!({}));
    let mut names = BTreeSet::new();
    let mut examples = Vec::new();
    for (n, example) in list.iter().enumerate() {
        let Some(map) = example.as_object() else {
            return Err(format!("example {} isn't an object", n + 1));
        };
        let name = match map.get("name") {
            Some(Value::String(name)) if !name.is_empty() => name.clone(),
            _ => return Err(format!("example {} has no name", n + 1)),
        };
        let fields = ["name", "description", "input", "params", "outcome"];
        if let Some(field) = map.keys().find(|k| !fields.contains(&k.as_str())) {
            return Err(format!("example {name} has an unknown field {field}"));
        }
        if !matches!(map.get("description"), None | Some(Value::String(_))) {
            return Err(format!("example {name} has a description that isn't text"));
        }
        let (Some(input), Some(outcome)) = (map.get("input"), map.get("outcome")) else {
            let missing = if map.contains_key("input") {
                "outcome"
            } else {
                "input"
            };
            return Err(format!("example {name} has no {missing}"));
        };
        if !names.insert(name.clone()) {
            return Err(format!("two examples are called {name}"));
        }
        examples.push(Example {
            name,
            input: input.clone(),
            params: map.get("params").unwrap_or(&shared).clone(),
            outcome: outcome.clone(),
        });
    }
    Ok(examples)
}

struct Line {
    requirement: String,
    subject: String,
    id: Value,
    passes: bool,
    check: String,
    because: Option<String>,
}

fn read_line(text: &str, requirement: &str, report: &Value) -> Result<Line, String> {
    let line = outcome::read_check_line(
        text,
        requirement,
        &outcome::names(&report["subjects"]),
        &outcome::names(&report["requirements"][requirement]["checks"]),
    )?;
    Ok(Line {
        requirement: requirement.to_string(),
        subject: line.subject,
        id: line.id,
        passes: line.passes,
        check: line.check,
        because: line.because,
    })
}

fn requirement_line<'a>(text: &'a str, report: &Value) -> Option<(&'a str, &'static str)> {
    ["is met", "is not met", "is not applicable"]
        .into_iter()
        .find_map(|words| {
            let name = text.strip_suffix(words)?.strip_suffix(' ')?;
            report["requirements"].get(name).map(|_| (name, words))
        })
}

fn shape(outcome: &Value) -> Result<Vec<Item>, String> {
    let Some(list) = outcome.as_array() else {
        return Err("the outcome isn't a list".to_string());
    };
    if list.is_empty() {
        return Err("the outcome is empty".to_string());
    }
    let wrong = |n: usize| format!("outcome item {n} isn't a line or a heading with its lines");
    let mut items = Vec::new();
    for (n, item) in list.iter().enumerate() {
        items.push(match item {
            Value::String(line) => Item::Line(line.clone()),
            Value::Object(map) if map.len() == 1 => {
                let (heading, lines) = map.iter().next().ok_or_else(|| wrong(n + 1))?;
                let lines = match lines {
                    Value::Null => Vec::new(),
                    Value::Array(lines) => lines
                        .iter()
                        .map(|line| {
                            line.as_str()
                                .map(str::to_string)
                                .ok_or_else(|| wrong(n + 1))
                        })
                        .collect::<Result<_, _>>()?,
                    _ => return Err(wrong(n + 1)),
                };
                Item::Group(heading.clone(), lines)
            }
            _ => return Err(wrong(n + 1)),
        });
    }
    Ok(items)
}

fn same_row(row: &Value, line: &Line) -> bool {
    row["requirement"] == line.requirement.as_str()
        && row["check"] == line.check.as_str()
        && row["subject"]["type"] == line.subject.as_str()
        && outcome::same_id(&row["subject"]["id"], &line.id)
        && row["subject"].get("in").is_none()
}

/// Checks an outcome against a report, by the matching and coverage rules of the spec.
pub fn check(outcome: &Value, report: &Value) -> Checked {
    let mut checked = Checked::default();
    let rows = report["results"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or_default();
    for row in rows {
        if row["check"] == "$well_formed" && row["passed"] != true {
            checked.problems.push(format!(
                "the policy is written wrong: {}: {}",
                row["requirement"].as_str().unwrap_or_default(),
                row["message"].as_str().unwrap_or_default()
            ));
        }
    }
    if !checked.problems.is_empty() {
        return checked;
    }
    checked.expected = match shape(outcome) {
        Ok(items) => items,
        Err(problem) => {
            checked.problems.push(problem);
            return checked;
        }
    };
    let mut region = Region::default();
    let mut lines = Vec::new();
    let mut problems = Vec::new();
    let mut status = |name: &str, words: &str, problems: &mut Vec<String>| {
        region.requirements.insert(name.to_string());
        let actual = outcome::status_words(&report["requirements"][name]["status"]);
        if actual != Some(words) {
            problems.push(format!(
                "the report says {name} {}",
                actual.unwrap_or("has no status")
            ));
        }
    };
    for item in &checked.expected {
        match item {
            Item::Line(text) if text == "compliant" || text == "not compliant" => {
                region.compliant = true;
                let actual = if report["compliant"] == true { "compliant" } else { "not compliant" };
                if text != actual {
                    problems.push(format!("the report says {actual}"));
                }
            }
            Item::Line(text) => match requirement_line(text, report) {
                Some((name, words)) => status(name, words, &mut problems),
                None => problems.push(format!(
                    "can't read the line '{text}': it isn't compliant, not compliant or a requirement of the policy followed by is met, is not met or is not applicable"
                )),
            },
            Item::Group(heading, group) => {
                let name = match requirement_line(heading, report) {
                    Some((name, words)) => {
                        status(name, words, &mut problems);
                        name
                    }
                    None if report["requirements"].get(heading.as_str()).is_none() => {
                        problems.push(format!("no requirement is called {heading}"));
                        continue;
                    }
                    None if group.is_empty() => {
                        problems.push(format!("the heading {heading} lists no lines"));
                        continue;
                    }
                    None => heading.as_str(),
                };
                for text in group {
                    match read_line(text, name, report) {
                        Ok(line) => lines.push(line),
                        Err(reason) => problems.push(format!("can't read the line '{text}': {reason}")),
                    }
                }
            }
        }
    }
    for line in &lines {
        region
            .checks
            .insert((line.requirement.clone(), line.check.clone()));
        checked
            .shown
            .insert((line.requirement.clone(), line.check.clone(), line.passes));
        let matching: Vec<&Value> = rows.iter().filter(|row| same_row(row, line)).collect();
        if matching.is_empty() {
            problems.push(format!(
                "the report has no row for {} {} and {} in {}",
                line.subject,
                outcome::id_text(&line.id).unwrap_or_default(),
                line.check,
                line.requirement
            ));
        }
        for row in matching {
            let agrees = (row["passed"] == true) == line.passes
                && line
                    .because
                    .as_ref()
                    .is_none_or(|because| row["message"] == because.as_str());
            if !agrees && let Ok(Some(actual)) = outcome::line_for(row, report) {
                problems.push(format!("the report says {actual}"));
            }
        }
    }
    for row in rows {
        let requirement = row["requirement"].as_str().unwrap_or_default();
        let check = row["check"].as_str().unwrap_or_default();
        let out_of_scope = check == "$applies" && row["cause"] == "value";
        let covered = region.compliant
            || region.requirements.contains(requirement)
            || region
                .checks
                .contains(&(requirement.to_string(), check.to_string()));
        if row["passed"] == true || out_of_scope || !covered {
            continue;
        }
        match outcome::line_for(row, report) {
            Err(reason) => problems.push(format!("can't check this yet: {reason}")),
            Ok(Some(line)) if !lines.iter().any(|l| !l.passes && same_row(row, l)) => {
                problems.push(format!("no line says {line}"))
            }
            Ok(_) => {}
        }
    }
    checked.actual = outcome::part(report, &region);
    checked.problems = problems;
    checked
}

fn indented(items: &[Item]) -> String {
    outcome::yaml(items)
        .lines()
        .map(|line| format!("    {line}\n"))
        .collect()
}

/// Runs every example of a policy and gives the text to print with the exit code: 1 when an example failed, or when `strict` is set and there is a warning, and 0 otherwise. Gives why the examples are written wrong when they are.
pub fn run(policy: &Value, strict: bool) -> Result<(String, u8), String> {
    let examples = read(policy)?;
    let mut text = String::new();
    let mut failed = 0;
    let mut shown = BTreeSet::new();
    for example in &examples {
        let report = ergo_policy_engine::report(&example.input, policy, &example.params);
        let checked = check(&example.outcome, &report);
        shown.extend(checked.shown);
        if checked.problems.is_empty() {
            text.push_str(&format!("passed: {}\n", example.name));
            continue;
        }
        failed += 1;
        text.push_str(&format!("failed: {}\n", example.name));
        for problem in &checked.problems {
            text.push_str(&format!("  {problem}\n"));
        }
        if !checked.expected.is_empty() {
            text.push_str("  expected:\n");
            text.push_str(&indented(&checked.expected));
            text.push_str("  actual:\n");
            text.push_str(&indented(&checked.actual));
        }
    }
    let mut warnings = 0;
    let requirements = policy["requirements"].as_object().into_iter().flatten();
    for (requirement, entry) in requirements.filter(|(name, _)| !name.starts_with('$')) {
        let checks = entry["checks"].as_object().into_iter().flatten();
        for (check, _) in checks.filter(|(name, _)| !name.starts_with('$')) {
            for (passes, words) in [(false, "failing"), (true, "passing")] {
                if !shown.contains(&(requirement.clone(), check.clone(), passes)) {
                    warnings += 1;
                    text.push_str(&format!(
                        "warning: no example shows {check} of {requirement} {words}\n"
                    ));
                }
            }
        }
    }
    text.push_str(&format!(
        "{} example{}: {} passed, {failed} failed\n",
        examples.len(),
        if examples.len() == 1 { "" } else { "s" },
        examples.len() - failed
    ));
    let code = if failed > 0 || (strict && warnings > 0) {
        1
    } else {
        0
    };
    Ok((text, code))
}
