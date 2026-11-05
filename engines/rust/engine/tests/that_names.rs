use serde_json::{Value, json};

fn report(name: &str, from: &str) -> Value {
    ergo_policy_engine::report(
        &json!({"ws": ["bay", "apple"], "items": [{"kind": "a"}, "x"]}),
        &json!({
            "ergo_spec": "v0.5",
            "subjects": {name: {"from": from}},
            "requirements": {"r": {"subject": name, "checks": {"c": "it is not empty"}}}
        }),
        &json!({}),
    )
}

fn expression(name: &str, from: &str) -> String {
    report(name, from)["requirements"]["r"]["checks"]["$applies"]["expression"]
        .as_str()
        .unwrap()
        .to_string()
}

#[test]
fn the_expression_spells_the_name_as_a_check_has_to_write_it() {
    let from = "every ws that starts with \"b\"";
    assert_eq!(expression("w", from), "w starts with \"b\"");
    assert_eq!(expression("my w", from), "\"my w\" starts with \"b\"");
    assert_eq!(expression("item", from), "\"item\" starts with \"b\"");
    assert_eq!(expression("that", from), "\"that\" starts with \"b\"");
}

#[test]
fn the_row_names_the_item_by_the_plain_subject_name() {
    for name in ["my w", "item", "that"] {
        let report = report(name, "every ws that starts with \"b\"");
        let apple = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "$applies" && row["cause"] == "value")
            .unwrap();
        assert_eq!(apple["inputs"][0]["name"], name);
        assert_eq!(apple["message"], format!("{name} is \"apple\""));
    }
}

#[test]
fn a_subject_named_like_a_field_its_whose_reads_lists_the_field_and_the_item_apart() {
    let report = ergo_policy_engine::report(
        &json!({"ws": [null]}),
        &json!({
            "ergo_spec": "v0.5",
            "subjects": {"x": {"from": "every ws whose x is 1 and that is not empty"}},
            "requirements": {"r": {"subject": "x", "checks": {"c": "it is not empty"}}}
        }),
        &json!({}),
    );
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "$applies")
        .unwrap();
    assert_eq!(
        row["inputs"],
        json!([
            {"name": ".x", "value": null, "locations": ["/ws/0"]},
            {"name": "x", "value": null, "locations": ["/ws/0"]}
        ])
    );
}

#[test]
fn a_subject_named_with_a_dollar_sign_gets_only_the_name_problem() {
    for name in ["$w", "$input"] {
        let report = report(name, "every ws that is not empty");
        let row = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "$well_formed")
            .unwrap();
        let problems: Vec<&Value> = row["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|input| input["name"].as_str().unwrap().starts_with("subjects."))
            .collect();
        assert_eq!(
            problems,
            vec![
                &json!({"name": format!("subjects.{name}"), "value": ["a name can't start with $"], "locations": []})
            ]
        );
    }
}
