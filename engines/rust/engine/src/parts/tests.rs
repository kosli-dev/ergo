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

#[test]
fn a_missing_input_is_absent_and_a_null_one_is_null() {
    assert_eq!(
        outcome(&read("x", Value::Null, Outcome::Absent), "", &[]),
        Some("absent")
    );
    assert_eq!(
        outcome(&read("x", Value::Null, Outcome::Null), "", &[]),
        Some("null")
    );
}

#[test]
fn a_value_the_message_says_is_the_wrong_kind_is_unusable() {
    let x = read("x", json!("1"), Outcome::Found);
    let sides = ["x".to_string()];
    assert_eq!(
        outcome(&x, "x is \"1\", which isn't a number", &sides),
        Some("unusable")
    );
    assert_eq!(outcome(&x, "x is \"1\"", &sides), Some("usable"));
}

#[test]
fn a_key_of_the_wrong_kind_is_still_usable_because_the_check_uses_only_what_it_names() {
    let k = read("k", json!(3), Outcome::Found);
    assert_eq!(
        outcome(&k, "k is 3, which isn't text", &["x".to_string()]),
        Some("usable")
    );
}

#[test]
#[ignore = "694: the outcome of an input comes from the check, not from the words of the message"]
fn a_walked_root_stays_usable_when_another_clause_of_the_message_says_which_isnt() {
    let xs = read("$input.xs[]", json!([3]), Outcome::Found);
    assert_eq!(
        outcome(
            &xs,
            "item 1 of $input.xs is 3; $params.q is \"s\", which isn't a number",
            &[]
        ),
        Some("usable")
    );
}

#[test]
fn a_worked_out_number_has_no_outcome() {
    let mut count = read("count of xs", json!(2), Outcome::Found);
    count.worked = true;
    assert_eq!(outcome(&count, "", &[]), None);
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
