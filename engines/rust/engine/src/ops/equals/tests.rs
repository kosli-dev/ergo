use super::*;
use crate::path::{Located, Location, Start, Step};
use serde_json::json;
use std::collections::BTreeMap;

fn cause(subject: Value, value: Value) -> Cause {
    let input = json!({"things": [subject]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let check = Equals {
        path: Path {
            start: Start::Subject,
            steps: vec![Step::Key("x".to_string())],
        },
        value,
    };
    run(&check, &ctx).cause
}

fn parsed(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

#[test]
fn passes_on_an_equal_value_and_fails_as_value_otherwise() {
    assert_eq!(cause(json!({"x": "a"}), json!("a")), Cause::Satisfied);
    assert_eq!(cause(json!({"x": "b"}), json!("a")), Cause::Value);
}

#[test]
fn numbers_compare_by_value() {
    assert_eq!(cause(parsed(r#"{"x": 1.0}"#), json!(1)), Cause::Satisfied);
    assert_eq!(cause(json!({"x": 150}), parsed("1.5e2")), Cause::Satisfied);
}

#[test]
fn a_value_of_another_type_fails_as_unusable() {
    assert_eq!(cause(json!({"x": "1"}), json!(1)), Cause::Unusable);
    assert_eq!(cause(json!({"x": [1]}), json!(1)), Cause::Unusable);
}

#[test]
fn a_missing_field_fails_as_absent_even_against_null() {
    assert_eq!(cause(json!({}), json!("a")), Cause::Absent);
    assert_eq!(cause(json!({}), Value::Null), Cause::Absent);
}

#[test]
fn a_null_field_passes_null_and_fails_anything_else_as_null() {
    assert_eq!(cause(json!({"x": null}), Value::Null), Cause::Satisfied);
    assert_eq!(cause(json!({"x": null}), json!("a")), Cause::Null);
}

#[test]
fn a_field_that_was_read_fails_null_as_value() {
    assert_eq!(cause(json!({"x": 0}), Value::Null), Cause::Value);
    assert_eq!(cause(json!({"x": ""}), Value::Null), Cause::Value);
}

#[test]
fn a_parent_that_cannot_hold_the_field_fails_with_its_outcome() {
    assert_eq!(cause(json!("s"), json!(1)), Cause::NotAnObject);
}
