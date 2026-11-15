use serde_json::{Value, json};

#[test]
fn params_that_arent_an_object_come_before_a_list_input_in_every_check_that_reads_both() {
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
    let both = r#"$params is 3, which isn't an object; $input is [{"id": "t", "k": "a", "n": 1, "rs": [{"n": 1, "v": "a"}], "v": "a"}], which isn't an object"#;
    for check in [
        "count_plus",
        "sum_plus",
        "plus",
        "plain",
        "every",
        "some_whose",
        "for_count_plus",
    ] {
        assert_eq!(said(check), json!(["unusable", both]), "{check}");
    }
}

#[test]
fn a_message_with_params_that_arent_an_object_drops_the_lines_about_missing_params_and_a_count_that_may_hold_them()
 {
    let natural = "$params.k is missing; item 1 of es: v: $params.k is missing; item 2 of es: $params.a is missing, and v is missing; and 1 more";
    assert_eq!(
        super::params_said_first(&json!(3), &[], &[natural.to_string()]),
        "$params is 3, which isn't an object; item 2 of es: v is missing"
    );
    assert_eq!(
        super::params_said_first(
            &json!(3),
            &["the check is false; zz is \"v\", which isn't a list, and $params is 3, which isn't a list".to_string()],
            &[]
        ),
        "$params is 3, which isn't a list; zz is \"v\", which isn't a list"
    );
}
