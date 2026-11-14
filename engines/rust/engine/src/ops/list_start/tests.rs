use crate::SPEC;
use serde_json::{Value, json};

fn row(check: Value, subject: Value) -> Value {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"t": {"from": "every xs"}},
        "requirements": {"r": {"subject": "t", "checks": {"c": check}}}
    });
    let report = crate::report(&json!({"xs": [subject]}), &policy, &json!({"w": "a"}));
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

#[test]
fn every_walks_a_subject_that_is_a_list_and_names_it_after_the_subject() {
    let found = row(
        json!("every name is \"a\""),
        json!([{"name": "a"}, {"name": "b"}]),
    );
    assert_eq!(found["cause"], "value");
    assert_eq!(found["inputs"][0]["name"], "t[].name");
    assert_eq!(found["failed_items"][0]["path"], "t[1].name");
    assert_eq!(found["message"], "item 2 of t: name is \"b\"");
}

#[test]
fn the_right_side_of_is_in_walks_a_subject_that_is_a_list_but_contains_does_not() {
    let subject = json!([{"name": "a"}, {"name": "b"}]);
    assert_eq!(
        row(json!("$params.w is in name"), subject.clone())["cause"],
        "satisfied"
    );
    assert_eq!(
        row(json!("$params.w contains name"), subject)["cause"],
        "not_an_object"
    );
}

#[test]
fn a_path_without_a_walking_word_still_fails_on_a_subject_that_is_a_list() {
    assert_eq!(
        row(json!("name is \"a\""), json!([{"name": "a"}]))["cause"],
        "not_an_object"
    );
}

#[test]
fn a_for_item_with_a_position_reads_a_list_subject_as_before() {
    let check = json!({"for": "first of owner as o", "assert": "o is \"a\""});
    assert_eq!(
        row(check, json!([{"owner": "a"}]))["cause"],
        "not_an_object"
    );
}

#[test]
fn a_named_by_key_read_from_a_subject_that_is_a_list_fails_the_whole_check() {
    let found = row(
        json!("every n is less than $params.m named by k"),
        json!([{"n": 1, "k": "a"}]),
    );
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(found["failed_items"], json!([]));
}
