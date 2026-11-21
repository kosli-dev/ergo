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
        steps: steps
            .iter()
            .map(|s| Step::Key(s.to_string()))
            .chain([Step::Members])
            .collect(),
    };
    let walked = walk(&path, &ctx, options);
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
fn every_member_of_an_object_with_no_list_on_the_path_passes_when_each_member_passes() {
    let subject = json!({"e": {"a": 1, "b": 1}});
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
    let walk = Walk {
        quantifier: Quantifier::Every,
        path: Path {
            start: Start::Subject,
            steps: vec![Step::Key("e".to_string()), Step::Members],
        },
        distinct: false,
        whose: Vec::new(),
        if_any: false,
        check: Box::new(Check::Equals(crate::ops::equals::Equals {
            path: Path {
                start: Start::Subject,
                steps: Vec::new(),
            },
            value: json!(1),
        })),
        for_aliases: Vec::new(),
    };
    assert_eq!(run(&walk, &ctx).verdict.cause, Cause::Satisfied);
    let walked = walk_of(&walk, &ctx);
    assert_eq!(walked.name, "e");
    assert!(walked.walked_last());
}

fn walk_of<'a>(walk: &Walk, ctx: &Ctx<'a>) -> Walked<'a> {
    super::super::walk(&walk.path, ctx, Options::default())
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

#[test]
fn a_failed_member_is_named_by_its_key_in_the_failed_items() {
    let subject = json!({"rs": [{"e": {"a": 1, "b": 2}}]});
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
    let walk = Walk {
        quantifier: Quantifier::Every,
        path: Path {
            start: Start::Subject,
            steps: vec![
                Step::Key("rs".to_string()),
                Step::Key("e".to_string()),
                Step::Members,
            ],
        },
        distinct: false,
        whose: Vec::new(),
        if_any: false,
        check: Box::new(Check::Equals(crate::ops::equals::Equals {
            path: Path {
                start: Start::Subject,
                steps: Vec::new(),
            },
            value: json!(1),
        })),
        for_aliases: Vec::new(),
    };
    let row = run(&walk, &ctx);
    assert_eq!(row.failed_items.len(), 1);
    assert_eq!(row.failed_items[0]["item"], json!("member b of rs[0].e"));
}

fn for_row(line: &str, assertion: &str, subject: Value) -> Value {
    let policy = json!({
        "ergo_spec": crate::SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": line, "assert": assertion}}}}
    });
    let mut subject = subject;
    subject["id"] = json!(1);
    let report = crate::report(&json!({"things": [subject]}), &policy, &json!({}));
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

fn entries(row: &Value) -> Vec<(String, String, Vec<String>)> {
    row["failures"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| {
            (
                f["kind"].as_str().unwrap().to_string(),
                f["name"].as_str().unwrap().to_string(),
                f["inputs"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|i| i["name"].as_str().unwrap().to_string())
                    .collect(),
            )
        })
        .collect()
}

#[test]
fn a_member_a_for_line_whose_cannot_decide_is_an_item_entry_named_by_its_key() {
    let row = for_row(
        "every member of ev whose k is 1 as e",
        "e.s is \"OK\"",
        json!({"ev": {"a": {"s": 1}, "b": 3, "c": {"k": 1}}}),
    );
    let found = entries(&row);
    assert_eq!(
        found[1..],
        [
            (
                "item".to_string(),
                "member a of ev".to_string(),
                vec!["ev.a.k".to_string()]
            ),
            ("item".to_string(), "member b of ev".to_string(), Vec::new()),
        ]
    );
    let row = for_row(
        "every member of ev as e",
        "e.s is \"OK\"",
        json!({"ev": {"a": 1}}),
    );
    assert_eq!(
        entries(&row),
        [("item".to_string(), "member a of ev".to_string(), Vec::new())]
    );
}

#[test]
fn a_for_line_says_a_value_it_reads_members_of_isnt_an_object() {
    let row = for_row(
        "every member of ev as e",
        "e.s is \"OK\"",
        json!({"ev": [1]}),
    );
    assert_eq!(row["message"], json!("ev is [1], which isn't an object"));
    let row = for_row(
        "every rs as r, every member of r.ev as f",
        "f.s is \"OK\"",
        json!({"rs": [{"ev": {"a": {"s": "OK"}}}, {"ev": 3}]}),
    );
    assert_eq!(
        row["message"],
        json!("item 2 of rs: r.ev is 3, which isn't an object")
    );
}
