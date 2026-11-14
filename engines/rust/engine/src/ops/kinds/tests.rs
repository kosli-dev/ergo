use super::*;
use crate::path::{Located, Location, Start, Step};
use serde_json::json;
use std::collections::BTreeMap;

fn x() -> Path {
    Path {
        start: Start::Subject,
        steps: vec![Step::Key("x".to_string())],
    }
}

fn on(subject: Value, run: impl Fn(&Ctx) -> Verdict) -> Cause {
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
    run(&ctx).cause
}

fn has(kind: Kind, subject: Value) -> Cause {
    on(subject, |ctx| {
        run_has_type(
            &HasType {
                path: x(),
                kind,
                not: false,
            },
            ctx,
        )
    })
}

fn lacks(kind: Kind, subject: Value) -> Cause {
    on(subject, |ctx| {
        run_has_type(
            &HasType {
                path: x(),
                kind,
                not: true,
            },
            ctx,
        )
    })
}

fn non_empty(subject: Value) -> Cause {
    on(subject, |ctx| {
        run_non_empty_string(
            &NonEmptyString {
                path: x(),
                not: false,
            },
            ctx,
        )
    })
}

fn not_non_empty(subject: Value) -> Cause {
    on(subject, |ctx| {
        run_non_empty_string(
            &NonEmptyString {
                path: x(),
                not: true,
            },
            ctx,
        )
    })
}

fn empty(not: bool, subject: Value) -> Cause {
    on(subject, |ctx| run_empty(&Empty { path: x(), not }, ctx))
}

#[test]
fn has_type_passes_on_its_type_and_fails_any_other_as_value() {
    for (kind, good, bad) in [
        (Kind::List, json!([]), json!({})),
        (Kind::String, json!(""), json!(1)),
        (Kind::Number, json!(1.5), json!("1")),
        (Kind::Boolean, json!(false), json!(0)),
        (Kind::Object, json!({}), json!([])),
    ] {
        assert_eq!(has(kind, json!({"x": good})), Cause::Satisfied, "{kind:?}");
        assert_eq!(has(kind, json!({"x": bad})), Cause::Value, "{kind:?}");
    }
}

#[test]
fn lacks_type_passes_on_any_other_type_and_fails_its_own_as_value() {
    for (kind, own, other) in [
        (Kind::List, json!([]), json!({})),
        (Kind::String, json!(""), json!(1)),
        (Kind::Number, json!(1.5), json!("1")),
        (Kind::Boolean, json!(false), json!(0)),
        (Kind::Object, json!({}), json!([])),
    ] {
        assert_eq!(
            lacks(kind, json!({"x": other})),
            Cause::Satisfied,
            "{kind:?}"
        );
        assert_eq!(lacks(kind, json!({"x": own})), Cause::Value, "{kind:?}");
    }
}

#[test]
fn lacks_type_fails_with_the_path_outcome_and_never_passes_on_nothing_read() {
    assert_eq!(lacks(Kind::String, json!({})), Cause::Absent);
    assert_eq!(lacks(Kind::String, json!({"x": null})), Cause::Null);
    assert_eq!(lacks(Kind::String, json!("s")), Cause::NotAnObject);
}

#[test]
fn not_a_non_empty_string_passes_on_an_empty_string_and_on_any_other_type() {
    assert_eq!(not_non_empty(json!({"x": ""})), Cause::Satisfied);
    assert_eq!(not_non_empty(json!({"x": 1})), Cause::Satisfied);
    assert_eq!(not_non_empty(json!({"x": ["a"]})), Cause::Satisfied);
    assert_eq!(not_non_empty(json!({"x": " "})), Cause::Value);
    assert_eq!(not_non_empty(json!({})), Cause::Absent);
    assert_eq!(not_non_empty(json!({"x": null})), Cause::Null);
}

#[test]
fn has_type_fails_with_the_path_outcome_when_nothing_was_read() {
    assert_eq!(has(Kind::String, json!({})), Cause::Absent);
    assert_eq!(has(Kind::String, json!({"x": null})), Cause::Null);
    assert_eq!(has(Kind::String, json!("s")), Cause::NotAnObject);
}

#[test]
fn a_non_empty_string_has_a_character_and_anything_else_fails_as_value() {
    assert_eq!(non_empty(json!({"x": " "})), Cause::Satisfied);
    assert_eq!(non_empty(json!({"x": ""})), Cause::Value);
    assert_eq!(non_empty(json!({"x": 1})), Cause::Value);
    assert_eq!(non_empty(json!({"x": ["a"]})), Cause::Value);
    assert_eq!(non_empty(json!({})), Cause::Absent);
    assert_eq!(non_empty(json!({"x": null})), Cause::Null);
}

#[test]
fn empty_takes_strings_and_lists() {
    assert_eq!(empty(false, json!({"x": ""})), Cause::Satisfied);
    assert_eq!(empty(false, json!({"x": []})), Cause::Satisfied);
    assert_eq!(empty(false, json!({"x": "a"})), Cause::Value);
    assert_eq!(empty(true, json!({"x": [1]})), Cause::Satisfied);
    assert_eq!(empty(true, json!({"x": "a"})), Cause::Satisfied);
    assert_eq!(empty(true, json!({"x": []})), Cause::Value);
}

#[test]
fn empty_fails_anything_else_as_unusable_and_nothing_read_with_the_outcome() {
    for v in [json!(0), json!(false), json!({})] {
        assert_eq!(empty(false, json!({"x": v.clone()})), Cause::Unusable);
        assert_eq!(empty(true, json!({"x": v})), Cause::Unusable);
    }
    assert_eq!(empty(false, json!({})), Cause::Absent);
    assert_eq!(empty(true, json!({"x": null})), Cause::Null);
}
