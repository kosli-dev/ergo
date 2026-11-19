use ergo_policy_engine::SPEC;
use serde_json::{Value, json};

fn row(check: Value, thing: Value, params: Value) -> Value {
    let report = ergo_policy_engine::report(
        &json!({"things": [thing]}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"t": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "t", "checks": {"c": check}}}
        }),
        &params,
    );
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

fn kinds(row: &Value) -> Vec<(String, String, String)> {
    row["failures"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| {
            (
                entry["kind"].as_str().unwrap().to_string(),
                entry["name"].as_str().unwrap().to_string(),
                entry["message"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

fn entry(kind: &str, name: &str, message: &str) -> (String, String, String) {
    (kind.to_string(), name.to_string(), message.to_string())
}

#[test]
fn a_for_line_key_that_cant_be_read_sits_on_the_row_with_no_assertion_entry() {
    let check = json!({"for": "every o named by $params.k as x", "assert": ["x is 1", "x is 2"]});
    let got = row(check, json!({"id": "t", "o": {"a": [1]}}), json!({}));
    assert_eq!(got["message"], "$params.k is missing");
    assert_eq!(got["cause"], "absent");
    assert!(kinds(&got).is_empty());
    let key = got["inputs"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(key["name"], "$params.k");
    assert_eq!(key["outcome"], "absent");
}

#[test]
fn a_for_line_key_that_cant_be_read_is_said_before_a_list_that_fails_whatever_the_key() {
    let check = json!({"for": "every o named by $params.k as x", "assert": ["x is 1", "z is 3"]});
    for (o, said, cause) in [
        (Value::Null, "o is null", "absent"),
        (
            json!("s"),
            "o is \"s\", which isn't a list or an object",
            "unusable",
        ),
        (json!([]), "o is []", "absent"),
    ] {
        let got = row(check.clone(), json!({"id": "t", "z": 2, "o": o}), json!({}));
        assert_eq!(
            got["message"],
            format!("z is 2; $params.k is missing; {said}")
        );
        assert_eq!(got["cause"], cause);
        assert_eq!(
            kinds(&got),
            vec![
                entry("assertion", "z is 3", "z is 2"),
                entry("list", "o", said)
            ]
        );
    }
}

#[test]
fn a_whose_key_that_is_missing_is_said_once_and_each_item_says_the_value_before_it() {
    let check =
        json!({"for": "every xs whose v is m named by $params.k as x", "assert": "x.v is 1"});
    let got = row(check, json!({"id": "t", "xs": [{"v": 1}]}), json!({}));
    assert_eq!(
        got["message"],
        "$params.k is missing; item 1 of xs: m is missing"
    );
    assert_eq!(
        kinds(&got),
        vec![
            entry("list", "xs", "$params.k is missing"),
            entry("item", "item 1 of xs", "m is missing")
        ]
    );
}

#[test]
fn a_clause_an_earlier_sentence_gave_is_said_once_in_the_row_and_kept_in_each_entry() {
    let got = row(
        json!({"assert": ["expires_at exists", "expires_at is after as_of"]}),
        json!({"id": "t"}),
        json!({}),
    );
    assert_eq!(got["message"], "expires_at is missing; as_of is missing");
    assert_eq!(
        kinds(&got),
        vec![
            entry("assertion", "expires_at exists", "expires_at is missing"),
            entry(
                "assertion",
                "expires_at is after as_of",
                "expires_at is missing, and as_of is missing"
            )
        ]
    );
}

#[test]
fn a_one_line_walk_says_the_value_before_a_missing_key_as_a_list_entry() {
    let got = row(
        json!("every o named by $params.k is 1"),
        json!({"id": "t"}),
        json!({}),
    );
    assert_eq!(got["message"], "$params.k is missing; o is missing");
    let assertion = &got["failures"][0];
    assert_eq!(assertion["message"], "$params.k is missing");
    assert_eq!(assertion["failures"][0]["kind"], "list");
    assert_eq!(assertion["failures"][0]["message"], "o is missing");
}

#[test]
fn a_walk_in_an_any_of_option_lists_the_params_it_reads_on_its_assertion() {
    let check = json!({"any_of": {
        "declared": "some ids.v is in $params.allowed",
        "other": "id is \"x\""
    }});
    let params = json!({"allowed": ["a", "b"]});
    let got = row(check, json!({"id": "t", "ids": [{"v": "c"}]}), params);
    let assertion = &got["failures"][0]["failures"][0];
    assert_eq!(assertion["kind"], "assertion");
    assert_eq!(
        assertion["inputs"],
        json!([
            {"locations": ["/things/0/ids/0/v"], "name": "ids[].v", "outcome": "usable", "value": ["c"]},
            {"locations": ["$params:/allowed"], "name": "$params.allowed", "outcome": "usable", "value": ["a", "b"]}
        ])
    );
}
