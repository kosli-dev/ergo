use serde_json::{Value, json};

fn report(name: &str, from: &str) -> Value {
    ergo_policy_engine::report(
        &json!({"ws": ["bay", "apple"], "items": [{"kind": "a"}, "x"]}),
        &json!({
            "ergo_spec": "v0.5-dev",
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
