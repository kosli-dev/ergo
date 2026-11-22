use serde_json::{Value, json};

fn lowered(sentence: &str) -> super::Check {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap()
}

fn root_clauses_of(
    sentence: &str,
    subject: &Value,
    input: &Value,
    params: Option<&Value>,
) -> Vec<(String, String)> {
    root_clauses_in(
        &crate::lower::Scope::new(),
        sentence,
        (subject, input, params),
        &[],
    )
}

fn root_clauses_in(
    scope: &crate::lower::Scope,
    sentence: &str,
    (subject, input, params): (&Value, &Value, Option<&Value>),
    aliases: &[(&str, &Value)],
) -> Vec<(String, String)> {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    let whole = crate::lower::lower_assertion(&tree.assertions[0], scope).unwrap();
    let inside: Vec<&super::Check> = match &whole {
        super::Check::Walk(walk) => walk
            .whose
            .iter()
            .chain(std::iter::once(&*walk.check))
            .collect(),
        other => vec![other],
    };
    let located = crate::path::Located {
        value: subject,
        location: crate::path::Location::input_root().key("s"),
    };
    let mut named =
        std::collections::BTreeMap::from([(crate::path::OUTER.to_string(), located.clone())]);
    for (name, value) in aliases {
        named.insert(
            (*name).to_string(),
            crate::path::Located {
                value,
                location: crate::path::Location::input_root().key(name),
            },
        );
    }
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: located.clone(),
        input,
        params,
        aliases: named,
    };
    super::root_clauses(&inside, &ctx)
        .into_iter()
        .map(|clause| (clause.name, clause.text))
        .collect()
}

#[test]
fn root_clauses_say_a_key_and_the_value_before_it() {
    let subject = json!({"id": "t", "n": 1});
    let input = json!({});
    let params = json!({"q": "s"});
    let said = root_clauses_of(
        "n is $params.q named by $input.k",
        &subject,
        &input,
        Some(&params),
    );
    let text: Vec<&str> = said.iter().map(|(_, text)| text.as_str()).collect();
    assert_eq!(
        text.join("; "),
        r#"$params.q is "s", which isn't an object; $input.k is missing"#
    );
}

#[test]
fn a_root_whose_value_holds_a_semicolon_is_one_clause() {
    let subject = json!({"id": "t", "n": 1});
    let input = json!({});
    let params = json!({"q": "a; b"});
    let said = root_clauses_of(
        "n is $params.q named by $input.k",
        &subject,
        &input,
        Some(&params),
    );
    assert_eq!(
        said,
        vec![
            (
                "$params.q".to_string(),
                r#"$params.q is "a; b", which isn't an object"#.to_string()
            ),
            ("$input.k".to_string(), "$input.k is missing".to_string()),
        ]
    );
}

#[test]
fn root_clauses_say_every_key_that_cant_be_read_worst_first_then_by_name() {
    let subject = json!({"id": "t", "zz": "a", "m": {"a": "a"}, "v": "a"});
    let input = json!({"j": 3});
    let said = root_clauses_of(
        "every es whose zz is m named by $input.k and whose v is m named by $input.j, if any, exists",
        &subject,
        &input,
        None,
    );
    assert_eq!(
        said,
        vec![
            (
                "$input.j".to_string(),
                "$input.j is 3, which isn't text".to_string()
            ),
            ("$input.k".to_string(), "$input.k is missing".to_string()),
        ]
    );
    let input = json!({"k": 3});
    let said = root_clauses_of(
        "every es whose zz is m named by $input.k and whose v is m named by $input.j, if any, exists",
        &subject,
        &input,
        None,
    );
    assert_eq!(
        said,
        vec![
            (
                "$input.k".to_string(),
                "$input.k is 3, which isn't text".to_string()
            ),
            ("$input.j".to_string(), "$input.j is missing".to_string()),
        ]
    );
}

#[test]
fn root_clauses_say_a_root_key_and_the_value_before_it_once_and_not_the_ref_they_stop() {
    let subject = json!({"id": "t", "rs": [{"zz": 1}]});
    let input = json!({});
    for sentence in [
        "every rs whose zz is in $input.m named by $input.k, if any, exists",
        "every rs whose zz is $input.m named by $input.k, if any, exists",
    ] {
        assert_eq!(
            root_clauses_of(sentence, &subject, &input, None),
            vec![
                ("$input.k".to_string(), "$input.k is missing".to_string()),
                ("$input.m".to_string(), "$input.m is missing".to_string()),
            ],
            "{sentence}"
        );
    }
}

#[test]
fn a_count_on_an_input_that_is_a_list_says_the_input_once_and_then_its_items() {
    let input = json!([{"id": "t", "rs": [{"zz": 1}, "s"]}]);
    let located = crate::path::Located {
        value: &input[0],
        location: crate::path::Location::input_root().index(0),
    };
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: located,
        input: &input,
        params: None,
        aliases: std::collections::BTreeMap::new(),
    };
    for sentence in [
        "count of rs whose zz is m named by $input.k is 1",
        "count of rs whose zz is $input.m named by $input.k is 1",
    ] {
        let check = lowered(sentence);
        let verdict = crate::ops::run(&check, &ctx);
        assert_eq!(
            super::pieces_text(&super::pieces(&check, &ctx, &verdict)),
            r#"$input is [{"id": "t", "rs": [{"zz": 1}, "s"]}], which isn't an object; item 2 of rs is "s", which isn't an object"#,
            "{sentence}"
        );
    }
}

#[test]
fn root_clauses_say_the_value_before_an_item_key_that_cant_take_a_key() {
    let subject = json!({"id": "t", "xs": [{"tags": ["x"]}]});
    let input = json!({"m": null});
    let said = root_clauses_of(
        "every xs whose tags contains $input.m named by key, if any, exists",
        &subject,
        &input,
        None,
    );
    assert_eq!(
        said,
        vec![("$input.m".to_string(), "$input.m is null".to_string())]
    );
}

#[test]
fn root_clauses_say_a_part_before_an_item_key_that_cant_take_a_key_by_the_parts_name() {
    let scope = crate::lower::Scope::new().with_part(
        "cov",
        crate::lower::PartDef {
            steps: vec![crate::path::Step::Key("c".into())],
            id: None,
        },
    );
    let input = json!({});
    for (part, said) in [
        (Some(json!("s")), r#"cov is "s", which isn't an object"#),
        (Some(json!(null)), "cov is null"),
        (Some(json!({})), "cov.m is missing"),
        (None, "cov is missing"),
    ] {
        let mut subject = json!({"id": "t", "xs": [{"key": "a", "tags": ["x"]}]});
        if let Some(part) = &part {
            subject["c"] = part.clone();
        }
        let text: Vec<String> = root_clauses_in(
            &scope,
            "every xs whose tags contains cov.m named by key, if any, exists",
            (&subject, &input, None),
            &[],
        )
        .into_iter()
        .map(|(_, text)| text)
        .collect();
        assert_eq!(text, [said], "{part:?}");
    }
}

#[test]
fn root_clauses_say_a_for_alias_that_is_a_key_and_cant_be_read() {
    let scope = crate::lower::Scope::new().with_for_alias("k");
    let subject = json!({"id": "t", "es": [{"zz": 1}]});
    let input = json!({});
    for (alias, said) in [
        (json!(3), vec!["k is 3, which isn't text"]),
        (json!(null), vec!["k is null"]),
        (json!("a"), vec![]),
    ] {
        let text: Vec<String> = root_clauses_in(
            &scope,
            "every es whose zz is m named by k, if any, exists",
            (&subject, &input, None),
            &[("k", &alias)],
        )
        .into_iter()
        .map(|(_, text)| text)
        .collect();
        assert_eq!(text, said, "{alias}");
    }
}

#[test]
fn root_clauses_leave_out_the_value_before_a_key_when_it_comes_from_the_item() {
    let subject = json!({"id": "t", "items": [{"zz": "a"}]});
    let input = json!({});
    let params = json!({});
    let said = root_clauses_of(
        "every items whose zz is m named by $params.k exists",
        &subject,
        &input,
        Some(&params),
    );
    assert_eq!(
        said,
        vec![("$params.k".to_string(), "$params.k is missing".to_string())]
    );
}

#[test]
fn root_clauses_keep_each_item_of_a_count_a_root_reads() {
    let subject = json!({"id": "t", "items": [{"n": 1}]});
    let input = json!({});
    let params = json!({"pos": [{"name": "a"}, {}, {}]});
    let said = root_clauses_of(
        "every items whose n is count of $params.pos.name exists",
        &subject,
        &input,
        Some(&params),
    );
    assert_eq!(
        said,
        vec![
            ("item 2 of $params.pos".to_string(), String::new()),
            ("item 3 of $params.pos".to_string(), String::new()),
        ]
    );
}

#[test]
fn root_clauses_say_a_root_before_is_in_ignoring_case_that_isnt_text() {
    let subject = json!({"id": "t", "xs": [], "ys": ["a"]});
    let input = json!({"cs": [{"name": "a"}]});
    let params = json!({"k": 3, "l": ["a"]});
    for sentence in [
        "every xs whose $params.k is in $params.l ignoring case, if any, exists",
        "every xs whose $params.k is in $input.cs.name ignoring case, if any, exists",
        "every xs whose $params.k is not in $params.l ignoring case, if any, exists",
    ] {
        let said = root_clauses_of(sentence, &subject, &input, Some(&params));
        assert_eq!(
            said,
            vec![(
                "$params.k".to_string(),
                "$params.k is 3, which isn't text".to_string()
            )],
            "{sentence}"
        );
    }
    let text = json!({"k": "a", "l": ["a"]});
    assert_eq!(
        root_clauses_of(
            "every xs whose $params.k is in $params.l ignoring case, if any, exists",
            &subject,
            &input,
            Some(&text),
        ),
        vec![]
    );
    assert_eq!(
        root_clauses_of(
            "every xs whose $params.k is in $params.l, if any, exists",
            &subject,
            &input,
            Some(&params),
        ),
        vec![]
    );
}

#[test]
fn walked_root_clauses_say_a_walked_root_that_holds_values_of_more_than_one_kind() {
    let super::Check::Walk(walk) = lowered("every items whose v is in $params.os.name exists")
    else {
        panic!("not a walk");
    };
    let subject = json!({"id": "t", "items": [{"v": "bob"}]});
    let input = json!({});
    let params = json!({"os": [{"name": "bob"}, {"name": 3}]});
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: crate::path::Located {
            value: &subject,
            location: crate::path::Location::input_root().key("s"),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    let whose: Vec<&super::Check> = walk.whose.iter().collect();
    let text: Vec<String> = super::walked_root_clauses(&whose, &ctx)
        .into_iter()
        .map(|clause| clause.text)
        .collect();
    assert_eq!(
        text,
        ["$params.os[].name is [\"bob\", 3], which isn't a list of one kind of value"]
    );
    assert_eq!(super::root_clauses(&whose, &ctx), []);
}

#[test]
fn walked_root_clauses_leave_out_a_list_the_item_holds() {
    let super::Check::Walk(walk) = lowered("every items whose v is in os.name exists") else {
        panic!("not a walk");
    };
    let subject = json!({"id": "t", "os": [{"name": "a"}, {}], "items": [{"v": "a"}]});
    let input = json!({});
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: crate::path::Located {
            value: &subject,
            location: crate::path::Location::input_root().key("s"),
        },
        input: &input,
        params: None,
        aliases: std::collections::BTreeMap::new(),
    };
    let whose: Vec<&super::Check> = walk.whose.iter().collect();
    assert_eq!(super::walked_root_clauses(&whose, &ctx), []);
}

#[test]
fn root_clauses_say_a_list_from_the_subject_a_count_in_the_item_cant_walk() {
    let tree =
        ergo_policy_sentences::parse_check("every items whose n equals count of pr.z exists")
            .unwrap();
    let scope = crate::lower::Scope::new().with_subject("pr");
    let super::Check::Walk(walk) =
        crate::lower::lower_assertion(&tree.assertions[0], &scope).unwrap()
    else {
        panic!("not a walk");
    };
    let subject = json!({"id": "t", "z": "ab", "items": [{"n": 1}]});
    let input = json!({});
    let located = crate::path::Located {
        value: &subject,
        location: crate::path::Location::input_root().key("s"),
    };
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: located.clone(),
        input: &input,
        params: None,
        aliases: std::collections::BTreeMap::from([(crate::path::OUTER.to_string(), located)]),
    };
    let whose: Vec<&super::Check> = walk.whose.iter().collect();
    let text: Vec<String> = super::root_clauses(&whose, &ctx)
        .into_iter()
        .map(|clause| clause.text)
        .collect();
    assert_eq!(text, ["pr.z is \"ab\", which isn't a list"]);
}

#[test]
fn root_clauses_say_a_key_from_the_subject_alone_when_the_value_before_it_is_missing() {
    let tree = ergo_policy_sentences::parse_check(
        "every xs whose v equals $params.m named by pr.k exists",
    )
    .unwrap();
    let scope = crate::lower::Scope::new().with_subject("pr");
    let super::Check::Walk(walk) =
        crate::lower::lower_assertion(&tree.assertions[0], &scope).unwrap()
    else {
        panic!("not a walk");
    };
    let subject = json!({"id": "t", "xs": [{"v": 1}]});
    let input = json!({});
    let params = json!({});
    let located = crate::path::Located {
        value: &subject,
        location: crate::path::Location::input_root().key("s"),
    };
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: located.clone(),
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::from([(crate::path::OUTER.to_string(), located)]),
    };
    let whose: Vec<&super::Check> = walk.whose.iter().collect();
    let text: Vec<String> = super::root_clauses(&whose, &ctx)
        .into_iter()
        .map(|clause| clause.text)
        .collect();
    assert_eq!(text, ["pr.k is missing"]);
}

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
fn unsaid_keeps_a_value_that_holds_a_semicolon_whole() {
    let mut seen = Vec::new();
    let first = super::unsaid_clauses(&super::said_as_text("b is missing".to_string()), &mut seen);
    assert_eq!(super::said_text(&first), "b is missing");
    let second = super::unsaid_clauses(
        &super::said_as_text("a; b is missing".to_string()),
        &mut seen,
    );
    assert_eq!(super::said_text(&second), "a; b is missing");
    let third = super::unsaid_clauses(
        &super::said_as_text("a; b is missing".to_string()),
        &mut seen,
    );
    assert_eq!(super::said_text(&third), "");
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

fn sentence_said(sentence: &str, subject: Value, params: Value) -> (crate::ops::Cause, String) {
    use crate::path::{Located, Location};
    let check = lowered(sentence);
    let input = json!({"things": [subject], "cs": [{"name": "a"}, {"name": null}]});
    let ctx = crate::path::Ctx {
        label: Some("thing".to_string()),
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    let verdict = crate::ops::run(&check, &ctx);
    let said = super::message(&check, &ctx, &verdict);
    (verdict.cause, said)
}

#[test]
fn a_field_beside_a_list_after_is_in_ignoring_case_says_its_own_cause_and_the_worst_cause_wins() {
    use crate::ops::Cause;
    for (sentence, subject, params, cause, said) in [
        (
            "v is in ys ignoring case",
            json!({"ys": ["a", null]}),
            json!({}),
            Cause::Absent,
            "v is missing, and item 2 of ys is null",
        ),
        (
            "v is in ys ignoring case",
            json!({"v": 3, "ys": ["a", null]}),
            json!({}),
            Cause::Unusable,
            "v is 3, which isn't text, and item 2 of ys is null",
        ),
        (
            "v is in ys ignoring case",
            json!({"ys": [3]}),
            json!({}),
            Cause::Unusable,
            "v is missing, and item 1 of ys is 3, which isn't text",
        ),
        (
            "v is not in ys ignoring case",
            json!({"v": null, "ys": [3]}),
            json!({}),
            Cause::Unusable,
            "v is null, and item 1 of ys is 3, which isn't text",
        ),
        (
            "$params.k is in $params.l ignoring case",
            json!({}),
            json!({"l": ["a", null]}),
            Cause::Absent,
            "$params.k is missing, and item 2 of $params.l is null",
        ),
        (
            "$params.k is in $params.l ignoring case",
            json!({}),
            json!({"k": 3, "l": ["a", null]}),
            Cause::Unusable,
            "$params.k is 3, which isn't text, and item 2 of $params.l is null",
        ),
        (
            "v is in $input.cs.name ignoring case",
            json!({}),
            json!({}),
            Cause::Absent,
            "v is missing, and item 2 of $input.cs: name is null",
        ),
        (
            "v is in $input.cs.name ignoring case",
            json!({"v": 3}),
            json!({}),
            Cause::Unusable,
            "v is 3, which isn't text, and item 2 of $input.cs: name is null",
        ),
    ] {
        assert_eq!(
            sentence_said(sentence, subject.clone(), params),
            (cause, said.to_string()),
            "{sentence} {subject}"
        );
    }
}

#[test]
fn joined_counts_members_as_items_and_says_how_many_more_after_three() {
    let parts: Vec<String> = ["a", "b", "c", "d"]
        .iter()
        .map(|k| format!("member {k} of xs is 1"))
        .chain(["$params.m is missing".to_string()])
        .collect();
    assert_eq!(
        super::joined(parts),
        "member a of xs is 1; member b of xs is 1; member c of xs is 1; $params.m is missing; and 1 more"
    );
}
