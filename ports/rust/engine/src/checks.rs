use crate::lower::{self, Scope};
use crate::name;
use crate::ops::Check;
use crate::path::{self, Ctx, Located, Location};
use crate::policy::{Form, OptionLines, Requirement, SubjectName};
use crate::reading::Reading;
use crate::report::written_expression;
use ergo_sentences as s;
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
    ok: bool,
}

fn read_lines(
    lines: &[&str],
    prefix: &str,
    aliases: &[&str],
    problems: &mut BTreeSet<String>,
) -> Lines {
    let mut trees = Vec::new();
    let mut ok = true;
    for (at, line) in lines.iter().enumerate() {
        let place = if lines.len() >= 2 {
            format!("{prefix}line {}: ", at + 1)
        } else {
            prefix.to_string()
        };
        match s::parse_check(line) {
            Ok(tree) => {
                for problem in s::check_problems(&tree, aliases) {
                    problems.insert(format!("{place}{problem}"));
                    ok = false;
                }
                trees.push(tree);
            }
            Err(errors) => {
                ok = false;
                for message in messages(errors) {
                    problems.insert(format!("{place}{message}"));
                }
            }
        }
    }
    Lines { trees, ok }
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
    scope: &Scope,
    aliases: &[&str],
    problems: &mut BTreeSet<String>,
) -> Option<Plan> {
    let mut items = Vec::new();
    for assertion in trees.iter().flat_map(|tree| &tree.assertions) {
        match lower::lower_assertion(assertion, scope) {
            Ok(check) => items.push(Item {
                text: s::print_assertion(assertion, aliases),
                check,
            }),
            Err(found) => problems.extend(found),
        }
    }
    let all_of = items.len() > 1;
    Some(Plan { items, all_of })
}

fn not_yet(expression: &str) -> Plan {
    Plan {
        items: vec![Item {
            text: expression.to_string(),
            check: Check::NotYet,
        }],
        all_of: false,
    }
}

fn read_one(
    check: &crate::policy::Check,
    scope: &Scope,
    reading: &Reading,
    subject: Option<&str>,
) -> CheckRead {
    let aliases_owned = scope.aliases();
    let aliases: Vec<&str> = aliases_owned.iter().map(String::as_str).collect();
    let mut problems = BTreeSet::new();
    let written = written_expression(check);
    let wrong = |problems: BTreeSet<String>| CheckRead {
        expression: written.clone(),
        problems,
        plan: None,
    };
    match &check.form {
        Form::Line(text) => {
            let lines = read_lines(&[text.as_str()], "", &aliases, &mut problems);
            if !lines.ok {
                return wrong(problems);
            }
            let plan = lowered_plan(&lines.trees, scope, &aliases, &mut problems);
            CheckRead {
                expression: printed(&lines.trees, &aliases),
                plan: if problems.is_empty() { plan } else { None },
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
            if !parsed.ok || !for_ok {
                return wrong(problems);
            }
            match for_tree {
                None => {
                    let plan = lowered_plan(&parsed.trees, scope, &aliases, &mut problems);
                    CheckRead {
                        expression: printed(&parsed.trees, &aliases),
                        plan: if problems.is_empty() { plan } else { None },
                        problems,
                    }
                }
                Some(tree) => {
                    let expression = format!(
                        "for {}: {}",
                        s::print_for(&tree, &aliases),
                        printed(&parsed.trees, &name_refs)
                    );
                    CheckRead {
                        plan: Some(not_yet(&expression)),
                        expression,
                        problems,
                    }
                }
            }
        }
        Form::AnyOf(Some(options)) => {
            let mut parts = Vec::new();
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
                        parts.push(format!("{option}({})", printed(&found.trees, &aliases)));
                    }
                    _ => ok = false,
                }
            }
            if !ok {
                return wrong(problems);
            }
            let expression = format!("one of: {}", parts.join(" | "));
            CheckRead {
                plan: Some(not_yet(&expression)),
                expression,
                problems,
            }
        }
        _ => wrong(problems),
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
    requirement
        .checks
        .iter()
        .map(|(check_name, check)| {
            (
                check_name.clone(),
                read_one(check, &scope, reading, subject),
            )
        })
        .collect()
}

pub fn refs_of(plan: &Plan, input: &Value, params: Option<&Value>) -> Vec<Value> {
    let ctx = Ctx {
        subject: Located {
            value: input,
            location: Location::input_root(),
        },
        input,
        params,
        aliases: BTreeMap::new(),
    };
    let mut entries: Vec<Value> = Vec::new();
    for item in &plan.items {
        for reference in item.check.refs() {
            let read = path::read(&reference, &ctx);
            let locations: Vec<String> = read.location.iter().map(Location::render).collect();
            entries.push(serde_json::json!({
                "name": name::name(&reference),
                "value": read.value.cloned().unwrap_or(Value::Null),
                "locations": locations,
            }));
        }
    }
    entries.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    entries.dedup();
    entries
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::policy::Policy;
    use serde_json::{Value, json};

    fn read(subjects: Value, checks: Value) -> BTreeMap<String, CheckRead> {
        let policy = Policy::read(&json!({
            "ergo_spec": "v0.2",
            "subjects": subjects,
            "requirements": {"r": {"subject": "t", "checks": checks}}
        }));
        let reading = Reading::of(&policy);
        read_checks(&reading, &policy.requirements["r"])
    }

    fn one(checks: Value) -> CheckRead {
        read(json!({"t": {"from": "ts"}}), checks)
            .remove("c")
            .unwrap()
    }

    fn problems(read: &CheckRead) -> Vec<&str> {
        read.problems.iter().map(String::as_str).collect()
    }

    fn compare_to(path: crate::path::Path) -> Check {
        use crate::ops::compare::{Cmp, Compare, Side};
        Check::Compare(Compare {
            left: Side::Path(crate::path::Path {
                start: crate::path::Start::Subject,
                steps: vec![crate::path::Step::Key("x".into())],
            }),
            right: Side::Path(path),
            cmp: Cmp::Eq,
            within: None,
        })
    }

    fn reference(start: crate::path::Start, key: &str) -> crate::path::Path {
        crate::path::Path {
            start,
            steps: vec![crate::path::Step::Key(key.into())],
        }
    }

    #[test]
    fn refs_are_read_once_from_the_params_and_the_input_and_sorted_by_name() {
        use crate::path::Start;
        let plan = Plan {
            items: ["b", "a", "a"]
                .iter()
                .map(|k| Item {
                    text: String::new(),
                    check: compare_to(reference(Start::Params, k)),
                })
                .chain(std::iter::once(Item {
                    text: String::new(),
                    check: compare_to(reference(Start::Input, "i")),
                }))
                .collect(),
            all_of: true,
        };
        let params = json!({"a": 1, "b": [2]});
        let found = refs_of(&plan, &json!({"i": "z"}), Some(&params));
        assert_eq!(
            found,
            [
                json!({"name": "$input.i", "value": "z", "locations": ["/i"]}),
                json!({"name": "$params.a", "value": 1, "locations": ["$params:/a"]}),
                json!({"name": "$params.b", "value": [2], "locations": ["$params:/b"]}),
            ]
        );
    }

    #[test]
    fn a_ref_that_cannot_be_read_shows_null_where_the_read_stopped() {
        use crate::path::Start;
        let plan = Plan {
            items: vec![Item {
                text: String::new(),
                check: compare_to(reference(Start::Params, "k")),
            }],
            all_of: false,
        };
        assert_eq!(
            refs_of(&plan, &json!({}), None),
            [json!({"name": "$params.k", "value": null, "locations": ["$params:"]})]
        );
        let params = json!({});
        assert_eq!(
            refs_of(&plan, &json!({}), Some(&params))[0]["locations"],
            json!(["$params:"])
        );
    }

    #[test]
    fn a_ref_step_is_a_ref_and_a_plain_field_on_the_right_is_not() {
        use crate::path::{Path, Start, Step};
        let named = Path {
            start: Start::Subject,
            steps: vec![
                Step::Key("m".into()),
                Step::Ref(Box::new(reference(Start::Params, "k"))),
            ],
        };
        let plan = Plan {
            items: vec![
                Item {
                    text: String::new(),
                    check: compare_to(named),
                },
                Item {
                    text: String::new(),
                    check: compare_to(reference(Start::Subject, "y")),
                },
            ],
            all_of: true,
        };
        let params = json!({"k": "a"});
        let found = refs_of(&plan, &json!({}), Some(&params));
        assert_eq!(found.len(), 1);
        assert_eq!(found[0]["name"], json!("$params.k"));
    }

    #[test]
    fn a_sentence_is_shown_in_its_canonical_spelling_and_lowers_to_one_assertion() {
        let read = one(json!({"c": "  x   does not exist "}));
        assert_eq!(read.expression, "x does not exist");
        let plan = read.plan.unwrap();
        assert_eq!(plan.items.len(), 1);
        assert!(!plan.all_of);
        assert!(matches!(&plan.items[0].check, Check::Present(p) if p.missing));
    }

    #[test]
    fn assertions_joined_with_and_or_listed_under_assert_are_one_all_of_check() {
        let joined = one(json!({"c": "x exists and y exists"}));
        let listed = one(json!({"c": {"assert": ["x exists", "y exists"]}}));
        for read in [joined, listed] {
            assert_eq!(read.expression, "x exists and y exists");
            let plan = read.plan.unwrap();
            assert!(plan.all_of);
            assert_eq!(plan.items.len(), 2);
            assert_eq!(plan.items[1].text, "y exists");
        }
    }

    #[test]
    fn a_sentence_that_does_not_parse_keeps_its_text_and_the_parsers_message() {
        let read = one(json!({"c": "  x is \"a  "}));
        assert_eq!(read.expression, "x is \"a");
        assert_eq!(problems(&read), ["unclosed quote at column 6"]);
        assert!(read.plan.is_none());
    }

    #[test]
    fn a_problem_in_one_line_of_a_list_starts_with_the_lines_number() {
        let read = one(json!({"c": {"assert": ["x exists", "y is \"a"]}}));
        assert_eq!(problems(&read), ["line 2: unclosed quote at column 6"]);
        let single = one(json!({"c": {"assert": ["y is \"a"]}}));
        assert_eq!(problems(&single), ["unclosed quote at column 6"]);
    }

    #[test]
    fn a_sentence_that_reads_but_is_written_wrong_is_listed_and_has_no_plan() {
        let read = one(json!({"c": "x equals x"}));
        assert_eq!(problems(&read), ["x is compared with itself"]);
        assert!(read.plan.is_none());
    }

    #[test]
    fn a_check_the_engine_cannot_run_yet_still_gets_a_plan_that_fails_as_unusable() {
        let read = one(json!({"c": "every xs.y is 1"}));
        let plan = read.plan.unwrap();
        assert!(matches!(plan.items[0].check, Check::NotYet));
        let read = one(json!({"c": "x is empty and y exists"}));
        let plan = read.plan.unwrap();
        assert!(matches!(plan.items[0].check, Check::NotYet));
        assert!(matches!(plan.items[1].check, Check::Present(_)));
    }

    #[test]
    fn a_for_check_is_printed_with_its_line_and_gets_one_plan_that_cannot_run_yet() {
        let read =
            one(json!({"c": {"for": "every xs as x", "assert": ["x.a exists", "x.b exists"]}}));
        assert_eq!(
            read.expression,
            "for every xs as x: x.a exists and x.b exists"
        );
        let plan = read.plan.unwrap();
        assert!(!plan.all_of);
        assert!(matches!(plan.items[0].check, Check::NotYet));
    }

    #[test]
    fn a_for_line_problem_starts_with_for() {
        let read = one(json!({"c": {"for": "every xs as x, every ys as x", "assert": "x exists"}}));
        assert_eq!(problems(&read), ["for: x is given twice"]);
        let read = one(json!({"c": {"for": "every xs", "assert": "x exists"}}));
        assert!(problems(&read)[0].starts_with("for: "));
    }

    #[test]
    fn a_for_alias_named_like_a_subject_or_a_part_is_written_wrong() {
        let read = read(
            json!({"t": {"from": "ts", "has": {"cov": "d"}}, "other": {}}),
            json!({"c": {"for": "every xs as cov, every ys as other", "assert": "cov exists"}}),
        );
        assert_eq!(
            problems(&read["c"]),
            [
                "cov can't be an alias: it's a part of t",
                "other can't be an alias: it's a subject's name"
            ]
        );
    }

    #[test]
    fn any_of_is_printed_with_its_options_sorted_and_each_option_problem_names_the_option() {
        let read = one(json!({"c": {"any_of": {"b": "y exists", "a": ["x exists", "z exists"]}}}));
        assert_eq!(
            read.expression,
            "one of: a(x exists and z exists) | b(y exists)"
        );
        let wrong = one(json!({"c": {"any_of": {"known": ["x exists", "y is \"a"]}}}));
        assert_eq!(
            problems(&wrong),
            ["option known: line 2: unclosed quote at column 6"]
        );
    }

    #[test]
    fn a_check_that_is_not_a_sentence_form_has_no_plan_and_keeps_what_was_written() {
        let read = one(json!({"c": {"description": "d"}}));
        assert_eq!(read.expression, "<missing assert>");
        assert!(read.plan.is_none());
        let read = one(json!({"c": 5}));
        assert_eq!(read.expression, "<invalid check>");
    }

    #[test]
    fn a_part_alias_in_an_assertion_reads_the_part() {
        let read = read(
            json!({"t": {"from": "ts", "has": {"cov": "d.b"}}}),
            json!({"c": "cov.x exists"}),
        );
        let plan = read["c"].plan.clone().unwrap();
        let Check::Present(found) = &plan.items[0].check else {
            panic!("not present");
        };
        assert!(matches!(found.path.start, crate::path::Start::Part(_)));
    }

    #[test]
    fn a_parent_name_in_an_assertion_reads_the_parent() {
        let read = read(
            json!({"p": {"from": "ps"}, "t": {"from": "p.ts"}}),
            json!({"c": "p.owner exists"}),
        );
        let plan = read["c"].plan.clone().unwrap();
        let Check::Present(found) = &plan.items[0].check else {
            panic!("not present");
        };
        assert_eq!(found.path.start, crate::path::Start::Alias("p".into()));
    }
}
