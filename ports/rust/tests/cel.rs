use serde_json::{Value, json};

fn rows(input: Value, expr: &str) -> Vec<Value> {
    let requirements = json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "cel", "expr": expr}}}});
    let report = ergo::report(&input, None, &requirements);
    report["results"].as_array().unwrap().iter().filter(|r| r["check"] == "c").cloned().collect()
}

fn verdict(item: Value, expr: &str) -> (bool, String) {
    let r = &rows(json!({"items": [item]}), expr)[0];
    (r["passed"].as_bool().unwrap(), r["cause"].as_str().unwrap().to_string())
}

fn well_formed_inputs(expr: &str) -> Value {
    let report = ergo::report(&json!({"items": [{"id": 1}]}), None, &json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "cel", "expr": expr}}}}));
    report["results"][0]["inputs"].clone()
}

#[test]
fn min_length_needs_a_list_with_an_item() {
    let e = "type(self.uncovered) == list && size(self.uncovered) >= 1";
    assert_eq!(verdict(json!({"id": 1, "uncovered": ["a.rs"]}), e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "uncovered": []}), e), (false, "value".into()));
    assert_eq!(verdict(json!({"id": 1}), e), (false, "absent".into()));
    assert_eq!(verdict(json!({"id": 1, "uncovered": "a.rs"}), e), (false, "value".into()));
}

#[test]
fn min_length_at_compares_a_length_with_another_field() {
    let e = "size(self.files) >= self.total_files";
    assert_eq!(verdict(json!({"id": 1, "files": ["a", "b"], "total_files": 2}), e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "files": ["a"], "total_files": 2}), e), (false, "value".into()));
    assert_eq!(verdict(json!({"id": 1, "files": ["a"]}), e), (false, "absent".into()));
    assert_eq!(verdict(json!({"id": 1, "files": ["a"], "total_files": null}), e), (false, "null".into()));
}

#[test]
fn length_eq_difference_does_arithmetic() {
    let e = "size(self.records) == self.findings_in - self.unverified";
    assert_eq!(verdict(json!({"id": 1, "records": [1, 2], "findings_in": 5, "unverified": 3}), e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "records": [1], "findings_in": 5, "unverified": 3}), e), (false, "value".into()));
}

#[test]
fn count_where_eq_sum_filters_then_counts() {
    let e = r#"self.raw.filter(f, f.source == "opus").size() == self.counts.a + self.counts.b"#;
    let item = json!({"id": 1, "raw": [{"source": "opus"}, {"source": "opus"}, {"source": "gpt"}], "counts": {"a": 1, "b": 1}});
    assert_eq!(verdict(item, e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "raw": [{"source": "opus"}], "counts": {"a": 1}}), e), (false, "absent".into()));
}

#[test]
fn keys_match_checks_every_key_against_a_pattern() {
    let e = "self.dispatched.all(k, k in self.shas && self.shas[k].matches('^[0-9a-f]{40}$'))";
    let sha = "0123456789abcdef0123456789abcdef01234567";
    assert_eq!(verdict(json!({"id": 1, "dispatched": ["a"], "shas": {"a": sha}}), e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "dispatched": ["a", "b"], "shas": {"a": sha}}), e), (false, "value".into()));
    assert_eq!(verdict(json!({"id": 1, "dispatched": ["a"], "shas": {"a": "nope"}}), e), (false, "value".into()));
}

#[test]
fn contains_all_needs_every_element() {
    let e = "type(self.targeted) == list && self.uncovered.all(x, x in self.targeted)";
    assert_eq!(verdict(json!({"id": 1, "targeted": ["a", "b"], "uncovered": ["a"]}), e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "targeted": ["b"], "uncovered": ["a"]}), e), (false, "value".into()));
    assert_eq!(verdict(json!({"id": 1, "targeted": {"x": "a"}, "uncovered": ["a"]}), e), (false, "value".into()));
}

#[test]
fn sum_eq_uses_the_sum_function_ergo_adds() {
    let total = r#"sum(self.stages.filter(s, s.kind == "llm").map(s, s.usd))"#;
    let e = format!("{total} - self.total <= 0.01 && self.total - {total} <= 0.01");
    let item = json!({"id": 1, "stages": [{"kind": "llm", "usd": 0.5}, {"kind": "llm", "usd": 0.25}, {"kind": "tool", "usd": 9}], "total": 0.75});
    assert_eq!(verdict(item, &e), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "stages": [{"kind": "llm", "usd": "x"}], "total": 0.75}), &e), (false, "unusable".into()));
}

#[test]
fn numbers_compare_across_int_and_double_like_ergo_does() {
    assert_eq!(verdict(json!({"id": 1, "n": 1.0}), "self.n == 1"), (true, "satisfied".into()));
    assert_eq!(verdict(json!({"id": 1, "n": 2}), "self.n > 1.5"), (true, "satisfied".into()));
}

#[test]
fn the_row_shows_the_expression_and_what_it_read() {
    let input = json!({"items": [{"id": 1, "files": ["a"], "total_files": 2}]});
    let requirements = json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "cel", "expr": "size(self.files) >= self.total_files"}}}});
    let report = ergo::report(&input, None, &requirements);
    assert_eq!(report["requirements"]["s"]["checks"]["c"]["expression"], "size(self.files) >= self.total_files");
    let row = report["results"].as_array().unwrap().iter().find(|r| r["check"] == "c").unwrap();
    assert_eq!(row["inputs"], json!([{"name": "files", "value": ["a"]}, {"name": "total_files", "value": 2}]));
}

#[test]
fn names_from_each_as_and_as_are_variables() {
    let input = json!({"prs": [{"number": 42, "author": "ann", "approvers": [{"username": "ann"}, {"username": "bob"}]}]});
    let check = json!({"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "cel", "expr": "a.username != pr.author"}});
    let requirements = json!({"s": {"from": ["prs", {"each_as": "pr"}], "id": ["number"], "checks": {"peer": check}}});
    let report = ergo::report(&input, None, &requirements);
    let row = report["results"].as_array().unwrap().iter().find(|r| r["check"] == "peer").unwrap();
    assert_eq!(row["passed"], true);
    assert_eq!(report["requirements"]["s"]["checks"]["peer"]["expression"], "some approvers as $a: a.username != pr.author");
    assert_eq!(row["inputs"], json!([{"name": "approvers[]", "value": [{"username": "ann"}, {"username": "bob"}]}, {"name": "$pr.author", "value": "ann"}]));
}

#[test]
fn params_and_input_are_variables() {
    let report = ergo::report(
        &json!({"env": "prod", "items": [{"id": 1, "score": 7}]}),
        Some(&json!({"min": 5})),
        &json!({"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "cel", "expr": "input.env == 'prod' && self.score >= params.min"}}}}),
    );
    let row = report["results"].as_array().unwrap().iter().find(|r| r["check"] == "c").unwrap();
    assert_eq!(row["passed"], true);
    assert_eq!(row["inputs"], json!([{"name": "$$input.env", "value": "prod"}, {"name": "$$params.min", "value": 5}, {"name": "score", "value": 7}]));
}

#[test]
fn a_cel_check_written_wrong_fails_well_formed_and_says_why() {
    assert_eq!(well_formed_inputs("size(self.files) >="), json!([{"name": "count(checks)", "value": 1}, {"name": "require", "value": "every"}, {"name": "checks.c", "value": ["invalid expr"]}]));
    assert_eq!(well_formed_inputs("bogus.x == 1"), json!([{"name": "count(checks)", "value": 1}, {"name": "require", "value": "every"}, {"name": "checks.c", "value": ["unknown name bogus"]}]));
    assert_eq!(verdict(json!({"id": 1}), "bogus.x == 1"), (false, "ill_formed".into()));
}

#[test]
fn a_result_that_is_not_a_boolean_fails_as_unusable() {
    assert_eq!(verdict(json!({"id": 1, "n": 3}), "self.n + 1"), (false, "unusable".into()));
}

#[test]
fn a_cel_filter_cannot_rule_a_subject_out_on_a_missing_field() {
    let input = json!({"items": [{"id": 1}]});
    let requirements = json!({"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"prod": {"op": "cel", "expr": "self.env == 'prod'"}}, "checks": {"c": {"op": "present", "path": ["id"]}}}});
    let report = ergo::report(&input, None, &requirements);
    assert_eq!(report["requirements"]["s"]["status"], "not_met");
    let row = report["results"].as_array().unwrap().iter().find(|r| r["check"] == "$applies").unwrap();
    assert_eq!(row["cause"], "absent");
}
