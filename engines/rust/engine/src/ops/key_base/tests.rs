use super::*;
use crate::path::{Located, Location, Start};
use serde_json::json;
use std::collections::BTreeMap;

fn ctx<'a>(subject: &'a Value, params: &'a Value, aliases: &[(&str, &'a Value)]) -> Ctx<'a> {
    Ctx {
        label: None,
        item_by_item: false,
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
fn a_whose_says_a_missing_or_null_key_or_one_that_isnt_text_once() {
    let tree = ergo_policy_sentences::parse_check("v is m named by $params.k").unwrap();
    let read =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let subject = json!({"v": 1});
    let params = json!({});
    assert_eq!(
        unreadable_keys(&read, &ctx(&subject, &params, &[])),
        vec![(Cause::Absent, "$params.k is missing".to_string())]
    );
    let params = json!({"k": null});
    assert_eq!(
        unreadable_keys(&read, &ctx(&subject, &params, &[])),
        vec![(Cause::Null, "$params.k is null".to_string())]
    );
    let params = json!({"k": 3});
    assert_eq!(
        unreadable_keys(&read, &ctx(&subject, &params, &[])),
        vec![(
            Cause::Unusable,
            "$params.k is 3, which isn't text".to_string()
        )]
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
    let said = crate::ops::tally::row_said(
        tally,
        &ctx,
        verdict.cause,
        crate::ops::message::said(&check, &ctx, &verdict),
    );
    rewrite(&check, &ctx, &mut verdict.cause, &mut verdict.inputs, said)
        .map(|said| crate::ops::message::said_text(&said))
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
fn a_rewrite_says_each_key_once_in_root_order_when_the_keys_are_joined_with_and() {
    assert_eq!(
        rewritten(
            "count of o named by $params.k plus count of p named by $params.j is 1",
            &json!({"o": "s"}),
            &json!({"k": 3, "j": 4}),
        )
        .as_deref(),
        Some(
            "$params.j is 4, which isn't text; $params.k is 3, which isn't text; o is \"s\", which isn't a list or an object; p is missing"
        )
    );
}

fn rewritten_plain(sentence: &str, subject: &Value, params: &Value) -> Option<String> {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let ctx = ctx(subject, params, &[]);
    let mut verdict = crate::ops::run(&check, &ctx);
    let said = crate::ops::message::said(&check, &ctx, &verdict);
    rewrite(&check, &ctx, &mut verdict.cause, &mut verdict.inputs, said)
        .map(|said| crate::ops::message::said_text(&said))
}

#[test]
fn a_base_is_a_root_clause_in_root_order() {
    assert_eq!(
        rewritten_plain(
            "o.v named by $params.k plus p.w named by $params.j is 1",
            &json!({"o": "s"}),
            &json!({"k": 3, "j": 4}),
        )
        .as_deref(),
        Some(
            "$params.j is 4, which isn't text; $params.k is 3, which isn't text; o is \"s\", which isn't an object; p.w is missing"
        )
    );
    assert_eq!(
        rewritten_plain(
            "m.v named by $params.k is 1",
            &json!({"m": "s"}),
            &json!({})
        )
        .as_deref(),
        Some("m is \"s\", which isn't an object; $params.k is missing")
    );
}

fn walked_by_position(start: Start, key: &str) -> Path {
    Path {
        start,
        steps: vec![
            Step::Key("m".to_string()),
            Step::Index(0),
            Step::Ref(Box::new(Path {
                start: Start::Params,
                steps: vec![Step::Key(key.to_string())],
            })),
        ],
    }
}

#[test]
fn a_for_line_list_whose_base_is_null_past_a_first_key_says_the_null_base() {
    let subject = json!({"p": null});
    let params = json!({});
    let found = for_list(
        &keyed(Start::Subject, &["p", "q"], "k"),
        false,
        &ctx(&subject, &params, &[]),
    )
    .unwrap();
    let (text, cause, _) = found.base.unwrap();
    assert_eq!((text.as_str(), cause), ("p is null", Cause::Null));
}

#[test]
fn a_for_line_list_that_starts_at_a_key_has_no_base_even_when_the_subject_is_an_empty_list() {
    let subject = json!([]);
    let params = json!({});
    let found = for_list(
        &keyed(Start::Subject, &[], "k"),
        false,
        &ctx(&subject, &params, &[]),
    )
    .unwrap();
    assert!(found.base.is_none());
}

#[test]
fn a_list_base_of_a_plain_check_isnt_an_object_but_a_count_may_walk_it() {
    assert_eq!(
        rewritten_plain("o named by $params.k is 1", &json!({"o": [1]}), &json!({})).as_deref(),
        Some("o is [1], which isn't an object; $params.k is missing")
    );
}

#[test]
fn a_key_that_reads_fine_leaves_no_base_to_say_for_a_params_path() {
    let params = json!({"m": "s", "k": "a"});
    let subject = json!({});
    let path = keyed(Start::Params, &["m"], "k");
    assert!(base_of(&path, false, &ctx(&subject, &params, &[])).is_none());
    let params = json!({"m": "s"});
    let (name, text, cause) = base_of(&path, false, &ctx(&subject, &params, &[])).unwrap();
    assert_eq!(name, "$params.m");
    assert_eq!(text, "$params.m is \"s\", which isn't an object");
    assert_eq!(cause, Cause::Unusable);
}

#[test]
fn a_base_before_a_position_has_no_problem_said_for_the_keys_before_it() {
    let input = json!({"m": "s"});
    let params = json!({});
    let path = walked_by_position(Start::Input, "k");
    assert!(base_of(&path, false, &ctx(&input, &params, &[])).is_none());
    assert!(from_base(&path, &ctx(&input, &params, &[])).is_none());
}

#[test]
fn a_path_that_starts_at_an_alias_with_a_key_that_reads_fine_says_nothing() {
    let subject = json!({});
    let params = json!({"i": "a"});
    let null = Value::Null;
    let path = keyed(Start::Alias("r".to_string()), &["x"], "i");
    assert!(alias_base(&path, &ctx(&subject, &params, &[("r", &null)])).is_none());
}

#[test]
fn a_path_from_an_alias_that_starts_at_a_key_has_no_base_even_when_the_alias_is_null() {
    let subject = json!({});
    let params = json!({});
    let null = Value::Null;
    let path = keyed(Start::Alias("r".to_string()), &[], "i");
    assert!(alias_base(&path, &ctx(&subject, &params, &[("r", &null)])).is_none());
}

#[test]
fn an_outcome_is_the_one_its_cause_names() {
    assert_eq!(outcome_of(Cause::Absent), Outcome::Absent);
    assert_eq!(outcome_of(Cause::Null), Outcome::Null);
    assert_eq!(outcome_of(Cause::Unusable), Outcome::Unusable);
    assert_eq!(outcome_of(Cause::NotAnObject), Outcome::NotAnObject);
    assert_eq!(outcome_of(Cause::Value), Outcome::Found);
}

#[test]
fn an_empty_list_before_a_key_that_cant_be_read_is_said_and_a_full_one_is_not() {
    let params = json!({});
    let path = keyed(Start::Subject, &["o"], "k");
    let subject = json!({"o": []});
    assert_eq!(
        empty_base(&path, &ctx(&subject, &params, &[])).as_deref(),
        Some("o is []")
    );
    let subject = json!({"o": [1]});
    assert_eq!(empty_base(&path, &ctx(&subject, &params, &[])), None);
}

#[test]
fn an_empty_base_needs_plain_keys_before_the_key_that_cant_be_read() {
    let params = json!({});
    let subject = json!([]);
    assert_eq!(
        empty_base(
            &keyed(Start::Subject, &[], "k"),
            &ctx(&subject, &params, &[])
        ),
        None
    );
    let subject = json!({"m": [[]]});
    assert_eq!(
        empty_base(
            &walked_by_position(Start::Subject, "k"),
            &ctx(&subject, &params, &[])
        ),
        None
    );
}

#[test]
fn a_whose_says_each_missing_key_once_and_every_different_one() {
    let tree = ergo_policy_sentences::parse_check(
        "v named by $params.k plus w named by $params.k plus u named by $params.j is 1",
    )
    .unwrap();
    let read =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let subject = json!({});
    let params = json!({});
    assert_eq!(
        unreadable_keys(&read, &ctx(&subject, &params, &[])),
        vec![
            (Cause::Absent, "$params.k is missing".to_string()),
            (Cause::Absent, "$params.j is missing".to_string())
        ]
    );
}

#[test]
fn a_key_that_cant_be_read_is_listed_once_beside_an_input_that_already_names_it() {
    let tree = ergo_policy_sentences::parse_check("o.v named by $params.k is 1").unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let subject = json!({"o": "s"});
    let params = json!({});
    let said = vec![json!({"name": "o"}), json!({"name": "$params.k"})];
    assert_eq!(
        entry_inputs(&check, &ctx(&subject, &params, &[]), Cause::Absent, &said),
        Vec::<Value>::new()
    );
    let names: Vec<Value> = entry_inputs(&check, &ctx(&subject, &params, &[]), Cause::Absent, &[])
        .into_iter()
        .map(|input| input["name"].clone())
        .collect();
    assert_eq!(names, [json!("$params.k"), json!("o")]);
}

#[test]
fn a_verdict_that_is_a_value_is_not_rewritten_even_when_a_base_cant_take_its_key() {
    let tree = ergo_policy_sentences::parse_check("o.v named by $params.k is 1").unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let subject = json!({"o": "s"});
    let params = json!({});
    let ctx = ctx(&subject, &params, &[]);
    let mut verdict = crate::ops::run(&check, &ctx);
    let said = crate::ops::message::said(&check, &ctx, &verdict);
    let mut cause = Cause::Value;
    assert!(rewrite(&check, &ctx, &mut cause, &mut verdict.inputs, said).is_none());
    assert_eq!(cause, Cause::Value);
}

fn rewritten_states(
    sentence: &str,
    subject: &Value,
    params: &Value,
    forced: Option<Outcome>,
) -> Vec<(String, Outcome)> {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    let check =
        crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap();
    let ctx = ctx(subject, params, &[]);
    let mut verdict = crate::ops::run(&check, &ctx);
    if let Some(state) = forced {
        for input in verdict.inputs.iter_mut() {
            input.state = state;
        }
    }
    let said = crate::ops::message::said(&check, &ctx, &verdict);
    rewrite(&check, &ctx, &mut verdict.cause, &mut verdict.inputs, said);
    verdict
        .inputs
        .into_iter()
        .map(|input| (input.name, input.state))
        .collect()
}

#[test]
fn a_key_read_off_a_subject_that_isnt_an_object_makes_its_input_not_an_object() {
    assert_eq!(
        rewritten_states("v named by $params.k is 1", &json!("s"), &json!({}), None),
        [("v named by $params.k".to_string(), Outcome::NotAnObject)]
    );
}

#[test]
fn an_input_takes_the_worst_outcome_of_its_base_and_its_key() {
    assert_eq!(
        rewritten_states(
            "o.v named by $params.k is 1",
            &json!({"o": "s"}),
            &json!({}),
            None
        ),
        [("o.v named by $params.k".to_string(), Outcome::Unusable)]
    );
}

#[test]
fn an_input_that_is_already_worse_than_its_base_and_its_key_keeps_its_outcome() {
    assert_eq!(
        rewritten_states(
            "o.v named by $params.k is 1",
            &json!({}),
            &json!({}),
            Some(Outcome::Unusable)
        ),
        [("o.v named by $params.k".to_string(), Outcome::Unusable)]
    );
}

#[test]
fn a_said_that_names_neither_a_key_nor_a_base_stays_where_it_was() {
    assert_eq!(
        rewritten_plain(
            "o.v named by $params.k plus x is 1",
            &json!({"o": "s", "x": "t"}),
            &json!({})
        )
        .as_deref(),
        Some(
            "x is \"t\", which isn't a number; o is \"s\", which isn't an object; $params.k is missing"
        )
    );
}

#[test]
fn a_count_says_a_key_and_its_base_after_the_clause_it_counts() {
    assert_eq!(
        rewritten(
            "count of o.v named by $params.k is 1",
            &json!({"o": "s"}),
            &json!({})
        )
        .as_deref(),
        Some(
            "o is \"s\", which isn't an object; $params.k is missing; o.v named by $params.k is missing"
        )
    );
    assert_eq!(
        rewritten(
            "count of o.v named by $params.k is 1",
            &json!({"o": "s"}),
            &json!({"k": 3})
        )
        .as_deref(),
        Some("$params.k is 3, which isn't text; o is \"s\", which isn't an object")
    );
}

#[test]
fn a_count_joins_the_counted_clauses_in_the_order_they_are_written_and_keeps_the_roots_apart() {
    assert_eq!(
        rewritten(
            "count of o.v named by $params.k plus count of xs is 1",
            &json!({"o": "s", "xs": 3}),
            &json!({})
        )
        .as_deref(),
        Some(
            "o.v named by $params.k is missing, and xs is 3, which isn't a list or an object; o is \"s\", which isn't an object; $params.k is missing"
        )
    );
    assert_eq!(
        rewritten(
            "count of xs plus count of o.v named by $params.k is 1",
            &json!({"o": "s", "xs": 3}),
            &json!({})
        )
        .as_deref(),
        Some(
            "xs is 3, which isn't a list or an object, and o.v named by $params.k is missing; o is \"s\", which isn't an object; $params.k is missing"
        )
    );
}

#[test]
fn a_count_that_reads_one_missing_key_twice_says_it_once() {
    assert_eq!(
        rewritten(
            "count of o.v named by $params.k plus count of o.w named by $params.k is 1",
            &json!({"o": "s"}),
            &json!({})
        )
        .as_deref(),
        Some(
            "o is \"s\", which isn't an object; $params.k is missing; o.v named by $params.k is missing; o.w named by $params.k is missing"
        )
    );
}

#[test]
fn a_count_of_a_list_with_a_key_that_isnt_text_says_the_key_and_a_base_that_isnt_a_list() {
    assert_eq!(
        rewritten(
            "count of o named by $params.k is 1",
            &json!({"o": 5}),
            &json!({"k": 3})
        )
        .as_deref(),
        Some("$params.k is 3, which isn't text; o is 5, which isn't a list or an object")
    );
    assert_eq!(
        rewritten(
            "count of o named by $params.k is 1",
            &json!({"o": [1]}),
            &json!({"k": 3})
        ),
        None
    );
}

#[test]
fn a_counted_item_clause_is_kept_even_when_its_text_is_a_base_problem() {
    let base_text = "o is 5, which isn't an object".to_string();
    let input = Input {
        name: "o".to_string(),
        value: json!(5),
        locations: Vec::new(),
        part: None,
        state: Outcome::Unusable,
        null_at: None,
        worked: false,
    };
    let bases = [KeyBase {
        path: "o.v named by $params.k".to_string(),
        key: "$params.k is missing".to_string(),
        key_name: "$params.k".to_string(),
        base: Some((base_text.clone(), Cause::Unusable, input)),
        off_object: false,
        key_cause: Cause::Absent,
    }];
    let said = vec![vec![Piece::Counted(vec![
        Clause::item("item 1 of xs", Cause::Value, base_text.clone(), Vec::new()),
        Clause::root("w", Cause::Value, "w is 2".to_string()),
    ])]];
    let (said, _) = said_with_bases(said, Cause::Absent, &bases);
    let text = message::said_text(&said);
    assert_eq!(
        text,
        "w is 2; o is 5, which isn't an object; o is 5, which isn't an object; $params.k is missing"
    );
}
