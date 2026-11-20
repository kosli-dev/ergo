use super::*;
use crate::path::Outcome;
use serde_json::json;

fn read(name: &str, value: Value, state: Outcome) -> Input {
    Input {
        name: name.to_string(),
        value,
        locations: Vec::new(),
        part: None,
        state,
        null_at: None,
        worked: false,
    }
}

fn lowered(sentence: &str) -> crate::ops::Check {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap()
}

fn outcome_of(
    sentences: &[&str],
    input: &Value,
    params: Option<&Value>,
    name: &str,
) -> Option<&'static str> {
    outcome_in(sentences, input, input, params, name)
}

fn outcome_in(
    sentences: &[&str],
    subject: &Value,
    input: &Value,
    params: Option<&Value>,
    name: &str,
) -> Option<&'static str> {
    let checks: Vec<crate::ops::Check> = sentences.iter().map(|s| lowered(s)).collect();
    let all: Vec<&crate::ops::Check> = checks.iter().collect();
    let ctx = crate::path::Ctx {
        subject: crate::path::Located {
            value: subject,
            location: crate::path::Location::input_root(),
        },
        input,
        params,
        aliases: std::collections::BTreeMap::new(),
        label: None,
        item_by_item: checks.iter().any(crate::ops::Check::reads_by_item),
    };
    let read = checks
        .iter()
        .flat_map(|check| crate::ops::run(check, &ctx).inputs)
        .find(|read| read.name == name)
        .unwrap();
    outcome(&read, crate::checks::input_unfit(&all, &read, &ctx))
}

#[test]
fn a_missing_input_is_absent_and_a_null_one_is_null_beside_a_value_the_row_cant_use() {
    let check = ["x is at least 3", "w is at least 3"];
    assert_eq!(
        outcome_of(&check, &json!({"w": "a"}), None, "x"),
        Some("absent")
    );
    assert_eq!(
        outcome_of(&check, &json!({"x": null, "w": "a"}), None, "x"),
        Some("null")
    );
    assert_eq!(
        outcome_of(&check, &json!({"w": "a"}), None, "w"),
        Some("unusable")
    );
    for state in [Outcome::Absent, Outcome::Null] {
        let missing = read("x", Value::Null, state);
        assert_eq!(outcome(&missing, true), outcome(&missing, false));
    }
}

#[test]
fn a_found_value_is_unusable_only_when_the_check_cant_use_it() {
    let check = ["x is at least 3"];
    assert_eq!(
        outcome_of(&check, &json!({"x": "1"}), None, "x"),
        Some("unusable")
    );
    assert_eq!(
        outcome_of(&check, &json!({"x": 1}), None, "x"),
        Some("usable")
    );
}

#[test]
fn a_side_the_compare_cant_use_is_unusable_without_a_message() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({"v": "a"}), None, "v"),
        Some("unusable")
    );
}

#[test]
fn a_side_the_compare_can_use_is_usable_when_the_check_fails() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({"v": 1}), None, "v"),
        Some("usable")
    );
}

#[test]
fn a_missing_side_is_absent_where_the_compare_needs_a_number() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({}), None, "v"),
        Some("absent")
    );
}

#[test]
fn a_null_side_is_null_where_the_compare_needs_a_number() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({"v": null}), None, "v"),
        Some("null")
    );
}

#[test]
fn a_key_of_the_wrong_kind_stays_usable() {
    assert_eq!(
        outcome_of(
            &["m named by k is 1"],
            &json!({"k": 3, "m": {"a": 1}}),
            None,
            "k"
        ),
        Some("usable")
    );
}

#[test]
fn a_walked_root_stays_usable_when_another_clause_of_the_message_says_which_isnt() {
    assert_eq!(
        outcome_of(
            &["every $input.xs is at least 5", "$params.q is at least 1"],
            &json!({"xs": [3]}),
            Some(&json!({"q": "s"})),
            "$input.xs[]"
        ),
        Some("usable")
    );
}

#[test]
fn a_walked_root_with_an_item_the_walk_cant_read_is_unusable() {
    assert_eq!(
        outcome_of(
            &["x is in $input.os.name"],
            &json!({"x": "bob", "os": [{"name": "bob"}, 3]}),
            None,
            "$input.os[].name"
        ),
        Some("unusable")
    );
}

#[test]
fn a_side_stays_usable_when_the_check_fails_on_the_other_side_before_using_it() {
    assert_eq!(
        outcome_of(&["l contains w"], &json!({"l": "a"}), None, "l"),
        Some("usable")
    );
}

#[test]
fn a_walked_list_that_starts_at_the_input_is_unusable_when_an_item_isnt_an_object() {
    assert_eq!(
        outcome_in(
            &["id is in $input.id"],
            &json!({"id": "a"}),
            &json!([{"id": "a"}, 1]),
            None,
            "$input[].id"
        ),
        Some("unusable")
    );
}

#[test]
fn a_walked_field_of_the_subject_stays_usable_when_an_item_isnt_an_object() {
    assert_eq!(
        outcome_of(
            &["x is in os.name"],
            &json!({"x": "bob", "os": [{"name": "bob"}, 3]}),
            None,
            "os[].name"
        ),
        Some("usable")
    );
}

#[test]
fn a_value_whose_name_ends_a_clause_about_another_value_stays_usable() {
    let subject = json!({"id": "a"});
    let input = json!([{"id": "a"}]);
    let sentences = ["id is in $input[0].id"];
    assert_eq!(
        outcome_in(&sentences, &subject, &input, None, "id"),
        Some("usable")
    );
    assert_eq!(
        outcome_in(&sentences, &subject, &input, None, "$input[0].id"),
        Some("unusable")
    );
}

#[test]
fn a_worked_out_number_has_no_outcome() {
    let mut count = read("count of xs", json!(2), Outcome::Found);
    count.worked = true;
    assert_eq!(outcome(&count, true), None);
}

#[test]
fn a_string_check_with_two_assertions_numbers_them() {
    assert_eq!(
        assertion_locations("r", "c", &json!("x is 1 and y is 2"), None, 2),
        vec![
            "$policy:/requirements/r/checks/c#1",
            "$policy:/requirements/r/checks/c#2"
        ]
    );
}

#[test]
fn a_listed_assert_points_at_each_line_and_escapes_the_keys() {
    assert_eq!(
        assertion_locations(
            "r/s",
            "c~",
            &json!({"assert": ["x is 1 and y is 2", "z is 3"]}),
            None,
            3
        ),
        vec![
            "$policy:/requirements/r~1s/checks/c~0/assert/0#1",
            "$policy:/requirements/r~1s/checks/c~0/assert/0#2",
            "$policy:/requirements/r~1s/checks/c~0/assert/1"
        ]
    );
}

#[test]
fn an_option_written_as_one_string_points_at_the_option() {
    assert_eq!(
        assertion_locations("r", "c", &json!({"any_of": {"o": "a is 1"}}), Some("o"), 1),
        vec!["$policy:/requirements/r/checks/c/any_of/o"]
    );
}

fn record(item: &str, path: &str, cause: &str, text: &str) -> Value {
    json!({
        "path": path,
        "item": item,
        "cause": cause,
        "value": 1,
        "locations": [],
        "ergo/text": text,
    })
}

#[test]
fn an_item_entry_says_its_clauses_without_its_name() {
    use crate::ops::clause::Kind;
    let item = said_clause("item 1 of xs", Cause::Value, "item 1 of xs: w is 2");
    assert_eq!(
        (item.kind, item.said[0].text.as_str()),
        (Kind::Item, "w is 2")
    );
    let root = said_clause("item 2 of xs", Cause::Value, "$params.min is \"s\"");
    assert_eq!(root.kind, Kind::Root);
    let list = said_clause("xs", Cause::Absent, "xs: is missing");
    assert_eq!(
        (list.kind, list.said[0].text.as_str()),
        (Kind::List, "is missing")
    );
    let walked = walk_entries(&[
        record(
            "item 1 of xs",
            "xs[0].v",
            "value",
            "item 1 of xs: v is \"p; q\"",
        ),
        record("item 1 of xs", "xs[0].w", "value", "item 1 of xs: w is 2"),
        record(
            "item 2 of xs",
            "xs[1].v",
            "unusable",
            "$params.min is \"s\"",
        ),
        record("xs", "xs", "absent", "xs: is missing"),
    ]);
    assert_eq!(walked.roots, ["$params.min is \"s\""]);
    let said: Vec<(&str, &str)> = walked
        .entries
        .iter()
        .map(|entry| match entry {
            Failure::Item { part, .. } | Failure::List(part) => {
                (part.name.as_str(), part.message.as_str())
            }
            _ => panic!("an entry that is neither an item nor a list"),
        })
        .collect();
    assert_eq!(
        said,
        [
            ("item 1 of xs", "v is \"p; q\"; w is 2"),
            ("xs", "is missing"),
        ]
    );
}

#[test]
fn walk_entries_read_each_records_clause_kind_and_not_its_text() {
    use crate::ops::clause::Kind;
    let records = [
        record(
            "item 1 of xs",
            "xs[0].v",
            "unusable",
            "item 1 of xs: v is 1",
        ),
        record("item 2 of xs", "xs[1].v", "value", "$params.min is 1"),
        record("xs", "xs", "absent", "xs: is missing"),
    ];
    let clauses = [
        Clause::root("$params.min", Cause::Unusable, "$params.min is \"s\"".to_string()),
        Clause::item(
            "item 2 of xs",
            Cause::Value,
            String::new(),
            vec![Clause::said(Cause::Value, "v is 2".to_string())],
        ),
        Clause {
            said: vec![Clause::said(Cause::Absent, "is missing".to_string())],
            ..Clause::list("xs", Cause::Absent, "xs: is missing".to_string())
        },
    ];
    let walked = walk_entries(&records, &clauses);
    let roots: Vec<(Kind, &str)> = walked
        .roots
        .iter()
        .map(|root| (root.kind, root.text.as_str()))
        .collect();
    assert_eq!(roots, [(Kind::Root, "$params.min is \"s\"")]);
    let said: Vec<(bool, &str, &str)> = walked
        .entries
        .iter()
        .map(|entry| match entry {
            Failure::Item { part, .. } => (true, part.name.as_str(), part.message.as_str()),
            Failure::List(part) => (false, part.name.as_str(), part.message.as_str()),
            _ => panic!("an entry that is neither an item nor a list"),
        })
        .collect();
    assert_eq!(
        said,
        [(true, "item 2 of xs", "v is 2"), (false, "xs", "is missing")]
    );
}
