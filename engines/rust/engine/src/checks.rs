use crate::lower::{self, Scope};
use crate::name;
use crate::ops::Check;
use crate::ops::any_of::AnyOf;
use crate::path::{self, Ctx, Located, Location, Path};
use crate::policy::{Form, OptionLines, Requirement, SubjectName};
use crate::reading::Reading;
use crate::report::written_expression;
use ergo_policy_sentences as s;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone)]
pub struct Item {
    pub text: String,
    pub check: Check,
}

#[derive(Debug, Clone)]
pub struct Plan {
    pub items: Vec<Item>,
    pub all_of: bool,
}

#[derive(Debug, Clone)]
pub struct CheckRead {
    pub expression: String,
    pub problems: BTreeSet<String>,
    pub plan: Option<Plan>,
}

fn messages(errors: Vec<s::SyntaxError>) -> Vec<String> {
    errors.into_iter().map(|e| e.message).collect()
}

struct Lines {
    trees: Vec<s::Check>,
    places: Vec<String>,
    ok: bool,
}

fn read_lines(
    lines: &[&str],
    prefix: &str,
    aliases: &[&str],
    problems: &mut BTreeSet<String>,
) -> Lines {
    let mut trees = Vec::new();
    let mut places = Vec::new();
    let mut ok = true;
    for (at, line) in lines.iter().enumerate() {
        let place = if lines.len() >= 2 {
            format!("{prefix}line {}: ", at + 1)
        } else {
            prefix.to_string()
        };
        match s::parse_check(line) {
            Ok(tree) => {
                let found = s::check_problems(&tree, aliases);
                let only_self = found == s::check_self_problems(&tree, aliases);
                if !found.is_empty() {
                    ok = false;
                }
                for problem in found {
                    problems.insert(format!("{place}{problem}"));
                }
                if only_self {
                    trees.push(tree);
                    places.push(place);
                }
            }
            Err(errors) => {
                ok = false;
                for message in messages(errors) {
                    problems.insert(format!("{place}{message}"));
                }
            }
        }
    }
    Lines { trees, places, ok }
}

fn printed(trees: &[s::Check], aliases: &[&str]) -> String {
    trees
        .iter()
        .map(|tree| s::print_check(tree, aliases))
        .collect::<Vec<_>>()
        .join(" and ")
}

fn lowered_plan(
    trees: &[s::Check],
    places: &[String],
    scope: &Scope,
    aliases: &[&str],
    problems: &mut BTreeSet<String>,
) -> Option<Plan> {
    let mut items = Vec::new();
    for (tree, place) in trees.iter().zip(places) {
        for assertion in &tree.assertions {
            match lower::lower_assertion(assertion, scope) {
                Ok(check) => items.push(Item {
                    text: s::print_assertion(assertion, aliases),
                    check,
                }),
                Err(found) => {
                    problems.extend(found.into_iter().map(|p| lower::in_place(place, &p)))
                }
            }
        }
    }
    let all_of = items.len() > 1;
    Some(Plan { items, all_of })
}

fn read_one(
    check: &crate::policy::Check,
    scope: &Scope,
    reading: &Reading,
    subject: Option<&str>,
) -> CheckRead {
    let read = read_form(check, scope, reading, subject);
    if check
        .problems
        .iter()
        .any(|problem| problem.starts_with("unknown field"))
    {
        return CheckRead {
            expression: written_expression(check),
            problems: read.problems,
            plan: None,
        };
    }
    read
}

fn read_form(
    check: &crate::policy::Check,
    scope: &Scope,
    reading: &Reading,
    subject: Option<&str>,
) -> CheckRead {
    let written = written_expression(check);
    if check.problems.contains("invalid for") {
        return CheckRead {
            expression: written,
            problems: BTreeSet::new(),
            plan: None,
        };
    }
    let named_scope = match subject {
        Some(name) => scope.clone().with_subject(name),
        None => scope.clone(),
    };
    let scope = &named_scope;
    let mut aliases_owned = scope.aliases();
    let mut print_owned = reading.printed_aliases(subject, scope);
    if let Some(name) = subject {
        aliases_owned.push(name.to_string());
        print_owned.push(name.to_string());
    }
    let aliases: Vec<&str> = aliases_owned.iter().map(String::as_str).collect();
    let print_aliases: Vec<&str> = print_owned.iter().map(String::as_str).collect();
    let mut problems = BTreeSet::new();
    let wrong = |problems: BTreeSet<String>| CheckRead {
        expression: written.clone(),
        problems,
        plan: None,
    };
    match &check.form {
        Form::Line(text) => {
            let lines = read_lines(&[text.as_str()], "", &aliases, &mut problems);
            let plan = lowered_plan(&lines.trees, &lines.places, scope, &aliases, &mut problems);
            if !lines.ok || !problems.is_empty() {
                return wrong(problems);
            }
            CheckRead {
                expression: printed(&lines.trees, &print_aliases),
                plan,
                problems,
            }
        }
        Form::Assert { lines, for_line } => {
            let texts: Vec<&str> = lines.iter().flatten().map(String::as_str).collect();
            if texts.len() != lines.len() || texts.is_empty() {
                return wrong(problems);
            }
            let mut names: Vec<String> = aliases_owned.clone();
            let mut for_tree = None;
            let mut for_ok = true;
            if let Some(text) = for_line {
                match s::parse_for(text) {
                    Ok(tree) => {
                        for problem in s::for_problems(&tree, &aliases) {
                            problems.insert(format!("for: {problem}"));
                            for_ok = false;
                        }
                        for item in &tree.items {
                            let alias = match item {
                                s::ForItem::Walk { alias, .. } | s::ForItem::Pick { alias, .. } => {
                                    alias
                                }
                            };
                            names.push(alias.clone());
                            for problem in reading.alias_clashes(subject, alias) {
                                problems.insert(problem);
                                for_ok = false;
                            }
                        }
                        for_tree = Some(tree);
                    }
                    Err(errors) => {
                        for_ok = false;
                        for message in messages(errors) {
                            problems.insert(format!("for: {message}"));
                        }
                    }
                }
            }
            let name_refs: Vec<&str> = names.iter().map(String::as_str).collect();
            let parsed = read_lines(&texts, "", &name_refs, &mut problems);
            match for_tree {
                None => {
                    let plan = lowered_plan(
                        &parsed.trees,
                        &parsed.places,
                        scope,
                        &aliases,
                        &mut problems,
                    );
                    if !parsed.ok || !for_ok || !problems.is_empty() {
                        return wrong(problems);
                    }
                    CheckRead {
                        expression: printed(&parsed.trees, &print_aliases),
                        plan,
                        problems,
                    }
                }
                Some(tree) => {
                    let expression = format!(
                        "for {}: {}",
                        s::print_for(&tree, &print_aliases),
                        printed(&parsed.trees, &name_refs)
                    );
                    let mut assertions: Vec<s::Assertion> = Vec::new();
                    let mut places: Vec<String> = Vec::new();
                    for (tree, place) in parsed.trees.iter().zip(&parsed.places) {
                        for assertion in &tree.assertions {
                            assertions.push(assertion.clone());
                            places.push(place.clone());
                        }
                    }
                    let plan = match lower::lower_for(&tree, &assertions, &places, scope) {
                        Ok(check) => Some(Plan {
                            items: vec![Item {
                                text: expression.clone(),
                                check,
                            }],
                            all_of: false,
                        }),
                        Err(found) => {
                            problems.extend(
                                found
                                    .into_iter()
                                    .filter(|p| !p.starts_with(lower::UNKNOWN_NAME)),
                            );
                            None
                        }
                    };
                    if !parsed.ok || !for_ok || !problems.is_empty() {
                        return wrong(problems);
                    }
                    CheckRead {
                        plan,
                        expression,
                        problems,
                    }
                }
            }
        }
        Form::AnyOf(Some(options)) => {
            let mut parts = Vec::new();
            let mut lowered_options = Vec::new();
            let mut lowered_names: Vec<String> = Vec::new();
            let mut ok = !options.is_empty();
            for (option, read) in options {
                match read {
                    OptionLines::Lines(lines) if !lines.is_empty() => {
                        let texts: Vec<&str> = lines.iter().flatten().map(String::as_str).collect();
                        if texts.len() != lines.len() {
                            ok = false;
                            continue;
                        }
                        let found = read_lines(
                            &texts,
                            &format!("option {option}: "),
                            &aliases,
                            &mut problems,
                        );
                        ok &= found.ok;
                        if let Some(plan) = lowered_plan(
                            &found.trees,
                            &found.places,
                            scope,
                            &aliases,
                            &mut problems,
                        ) {
                            lowered_names.push(option.to_string());
                            lowered_options.push(plan.items.into_iter().map(|i| i.check).collect());
                        }
                        parts.push(format!(
                            "{option}({})",
                            printed(&found.trees, &print_aliases)
                        ));
                    }
                    _ => ok = false,
                }
            }
            if !ok || !problems.is_empty() {
                return wrong(problems);
            }
            let expression = format!("one of: {}", parts.join(" | "));
            let plan = Plan {
                items: vec![Item {
                    text: expression.clone(),
                    check: Check::AnyOf(AnyOf {
                        names: lowered_names,
                        options: lowered_options,
                    }),
                }],
                all_of: false,
            };
            CheckRead {
                plan: Some(plan),
                expression,
                problems,
            }
        }
        _ => wrong(problems),
    }
}

const SUBJECT_ADVICE: &str = ": to read the subject's ";

fn with_subject(problem: String, written: Option<&str>) -> String {
    if !problem.contains(s::SUBJECT_MARK) {
        return problem;
    }
    match written {
        Some(name) => problem.replace(s::SUBJECT_MARK, name),
        None => match problem.find(SUBJECT_ADVICE) {
            Some(at) => problem[..at].to_string(),
            None => problem.replace(s::SUBJECT_MARK, ""),
        },
    }
}

pub fn read_checks(reading: &Reading, requirement: &Requirement) -> BTreeMap<String, CheckRead> {
    let subject = match &requirement.subject {
        SubjectName::Named(name) => Some(name.as_str()),
        _ => None,
    };
    let scope = subject
        .and_then(|name| reading.infos.get(name))
        .map(|info| info.scope.clone())
        .unwrap_or_default();
    let written = subject
        .map(crate::name::parent_key_text)
        .filter(|text| !text.starts_with('"'));
    requirement
        .checks
        .iter()
        .map(|(check_name, check)| {
            let mut read = read_one(check, &scope, reading, subject);
            read.problems = read
                .problems
                .into_iter()
                .map(|problem| with_subject(problem, written.as_deref()))
                .collect();
            (check_name.clone(), read)
        })
        .collect()
}

pub fn refs_of(plan: &Plan, input: &Value, params: Option<&Value>) -> Vec<Value> {
    let checks: Vec<&Check> = plan.items.iter().map(|item| &item.check).collect();
    refs_of_checks(&checks, input, params)
}

pub fn refs_of_checks(checks: &[&Check], input: &Value, params: Option<&Value>) -> Vec<Value> {
    let paths: Vec<(Path, bool)> = checks
        .iter()
        .flat_map(|check| {
            let walking = check.walking_refs();
            check
                .refs()
                .into_iter()
                .map(|reference| {
                    let walks = walking.contains(&reference);
                    (reference, walks)
                })
                .collect::<Vec<_>>()
        })
        .collect();
    refs_walked(&paths, input, params)
}

pub fn refs_read(paths: &[Path], input: &Value, params: Option<&Value>) -> Vec<Value> {
    let paths: Vec<(Path, bool)> = paths.iter().map(|p| (p.clone(), false)).collect();
    refs_walked(&paths, input, params)
}

fn refs_walked(paths: &[(Path, bool)], input: &Value, params: Option<&Value>) -> Vec<Value> {
    let ctx = Ctx {
        label: None,
        item_by_item: true,
        in_option: false,
        subject: Located {
            value: input,
            location: Location::input_root(),
        },
        input,
        params,
        aliases: BTreeMap::new(),
    };
    let mut entries: Vec<Value> = Vec::new();
    for (reference, walks) in paths {
        if let Some(walk) = crate::ops::lists::walked(reference, &ctx).filter(|_| *walks) {
            entries.push(serde_json::json!({
                "name": walk.name,
                "value": walk.value,
                "locations": walk.locations,
            }));
            continue;
        }
        let read = path::read(reference, &ctx);
        let locations: Vec<String> = read.location.iter().map(Location::render).collect();
        entries.push(serde_json::json!({
            "name": name::name(reference),
            "value": read.value.cloned().unwrap_or(Value::Null),
            "locations": locations,
        }));
    }
    entries.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    entries.dedup();
    entries
}

#[cfg(test)]
mod tests;
