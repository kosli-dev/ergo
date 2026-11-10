use ergo_policy_engine::SPEC;
use serde_json::{Value, json};

fn report(subject: &str, from: &str, check: &str, input: Value) -> Value {
    ergo_policy_engine::report(
        &input,
        &json!({
            "ergo_spec": SPEC,
            "subjects": {subject: {"from": from}},
            "requirements": {"r": {"subject": subject, "checks": {"c": check}}}
        }),
        &json!({}),
    )
}

fn rows(report: &Value, check: &str) -> Vec<(String, String)> {
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["check"] == check)
        .map(|row| {
            (
                row["cause"].as_str().unwrap().to_string(),
                row["message"].as_str().unwrap_or("").to_string(),
            )
        })
        .collect()
}

fn things() -> Value {
    json!({"things": [{"x": 1, "name": "a"}, null, 5, {"x": 2}]})
}

#[test]
fn nothing_can_follow_the_subject_name() {
    let report = report("thing", "things", "thing.x is 1", things());
    assert_eq!(
        rows(&report, "$well_formed"),
        [(
            "value".to_string(),
            "checks.c: thing.x: nothing can follow thing, which means the subject: for a field called thing, write .thing.x".to_string()
        )]
    );
}

#[test]
fn the_subject_name_cannot_name_a_key() {
    let report = report("thing", "things", "$input.m named by thing is 1", things());
    assert_eq!(
        rows(&report, "$well_formed"),
        [(
            "value".to_string(),
            "checks.c: named by thing: thing is the whole subject, so it can't name a key"
                .to_string()
        )]
    );
}

#[test]
fn a_check_on_the_subject_name_reads_every_item_and_names_it_in_each_message() {
    let report = report("thing", "things", "thing is not empty", things());
    assert_eq!(
        rows(&report, "c"),
        [
            (
                "unusable",
                "thing is {\"name\": \"a\", \"x\": 1}, which isn't text or a list"
            ),
            ("null", "thing is null"),
            ("unusable", "thing is 5, which isn't text or a list"),
            (
                "unusable",
                "thing is {\"x\": 2}, which isn't text or a list"
            ),
        ]
        .map(|(c, m)| (c.to_string(), m.to_string()))
    );
}

#[test]
fn a_field_named_like_the_subject_is_reached_with_a_dot_and_fails_closed_on_other_items() {
    let report = report("thing", "things", ".thing is not empty", things());
    assert_eq!(
        rows(&report, "c"),
        [
            ("absent", ".thing is missing"),
            ("not_an_object", "thing is null, which isn't an object"),
            ("not_an_object", "thing is 5, which isn't an object"),
            ("absent", ".thing is missing"),
        ]
        .map(|(c, m)| (c.to_string(), m.to_string()))
    );
}

#[test]
fn first_of_the_subject_name_reads_an_item_of_a_list_subject() {
    let report = report("thing", "things", "first of thing is 1", things());
    assert_eq!(
        rows(&report, "c"),
        [
            (
                "unusable",
                "thing is {\"name\": \"a\", \"x\": 1}, which isn't a list"
            ),
            ("null", "thing is null"),
            ("unusable", "thing is 5, which isn't a list"),
            ("unusable", "thing is {\"x\": 2}, which isn't a list"),
        ]
        .map(|(c, m)| (c.to_string(), m.to_string()))
    );
}

#[test]
fn a_subject_called_it_is_an_ordinary_name() {
    let report = report("it", "its", "it is not empty", json!({"its": [{"v": 1}]}));
    assert_eq!(rows(&report, "$well_formed")[0].0, "satisfied");
    assert_eq!(
        rows(&report, "c"),
        [(
            "unusable".to_string(),
            "it is {\"v\": 1}, which isn't text or a list".to_string()
        )]
    );
}

#[test]
fn the_subjects_name_in_its_own_from_line_whose_reads_the_items_own_field() {
    let report = report(
        "kid",
        "kids whose kid is 1",
        "kid is not empty",
        json!({"kids": [{"v": 1, "x": 1}, 4]}),
    );
    assert_eq!(
        rows(&report, "$applies"),
        [
            ("absent", ".kid is missing"),
            ("not_an_object", "kid is 4, which isn't an object"),
        ]
        .map(|(c, m)| (c.to_string(), m.to_string()))
    );
}
