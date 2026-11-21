use super::super::*;
use std::collections::BTreeMap;

fn members(
    subject: Value,
    steps: &[&str],
    options: Options,
) -> (
    Vec<(String, Value, String)>,
    Vec<(Cause, Value, String)>,
    String,
) {
    let input = json!({});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &subject,
            location: Location::input_root().key("s"),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let path = Path {
        start: Start::Subject,
        steps: steps.iter().map(|s| Step::Key(s.to_string())).collect(),
    };
    let walked = walk(
        &path,
        &ctx,
        Options {
            member: true,
            ..options
        },
    );
    (
        walked
            .items
            .iter()
            .map(|item| {
                (
                    walked.item_name(&item.item_segs),
                    item.shown(),
                    item.end_location.render(),
                )
            })
            .collect(),
        walked
            .failures
            .iter()
            .map(|failure| (failure.cause, failure.value.clone(), failure.msg.clone()))
            .collect(),
        walked.name,
    )
}

#[test]
fn each_member_of_the_object_the_path_ends_at_is_an_item_in_key_order_named_by_its_key() {
    let (items, failures, name) = members(
        json!({"e": {"b": 2, "a": 1, "a; b": 3, "": 4, "1": 5}}),
        &["e"],
        Options::default(),
    );
    assert!(failures.is_empty());
    assert_eq!(name, "e");
    assert_eq!(
        items,
        [
            (
                "member \"\" of e".to_string(),
                json!(4),
                "/s/e/".to_string()
            ),
            (
                "member \"1\" of e".to_string(),
                json!(5),
                "/s/e/1".to_string()
            ),
            ("member a of e".to_string(), json!(1), "/s/e/a".to_string()),
            (
                "member \"a; b\" of e".to_string(),
                json!(3),
                "/s/e/a; b".to_string()
            ),
            ("member b of e".to_string(), json!(2), "/s/e/b".to_string()),
        ]
    );
}

#[test]
fn a_list_along_the_path_is_walked_but_the_one_it_ends_at_is_not() {
    let (items, failures, name) = members(
        json!({"rs": [{"e": {"k": 1}}, {"e": [{"k": 2}]}]}),
        &["rs", "e"],
        Options::default(),
    );
    assert_eq!(name, "rs[].e");
    assert_eq!(
        items,
        [(
            "item 1 of rs: member k of e".to_string(),
            json!(1),
            "/s/rs/0/e/k".to_string()
        )]
    );
    assert_eq!(
        failures,
        [(
            Cause::Unusable,
            json!([{"k": 2}]),
            "item 2 of rs: e is [{\"k\": 2}], which isn't an object".to_string()
        )]
    );
}

#[test]
fn an_end_that_is_missing_or_null_keeps_its_cause_and_one_that_is_not_an_object_is_unusable() {
    for (subject, cause, said) in [
        (json!({}), Cause::Absent, "e is missing"),
        (json!({"e": null}), Cause::Null, "e is null"),
        (
            json!({"e": "x"}),
            Cause::Unusable,
            "e is \"x\", which isn't an object",
        ),
        (
            json!({"e": [1]}),
            Cause::Unusable,
            "e is [1], which isn't an object",
        ),
    ] {
        let (items, failures, _) = members(subject, &["e"], Options::default());
        assert!(items.is_empty());
        assert_eq!(failures.len(), 1);
        assert_eq!((failures[0].0, failures[0].2.as_str()), (cause, said));
    }
}

#[test]
fn an_object_with_no_members_fails_as_value_unless_if_any_or_a_tally_skips_it() {
    let (items, failures, _) = members(json!({"e": {}}), &["e"], Options::default());
    assert!(items.is_empty());
    assert_eq!(failures, [(Cause::Value, json!({}), "e is {}".to_string())]);
    for options in [
        Options {
            if_any: true,
            ..Options::default()
        },
        Options {
            empty_adds_nothing: true,
            ..Options::default()
        },
    ] {
        let (items, failures, _) = members(json!({"e": {}}), &["e"], options);
        assert!(items.is_empty() && failures.is_empty());
    }
}
