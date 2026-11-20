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
    let checks: Vec<crate::ops::Check> = sentences.iter().map(|s| lowered(s)).collect();
    let all: Vec<&crate::ops::Check> = checks.iter().collect();
    let ctx = crate::path::Ctx {
        subject: crate::path::Located {
            value: input,
            location: crate::path::Location::input_root(),
        },
        input,
        params,
        aliases: std::collections::BTreeMap::new(),
        label: None,
        item_by_item: checks.iter().any(crate::ops::Check::reads_by_item),
        in_option: false,
    };
    let read = checks
        .iter()
        .flat_map(|check| crate::ops::run(check, &ctx).inputs)
        .find(|read| read.name == name)
        .unwrap();
    outcome(&read, crate::checks::input_unfit(&all, &read, &ctx))
}

#[test]
fn a_missing_input_is_absent_and_a_null_one_is_null() {
    assert_eq!(
        outcome(&read("x", Value::Null, Outcome::Absent), true),
        Some("absent")
    );
    assert_eq!(
        outcome(&read("x", Value::Null, Outcome::Null), true),
        Some("null")
    );
}

#[test]
fn a_found_value_is_unusable_only_when_the_check_cant_use_it() {
    let x = read("x", json!("1"), Outcome::Found);
    assert_eq!(outcome(&x, true), Some("unusable"));
    assert_eq!(outcome(&x, false), Some("usable"));
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
