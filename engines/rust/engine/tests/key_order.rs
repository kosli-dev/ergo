use serde_json::Value;

fn read(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

const POLICY: &str = r#"{
    "ergo_spec": "v0.4-dev",
    "description": "keys in one order",
    "meta": {"owner": "ops", "area": "release"},
    "subjects": {
        "thing": {"from": "things whose kind exists", "identified_by": "id", "has": {"m": "meta", "n": {"from": "notes", "identified_by": "id"}}},
        "other": {"from": "others", "identified_by": "id"}
    },
    "requirements": {
        "r1": {
            "subject": "thing",
            "description": "first",
            "meta": {"z": 1, "a": 2},
            "checks": {
                "c2": "x is at least $params.min",
                "c1": {"any_of": {"b": "y exists", "a": ["x is 1", "m.k exists"]}},
                "c3": {"assert": ["x exists", "y exists"], "description": "both"}
            }
        },
        "r0": {"subject": "other", "require": "some", "min_subjects": 0, "checks": {"k": "kind exists"}}
    }
}"#;

const POLICY_REORDERED: &str = r#"{
    "requirements": {
        "r0": {"checks": {"k": "kind exists"}, "min_subjects": 0, "require": "some", "subject": "other"},
        "r1": {
            "checks": {
                "c3": {"description": "both", "assert": ["x exists", "y exists"]},
                "c1": {"any_of": {"a": ["x is 1", "m.k exists"], "b": "y exists"}},
                "c2": "x is at least $params.min"
            },
            "meta": {"a": 2, "z": 1},
            "description": "first",
            "subject": "thing"
        }
    },
    "subjects": {
        "other": {"identified_by": "id", "from": "others"},
        "thing": {"has": {"n": {"identified_by": "id", "from": "notes"}, "m": "meta"}, "identified_by": "id", "from": "things whose kind exists"}
    },
    "meta": {"area": "release", "owner": "ops"},
    "description": "keys in one order",
    "ergo_spec": "v0.4-dev"
}"#;

const INPUT: &str = r#"{
    "things": [
        {"id": "t1", "kind": "a", "x": 1, "y": 2, "meta": {"k": 1, "j": 2}, "notes": {"id": "n1", "b": 1, "a": 2}},
        {"id": "t2", "kind": "b", "x": 5, "meta": {"j": 1}},
        {"id": "t3", "x": 0}
    ],
    "others": [{"id": "o1", "kind": "k"}, {"id": "o2"}]
}"#;

const INPUT_REORDERED: &str = r#"{
    "others": [{"id": "o1", "kind": "k"}, {"id": "o2"}],
    "things": [
        {"notes": {"a": 2, "b": 1, "id": "n1"}, "meta": {"j": 2, "k": 1}, "y": 2, "x": 1, "kind": "a", "id": "t1"},
        {"meta": {"j": 1}, "x": 5, "kind": "b", "id": "t2"},
        {"x": 0, "id": "t3"}
    ]
}"#;

const PARAMS: &str = r#"{"min": 2, "max": 9}"#;

const PARAMS_REORDERED: &str = r#"{"max": 9, "min": 2}"#;

#[test]
fn the_report_is_byte_identical_whatever_order_the_keys_of_the_policy_input_and_params_are_written_in()
 {
    let first = ergo_policy_engine::report(&read(INPUT), &read(POLICY), &read(PARAMS));
    let second = ergo_policy_engine::report(
        &read(INPUT_REORDERED),
        &read(POLICY_REORDERED),
        &read(PARAMS_REORDERED),
    );
    assert_eq!(first.to_string(), second.to_string());
    assert_eq!(
        ergo_policy_engine::violations(&first).to_string(),
        ergo_policy_engine::violations(&second).to_string()
    );
}

#[test]
fn the_report_of_the_key_order_policy_runs_its_checks_rather_than_failing_them_as_written_wrong() {
    let report = ergo_policy_engine::report(&read(INPUT), &read(POLICY), &read(PARAMS));
    let results = report["results"].as_array().unwrap();
    assert!(
        results
            .iter()
            .all(|row| row["check"] != "$well_formed" || row["passed"] == true)
    );
    let checks: Vec<&str> = results
        .iter()
        .filter_map(|row| row["check"].as_str())
        .filter(|check| !check.starts_with('$'))
        .collect();
    assert!(checks.contains(&"c1") && checks.contains(&"c2") && checks.contains(&"c3"));
}
