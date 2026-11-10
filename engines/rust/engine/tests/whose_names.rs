use ergo_policy_engine::SPEC;
use serde_json::{Value, json};

fn messages(check: &str, input: Value) -> Vec<String> {
    let report = ergo_policy_engine::report(
        &input,
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"t": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "t", "checks": {"c": check}}}
        }),
        &json!({}),
    );
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["check"] == "c")
        .map(|row| row["message"].as_str().unwrap_or("").to_string())
        .collect()
}

fn subject_with_a_bad_list(row: Value) -> Value {
    json!({"things": [{"id": "x", "os": [{"name": "b"}, {}], "rows": [row]}]})
}

#[test]
fn a_name_on_the_right_of_a_whose_is_read_from_the_row_not_the_subject() {
    for check in [
        "count of rows whose v is in os.name is 1",
        "every rows whose v is in os.name is not empty",
        "some rows whose v is in os.name is not empty",
    ] {
        for (row, said) in [
            (json!({"v": "a"}), "item 1 of rows: os.name is missing"),
            (json!({"v": "a", "os": null}), "item 1 of rows: os is null"),
        ] {
            assert_eq!(
                messages(check, subject_with_a_bad_list(row.clone())),
                [said],
                "{check} on {row}"
            );
        }
    }
}
