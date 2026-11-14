use super::*;
use crate::path::{Located, Location, PartStart, Step};
use std::collections::BTreeMap;

fn ctx<'a>(subject: &'a Value, input: &'a Value) -> Ctx<'a> {
    Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: subject,
            location: Location::input_root().key("s"),
        },
        input,
        params: None,
        aliases: BTreeMap::new(),
    }
}

fn present(path: Path, missing: bool) -> Check {
    Check::Present(present::Present { path, missing })
}

fn key(text: &str) -> Step {
    Step::Key(text.to_string())
}

#[test]
fn run_gives_the_verdict_of_the_operator_the_check_holds() {
    let subject = json!({"x": 1});
    let input = json!({});
    let path = Path {
        start: path::Start::Subject,
        steps: vec![key("x")],
    };
    let found = run(&present(path.clone(), false), &ctx(&subject, &input));
    assert!(found.passed());
    let failed = run(&present(path, true), &ctx(&subject, &input));
    assert_eq!(failed.cause, Cause::Value);
    let equals = Check::Equals(equals::Equals {
        path: Path {
            start: path::Start::Subject,
            steps: vec![key("x")],
        },
        value: json!(1),
    });
    assert!(run(&equals, &ctx(&subject, &input)).passed());
}

#[test]
fn an_input_read_through_a_part_is_tagged_with_the_alias_and_the_parts_id() {
    let subject = json!({"d": {"id": "c1", "x": 1}});
    let input = json!({});
    let start = path::Start::Part(Box::new(PartStart {
        name: "cov".into(),
        base: path::Start::Subject,
        steps: vec![key("d")],
        id: Some(vec![key("id")]),
    }));
    let verdict = run(
        &present(
            Path {
                start,
                steps: vec![key("x")],
            },
            false,
        ),
        &ctx(&subject, &input),
    );
    assert_eq!(
        verdict.inputs[0].to_json(),
        json!({"name": "cov.x", "value": 1, "locations": ["/s/d/x"], "part": {"name": "cov", "id": "c1"}})
    );
}

#[test]
fn a_field_step_gives_the_field_as_an_entry_after_the_path_and_null_where_it_is_missing() {
    let input = json!({});
    let path = |subject: &Value| {
        let path = Path {
            start: path::Start::Subject,
            steps: vec![
                key("values"),
                Step::Field(Box::new(Path {
                    start: path::Start::Subject,
                    steps: vec![key("key")],
                })),
            ],
        };
        read_path(&path, &ctx(subject, &input)).inputs
    };
    let found = path(&json!({"key": "k1", "values": {"k1": 5}}));
    assert_eq!(
        found.iter().map(Input::to_json).collect::<Vec<_>>(),
        [
            json!({"name": "values named by key", "value": 5, "locations": ["/s/values/k1"]}),
            json!({"name": "key", "value": "k1", "locations": ["/s/key"]}),
        ]
    );
    let missing = path(&json!({"values": {"k1": 5}}));
    assert_eq!(
        missing[1].to_json(),
        json!({"name": "key", "value": null, "locations": ["/s"]})
    );
}

#[test]
fn an_input_read_without_a_part_has_no_tag() {
    let subject = json!({"x": 1});
    let input = json!({});
    let path = Path {
        start: path::Start::Subject,
        steps: vec![key("x")],
    };
    let verdict = run(&present(path, false), &ctx(&subject, &input));
    assert!(verdict.inputs[0].to_json().get("part").is_none());
}
