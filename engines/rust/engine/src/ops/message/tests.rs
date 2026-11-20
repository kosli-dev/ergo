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
    let whole = lowered(sentence);
    let inside: Vec<&super::Check> = match &whole {
        super::Check::Walk(walk) => walk
            .whose
            .iter()
            .chain(std::iter::once(&*walk.check))
            .collect(),
        other => vec![other],
    };
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: crate::path::Located {
            value: subject,
            location: crate::path::Location::input_root().key("s"),
        },
        input,
        params,
        aliases: std::collections::BTreeMap::new(),
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
