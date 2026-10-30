use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

struct Case {
    id: String,
    group: Value,
    case: Value,
}

fn rust_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..")
}

fn load_cases(dir: &Path) -> Vec<Case> {
    let mut topics: Vec<PathBuf> = fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("can't read {}: {e}", dir.display()))
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.is_dir())
        .collect();
    topics.sort();
    let mut cases = Vec::new();
    for topic in topics {
        let name = topic.file_name().unwrap().to_string_lossy().into_owned();
        let file = topic.join("cases.json");
        let text = fs::read_to_string(&file)
            .unwrap_or_else(|e| panic!("can't read {}: {e}", file.display()));
        let groups: Value = serde_json::from_str(&text)
            .unwrap_or_else(|e| panic!("can't parse {}: {e}", file.display()));
        for group in groups
            .as_array()
            .expect("cases.json holds a list of groups")
        {
            for case in group["cases"].as_array().expect("a group has cases") {
                let id = format!(
                    "{name} / {} / {}",
                    group["description"]
                        .as_str()
                        .expect("a group has a description"),
                    case["description"]
                        .as_str()
                        .expect("a case has a description"),
                );
                cases.push(Case {
                    id,
                    group: group.clone(),
                    case: case.clone(),
                });
            }
        }
    }
    cases
}

fn params(group: &Value) -> Value {
    group.get("params").cloned().unwrap_or_else(|| json!({}))
}

fn decimal(text: &str) -> (bool, String, i128) {
    let (negative, unsigned) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text),
    };
    let (mantissa, exponent) = match unsigned.split_once(['e', 'E']) {
        Some((m, e)) => (m, e.trim_start_matches('+').parse::<i128>().unwrap()),
        None => (unsigned, 0),
    };
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let digits = format!("{whole}{fraction}");
    let digits = digits.trim_start_matches('0');
    let trimmed = digits.trim_end_matches('0');
    if trimmed.is_empty() {
        return (false, String::new(), 0);
    }
    let exponent = exponent - fraction.len() as i128 + (digits.len() - trimmed.len()) as i128;
    (negative, trimmed.to_string(), exponent)
}

fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => decimal(&x.to_string()) == decimal(&y.to_string()),
        (Value::Array(x), Value::Array(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(a, b)| same(a, b))
        }
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w)))
        }
        _ => a == b,
    }
}

fn wanted(case: &Value, field: &str) -> Option<Map<String, Value>> {
    match case.get(field) {
        None => Some(Map::new()),
        Some(Value::Object(map)) => Some(map.clone()),
        Some(_) => None,
    }
}

fn every<F>(case: &Value, field: &str, test: F) -> bool
where
    F: Fn(&str, &Value) -> bool,
{
    wanted(case, field).is_some_and(|map| map.iter().all(|(k, v)| test(k, v)))
}

fn every_check<F>(case: &Value, field: &str, test: F) -> bool
where
    F: Fn(&str, &str, &Value) -> bool,
{
    every(case, field, |name, checks| {
        checks
            .as_object()
            .is_some_and(|checks| checks.iter().all(|(check, v)| test(name, check, v)))
    })
}

fn rows_match(case: &Value, report: &Value) -> bool {
    let (Some(rows), Some(want)) = (
        report.get("results").and_then(Value::as_array),
        case.get("results").and_then(Value::as_array),
    ) else {
        return false;
    };
    let listed = |check: &str| {
        want.iter()
            .any(|row| row.get("check").and_then(Value::as_str) == Some(check))
    };
    let compared: Vec<Value> = rows
        .iter()
        .filter(|row| match row.get("check").and_then(Value::as_str) {
            Some(check) => !check.starts_with('$') || check == "$applies" || listed(check),
            None => true,
        })
        .cloned()
        .collect();
    same(&Value::Array(compared), &Value::Array(want.clone()))
}

fn passes(case: &Value, report: &Value, violations: &dyn Fn(&Value) -> Value) -> bool {
    let requirement = |name: &str| report.get("requirements").and_then(|r| r.get(name));
    let check = |name: &str, check: &str| {
        requirement(name)
            .and_then(|r| r.get("checks"))
            .and_then(|c| c.get(check))
    };
    let is = |found: Option<&Value>, want: &Value| found.is_some_and(|found| same(found, want));
    rows_match(case, report)
        && every(case, "status", |name, status| {
            is(requirement(name).and_then(|r| r.get("status")), status)
        })
        && report.get("compliant").is_some_and(|compliant| {
            case.get("compliant")
                .is_none_or(|want| same(compliant, want))
        })
        && every_check(case, "expressions", |name, c, expression| {
            is(check(name, c).and_then(|c| c.get("expression")), expression)
        })
        && every(case, "requirements", |name, fields| {
            fields.as_object().is_some_and(|fields| {
                fields.iter().all(|(field, value)| match field.as_str() {
                    "checks" => value.as_object().is_some_and(|checks| {
                        checks.iter().all(|(c, fields)| {
                            fields.as_object().is_some_and(|fields| {
                                fields
                                    .iter()
                                    .all(|(f, v)| is(check(name, c).and_then(|c| c.get(f)), v))
                            })
                        })
                    }),
                    _ => is(requirement(name).and_then(|r| r.get(field)), value),
                })
            })
        })
        && case
            .get("violations")
            .is_none_or(|want| same(&violations(report), want))
        && every(case, "report", |field, value| is(report.get(field), value))
        && every_check(case, "refs", |name, c, refs| {
            check(name, c).is_some_and(|entry| same(entry.get("$refs").unwrap_or(&json!([])), refs))
        })
}

fn list_problems(ids: &[String], failing: &BTreeSet<String>, known: &[String]) -> Vec<String> {
    let mut problems = Vec::new();
    let mut seen = BTreeSet::new();
    for id in ids {
        if !seen.insert(id) {
            problems.push(format!("two cases are named {id}"));
        }
    }
    let mut listed = BTreeSet::new();
    for id in known {
        if !listed.insert(id) {
            problems.push(format!("known-failures.txt lists {id} twice"));
        } else if !seen.contains(id) {
            problems.push(format!(
                "known-failures.txt lists {id}, but there's no such case"
            ));
        } else if !failing.contains(id) {
            problems.push(format!(
                "passes, so remove it from known-failures.txt: {id}"
            ));
        }
    }
    for id in failing {
        if !listed.contains(id) {
            problems.push(format!("fails: {id}"));
        }
    }
    problems
}

#[test]
fn every_case_passes_unless_known_to_fail() {
    let cases = load_cases(&rust_dir().join("../../spec/cases"));
    assert!(!cases.is_empty(), "no cases found in spec/cases");
    let known_file = rust_dir().join("known-failures.txt");
    let known: Vec<String> = fs::read_to_string(&known_file)
        .unwrap_or_else(|e| panic!("can't read {}: {e}", known_file.display()))
        .lines()
        .filter(|line| !line.is_empty())
        .map(String::from)
        .collect();
    let failing: BTreeSet<String> = cases
        .iter()
        .filter(|c| {
            let report =
                ergo_engine::report(&c.case["input"], &c.group["policy"], &params(&c.group));
            !passes(&c.case, &report, &ergo_engine::violations)
        })
        .map(|c| c.id.clone())
        .collect();
    let ids: Vec<String> = cases.iter().map(|c| c.id.clone()).collect();
    println!("{} of {} cases pass", ids.len() - failing.len(), ids.len());
    let problems = list_problems(&ids, &failing, &known);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

fn sample_case() -> Value {
    json!({
        "description": "case",
        "input": {"x": 1},
        "results": [{
            "requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
            "passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}]
        }]
    })
}

fn sample_report() -> Value {
    json!({
        "description": "",
        "compliant": true,
        "requirements": {"s": {
            "status": "met",
            "subjects": {"matching": 1, "total": 1},
            "checks": {
                "c": {"expression": "x is present", "description": ""},
                "$min_subjects": {"description": "at least one"}
            }
        }},
        "results": [
            {"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "$well_formed", "passed": true, "cause": "satisfied", "inputs": []},
            {"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c", "passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}]}
        ]
    })
}

fn no_violations(_: &Value) -> Value {
    json!([])
}

fn with(case: &Value, field: &str, value: Value) -> Value {
    let mut case = case.clone();
    case[field] = value;
    case
}

#[test]
fn a_case_that_matches_its_report_passes() {
    assert!(passes(&sample_case(), &sample_report(), &no_violations));
}

#[test]
fn a_case_with_the_wrong_rows_fails() {
    assert!(!passes(
        &with(&sample_case(), "results", json!([])),
        &sample_report(),
        &no_violations
    ));
}

#[test]
fn rows_in_another_order_fail() {
    let mut report = sample_report();
    report["results"]
        .as_array_mut()
        .unwrap()
        .push(json!({"requirement": "s", "check": "d"}));
    let mut case = sample_case();
    case["results"]
        .as_array_mut()
        .unwrap()
        .insert(0, json!({"requirement": "s", "check": "d"}));
    assert!(!passes(&case, &report, &no_violations));
}

#[test]
fn a_dollar_row_is_compared_only_when_the_case_lists_its_check() {
    let mut case = sample_case();
    case["results"].as_array_mut().unwrap().insert(0, json!({
        "requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "$well_formed", "passed": false, "cause": "satisfied", "inputs": []
    }));
    assert!(!passes(&case, &sample_report(), &no_violations));
}

#[test]
fn an_applies_row_is_always_compared() {
    let mut report = sample_report();
    report["results"]
        .as_array_mut()
        .unwrap()
        .push(json!({"requirement": "s", "check": "$applies"}));
    assert!(!passes(&sample_case(), &report, &no_violations));
}

#[test]
fn a_report_without_results_fails_even_when_the_case_wants_none() {
    let case = with(&sample_case(), "results", json!([]));
    assert!(!passes(&case, &json!({"compliant": true}), &no_violations));
    assert!(!passes(&case, &Value::Null, &no_violations));
}

#[test]
fn a_case_with_the_wrong_status_fails() {
    let case = with(&sample_case(), "status", json!({"s": "not_met"}));
    assert!(!passes(&case, &sample_report(), &no_violations));
    let case = with(&sample_case(), "status", json!({"t": "met"}));
    assert!(!passes(&case, &sample_report(), &no_violations));
    let case = with(&sample_case(), "status", json!({"s": "met"}));
    assert!(passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_case_with_the_wrong_compliant_fails() {
    let case = with(&sample_case(), "compliant", json!(false));
    assert!(!passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_report_without_compliant_fails() {
    let mut report = sample_report();
    report.as_object_mut().unwrap().remove("compliant");
    assert!(!passes(&sample_case(), &report, &no_violations));
}

#[test]
fn a_case_with_the_wrong_expression_fails() {
    let case = with(
        &sample_case(),
        "expressions",
        json!({"s": {"c": "y is present"}}),
    );
    assert!(!passes(&case, &sample_report(), &no_violations));
    let case = with(
        &sample_case(),
        "expressions",
        json!({"s": {"c": "x is present"}}),
    );
    assert!(passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_case_with_the_wrong_refs_fails() {
    let case = with(
        &sample_case(),
        "refs",
        json!({"s": {"c": [{"name": "$$params.x", "value": 1}]}}),
    );
    assert!(!passes(&case, &sample_report(), &no_violations));
}

#[test]
fn missing_refs_count_as_none() {
    let case = with(&sample_case(), "refs", json!({"s": {"c": []}}));
    assert!(passes(&case, &sample_report(), &no_violations));
}

#[test]
fn refs_of_a_check_the_report_lacks_fail() {
    let case = with(&sample_case(), "refs", json!({"s": {"d": []}}));
    assert!(!passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_case_with_the_wrong_requirement_entry_fails() {
    for want in [
        json!({"subjects": {"matching": 2, "total": 1}}),
        json!({"checks": {"$min_subjects": {"description": "nope"}}}),
        json!({"checks": {"d": {"description": ""}}}),
    ] {
        let case = with(&sample_case(), "requirements", json!({"s": want}));
        assert!(!passes(&case, &sample_report(), &no_violations));
    }
}

#[test]
fn a_requirement_entry_compares_only_the_listed_fields() {
    let case = with(
        &sample_case(),
        "requirements",
        json!({"s": {"subjects": {"matching": 1, "total": 1}, "checks": {"$min_subjects": {"description": "at least one"}}}}),
    );
    assert!(passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_case_with_the_wrong_violations_fails() {
    let case = with(&sample_case(), "violations", json!([{}]));
    assert!(!passes(&case, &sample_report(), &no_violations));
    let case = with(&sample_case(), "violations", json!([]));
    assert!(passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_case_with_the_wrong_report_field_fails() {
    let case = with(&sample_case(), "report", json!({"description": "nope"}));
    assert!(!passes(&case, &sample_report(), &no_violations));
    let case = with(&sample_case(), "report", json!({"meta": {}}));
    assert!(!passes(&case, &sample_report(), &no_violations));
}

#[test]
fn a_case_field_that_is_not_an_object_fails() {
    for field in ["status", "expressions", "refs", "requirements", "report"] {
        let case = with(&sample_case(), field, json!([]));
        assert!(!passes(&case, &sample_report(), &no_violations), "{field}");
    }
}

#[test]
fn numbers_are_compared_by_value() {
    let parse = |text: &str| serde_json::from_str::<Value>(text).unwrap();
    for (a, b) in [
        ("1", "1.0"),
        ("100", "1e2"),
        ("0.5", "5E-1"),
        ("0", "-0.0"),
        ("1e400", "10e399"),
        ("-12.50", "-1.25e+1"),
    ] {
        assert!(same(&parse(a), &parse(b)), "{a} and {b}");
    }
    for (a, b) in [
        ("1", "2"),
        ("1", "-1"),
        ("1", "10"),
        ("0.1", "1"),
        ("1e400", "1e401"),
    ] {
        assert!(!same(&parse(a), &parse(b)), "{a} and {b}");
    }
}

#[test]
fn a_number_is_not_the_same_as_its_string() {
    assert!(!same(&json!(1), &json!("1")));
}

#[test]
fn key_order_does_not_matter() {
    let a: Value = serde_json::from_str(r#"{"a": 1, "b": [1, {"c": 2, "d": 3}]}"#).unwrap();
    let b: Value = serde_json::from_str(r#"{"b": [1, {"d": 3, "c": 2}], "a": 1}"#).unwrap();
    assert!(same(&a, &b));
}

#[test]
fn an_extra_key_is_a_difference() {
    assert!(!same(&json!({"a": 1}), &json!({"a": 1, "b": 2})));
}

#[test]
fn params_are_passed_as_written_and_default_to_an_empty_object() {
    assert_eq!(params(&json!({"params": null})), Value::Null);
    assert_eq!(params(&json!({"params": {"n": 1}})), json!({"n": 1}));
    assert_eq!(params(&json!({})), json!({}));
}

#[test]
fn a_new_failure_is_a_problem() {
    let ids = ["a".to_string(), "b".to_string()];
    let failing = BTreeSet::from(["a".to_string()]);
    assert_eq!(list_problems(&ids, &failing, &[]), ["fails: a"]);
}

#[test]
fn a_listed_case_that_passes_is_a_problem() {
    let ids = ["a".to_string(), "b".to_string()];
    let failing = BTreeSet::from(["a".to_string()]);
    let known = ["a".to_string(), "b".to_string()];
    assert_eq!(
        list_problems(&ids, &failing, &known),
        ["passes, so remove it from known-failures.txt: b"]
    );
}

#[test]
fn a_listed_case_that_does_not_exist_is_a_problem() {
    let ids = ["a".to_string()];
    let known = ["z".to_string()];
    assert_eq!(
        list_problems(&ids, &BTreeSet::new(), &known),
        ["known-failures.txt lists z, but there's no such case"]
    );
}

#[test]
fn a_case_listed_twice_is_a_problem() {
    let ids = ["a".to_string()];
    let failing = BTreeSet::from(["a".to_string()]);
    let known = ["a".to_string(), "a".to_string()];
    assert_eq!(
        list_problems(&ids, &failing, &known),
        ["known-failures.txt lists a twice"]
    );
}

#[test]
fn two_cases_with_the_same_name_are_a_problem() {
    let ids = ["a".to_string(), "a".to_string()];
    let failing = BTreeSet::from(["a".to_string()]);
    let known = ["a".to_string()];
    assert_eq!(
        list_problems(&ids, &failing, &known),
        ["two cases are named a"]
    );
}

#[test]
fn every_listed_failing_case_is_fine() {
    let ids = ["a".to_string(), "b".to_string()];
    let failing = BTreeSet::from(["a".to_string()]);
    let known = ["a".to_string()];
    assert!(list_problems(&ids, &failing, &known).is_empty());
}
