use super::*;
use crate::policy::Policy;

fn policy(requirements: Value) -> Value {
    json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": requirements,
    })
}

fn report_of(policy: Value, params: Value) -> Value {
    let read = Policy::read(&policy);
    assemble(&read, &BTreeMap::new(), &BTreeMap::new(), &params)
}

fn row_of_check<'a>(report: &'a Value, requirement: &str, check: &str) -> &'a Value {
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["requirement"] == requirement && r["check"] == check)
        .unwrap()
}

fn row(requirement: &str, check: &str, cause: Cause) -> Row {
    Row {
        requirement: requirement.to_string(),
        subject_type: json!("thing"),
        subject_id: json!(1),
        subject_in: None,
        check: check.to_string(),
        cause,
        inputs: vec![input("x", json!(1), &["/t/0/x".to_string()])],
        message: None,
        failed_items: None,
        failed_assertions: None,
    }
}

fn requirement_of(value: Value) -> (Policy, Requirement) {
    let read = Policy::read(&policy(json!({"s": value})));
    let requirement = read.requirements["s"].clone();
    (read, requirement)
}

fn good() -> Value {
    json!({"subject": "thing", "checks": {"c": "x exists"}})
}

#[test]
fn a_row_prints_as_the_schema_wants() {
    let mut r = row("s", "c", Cause::Value);
    r.subject_in = Some(Map::from_iter([("artifact".to_string(), json!("sha-1"))]));
    r.failed_items = Some(json!([]));
    r.failed_assertions = Some(json!([{"assertion": "a", "cause": "value"}]));
    assert_eq!(
        r.to_json(),
        json!({
            "requirement": "s",
            "subject": {"type": "thing", "id": 1, "in": {"artifact": "sha-1"}},
            "check": "c",
            "passed": false,
            "cause": "value",
            "inputs": [{"name": "x", "value": 1, "locations": ["/t/0/x"]}],
            "failed_items": [],
            "failed_assertions": [{"assertion": "a", "cause": "value"}],
        })
    );
}

#[test]
fn a_row_passes_only_with_the_cause_satisfied() {
    assert!(row("s", "c", Cause::Satisfied).passed());
    for cause in [
        Cause::NotAnObject,
        Cause::Ambiguous,
        Cause::Unusable,
        Cause::Absent,
        Cause::Null,
        Cause::Value,
    ] {
        assert!(!row("s", "c", cause).passed());
    }
    assert_eq!(
        row("s", "c", Cause::Satisfied).to_json()["passed"],
        json!(true)
    );
}

#[test]
fn a_row_without_a_parent_has_no_in() {
    assert!(
        row("s", "c", Cause::Value).to_json()["subject"]
            .get("in")
            .is_none()
    );
    assert!(
        row("s", "c", Cause::Value)
            .to_json()
            .get("failed_items")
            .is_none()
    );
}

#[test]
fn a_requirement_written_right_has_a_satisfied_well_formed_row_of_count_and_require() {
    let (read, requirement) = requirement_of(good());
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    assert_eq!(
        well_formed.to_json(),
        json!({
            "requirement": "s",
            "subject": {"type": "thing", "id": null},
            "check": "$well_formed",
            "passed": true,
            "cause": "satisfied",
            "inputs": [
                {"name": "count(checks)", "value": 1, "locations": []},
                {"name": "require", "value": "every", "locations": []}
            ],
        })
    );
}

#[test]
fn well_formed_lists_count_and_require_then_field_problems_then_check_problems_sorted_by_name() {
    let (read, requirement) = requirement_of(json!({
        "subject": "thing",
        "checks": {"c": {"op": "x"}, "a": 5},
        "zz": 1,
        "aa": 2
    }));
    let row = well_formed_row(&read, "s", &requirement, None);
    let names: Vec<_> = row.inputs.iter().map(|i| i["name"].clone()).collect();
    assert_eq!(
        names,
        [
            "count(checks)",
            "require",
            "aa",
            "zz",
            "checks.a",
            "checks.c"
        ]
    );
    assert_eq!(row.cause, Cause::Value);
}

#[test]
fn a_wrong_require_stays_second_whatever_the_other_problems_are() {
    let (read, requirement) = requirement_of(json!({
        "subject": "thing",
        "require": "most",
        "checks": {"c": "x exists"},
        "aa": 1
    }));
    let row = well_formed_row(&read, "s", &requirement, None);
    assert_eq!(
        row.inputs,
        [
            input("count(checks)", json!(1), &[]),
            input("require", json!(["neither every nor some"]), &[]),
            input("aa", json!(["unknown field"]), &[]),
        ]
    );
}

#[test]
fn policy_problems_come_last_and_fail_every_requirement() {
    let mut p = policy(json!({"s": good(), "t": good()}));
    p["ergo_spec"] = json!(1);
    p["description"] = json!(5);
    p["meta"] = json!("m");
    p["requirements"]["t"]["zz"] = json!(1);
    let report = report_of(p, Value::Null);
    for name in ["s", "t"] {
        let row = row_of_check(&report, name, "$well_formed");
        assert_eq!(row["passed"], json!(false));
        let tail: Vec<_> = row["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .rev()
            .take(3)
            .map(|i| i["name"].as_str().unwrap().to_string())
            .collect();
        assert_eq!(
            tail,
            ["policy meta", "policy ergo_spec", "policy description"]
        );
    }
    let inputs = row_of_check(&report, "t", "$well_formed")["inputs"].clone();
    assert_eq!(
        inputs[2],
        json!({"name": "zz", "value": ["unknown field"], "locations": []})
    );
    assert_eq!(report["description"], json!(""));
    assert_eq!(report["meta"], json!({}));
}

#[test]
fn extra_problems_given_for_a_requirement_fail_its_well_formed_row_and_nothing_else() {
    let read = Policy::read(&policy(json!({"s": good(), "t": good()})));
    let mut extra = BTreeMap::new();
    let mut problems = Problems::new();
    crate::policy::add_problem(&mut problems, "checks.c".to_string(), "doesn't parse");
    extra.insert("s".to_string(), problems);
    let report = assemble(&read, &extra, &BTreeMap::new(), &Value::Null);
    let s = row_of_check(&report, "s", "$well_formed");
    assert_eq!(s["passed"], json!(false));
    assert_eq!(
        s["inputs"][2],
        json!({"name": "checks.c", "value": ["doesn't parse"], "locations": []})
    );
    assert_eq!(
        row_of_check(&report, "t", "$well_formed")["passed"],
        json!(true)
    );
    assert_eq!(report["requirements"]["s"]["status"], json!("not_met"));
}

#[test]
fn a_requirement_that_is_not_an_object_lists_what_was_written() {
    let report = report_of(policy(json!({"s": "x"})), Value::Null);
    let row = row_of_check(&report, "s", "$well_formed");
    assert_eq!(row["passed"], json!(false));
    assert_eq!(
        row["inputs"],
        json!([
            {"name": "count(checks)", "value": 0, "locations": []},
            {"name": "require", "value": "every", "locations": []},
            {"name": "requirement", "value": "x", "locations": []}
        ])
    );
    assert_eq!(row["subject"], json!({"type": "subject", "id": null}));
    assert_eq!(report["requirements"]["s"]["subject"], Value::Null);
}

#[test]
fn a_requirement_written_wrong_gets_only_its_well_formed_row() {
    let report = report_of(
        policy(
            json!({"bad": {"subject": "thing", "require": "most", "checks": {"c": "x exists"}}}),
        ),
        Value::Null,
    );
    let results = report["results"].as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["check"], json!("$well_formed"));
    let entry = &report["requirements"]["bad"];
    assert_eq!(entry["status"], json!("not_met"));
    assert_eq!(entry["subjects"], json!({"total": 0, "matching": 0}));
    assert_eq!(entry["require"], json!("most"));
    assert_eq!(entry["causes"], json!([{"cause": "value", "rows": 1}]));
    assert_eq!(report["compliant"], json!(false));
}

#[test]
fn a_written_wrong_requirement_still_lists_every_check_and_the_ones_ergo_adds() {
    let report = report_of(
        policy(json!({"s": {"subject": "thing", "checks": {"c": "x is \"a"}}})),
        Value::Null,
    );
    let checks = &report["requirements"]["s"]["checks"];
    let mut names: Vec<_> = checks.as_object().unwrap().keys().cloned().collect();
    names.sort();
    assert_eq!(names, ["$min_subjects", "$unique_ids", "$well_formed", "c"]);
    assert_eq!(checks["c"]["expression"], json!("x is \"a"));
    assert_eq!(
        checks["$well_formed"]["expression"],
        json!("count(problems) == 0")
    );
    assert_eq!(
        checks["$min_subjects"],
        json!({
            "description": "The in-scope thing count is at least 1",
            "expression": "count(matching(things)) >= 1",
            "meta": {}
        })
    );
    assert_eq!(
        checks["$unique_ids"],
        json!({
            "description": "Every thing id is unique",
            "expression": "count(repeated(ids(things))) == 0",
            "meta": {}
        })
    );
}

#[test]
fn reserved_names_list_only_ergos_own_check() {
    let report = report_of(
        policy(json!({"s": {"subject": "thing", "checks": {
            "$well_formed": "x is 2", "$min_subjects": "x is 2", "$unique_ids": "x is 2", "$applies": "x is 2"
        }}})),
        Value::Null,
    );
    let checks = report["requirements"]["s"]["checks"].as_object().unwrap();
    let mut names: Vec<_> = checks.keys().cloned().collect();
    names.sort();
    assert_eq!(names, ["$min_subjects", "$unique_ids", "$well_formed"]);
    assert_eq!(
        checks["$well_formed"]["expression"],
        json!("count(problems) == 0")
    );
    let row = row_of_check(&report, "s", "$well_formed");
    assert_eq!(row["inputs"][0]["value"], json!(4));
}

#[test]
fn a_requirement_with_no_checks_says_empty() {
    let report = report_of(
        policy(json!({"s": {"subject": "thing", "checks": {}}})),
        Value::Null,
    );
    let row = row_of_check(&report, "s", "$well_formed");
    assert_eq!(
        row["inputs"],
        json!([
            {"name": "count(checks)", "value": 0, "locations": []},
            {"name": "require", "value": "every", "locations": []},
            {"name": "checks", "value": ["empty"], "locations": []}
        ])
    );
}

#[test]
fn a_requirement_with_no_subject_names_none_and_types_its_rows_subject() {
    let report = report_of(
        policy(json!({"s": {"checks": {"c": "x exists"}}})),
        Value::Null,
    );
    let row = row_of_check(&report, "s", "$well_formed");
    assert_eq!(row["subject"], json!({"type": "subject", "id": null}));
    assert_eq!(report["requirements"]["s"]["subject"], Value::Null);
    assert_eq!(
        report["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
        json!("count(matching(<invalid from>)) >= 1")
    );
    assert_eq!(report["subjects"], json!({}));
}

#[test]
fn a_subject_that_is_not_in_subjects_is_typed_as_written_and_named_null() {
    let report = report_of(
        policy(json!({"s": {"subject": "nope", "checks": {"c": "x exists"}}})),
        Value::Null,
    );
    assert_eq!(
        row_of_check(&report, "s", "$well_formed")["subject"]["type"],
        json!("nope")
    );
    assert_eq!(report["requirements"]["s"]["subject"], Value::Null);
    assert_eq!(
        row_of_check(&report, "s", "$well_formed")["inputs"][2],
        json!({"name": "subject", "value": ["not in subjects"], "locations": []})
    );
}

#[test]
fn requirements_come_in_name_order_in_each_group_of_rows() {
    let report = report_of(
        policy(json!({"b": good(), "a": good(), "B": good()})),
        Value::Null,
    );
    let order: Vec<_> = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            format!(
                "{}:{}",
                r["requirement"].as_str().unwrap(),
                r["check"].as_str().unwrap()
            )
        })
        .collect();
    assert_eq!(
        order,
        [
            "B:$well_formed",
            "a:$well_formed",
            "b:$well_formed",
            "B:$min_subjects",
            "a:$min_subjects",
            "b:$min_subjects",
            "B:$unique_ids",
            "a:$unique_ids",
            "b:$unique_ids",
        ]
    );
}

#[test]
fn a_requirement_the_stub_finds_nothing_for_fails_min_subjects_as_value() {
    let report = report_of(policy(json!({"s": good()})), Value::Null);
    let row = row_of_check(&report, "s", "$min_subjects");
    assert_eq!(row["cause"], json!("value"));
    assert_eq!(
        row["inputs"],
        json!([{"name": "in-scope thing count", "value": 0, "locations": []}])
    );
    assert_eq!(report["requirements"]["s"]["status"], json!("not_met"));
    assert_eq!(report["compliant"], json!(false));
}

#[test]
fn min_subjects_zero_with_nothing_found_is_not_applicable_and_describes_reading_the_list() {
    let report = report_of(
        policy(json!({"s": {"subject": "thing", "min_subjects": 0, "checks": {"c": "x exists"}}})),
        Value::Null,
    );
    assert_eq!(
        report["requirements"]["s"]["status"],
        json!("not_applicable")
    );
    assert_eq!(report["compliant"], json!(true));
    assert_eq!(
        report["requirements"]["s"]["checks"]["$min_subjects"],
        json!({"description": "The thing list can be read", "expression": "things can be read", "meta": {}})
    );
}

#[test]
fn params_that_are_not_an_object_fail_min_subjects_as_unusable_and_say_why() {
    for params in [json!("p"), json!([]), json!(1), json!(true)] {
        let report = report_of(
            policy(
                json!({"s": {"subject": "thing", "min_subjects": 0, "checks": {"c": "x exists"}}}),
            ),
            params,
        );
        let row = row_of_check(&report, "s", "$min_subjects");
        assert_eq!(row["cause"], json!("unusable"));
        assert_eq!(
            row["inputs"][1],
            json!({"name": "$params", "value": ["not an object"], "locations": []})
        );
        assert_eq!(report["requirements"]["s"]["status"], json!("not_met"));
    }
    for params in [Value::Null, json!({})] {
        assert!(unreadable_params(&params).is_empty());
    }
}

#[test]
fn a_policy_with_no_requirements_is_never_compliant() {
    let report = report_of(
        json!({"ergo_spec": SPEC, "subjects": {}, "requirements": {}}),
        Value::Null,
    );
    assert_eq!(report["compliant"], json!(false));
    assert_eq!(report["results"].as_array().unwrap().len(), 1);
    let report = report_of(json!(null), Value::Null);
    assert_eq!(report["compliant"], json!(false));
}

#[test]
fn a_policy_with_no_requirements_has_a_requirement_of_its_own_that_says_what_is_wrong() {
    let report = report_of(json!({"ergo_spec": "v9.9"}), Value::Null);
    let entry = &report["requirements"]["$policy"];
    assert_eq!(entry["subject"], json!("$policy"));
    assert_eq!(entry["status"], json!("not_met"));
    assert_eq!(entry["subjects"], json!({"total": 0, "matching": 0}));
    assert_eq!(report["subjects"], json!({}));
    let row = row_of_check(&report, "$policy", "$well_formed");
    assert_eq!(row["subject"], json!({"type": "$policy", "id": "$policy"}));
    assert_eq!(
        row["inputs"],
        json!([
            {"name": "policy ergo_spec", "value": [format!("unsupported version v9.9, expected {SPEC}")], "locations": []},
            {"name": "requirements", "value": ["missing"], "locations": []},
        ])
    );
    let listed = crate::violations(&report);
    assert_eq!(listed.as_array().unwrap().len(), 1);
    for (written, wanted) in [
        (json!({"requirements": {}}), "empty"),
        (json!({"requirements": []}), "not an object"),
        (json!({"requirements": null}), "missing"),
    ] {
        let report = report_of(written, Value::Null);
        let row = row_of_check(&report, "$policy", "$well_formed");
        let last = row["inputs"].as_array().unwrap().last().unwrap().clone();
        assert_eq!(last["value"], json!([wanted]));
    }
}

#[test]
fn a_policy_that_is_not_an_object_says_so_in_place_of_requirements() {
    let report = report_of(json!("x"), Value::Null);
    let row = row_of_check(&report, "$policy", "$well_formed");
    assert_eq!(
        row["inputs"],
        json!([{"name": "policy", "value": ["not an object"], "locations": []}])
    );
    let report = report_of(
        json!({"ergo_spec": SPEC, "requirements": [{"subject": "s", "checks": {"c": "x exists"}}]}),
        Value::Null,
    );
    assert_eq!(report["requirements"].as_object().unwrap().len(), 1);
    assert!(report["requirements"].get("$policy").is_some());
}

#[test]
fn a_policy_with_a_requirement_gets_no_requirement_of_its_own() {
    let report = report_of(policy(json!({"s": good()})), Value::Null);
    assert!(report["requirements"].get("$policy").is_none());
}

#[test]
fn a_name_that_starts_with_a_dollar_sign_is_written_wrong_wherever_it_stands() {
    let wrong = json!(["a name can't start with $"]);
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"$s": {"from": "xs"}, "t": {"from": "xs", "has": {"$p": "ys"}}},
        "requirements": {
            "$r": {"subject": "t", "checks": {"c": "x exists"}},
            "q": {"subject": "$s", "checks": {"c": "x exists"}},
            "o": {"subject": "t", "checks": {"c": {"any_of": {"$o": "x exists", "p": "x is 1"}}}},
            "k": {"subject": "t", "checks": {"$k": "x exists"}},
            "ok": {"subject": "t", "checks": {"a$b": "x exists"}},
        }
    });
    let report = report_of(policy, Value::Null);
    let inputs = |requirement: &str| -> Vec<Value> {
        row_of_check(&report, requirement, "$well_formed")["inputs"]
            .as_array()
            .unwrap()
            .clone()
    };
    assert!(
        inputs("$r")
            .iter()
            .any(|i| i["name"] == "requirement name" && i["value"] == wrong)
    );
    assert!(
        inputs("q")
            .iter()
            .any(|i| i["name"] == "subjects.$s" && i["value"] == wrong)
    );
    assert!(inputs("o").iter().any(|i| i["name"] == "checks.c"
        && i["value"] == json!(["option $o: a name can't start with $"])));
    assert!(
        inputs("k")
            .iter()
            .any(|i| i["name"] == "checks.$k" && i["value"] == wrong)
    );
    assert!(
        inputs("k")
            .iter()
            .any(|i| i["name"] == "subjects.t.has.$p" && i["value"] == wrong)
    );
    assert_eq!(
        row_of_check(&report, "ok", "$well_formed")["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|i| i["name"].as_str().is_some_and(|n| n.starts_with("checks.")))
            .count(),
        0
    );
}

#[test]
fn a_name_that_starts_or_ends_with_a_space_or_an_invisible_character_is_written_wrong_wherever_it_stands()
 {
    let wrong = "a name can't start or end with a space or an invisible character";
    for name in [" x", "x ", "\u{a0}x", "x\u{200b}", "\u{feff}x", "\tx"] {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {name: {"from": "xs"}, "u": {"from": "xs"}},
            "requirements": {
                name: {"subject": "u", "checks": {"c": "x exists"}},
                "q": {"subject": name, "checks": {"c": "x exists"}},
                "o": {"subject": "u", "checks": {"c": {"any_of": {name: "x exists", "p": "x is 1"}}}},
                "k": {"subject": "u", "checks": {name: "x exists"}},
            }
        });
        let report = report_of(policy, Value::Null);
        let has = |requirement: &str, matches: &dyn Fn(&Value) -> bool| {
            row_of_check(&report, requirement, "$well_formed")["inputs"]
                .as_array()
                .unwrap()
                .iter()
                .any(matches)
        };
        assert!(has(name, &|i| i["name"] == "requirement name"
            && i["value"] == json!([wrong])));
        assert!(has("q", &|i| i["value"] == json!([wrong])
            && i["name"]
                .as_str()
                .is_some_and(|n| n.starts_with("subjects."))));
        assert!(has("o", &|i| i["name"] == "checks.c"
            && i["value"] == json!([format!("option {name}: {wrong}")])));
        assert!(has("k", &|i| i["value"] == json!([wrong])
            && i["name"].as_str().is_some_and(|n| n.starts_with("checks."))));
        let parts = report_of(
            json!({
                "ergo_spec": SPEC,
                "subjects": {"t": {"from": "xs", "has": {name: "ys"}}},
                "requirements": {"h": {"subject": "t", "checks": {"c": "x exists"}}}
            }),
            Value::Null,
        );
        assert!(
            row_of_check(&parts, "h", "$well_formed")["inputs"]
                .as_array()
                .unwrap()
                .iter()
                .any(|i| i["value"] == json!([wrong])
                    && i["name"].as_str().is_some_and(|n| n.contains(".has.")))
        );
    }
}

#[test]
fn a_requirement_called_policy_is_written_wrong() {
    let report = report_of(policy(json!({"$policy": good()})), Value::Null);
    let row = row_of_check(&report, "$policy", "$well_formed");
    assert_eq!(row["passed"], json!(false));
    assert_eq!(
        row["inputs"][0],
        json!({"name": "requirement name", "value": ["a name can't start with $"], "locations": []})
    );
}

#[test]
fn the_report_names_the_spec_version_and_the_engine() {
    let report = report_of(policy(json!({"s": good()})), Value::Null);
    assert_eq!(report["ergo"], json!(SPEC));
    assert_eq!(
        report["engine"],
        json!({"name": "ergo-rust", "version": env!("CARGO_PKG_VERSION")})
    );
    assert_eq!(report["engine"].as_object().unwrap().len(), 2);
}

#[test]
fn requirement_description_and_meta_are_copied_or_default() {
    let report = report_of(
        policy(json!({
            "s": {"subject": "thing", "description": "Every thing is approved", "meta": {"control": "C-1", "v": 1.5},
                  "checks": {"c": {"assert": "x exists", "description": "Approved", "meta": {"k": 1}}}},
            "t": good()
        })),
        Value::Null,
    );
    assert_eq!(
        report["requirements"]["s"]["description"],
        json!("Every thing is approved")
    );
    assert_eq!(
        report["requirements"]["s"]["meta"],
        json!({"control": "C-1", "v": 1.5})
    );
    assert_eq!(
        report["requirements"]["s"]["checks"]["c"],
        json!({"description": "Approved", "expression": "x exists", "meta": {"k": 1}})
    );
    assert_eq!(report["requirements"]["t"]["description"], json!(""));
    assert_eq!(report["requirements"]["t"]["meta"], json!({}));
    assert_eq!(
        report["requirements"]["t"]["checks"]["c"]["meta"],
        json!({})
    );
}

#[test]
fn a_subject_with_a_filter_gets_an_applies_check_and_a_subject_with_none_does_not() {
    let mut p = policy(json!({"s": good()}));
    p["subjects"]["thing"]["from"] = json!("things whose e exists");
    let report = report_of(p, Value::Null);
    let checks = &report["requirements"]["s"]["checks"];
    assert_eq!(
        checks["$applies"],
        json!({"description": "The thing is in scope", "expression": "e exists", "meta": {}})
    );
    assert_eq!(
        checks["$min_subjects"]["expression"],
        json!("count(matching(things)) >= 1")
    );
    let plain = report_of(policy(json!({"s": good()})), Value::Null);
    assert!(
        plain["requirements"]["s"]["checks"]
            .get("$applies")
            .is_none()
    );
}

#[test]
fn a_subject_without_from_reads_the_field_named_like_it() {
    let mut p = policy(json!({"s": {"subject": "pull request", "checks": {"c": "x exists"}}}));
    p["subjects"] = json!({"pull request": null});
    let report = report_of(p, Value::Null);
    assert_eq!(
        report["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
        json!("count(matching(\"pull request\")) >= 1")
    );
    assert_eq!(
        report["requirements"]["s"]["checks"]["$min_subjects"]["description"],
        json!("The in-scope pull request count is at least 1")
    );
    assert_eq!(
        report["subjects"]["pull request"],
        json!({"description": "", "from": "\"pull request\"", "identified_by": null, "parts": {}})
    );
}

#[test]
fn a_from_that_is_not_a_string_prints_as_invalid() {
    let mut p = policy(json!({"s": good()}));
    p["subjects"]["thing"] = json!({"from": ["a"], "identified_by": ["id"]});
    let report = report_of(p, Value::Null);
    assert_eq!(report["subjects"]["thing"]["from"], json!("<invalid from>"));
    assert_eq!(
        report["subjects"]["thing"]["identified_by"],
        json!("<invalid identified_by>")
    );
    assert_eq!(
        report["requirements"]["s"]["checks"]["$unique_ids"]["expression"],
        json!("count(repeated(ids(<invalid from>))) == 0")
    );
}

fn subjects_of(subjects: Value, subject: &str) -> Value {
    let mut p = policy(json!({"s": {"subject": subject, "checks": {"c": "n exists"}}}));
    p["subjects"] = subjects;
    report_of(p, Value::Null)["subjects"].clone()
}

fn entry(from: &str, id: Option<&str>) -> Value {
    json!({"description": "", "from": from, "identified_by": id, "parts": {}})
}

#[test]
fn a_subject_with_applies_to_or_of_has_an_invalid_from() {
    let applies = subjects_of(
        json!({"d": {"from": "ds", "identified_by": "id", "applies_to": {"f": {"op": "present", "path": ["x"]}}}}),
        "d",
    );
    assert_eq!(applies["d"], entry("<invalid from>", Some("id")));
    let of = subjects_of(
        json!({"d": {"from": "ds", "identified_by": "id", "of": "ds"}}),
        "d",
    );
    assert_eq!(of["d"], entry("<invalid from>", Some("id")));
}

#[test]
fn a_subject_that_narrows_another_keeps_its_id_when_its_from_is_written_wrong() {
    for line in [
        "parent whose n is one of 1, \"a\"",
        "parent whose n is $foo",
        "every parent",
    ] {
        let found = subjects_of(
            json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": line}}),
            "kid",
        );
        assert_eq!(found["kid"], entry("<invalid from>", Some("id")), "{line}");
        assert_eq!(found["parent"], entry("things", Some("id")), "{line}");
    }
}

#[test]
fn a_subject_that_narrows_another_has_its_id_when_its_from_is_written_wrong_even_with_an_id_of_its_own()
 {
    for line in [
        "every parent",
        "parent whose n is 1",
        "parent whose n is one of 1, \"a\"",
    ] {
        let found = subjects_of(
            json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": line, "identified_by": "n"}}),
            "kid",
        );
        let from = if line == "parent whose n is 1" {
            line
        } else {
            "<invalid from>"
        };
        assert_eq!(found["kid"], entry(from, Some("id")), "{line}");
    }
}

#[test]
fn a_child_whose_from_has_an_unknown_name_lists_the_subject_it_starts_at() {
    let found = subjects_of(
        json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": "parent.items whose zz is $foo", "identified_by": "n"}}),
        "kid",
    );
    assert_eq!(found["kid"], entry("<invalid from>", Some("n")));
    assert_eq!(found["parent"], entry("things", Some("id")));
}

#[test]
fn every_on_a_subject_start_is_one_problem_under_from_and_none_under_identified_by() {
    let mut p = policy(json!({"r": {"subject": "kid", "checks": {"c": "n exists"}}}));
    p["subjects"] = json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": "every parent", "identified_by": "n"}});
    let reading = Reading::of(&Policy::read(&p));
    let problems = &reading.infos["kid"].problems;
    assert_eq!(problems.len(), 1);
    assert!(problems.contains_key("subjects.kid.from"));
}

#[test]
fn a_subject_entry_has_its_description_from_id_and_parts() {
    let mut p = policy(json!({"s": good()}));
    p["subjects"]["thing"] = json!({
        "description": "A thing",
        "from": "  things ",
        "identified_by": " id ",
        "has": {
            "a": "x.y",
            "b": {"from": " x ", "identified_by": "id"},
            "c": {"from": 5, "identified_by": 5},
            "d": 5,
            "e": {"identified_by": "id"}
        }
    });
    let report = report_of(p, Value::Null);
    assert_eq!(
        report["subjects"]["thing"],
        json!({
            "description": "A thing",
            "from": "things",
            "identified_by": "id",
            "parts": {
                "a": {"from": "x.y", "identified_by": null},
                "b": {"from": "x", "identified_by": "id"},
                "c": {"from": "<invalid from>", "identified_by": "<invalid identified_by>"},
                "d": {"from": "<invalid from>", "identified_by": null},
                "e": {"from": "<invalid from>", "identified_by": "id"}
            }
        })
    );
}

#[test]
fn a_subject_that_is_written_wrong_still_has_its_entry_and_one_no_requirement_uses_has_none() {
    let mut p = policy(json!({"s": good()}));
    p["subjects"] = json!({"thing": "x", "other": {"from": "t"}});
    let report = report_of(p, Value::Null);
    assert_eq!(
        report["subjects"],
        json!({"thing": {"description": "", "from": "<invalid from>", "identified_by": null, "parts": {}}})
    );
}

fn status_of(require: &str, groups: Vec<Vec<Cause>>, matching: u64) -> &'static str {
    let (_, requirement) = requirement_of(
        json!({"subject": "thing", "require": require, "checks": {"c": "x exists"}}),
    );
    let (read, _) = requirement_of(good());
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    let evaluation = Evaluation {
        total: matching,
        matching,
        min_subjects: vec![row("s", "$min_subjects", Cause::Satisfied)],
        unique_ids: vec![row("s", "$unique_ids", Cause::Satisfied)],
        unique_ancestor_ids: Vec::new(),
        applies: Vec::new(),
        subject_rows: groups
            .into_iter()
            .map(|g| g.into_iter().map(|c| row("s", "c", c)).collect())
            .collect(),
    };
    status(&requirement, &well_formed, &evaluation)
}

#[test]
fn every_needs_every_subject_to_pass_every_check() {
    use Cause::*;
    assert_eq!(
        status_of(
            "every",
            vec![vec![Satisfied, Satisfied], vec![Satisfied]],
            2
        ),
        "met"
    );
    assert_eq!(
        status_of("every", vec![vec![Satisfied, Value], vec![Satisfied]], 2),
        "not_met"
    );
    assert_eq!(status_of("every", vec![vec![Absent]], 1), "not_met");
}

#[test]
fn some_needs_one_subject_to_pass_every_check_by_itself() {
    use Cause::*;
    assert_eq!(
        status_of(
            "some",
            vec![vec![Satisfied, Value], vec![Value, Satisfied]],
            2
        ),
        "not_met"
    );
    assert_eq!(
        status_of(
            "some",
            vec![vec![Satisfied, Value], vec![Satisfied, Satisfied]],
            2
        ),
        "met"
    );
}

#[test]
fn a_requirement_that_would_be_met_with_no_subject_in_scope_is_not_applicable() {
    assert_eq!(status_of("every", vec![], 0), "not_applicable");
    assert_eq!(status_of("some", vec![], 0), "not_applicable");
}

fn status_with(min: Cause, unique: Cause, applies: &[Cause]) -> &'static str {
    let (read, requirement) = requirement_of(good());
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    let evaluation = Evaluation {
        total: 1,
        matching: 1,
        min_subjects: vec![row("s", "$min_subjects", min)],
        unique_ids: vec![row("s", "$unique_ids", unique)],
        unique_ancestor_ids: Vec::new(),
        applies: applies.iter().map(|c| row("s", "$applies", *c)).collect(),
        subject_rows: vec![vec![row("s", "c", Cause::Satisfied)]],
    };
    status(&requirement, &well_formed, &evaluation)
}

#[test]
fn min_subjects_unique_ids_and_unreadable_filters_make_a_requirement_not_met() {
    use Cause::*;
    assert_eq!(
        status_with(Satisfied, Satisfied, &[Satisfied, Value]),
        "met"
    );
    assert_eq!(status_with(Value, Satisfied, &[]), "not_met");
    assert_eq!(status_with(Satisfied, Value, &[]), "not_met");
    for cause in [Absent, Null, Unusable, NotAnObject, Ambiguous] {
        assert_eq!(status_with(Satisfied, Satisfied, &[cause]), "not_met");
    }
}

#[test]
fn a_requirement_that_is_written_wrong_is_not_met_whatever_it_evaluated_to() {
    let (read, requirement) =
        requirement_of(json!({"subject": "thing", "require": "x", "checks": {"c": "x exists"}}));
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    let evaluation = Evaluation {
        total: 1,
        matching: 1,
        ..Evaluation::default()
    };
    assert_eq!(status(&requirement, &well_formed, &evaluation), "not_met");
}

#[test]
fn causes_count_the_rows_that_would_be_violations_worst_first() {
    let (read, requirement) = requirement_of(good());
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    let evaluation = Evaluation {
        total: 3,
        matching: 2,
        min_subjects: vec![row("s", "$min_subjects", Cause::Satisfied)],
        unique_ids: vec![row("s", "$unique_ids", Cause::Satisfied)],
        unique_ancestor_ids: Vec::new(),
        applies: vec![
            row("s", "$applies", Cause::Value),
            row("s", "$applies", Cause::Absent),
        ],
        subject_rows: vec![
            vec![row("s", "c", Cause::Value), row("s", "d", Cause::Satisfied)],
            vec![row("s", "c", Cause::Value), row("s", "d", Cause::Absent)],
        ],
    };
    assert_eq!(
        causes("not_met", &requirement, &well_formed, &evaluation),
        json!([{"cause": "absent", "rows": 2}, {"cause": "value", "rows": 2}])
    );
    assert_eq!(
        causes("met", &requirement, &well_formed, &evaluation),
        json!([])
    );
    assert_eq!(
        causes("not_applicable", &requirement, &well_formed, &evaluation),
        json!([])
    );
}

fn child_row(check: &str, parent: &str, cause: Cause) -> Row {
    let mut r = row("s", check, cause);
    r.subject_in = Some(Map::from_iter([("p".to_string(), json!(parent))]));
    r
}

#[test]
fn some_on_child_subjects_is_decided_under_each_parent() {
    let (read, requirement) =
        requirement_of(json!({"subject": "thing", "require": "some", "checks": {"c": "x exists"}}));
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    let mut evaluation = Evaluation {
        total: 3,
        matching: 3,
        subject_rows: vec![
            vec![child_row("c", "p1", Cause::Satisfied)],
            vec![child_row("c", "p1", Cause::Absent)],
            vec![child_row("c", "p2", Cause::Absent)],
        ],
        ..Evaluation::default()
    };
    assert_eq!(status(&requirement, &well_formed, &evaluation), "not_met");
    assert_eq!(
        causes("not_met", &requirement, &well_formed, &evaluation),
        json!([{"cause": "absent", "rows": 1}])
    );
    evaluation.subject_rows[2] = vec![child_row("c", "p2", Cause::Satisfied)];
    assert_eq!(status(&requirement, &well_formed, &evaluation), "met");
}

#[test]
fn some_on_child_subjects_groups_parent_ids_1_and_1_0_together() {
    let (read, requirement) =
        requirement_of(json!({"subject": "thing", "require": "some", "checks": {"c": "x exists"}}));
    let well_formed = well_formed_row(&read, "s", &requirement, None);
    let mut one = child_row("c", "p", Cause::Satisfied);
    one.subject_in = Some(Map::from_iter([(
        "p".to_string(),
        serde_json::from_str("1").unwrap(),
    )]));
    let mut one_point_zero = child_row("c", "p", Cause::Absent);
    one_point_zero.subject_in = Some(Map::from_iter([(
        "p".to_string(),
        serde_json::from_str("1.0").unwrap(),
    )]));
    let evaluation = Evaluation {
        total: 2,
        matching: 2,
        subject_rows: vec![vec![one], vec![one_point_zero]],
        ..Evaluation::default()
    };
    assert_eq!(status(&requirement, &well_formed, &evaluation), "met");
}

fn full_report() -> Value {
    let (read, requirement) = requirement_of(json!({
        "subject": "thing",
        "checks": {"c": "every cs.v is in $params.ok", "d": "x exists"}
    }));
    let mut defs = json!({});
    let report_defs = check_defs(
        &Reading::of(&read),
        &read,
        &requirement,
        &Problems::new(),
        &Value::Null,
        &Value::Null,
    );
    for (name, def) in report_defs {
        defs[name] = def.to_json();
    }
    defs["c"]["$refs"] = json!([input(
        "$params.ok",
        json!(["a"]),
        &["$params:/ok".to_string()]
    )]);
    let failed = |name: &str, passed: bool| {
        let cause = if passed { "satisfied" } else { "value" };
        json!({
            "requirement": name,
            "subject": {"type": "thing", "id": 1},
            "check": "c",
            "passed": passed,
            "cause": cause,
            "inputs": [input("cs[].v", json!(["z"]), &["/t/0/cs/0/v".to_string()])],
            "failed_items": [{"path": "cs[0].v", "item": "item 1 of cs", "cause": "value", "value": "z", "locations": ["/t/0/cs/0/v"]}],
        })
    };
    json!({
        "requirements": {
            "s": {"status": "not_met", "checks": defs},
            "holds": {"status": "met", "checks": defs},
            "na": {"status": "not_applicable", "checks": defs},
        },
        "results": [
            failed("s", false),
            failed("s", true),
            failed("holds", false),
            failed("na", false),
            {"requirement": "s", "subject": {"type": "thing", "id": 2}, "check": "$applies", "passed": false, "cause": "value", "inputs": []},
            {"requirement": "s", "subject": {"type": "thing", "id": 3}, "check": "$applies", "passed": false, "cause": "absent", "inputs": []},
        ],
    })
}

#[test]
fn violations_are_the_failed_rows_of_requirements_that_are_not_met() {
    let violations = violations(&full_report());
    let list = violations.as_array().unwrap();
    assert_eq!(list.len(), 2);
    assert_eq!(list[0]["requirement"], json!("s"));
    assert_eq!(list[0]["check"], json!("c"));
    assert_eq!(list[1]["check"], json!("$applies"));
    assert_eq!(list[1]["cause"], json!("absent"));
}

#[test]
fn a_violation_adds_description_expression_and_refs_at_the_end_of_its_inputs() {
    let violations = violations(&full_report());
    let first = &violations[0];
    assert_eq!(first["description"], json!(""));
    assert_eq!(first["expression"], json!("every cs.v is in $params.ok"));
    assert_eq!(
        first["inputs"],
        json!([
            {"name": "cs[].v", "value": ["z"], "locations": ["/t/0/cs/0/v"]},
            {"name": "$params.ok", "value": ["a"], "locations": ["$params:/ok"]}
        ])
    );
    assert_eq!(first["failed_items"][0]["path"], json!("cs[0].v"));
    assert!(first.get("passed").is_none());
    assert!(first.get("failed_assertions").is_none());
    assert_eq!(first["subject"], json!({"type": "thing", "id": 1}));
}

#[test]
fn a_violation_lists_a_ref_once_when_its_row_lists_it_already() {
    let report = crate::report(
        &json!({"things": [{"id": "t", "x": "z"}]}),
        &json!({
            "ergo_spec": crate::SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x is in $params.k"}}}
        }),
        &json!({"k": ["a"]}),
    );
    assert_eq!(
        violations(&report)[0]["inputs"],
        json!([
            {"name": "x", "value": "z", "locations": ["/things/0/x"]},
            {"name": "$params.k", "value": ["a"], "locations": ["$params:/k"]}
        ])
    );
}

#[test]
fn every_count_and_for_rows_list_a_ref_after_a_list_phrase_as_is_at_least_lists_its_right_side() {
    let report = crate::report(
        &json!({"things": [{"id": "t", "xs": [{"n": 1}]}], "l": [2], "z": 5}),
        &json!({
            "ergo_spec": crate::SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {
                "every_in": "every xs.n is in $input.l",
                "every_least": "every xs.n is at least $input.z",
                "every_params": "every xs.n is in $params.l",
                "count_in": "count of xs whose n is in $input.l is 1",
                "count_least": "count of xs whose n is at least $input.z is 1",
                "for_in": {"for": "every xs as x", "assert": "x.n is in $params.l"},
                "for_least": {"for": "every xs as x", "assert": "x.n is at least $params.z"}
            }}}
        }),
        &json!({"l": [2], "z": 5}),
    );
    let names = |check: &str| -> Vec<String> {
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == check)
            .unwrap()["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|input| input["name"].as_str().unwrap().to_string())
            .collect()
    };
    assert_eq!(names("every_in"), ["$input.l", "xs[].n"]);
    assert_eq!(names("every_least"), ["$input.z", "xs[].n"]);
    assert_eq!(names("every_params"), ["xs[].n"]);
    assert_eq!(
        names("count_in"),
        ["count of xs whose n is in $input.l", "xs[]", "$input.l"]
    );
    assert_eq!(
        names("count_least"),
        [
            "count of xs whose n is at least $input.z",
            "xs[]",
            "$input.z"
        ]
    );
    assert_eq!(names("for_in"), ["$params.l", "xs[]"]);
    assert_eq!(names("for_least"), ["$params.z", "xs[]"]);
}

#[test]
fn a_violation_of_an_added_check_has_the_description_ergo_gave_it() {
    let report = report_of(policy(json!({"s": good()})), Value::Null);
    let list = violations(&report);
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["check"], json!("$min_subjects"));
    assert_eq!(
        list[0]["description"],
        json!("The in-scope thing count is at least 1")
    );
    assert_eq!(list[0]["expression"], json!("count(matching(things)) >= 1"));
    assert_eq!(list[0]["cause"], json!("value"));
}

#[test]
fn violations_of_a_requirement_written_wrong_are_its_well_formed_row() {
    let report = report_of(
        policy(json!({"s": {"subject": "thing", "checks": {"c": "x is \"a"}, "zz": 1}})),
        Value::Null,
    );
    let list = violations(&report);
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["check"], json!("$well_formed"));
    assert_eq!(list[0]["expression"], json!("count(problems) == 0"));
    assert_eq!(list[0]["inputs"][2]["name"], json!("zz"));
}

#[test]
fn violations_fail_closed_on_a_report_that_lacks_a_requirement_entry() {
    let report = json!({"results": [
        {"requirement": "s", "subject": {"type": "t", "id": null}, "check": "c", "passed": false, "cause": "value", "inputs": []},
        {"requirement": "s", "subject": {"type": "t", "id": null}, "check": "c", "passed": true, "cause": "satisfied", "inputs": []},
    ]});
    let list = violations(&report);
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["description"], json!(""));
    assert_eq!(list[0]["expression"], json!(""));
    assert_eq!(violations(&json!({})), json!([]));
    assert_eq!(violations(&json!(null)), json!([]));
}

#[test]
fn a_violation_keeps_failed_assertions() {
    let report = json!({
        "requirements": {"s": {"status": "not_met", "checks": {"c": {"description": "d", "expression": "e"}}}},
        "results": [{"requirement": "s", "subject": {"type": "t", "id": 1}, "check": "c", "passed": false, "cause": "value", "inputs": [],
                     "failed_assertions": [{"assertion": "a", "cause": "value"}]}],
    });
    assert_eq!(
        violations(&report)[0]["failed_assertions"],
        json!([{"assertion": "a", "cause": "value"}])
    );
}

#[test]
fn the_unique_ids_row_lists_the_repeated_ids() {
    let (_, requirement) = requirement_of(good());
    let ok = unique_ids_row("s", &requirement, vec![], &[]);
    assert_eq!(ok.cause, Cause::Satisfied);
    let bad = unique_ids_row(
        "s",
        &requirement,
        vec![json!("b"), json!(10)],
        &["/t/0/id".to_string()],
    );
    assert_eq!(bad.cause, Cause::Value);
    assert_eq!(
        bad.inputs,
        [input(
            "repeated thing ids",
            json!(["b", 10]),
            &["/t/0/id".to_string()]
        )]
    );
}

#[test]
fn the_min_subjects_row_passes_at_the_minimum_and_fails_with_the_cause_it_is_given() {
    let (_, requirement) =
        requirement_of(json!({"subject": "thing", "min_subjects": 2, "checks": {"c": "x exists"}}));
    assert_eq!(
        min_subjects_row("s", &requirement, 2, &[], None, vec![]).cause,
        Cause::Satisfied
    );
    assert_eq!(
        min_subjects_row("s", &requirement, 1, &[], None, vec![]).cause,
        Cause::Value
    );
    assert_eq!(
        min_subjects_row("s", &requirement, 5, &[], Some(Cause::Absent), vec![]).cause,
        Cause::Absent
    );
}

#[test]
fn written_expressions_follow_what_was_written() {
    let expression = |check: Value| {
        written_expression(
            &crate::policy::Policy::read(&policy(
                json!({"s": {"subject": "thing", "checks": {"c": check}}}),
            ))
            .requirements["s"]
                .checks["c"],
        )
    };
    assert_eq!(expression(json!("  x exists ")), "x exists");
    assert_eq!(expression(json!({"assert": ["a ", " b"]})), "a and b");
    assert_eq!(expression(json!({"assert": []})), "");
    assert_eq!(expression(json!({"assert": 5})), "<invalid assert>");
    assert_eq!(
        expression(json!({"assert": ["a", 5]})),
        "a and <invalid assert>"
    );
    assert_eq!(expression(json!({"op": "present"})), "<missing assert>");
    assert_eq!(expression(json!(5)), "<invalid check>");
    assert_eq!(expression(json!({"any_of": 5})), "<invalid any_of>");
    assert_eq!(expression(json!({"any_of": {}})), "one of: <empty options>");
    assert_eq!(
        expression(json!({"any_of": {"b": ["y", "z"], "a": "x", "c": [], "d": 5}})),
        "one of: a(x) | b(y and z) | c(<empty option>) | d(<invalid option>)"
    );
}

#[test]
fn field_name_keys_are_what_the_well_formed_row_names() {
    let (read, requirement) = requirement_of(json!({"subject": "thing", "checks": {"a b": 5}}));
    let row = well_formed_row(&read, "s", &requirement, None);
    assert_eq!(row.inputs[2]["name"], json!("checks.\"a b\""));
}

#[test]
fn the_spec_is_written_as_v_digits_dot_digits_with_an_optional_dev() {
    let version = SPEC.strip_prefix('v').unwrap();
    let version = version.strip_suffix("-dev").unwrap_or(version);
    let (major, minor) = version.split_once('.').unwrap();
    for part in [major, minor] {
        assert!(!part.is_empty() && part.chars().all(|c| c.is_ascii_digit()));
    }
}

#[test]
fn the_engine_is_named_ergo_rust() {
    assert_eq!(engine()["name"], json!("ergo-rust"));
}

#[test]
fn a_ref_through_a_list_of_params_points_at_where_the_read_stopped() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"s": {"subject": "thing", "checks": {
            "c": "x is in $params[0].v",
            "d": "x is in $params[0]"
        }}}
    });
    let report = crate::report(
        &json!({"things": [{"id": "t", "x": 1}]}),
        &policy,
        &json!([[1]]),
    );
    let checks = &report["requirements"]["s"]["checks"];
    assert_eq!(
        checks["c"]["$refs"],
        json!([{"name": "$params[0].v", "value": null, "locations": ["$params:/0"]}])
    );
    assert_eq!(
        checks["d"]["$refs"],
        json!([{"name": "item 1 of $params", "value": [1], "locations": ["$params:/0"]}])
    );
}
