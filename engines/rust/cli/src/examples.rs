//! Experimental: reads the examples of a policy and checks each one's outcome against its report.

use crate::outcome::{self, Item, Region, heading, requirement_line};
use crate::pretty::{Mark, Show, Style, escape};
use serde_json::{Value, json};
use std::collections::BTreeSet;

/// One example of a policy, with the params it runs with.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Example {
    /// The example's name, unique in the policy.
    pub name: String,
    /// The input to build the report from.
    pub input: Value,
    /// The example's own `params`, or else the policy's `tests.params`, or else `{}`.
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

/// Says which key is written twice inside `tests`, given the paths that [crate::yaml::repeated_keys] gives, like `the key outcome is written twice in tests.examples[1]`.
pub fn repeated(paths: &[Vec<String>]) -> Result<(), String> {
    let Some((key, outer)) = paths
        .iter()
        .find(|path| matches!(path.first().map(String::as_str), Some("tests")))
        .and_then(|path| path.split_last())
    else {
        return Ok(());
    };
    let mut place = String::new();
    for step in outer {
        if !place.is_empty() && !step.starts_with('[') {
            place.push('.');
        }
        place.push_str(step);
    }
    Err(if place.is_empty() {
        format!("the key {key} is written twice")
    } else {
        format!("the key {key} is written twice in {place}")
    })
}

/// Reads the examples of a policy, or says why they're written wrong.
pub fn read(policy: &Value) -> Result<Vec<Example>, String> {
    let mut moved = Vec::new();
    if policy.get("examples").is_some() {
        moved.push("examples moved under tests, write it as tests.examples");
    }
    if policy.get("example_params").is_some() {
        moved.push("example_params moved under tests, write it as tests.params");
    }
    if !moved.is_empty() {
        return Err(moved.join("; "));
    }
    let tests = match policy.get("tests") {
        None => &serde_json::Map::new(),
        Some(Value::Object(tests)) => tests,
        Some(_) => return Err("tests isn't an object".to_string()),
    };
    if let Some(key) = tests
        .keys()
        .find(|k| !["examples", "params"].contains(&k.as_str()))
    {
        return Err(if matches!(key.as_str(), "inputs" | "rules") {
            format!("tests.{key} isn't supported yet")
        } else {
            format!("tests has an unknown key {key}")
        });
    }
    let list = match tests.get("examples") {
        None | Some(Value::Null) => &Vec::new(),
        Some(Value::Array(list)) => list,
        _ => return Err("tests.examples isn't a list".to_string()),
    };
    if list.is_empty() {
        return Err("the policy has no examples".to_string());
    }
    let shared = tests.get("params").cloned().unwrap_or(json!({}));
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
        written(outcome, &policy["requirements"])
            .map_err(|problem| format!("example {name}: {problem}"))?;
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
    id: Option<Value>,
    passes: bool,
    check: String,
    because: Option<String>,
    parents: Vec<(String, Value)>,
}

fn read_line(text: &str, requirement: &str, policy: &Value) -> Result<Line, String> {
    let line = outcome::read_check_line(
        text,
        requirement,
        policy["requirements"][requirement]["subject"]
            .as_str()
            .unwrap_or_default(),
        &outcome::names(&policy["subjects"]),
        &outcome::names(&policy["requirements"][requirement]["checks"]),
    )?;
    let ancestors = ergo_policy_engine::ancestors(policy, &line.subject);
    let named: Vec<&String> = line.parents.iter().map(|(name, _)| name).collect();
    let no_parent_at_all = line.id.is_none() && named.is_empty();
    if named != ancestors.iter().collect::<Vec<_>>() && !no_parent_at_all {
        let what = if line.id.is_some() { "its id" } else { "it" };
        return Err(if ancestors.is_empty() {
            format!(
                "{} isn't read inside another subject, so nothing follows {what} but passes or fails",
                line.subject
            )
        } else {
            let needed: String = ancestors
                .iter()
                .map(|name| format!(" in {name} <id>"))
                .collect();
            format!(
                "{} is read inside {}, so {what} is followed by{needed}",
                line.subject,
                ancestors.join(" inside ")
            )
        });
    }
    Ok(Line {
        requirement: requirement.to_string(),
        subject: line.subject,
        id: line.id,
        passes: line.passes,
        check: line.check,
        because: line.because,
        parents: line.parents,
    })
}

fn written(outcome: &Value, requirements: &Value) -> Result<(), String> {
    for item in shape(outcome)? {
        if let Item::Group(text, lines) = item
            && !matches!(heading(&text, requirements)?, Some((_, Some(_))))
            && lines.is_empty()
        {
            return Err(format!("the heading {text} lists no lines"));
        }
    }
    Ok(())
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
        && match &line.id {
            Some(id) => outcome::same_id(&row["subject"]["id"], id),
            None => row["subject"]["id"].is_null(),
        }
        && same_parents(&row["subject"], &line.parents)
}

fn same_parents(subject: &Value, parents: &[(String, Value)]) -> bool {
    match subject.get("in") {
        None => parents.is_empty(),
        Some(Value::Object(given)) => {
            given.len() == parents.len()
                && parents.iter().all(|(name, id)| {
                    given
                        .get(name)
                        .is_some_and(|given| outcome::same_id(given, id))
                })
        }
        Some(_) => false,
    }
}

fn agrees(row: &Value, line: &Line) -> bool {
    let out_of_scope = line.check == "$applies" && !line.passes;
    (row["passed"] == true) == line.passes
        && (!out_of_scope || row["cause"] == "value")
        && line
            .because
            .as_ref()
            .is_none_or(|because| row["message"] == because.as_str())
}

fn disagreement(row: &Value, policy: &Value) -> String {
    match outcome::said(row, policy) {
        Ok(line) => format!("the report says {line}"),
        Err(reason) => format!("can't check this yet: {reason}"),
    }
}

/// Checks an outcome against a report made from `policy`, by the matching and coverage rules of the spec, reading its lines with the subject and check names of `policy`.
pub fn check(outcome: &Value, report: &Value, policy: &Value) -> Checked {
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
            problems.push(match actual {
                Some(actual) => format!("the report says {name} {actual}"),
                None => format!(
                    "the report says {}",
                    outcome::status_problem(name, &report["requirements"][name]["status"])
                ),
            });
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
            Item::Line(text) => match requirement_line(text, &report["requirements"]) {
                Some((name, words)) => status(name, words, &mut problems),
                None => problems.push(format!(
                    "can't read the line '{text}': it isn't compliant, not compliant or a requirement of the policy followed by is met, is not met or is not applicable"
                )),
            },
            Item::Group(text, group) => {
                let name = match heading(text, &report["requirements"]) {
                    Err(problem) => {
                        problems.push(problem);
                        continue;
                    }
                    Ok(Some((name, Some(words)))) => {
                        status(name, words, &mut problems);
                        name
                    }
                    Ok(None) => {
                        problems.push(format!("no requirement is called {text}"));
                        continue;
                    }
                    Ok(Some(_)) if group.is_empty() => {
                        problems.push(format!("the heading {text} lists no lines"));
                        continue;
                    }
                    Ok(Some((name, None))) => name,
                };
                for text in group {
                    match read_line(text, name, policy) {
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
        let matching: Vec<&Value> = rows.iter().filter(|row| same_row(row, line)).collect();
        if matching.is_empty() {
            problems.push(format!(
                "the report has no row for {} and {} in {}",
                outcome::subject_words(&line.subject, line.id.as_ref(), &line.parents),
                line.check,
                line.requirement
            ));
        }
        let mut agreed = !matching.is_empty();
        for row in matching {
            if !agrees(row, line) {
                agreed = false;
                problems.push(disagreement(row, policy));
            }
        }
        if agreed {
            checked
                .shown
                .insert((line.requirement.clone(), line.check.clone(), line.passes));
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
        match outcome::line_for(row, policy) {
            Err(reason) => problems.push(format!("can't check this yet: {reason}")),
            Ok(Some(line)) if !lines.iter().any(|l| !l.passes && same_row(row, l)) => {
                problems.push(format!("no line says {line}"))
            }
            Ok(_) => {}
        }
    }
    checked.actual = outcome::part(report, policy, &region);
    let mut seen = BTreeSet::new();
    problems.retain(|problem| seen.insert(problem.clone()));
    checked.problems = problems;
    checked
}

fn shown_block(items: &[Item], style: Option<&Style>) -> String {
    let block = indented(items);
    match style {
        None => block,
        Some(_) => block
            .lines()
            .map(|line| format!("{}\n", escape(line)))
            .collect(),
    }
}

fn indented(items: &[Item]) -> String {
    outcome::yaml(items)
        .lines()
        .map(|line| format!("    {line}\n"))
        .collect()
}

/// Runs every example of a policy with the Rust engine and gives what [results] gives. Gives why the examples are written wrong when they are.
pub fn run(policy: &Value, strict: bool) -> Result<(String, u8), String> {
    let examples = read(policy)?;
    let reports: Vec<Value> = examples
        .iter()
        .map(|e| ergo_policy_engine::report(&e.input, policy, &e.params))
        .collect();
    Ok(results(policy, &examples, &reports, strict))
}

/// Checks each example of a policy against its report, the one at the same place in `reports`, and gives the text to print with the exit code: 1 when an example failed, or when `strict` is set and there is a warning, and 0 otherwise.
pub fn results(
    policy: &Value,
    examples: &[Example],
    reports: &[Value],
    strict: bool,
) -> (String, u8) {
    results_styled(policy, examples, reports, strict, None)
}

/// Does what [results] does, and when `style` is given writes the lines for a terminal: a mark in place of `passed:`, `failed:` and `warning:`, only the failed examples unless `style.show` is all, and a summary line that starts with the therefore sign, after an empty line.
pub fn results_styled(
    policy: &Value,
    examples: &[Example],
    reports: &[Value],
    strict: bool,
    style: Option<&Style>,
) -> (String, u8) {
    let mut text = String::new();
    let mut failed = 0;
    let mut shown = BTreeSet::new();
    for (example, report) in examples.iter().zip(reports) {
        let checked = check(&example.outcome, report, policy);
        if checked.problems.is_empty() {
            shown.extend(checked.shown);
            match style {
                None => text.push_str(&format!("passed: {}\n", example.name)),
                Some(style) if style.show == Show::All => {
                    text.push_str(&format!("{}\n", style.line(Mark::Pass, &example.name)));
                }
                Some(_) => {}
            }
            continue;
        }
        failed += 1;
        match style {
            None => text.push_str(&format!("failed: {}\n", example.name)),
            Some(style) => text.push_str(&format!("{}\n", style.line(Mark::Fail, &example.name))),
        }
        for problem in &checked.problems {
            match style {
                None => text.push_str(&format!("  {problem}\n")),
                Some(_) => text.push_str(&format!("  {}\n", escape(problem))),
            }
        }
        if !checked.expected.is_empty() {
            text.push_str("  expected:\n");
            text.push_str(&shown_block(&checked.expected, style));
            text.push_str("  actual:\n");
            text.push_str(&shown_block(&checked.actual, style));
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
                    let warning = format!("no example shows {check} of {requirement} {words}");
                    match style {
                        None => text.push_str(&format!("warning: {warning}\n")),
                        Some(style) => {
                            text.push_str(&format!("{}\n", style.line(Mark::Warn, &warning)));
                        }
                    }
                }
            }
        }
    }
    let summary = format!(
        "{} example{}: {} passed, {failed} failed",
        examples.len(),
        if examples.len() == 1 { "" } else { "s" },
        examples.len() - failed
    );
    match style {
        None => text.push_str(&format!("{summary}\n")),
        Some(style) => {
            if !text.is_empty() {
                text.push('\n');
            }
            text.push_str(&format!("{}\n", style.line(Mark::Therefore, &summary)));
        }
    }
    let code = if failed > 0 || (strict && warnings > 0) {
        1
    } else {
        0
    };
    (text, code)
}
