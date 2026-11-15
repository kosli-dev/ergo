use serde_json::{Value, json};

#[test]
fn params_that_arent_an_object_follow_a_list_input_only_in_a_count_of_a_sum_of_or_a_plus() {
    let input = json!([{"id": "t", "k": "a", "n": 1, "v": "a", "rs": [{"v": "a", "n": 1}]}]);
    let checks = json!({
        "count_plus": "count of rs is n plus $params.q named by $input.k",
        "sum_plus": "sum of rs.n plus $params.q named by $input.k is 1",
        "plus": "n plus $params.q named by $input.k is 2",
        "plain": "v is $params.m named by $input.k",
        "every": "every rs.v is $params.m named by $input.k",
        "some_whose": "some rs whose v is $params.m named by $input.k exists",
        "for_count_plus": {"for": "every rs as r", "assert": "count of rs is r.n plus $params.q named by $input.k"},
    });
    let policy = json!({
        "ergo_spec": crate::SPEC,
        "subjects": {"t": {"from": "$input", "identified_by": "id"}},
        "requirements": {"r": {"subject": "t", "checks": checks}},
    });
    let report = crate::report(&input, &policy, &json!(3));
    let said = |check: &str| -> Value {
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["check"] == check)
            .map(|r| json!([r["cause"], r["message"]]))
            .unwrap()
    };
    let both = r#"$input is [{"id": "t", "k": "a", "n": 1, "rs": [{"n": 1, "v": "a"}], "v": "a"}], which isn't an object, and $params is 3, which isn't an object"#;
    for check in ["count_plus", "sum_plus", "plus"] {
        assert_eq!(said(check), json!(["unusable", both]), "{check}");
    }
    for check in ["plain", "every", "some_whose", "for_count_plus"] {
        assert_eq!(
            said(check),
            json!(["unusable", "$params is 3, which isn't an object"]),
            "{check}"
        );
    }
}
