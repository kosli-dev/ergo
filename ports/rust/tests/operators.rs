use ergo::Operators;
use serde_json::{Value, json};

fn pr_reviewer() -> Value {
    json!({
        "min_length": {
            "params": {"path": {"kind": "path", "type": "list"}, "min": "number"},
            "expression": "count({path}) >= {min}",
            "passes": "size(path) >= min"
        },
        "min_length_at": {
            "params": {"path": {"kind": "path", "type": "list"}, "min_path": {"kind": "path", "type": "number"}},
            "expression": "count({path}) >= {min_path}",
            "passes": "size(path) >= min_path"
        },
        "length_eq_difference": {
            "params": {"left": {"kind": "path", "type": "list"}, "right": {"kind": "path", "type": "number"}, "minus": {"kind": "path", "type": "number"}},
            "expression": "count({left}) == {right} - {minus}",
            "passes": "size(left) == right - minus"
        },
        "count_where_eq_sum": {
            "params": {"path": {"kind": "path", "type": "list"}, "field": "string", "value": "value", "sum": "paths"},
            "expression": "count({path} where {field} == {value}) == sum({sum})",
            "passes": "path.filter(e, field in e && e[field] == value).size() == ergo.sum(sum)"
        },
        "keys_match": {
            "params": {"keys": {"kind": "path", "type": "list"}, "path": {"kind": "path", "type": "object"}, "patterns": "value"},
            "expression": "every {keys} keys a {path} matching one of {patterns}",
            "passes": "keys.all(k, k in path && type(path[k]) == string && patterns.exists(p, path[k].matches(p)))"
        },
        "contains_all": {
            "params": {"path": {"kind": "path", "type": "list"}, "of": {"kind": "path", "type": "list"}},
            "expression": "{path} contains every {of}",
            "passes": "of.all(x, x in path)"
        },
        "sum_eq": {
            "version": "1",
            "params": {
                "path": {"kind": "path", "type": "list"},
                "field": "string",
                "only": {"kind": "value", "optional": true, "default": {}},
                "total": {"kind": "path", "type": "number"},
                "tolerance": "number"
            },
            "expression": "sum({path}.{field} where {only}) == {total} within {tolerance}",
            "passes": "path.filter(e, only.all(k, k in e && e[k] == only[k])).all(e, field in e && type(e[field]) in [int, uint, double]) && ergo.sum(path.filter(e, only.all(k, k in e && e[k] == only[k])).map(e, e[field])) - total <= tolerance && total - ergo.sum(path.filter(e, only.all(k, k in e && e[k] == only[k])).map(e, e[field])) <= tolerance"
        }
    })
}

fn ops() -> Operators {
    Operators::load(&pr_reviewer()).unwrap()
}

fn report(item: Value, check: Value) -> Value {
    ergo::report_with(&json!({"items": [item]}), None, &json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), &ops())
}

fn row(report: &Value) -> Value {
    report["results"].as_array().unwrap().iter().find(|r| r["check"] == "c").unwrap().clone()
}

fn verdict(item: Value, check: Value) -> (bool, String) {
    let r = row(&report(item, check));
    (r["passed"].as_bool().unwrap(), r["cause"].as_str().unwrap().to_string())
}

#[test]
fn a_policy_names_the_operator_and_ergo_reads_its_paths_in_param_name_order() {
    let check = json!({"op": "min_length_at", "path": ["files"], "min_path": ["total_files"]});
    let rep = report(json!({"id": 1, "files": ["a"], "total_files": 2}), check);
    assert_eq!(rep["requirements"]["s"]["checks"]["c"]["expression"], "count(files) >= total_files");
    let r = row(&rep);
    assert_eq!((r["passed"].clone(), r["cause"].clone()), (json!(false), json!("value")));
    assert_eq!(r["inputs"], json!([{"name": "total_files", "value": 2}, {"name": "files", "value": ["a"]}]));
}

#[test]
fn missing_null_and_wrong_typed_paths_fail_closed_before_the_body_runs() {
    let check = json!({"op": "min_length_at", "path": ["files"], "min_path": ["total_files"]});
    assert_eq!(verdict(json!({"id": 1, "files": ["a", "b"], "total_files": 2}), check.clone()), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "total_files": 2}), check.clone()), (false, "absent".into()));
    assert_eq!(verdict(json!({"id": 1, "files": ["a"], "total_files": null}), check.clone()), (false, "null".into()));
    assert_eq!(verdict(json!({"id": 1, "files": "a", "total_files": 1}), check.clone()), (false, "unusable".into()));
    assert_eq!(verdict(json!({"id": 1, "files": ["a"], "total_files": "1"}), check), (false, "unusable".into()));
}

#[test]
fn min_length_takes_a_number_from_the_policy() {
    let check = json!({"op": "min_length", "path": ["uncovered"], "min": 1});
    assert_eq!(verdict(json!({"id": 1, "uncovered": ["a.rs"]}), check.clone()), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "uncovered": []}), check), (false, "value".into()));
}

#[test]
fn length_eq_difference_does_arithmetic() {
    let check = json!({"op": "length_eq_difference", "left": ["records"], "right": ["findings_in"], "minus": ["unverified"]});
    assert_eq!(verdict(json!({"id": 1, "records": [1, 2], "findings_in": 5, "unverified": 3}), check.clone()), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "records": [1], "findings_in": 5, "unverified": 3}), check), (false, "value".into()));
}

#[test]
fn count_where_eq_sum_reads_a_list_of_paths() {
    let check = json!({"op": "count_where_eq_sum", "path": ["raw"], "field": "source", "value": "opus", "sum": [["counts", "a"], ["counts", "b"]]});
    let item = json!({"id": 1, "raw": [{"source": "opus"}, {"source": "opus"}, {"source": "gpt"}], "counts": {"a": 1, "b": 1}});
    let rep = report(item, check.clone());
    assert_eq!(rep["requirements"]["s"]["checks"]["c"]["expression"], r#"count(raw where "source" == "opus") == sum([counts.a, counts.b])"#);
    assert_eq!(row(&rep)["passed"], true);
    assert_eq!(verdict(json!({"id": 1, "raw": [], "counts": {"a": 1}}), check), (false, "absent".into()));
}

#[test]
fn keys_match_checks_every_key_against_a_pattern() {
    let check = json!({"op": "keys_match", "keys": ["dispatched"], "path": ["shas"], "patterns": ["^[0-9a-f]{40}$"]});
    let sha = "0123456789abcdef0123456789abcdef01234567";
    assert_eq!(verdict(json!({"id": 1, "dispatched": ["a"], "shas": {"a": sha}}), check.clone()), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "dispatched": ["a", "b"], "shas": {"a": sha}}), check.clone()), (false, "value".into()));
    assert_eq!(verdict(json!({"id": 1, "dispatched": ["a"], "shas": {"a": 5}}), check), (false, "value".into()));
}

#[test]
fn contains_all_needs_a_list_on_both_sides() {
    let check = json!({"op": "contains_all", "path": ["targeted"], "of": ["uncovered"]});
    assert_eq!(verdict(json!({"id": 1, "targeted": ["a", "b"], "uncovered": ["a"]}), check.clone()), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "targeted": ["b"], "uncovered": ["a"]}), check.clone()), (false, "value".into()));
    assert_eq!(verdict(json!({"id": 1, "targeted": {"x": "a"}, "uncovered": ["a"]}), check), (false, "unusable".into()));
}

#[test]
fn sum_eq_uses_ergo_sum_and_an_optional_param() {
    let check = json!({"op": "sum_eq", "path": ["stages"], "field": "usd", "only": {"kind": "llm"}, "total": ["total"], "tolerance": 0.01});
    let item = json!({"id": 1, "stages": [{"kind": "llm", "usd": 0.5}, {"kind": "llm", "usd": 0.25}, {"kind": "tool", "usd": 9}], "total": 0.75});
    assert_eq!(verdict(item.clone(), check), (true, "satisfied".into()));
    let without_only = json!({"op": "sum_eq", "path": ["stages"], "field": "usd", "total": ["total"], "tolerance": 0.01});
    assert_eq!(verdict(item, without_only), (false, "value".into()));
    let bad = json!({"op": "sum_eq", "path": ["stages"], "field": "usd", "total": ["total"], "tolerance": 0.01});
    assert_eq!(verdict(json!({"id": 1, "stages": [{"usd": "x"}], "total": 0.75}), bad), (false, "value".into()));
}

#[test]
fn a_param_can_read_a_name_and_the_row_shows_it() {
    let input = json!({"prs": [{"number": 42, "approvals": 1, "reviewers": ["a", "b"]}]});
    let check = json!({"op": "min_length_at", "path": ["$pr", "reviewers"], "min_path": ["$pr", "approvals"]});
    let requirements = json!({"s": {"from": ["prs", {"each_as": "pr"}], "id": ["number"], "checks": {"c": check}}});
    let rep = ergo::report_with(&input, None, &requirements, &ops());
    assert_eq!(rep["requirements"]["s"]["checks"]["c"]["expression"], "count($pr.reviewers) >= $pr.approvals");
    assert_eq!(row(&rep)["inputs"], json!([{"name": "$pr.approvals", "value": 1}, {"name": "$pr.reviewers", "value": ["a", "b"]}]));
    assert_eq!(row(&rep)["passed"], true);
}

#[test]
fn a_custom_operator_can_sit_inside_all() {
    let check = json!({"op": "all", "path": ["rounds"], "check": {"op": "min_length", "path": ["notes"], "min": 1}});
    let rep = report(json!({"id": 1, "rounds": [{"notes": ["x"]}, {"notes": []}]}), check);
    assert_eq!(rep["requirements"]["s"]["checks"]["c"]["expression"], "every rounds: count(notes) >= 1");
    let r = row(&rep);
    assert_eq!(r["cause"], "value");
    assert_eq!(r["failed_items"], json!([{"cause": "value", "path": "rounds[1]", "value": {"notes": []}}]));
}

#[test]
fn a_param_can_come_from_the_params() {
    let check = json!({"op": "min_length", "path": ["uncovered"], "min": {"ref": ["$$params", "min"]}});
    let rep = ergo::report_with(&json!({"items": [{"id": 1, "uncovered": ["a"]}]}), Some(&json!({"min": 2})), &json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), &ops());
    assert_eq!(rep["requirements"]["s"]["checks"]["c"]["expression"], "count(uncovered) >= $$params.min");
    assert_eq!(rep["requirements"]["s"]["checks"]["c"]["$refs"], json!([{"name": "$$params.min", "value": 2}]));
    assert_eq!(row(&rep)["cause"], "value");
}

#[test]
fn the_report_records_which_definitions_it_used() {
    let rep = report(json!({"id": 1, "uncovered": ["a"]}), json!({"op": "min_length", "path": ["uncovered"], "min": 1}));
    let used = rep["operators"].as_object().unwrap();
    assert_eq!(used.keys().collect::<Vec<_>>(), vec!["min_length"]);
    assert_eq!(used["min_length"]["sha256"].as_str().unwrap().len(), 64);
    let plain = ergo::report(&json!({"items": [{"id": 1}]}), None, &json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}}));
    assert!(plain.get("operators").is_none());
}

#[test]
fn a_check_written_wrong_for_its_definition_fails_well_formed() {
    let rep = report(json!({"id": 1}), json!({"op": "min_length", "path": ["uncovered"], "min": "one", "mni": 1}));
    assert_eq!(rep["results"][0]["passed"], false);
    assert_eq!(rep["results"][0]["inputs"][2], json!({"name": "checks.c", "value": ["invalid min", "unknown field mni"]}));
    assert_eq!(row(&rep)["cause"], "ill_formed");
    let missing = report(json!({"id": 1}), json!({"op": "min_length", "path": ["uncovered"]}));
    assert_eq!(missing["results"][0]["inputs"][2], json!({"name": "checks.c", "value": ["missing min"]}));
}

#[test]
fn without_definitions_the_operator_is_unknown() {
    let rep = ergo::report(&json!({"items": [{"id": 1}]}), None, &json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "min_length", "path": ["x"], "min": 1}}}}));
    assert_eq!(rep["results"][0]["inputs"][2], json!({"name": "checks.c", "value": ["unknown op min_length"]}));
}

#[test]
fn broken_definitions_are_refused_when_loaded() {
    let errors = |d: Value| Operators::load(&d).err().unwrap();
    assert_eq!(errors(json!({"x": {"params": {"a": "number"}, "passes": "a >"}}))[0].split(':').next().unwrap(), "operator x");
    assert_eq!(errors(json!({"x": {"params": {"a": "number"}, "passes": "b > 1"}})), vec!["operator x: its passes reads b, which isn't one of its params"]);
    assert_eq!(errors(json!({"x": {"params": {"a": "number"}, "passes": "a > 1", "expression": "{b}"}})), vec!["operator x: its expression names {b}, which isn't one of its params"]);
    assert_eq!(errors(json!({"equals": {"passes": "true"}})), vec!["operator equals: its name must be a plain identifier that isn't a built-in operator"]);
    assert_eq!(errors(json!({"x": {"params": {"a": "date"}, "passes": "true"}})), vec!["operator x: param a has an unknown kind date"]);
}
