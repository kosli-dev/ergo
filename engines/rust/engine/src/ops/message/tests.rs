use serde_json::{Value, json};

#[test]
fn a_clause_an_earlier_sentence_gave_is_left_out_and_the_rest_is_kept() {
    let mut said: Vec<String> = Vec::new();
    assert_eq!(
        super::unsaid("expires_at is missing", &mut said),
        "expires_at is missing"
    );
    assert_eq!(
        super::unsaid("expires_at is missing, and as_of is missing", &mut said),
        "as_of is missing"
    );
    assert_eq!(super::unsaid("as_of is missing", &mut said), "");
}

#[test]
fn a_clause_said_twice_by_one_sentence_stays_twice() {
    let mut said: Vec<String> = Vec::new();
    assert_eq!(
        super::unsaid("v is 2, and v is 2; w is 3", &mut said),
        "v is 2, and v is 2; w is 3"
    );
    assert_eq!(super::unsaid("v is 2, and z is 1", &mut said), "z is 1");
}

#[test]
fn a_separator_inside_a_quoted_value_doesnt_split_a_clause() {
    let mut said = vec!["b is missing".to_string()];
    assert_eq!(
        super::unsaid(r#"a is "x; b is missing", and b is missing"#, &mut said),
        r#"a is "x; b is missing""#
    );
}

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

fn compare_said(subject: Value, right: crate::ops::compare::Side) -> String {
    use crate::ops::compare::{Cmp, Compare, Ignoring, Side};
    use crate::path::{Located, Location, Path, Start, Step};
    let check = crate::ops::Check::Compare(Compare {
        left: Side::Path(Path {
            start: Start::Subject,
            steps: vec![Step::Key("x".to_string())],
        }),
        right,
        cmp: Cmp::Eq,
        within: None,
        ignoring: Some(Ignoring {
            case: true,
            spaces: true,
        }),
    });
    let input = json!({"things": [subject]});
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: std::collections::BTreeMap::new(),
    };
    let verdict = crate::ops::run(&check, &ctx);
    super::message(&check, &ctx, &verdict)
}

#[test]
fn is_ignoring_case_says_each_side_that_isnt_text() {
    use crate::ops::compare::Side;
    use crate::path::{Path, Start, Step};
    let y = || {
        Side::Path(Path {
            start: Start::Subject,
            steps: vec![Step::Key("y".to_string())],
        })
    };
    assert_eq!(
        compare_said(json!({"x": "a", "y": 3}), y()),
        "y is 3, which isn't text"
    );
    assert_eq!(
        compare_said(json!({"x": 3, "y": "a"}), y()),
        "x is 3, which isn't text"
    );
    assert_eq!(
        compare_said(json!({"x": [1], "y": true}), y()),
        "x is [1], which isn't text, and y is true, which isn't text"
    );
    assert_eq!(
        compare_said(json!({"x": 3}), Side::Value(json!("a"))),
        "x is 3, which isn't text"
    );
    assert_eq!(
        compare_said(json!({"x": "  Blocked "}), Side::Value(json!("done"))),
        "x is \"  Blocked \""
    );
}

fn in_said(subject: Value, list: Value) -> (crate::cause::Cause, String) {
    use crate::ops::compare::Ignoring;
    use crate::ops::lists::{In, Right};
    use crate::path::{Located, Location, Path, Start, Step};
    let key = |start: Start, name: &str| Path {
        start,
        steps: vec![Step::Key(name.to_string())],
    };
    let check = crate::ops::Check::In(In {
        path: key(Start::Subject, "x"),
        values: Right::Ref(key(Start::Params, "l")),
        not: false,
        ignoring: Some(Ignoring {
            case: true,
            spaces: false,
        }),
    });
    let input = json!({"things": [subject]});
    let params = json!({ "l": list });
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    let verdict = crate::ops::run(&check, &ctx);
    (verdict.cause, super::message(&check, &ctx, &verdict))
}

#[test]
fn is_in_ignoring_case_says_each_null_value_of_the_list_when_it_fails_as_null() {
    use crate::cause::Cause;
    assert_eq!(
        in_said(json!({"x": "bug"}), json!(["Bug", null, "a", null])),
        (
            Cause::Null,
            "item 2 of $params.l is null, and item 4 of $params.l is null".to_string()
        )
    );
    assert_eq!(
        in_said(json!({"x": null}), json!(["Bug", null])),
        (
            Cause::Null,
            "x is null, and item 2 of $params.l is null".to_string()
        )
    );
}

#[test]
fn an_option_line_of_is_in_ignoring_case_says_the_list_that_isnt_text_as_the_sentence_alone_does() {
    use crate::ops::compare::Ignoring;
    use crate::ops::lists::{In, Right};
    use crate::path::{Located, Location, Path, Start, Step};
    let key = |start: Start, name: &str| Path {
        start,
        steps: vec![Step::Key(name.to_string())],
    };
    let check = crate::ops::Check::In(In {
        path: key(Start::Subject, "x"),
        values: Right::Ref(key(Start::Params, "l")),
        not: false,
        ignoring: Some(Ignoring {
            case: false,
            spaces: true,
        }),
    });
    let params = json!({"l": ["a", null, 3, "Q"]});
    for subject in [
        json!({"x": " A "}),
        json!({"x": 3}),
        json!({}),
        json!({"x": null}),
    ] {
        let input = json!({"things": [subject]});
        let ctx = crate::path::Ctx {
            label: None,
            item_by_item: false,
            in_option: true,
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: Some(&params),
            aliases: std::collections::BTreeMap::new(),
        };
        let verdict = crate::ops::run(&check, &ctx);
        let line = super::option_line_text(&check, &ctx, None, &verdict);
        assert_eq!(line, super::message(&check, &ctx, &verdict), "{subject}");
        assert!(
            line.contains(
                "item 2 of $params.l is null, and item 3 of $params.l is 3, which isn't text"
            ),
            "{subject}: {line}"
        );
    }
}
