use super::*;
use crate::path::{Located, Location, Start};
use serde_json::json;
use std::collections::BTreeMap;

fn ctx<'a>(subject: &'a Value, params: &'a Value, aliases: &[(&str, &'a Value)]) -> Ctx<'a> {
    Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: subject,
            location: Location::input_root().key("s"),
        },
        input: subject,
        params: Some(params),
        aliases: aliases
            .iter()
            .map(|(name, value)| {
                (
                    (*name).to_string(),
                    Located {
                        value,
                        location: Location::input_root().key(name),
                    },
                )
            })
            .collect::<BTreeMap<_, _>>(),
    }
}

fn keyed(start: Start, keys: &[&str], key: &str) -> Path {
    let mut steps: Vec<Step> = keys.iter().map(|k| Step::Key((*k).to_string())).collect();
    steps.push(Step::Ref(Box::new(Path {
        start: Start::Params,
        steps: vec![Step::Key(key.to_string())],
    })));
    Path { start, steps }
}

#[test]
fn a_for_line_list_with_a_missing_key_says_the_key_and_a_missing_base() {
    let subject = json!({"z": 2});
    let params = json!({});
    let found = for_list(
        &keyed(Start::Subject, &["o"], "k"),
        false,
        &ctx(&subject, &params, &[]),
    )
    .unwrap();
    assert_eq!(found.key_text, "$params.k is missing");
    assert_eq!(found.key.state, Outcome::Absent);
    let (text, cause, input) = found.base.unwrap();
    assert_eq!(text, "o is missing");
    assert_eq!(cause, Cause::Absent);
    assert_eq!(input.name, "o");
}

#[test]
fn a_for_line_list_with_a_null_key_says_a_null_base() {
    let subject = json!({"o": null});
    let params = json!({"k": null});
    let found = for_list(
        &keyed(Start::Subject, &["o"], "k"),
        false,
        &ctx(&subject, &params, &[]),
    )
    .unwrap();
    assert_eq!(found.key_text, "$params.k is null");
    let (text, cause, _) = found.base.unwrap();
    assert_eq!((text.as_str(), cause), ("o is null", Cause::Null));
}

#[test]
fn a_for_line_list_with_a_key_that_isnt_text_says_a_base_that_isnt_a_list_or_an_object() {
    let subject = json!({"o": "s"});
    let params = json!({"k": 3});
    let found = for_list(
        &keyed(Start::Subject, &["o"], "k"),
        false,
        &ctx(&subject, &params, &[]),
    )
    .unwrap();
    assert_eq!(found.key_text, "$params.k is 3, which isn't text");
    assert_eq!(found.key.state, Outcome::Unusable);
    let (text, cause, _) = found.base.unwrap();
    assert_eq!(text, "o is \"s\", which isn't a list or an object");
    assert_eq!(cause, Cause::Unusable);
}

#[test]
fn an_empty_base_is_a_problem_only_without_if_any() {
    let subject = json!({"o": []});
    let params = json!({});
    let path = keyed(Start::Subject, &["o"], "k");
    let found = for_list(&path, false, &ctx(&subject, &params, &[])).unwrap();
    let (text, cause, input) = found.base.unwrap();
    assert_eq!((text.as_str(), cause), ("o is []", Cause::Value));
    assert_eq!(input.state, Outcome::Found);
    let found = for_list(&path, true, &ctx(&subject, &params, &[])).unwrap();
    assert!(found.base.is_none());
}

#[test]
fn a_base_that_is_an_object_is_no_problem_and_a_key_that_reads_fine_is_none() {
    let subject = json!({"o": {"a": [1]}});
    let params = json!({});
    let path = keyed(Start::Subject, &["o"], "k");
    assert!(
        for_list(&path, false, &ctx(&subject, &params, &[]))
            .unwrap()
            .base
            .is_none()
    );
    let params = json!({"k": "a"});
    assert!(for_list(&path, false, &ctx(&subject, &params, &[])).is_none());
}

#[test]
fn a_path_from_an_alias_says_a_null_alias_and_a_missing_field_past_it() {
    let subject = json!({});
    let params = json!({});
    let empty = json!({});
    let null = Value::Null;
    let path = keyed(Start::Alias("r".to_string()), &["x", "y"], "i");
    let (key, base, cause) = alias_base(&path, &ctx(&subject, &params, &[("r", &empty)])).unwrap();
    assert_eq!(key, "$params.i is missing");
    assert_eq!((base.as_str(), cause), ("r.x.y is missing", Cause::Absent));
    let (_, base, cause) = alias_base(&path, &ctx(&subject, &params, &[("r", &null)])).unwrap();
    assert_eq!((base.as_str(), cause), ("r is null", Cause::Null));
}

#[test]
fn a_whose_says_a_missing_or_null_key_once_unless_another_key_isnt_text() {
    let tree = ergo_policy_sentences::parse_check("v is m named by $params.k").unwrap();
    let read =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let subject = json!({"v": 1});
    let params = json!({});
    assert_eq!(
        missing_keys(&read, &ctx(&subject, &params, &[])),
        vec![(Cause::Absent, "$params.k is missing".to_string())]
    );
    let params = json!({"k": null});
    assert_eq!(
        missing_keys(&read, &ctx(&subject, &params, &[])),
        vec![(Cause::Null, "$params.k is null".to_string())]
    );
    let params = json!({"k": 3});
    assert!(missing_keys(&read, &ctx(&subject, &params, &[])).is_empty());
    assert_eq!(
        unusable_keys(&read, &ctx(&subject, &params, &[])),
        vec!["$params.k is 3, which isn't text".to_string()]
    );
}

#[test]
fn a_from_line_says_a_base_that_cant_take_a_key() {
    let input = json!({"m": "s"});
    let params = json!({});
    let path = keyed(Start::Input, &["m"], "k");
    let (text, cause) = from_base(&path, &ctx(&input, &params, &[])).unwrap();
    assert_eq!(text, "$input.m is \"s\", which isn't a list or an object");
    assert_eq!(cause, Cause::Unusable);
    let input = json!({"m": {"a": []}});
    assert!(from_base(&path, &ctx(&input, &params, &[])).is_none());
}

#[test]
fn a_key_read_from_a_field_that_holds_no_text_is_flawed_but_a_params_key_is_not_counted() {
    let subject = json!({"p": 3});
    let params = json!({});
    let field_key = Path {
        start: Start::Subject,
        steps: vec![
            Step::Key("rows".to_string()),
            Step::Field(Box::new(Path {
                start: Start::Subject,
                steps: vec![Step::Key("p".to_string())],
            })),
        ],
    };
    assert!(field_key_flawed(&field_key, &ctx(&subject, &params, &[])));
    let params_key = keyed(Start::Subject, &["rows"], "k");
    assert!(!field_key_flawed(&params_key, &ctx(&subject, &params, &[])));
}

#[test]
fn a_worse_base_makes_an_input_worse_and_a_milder_one_keeps_it() {
    assert_eq!(
        worse_state(Outcome::Null, Cause::Absent),
        Some(Outcome::Absent)
    );
    assert_eq!(worse_state(Outcome::Unusable, Cause::Absent), None);
}

#[test]
fn an_assertion_lists_a_key_it_cant_read_when_an_item_that_isnt_an_object_makes_the_cause_worse() {
    let tree =
        ergo_policy_sentences::parse_check("count of es.v that is m named by $params.k is 0")
            .unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let subject = json!({"es": [{"v": 2}]});
    let params = json!({"k": 3});
    let names: Vec<Value> = entry_inputs(
        &check,
        &ctx(&subject, &params, &[]),
        Cause::NotAnObject,
        &[],
    )
    .into_iter()
    .map(|input| input["name"].clone())
    .collect();
    assert_eq!(names, [json!("$params.k")]);
}

#[test]
fn a_plain_check_on_an_input_that_is_a_list_lists_no_key_beside_the_input() {
    let tree =
        ergo_policy_sentences::parse_check("$input.m named by $params.k is a string").unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let input = json!([{"id": "t", "tags": ["a"], "m": {"a": "a"}}]);
    let params = json!({});
    assert_eq!(
        entry_inputs(&check, &ctx(&input, &params, &[]), Cause::NotAnObject, &[]),
        Vec::<Value>::new()
    );
}

fn rewritten(sentence: &str, subject: &Value, params: &Value) -> Option<String> {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let Check::Tally(tally) = &check else {
        panic!("{sentence} is not a count or a sum");
    };
    let ctx = ctx(subject, params, &[]);
    let mut verdict = crate::ops::run(&check, &ctx);
    let said = crate::ops::tally::row_message(
        tally,
        &ctx,
        verdict.cause,
        crate::ops::message::pieces(&check, &ctx, &verdict),
    );
    rewrite(&check, &ctx, &mut verdict.cause, &mut verdict.inputs, said)
}

#[test]
fn a_rewrite_says_a_key_and_a_base_that_hold_a_semicolon_once_each() {
    assert_eq!(
        rewritten(
            "count of o.v named by $params.k is 1",
            &json!({"o": "a; b"}),
            &json!({"k": ["x; y"]}),
        )
        .as_deref(),
        Some("$params.k is [\"x; y\"], which isn't text; o is \"a; b\", which isn't an object")
    );
}

#[test]
fn a_rewrite_says_each_key_once_when_the_keys_are_joined_with_and() {
    assert_eq!(
        rewritten(
            "count of o named by $params.k plus count of p named by $params.j is 1",
            &json!({"o": "s"}),
            &json!({"k": 3, "j": 4}),
        )
        .as_deref(),
        Some(
            "$params.k is 3, which isn't text, and $params.j is 4, which isn't text; o is \"s\", which isn't a list or an object; p is missing"
        )
    );
}
