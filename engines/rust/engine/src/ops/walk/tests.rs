use super::*;
use crate::ops::{equals::Equals, present::Present};
use std::collections::BTreeMap;

fn key(text: &str) -> Step {
    Step::Key(text.to_string())
}

fn at(start: Start, steps: &[&str]) -> Path {
    Path {
        start,
        steps: steps.iter().map(|s| key(s)).collect(),
    }
}

fn ctx<'a>(subject: &'a Value, input: &'a Value, params: Option<&'a Value>) -> Ctx<'a> {
    Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: subject,
            location: Location::input_root().key("s"),
        },
        input,
        params,
        aliases: BTreeMap::new(),
    }
}

fn walked(subject: Value, steps: &[&str], options: Options) -> (Vec<Value>, Vec<Value>, String) {
    let input = json!({});
    let context = ctx(&subject, &input, None);
    let result = walk(&at(Start::Subject, steps), &context, options);
    (
        result.items.iter().map(WalkItem::shown).collect(),
        result.failures.iter().map(Failure::to_json).collect(),
        result.name,
    )
}

fn every(steps: &[&str], whose: Vec<Check>, check: Check, if_any: bool) -> Walk {
    Walk {
        quantifier: Quantifier::Every,
        path: at(Start::Subject, steps),
        distinct: false,
        whose,
        if_any,
        check: Box::new(check),
        for_aliases: Vec::new(),
    }
}

fn equals(value: Value) -> Check {
    Check::Equals(Equals {
        path: at(Start::Subject, &[]),
        value,
    })
}

fn present(missing: bool) -> Check {
    Check::Present(Present {
        path: at(Start::Subject, &[]),
        missing,
    })
}

fn row(walk: &Walk, subject: Value) -> Run {
    let input = json!({});
    let params = json!({});
    run(walk, &ctx(&subject, &input, Some(&params)))
}

#[test]
fn a_walk_without_a_flawed_check_is_not_flawed_and_one_inside_an_any_of_is_asked_too() {
    let inner = every(&["ys"], vec![], equals(json!(1)), false);
    let wrapped = every(
        &["xs"],
        vec![Check::AnyOf(crate::ops::any_of::AnyOf {
            names: Vec::new(),
            texts: Vec::new(),
            options: vec![vec![Check::Walk(Box::new(inner))]],
        })],
        equals(json!(1)),
        false,
    );
    let subject = json!({"xs": [{"ys": [1]}]});
    let input = json!({});
    assert!(!wrapped.flawed(&ctx(&subject, &input, None)));
    assert!(!Check::Walk(Box::new(wrapped)).flawed(&ctx(&subject, &input, None)));
}

#[test]
fn the_last_list_is_walked_and_its_items_are_the_ends() {
    let (items, failures, name) = walked(
        json!({"xs": [{"a": 1}, {"a": 2}]}),
        &["xs", "a"],
        Options::default(),
    );
    assert_eq!(items, [json!(1), json!(2)]);
    assert!(failures.is_empty());
    assert_eq!(name, "xs[].a");
    let (items, _, name) = walked(json!({"xs": ["a", "b"]}), &["xs"], Options::default());
    assert_eq!(items, [json!("a"), json!("b")]);
    assert_eq!(name, "xs[]");
}

#[test]
fn every_list_along_the_path_is_walked_and_named_with_brackets() {
    let (items, _, name) = walked(
        json!({"ps": [{"cs": [{"s": 1}, {"s": 2}]}, {"cs": [{"s": 3}]}]}),
        &["ps", "cs", "s"],
        Options::default(),
    );
    assert_eq!(items, [json!(1), json!(2), json!(3)]);
    assert_eq!(name, "ps[].cs[].s");
}

#[test]
fn an_empty_list_fails_as_value_unless_if_any_or_a_tally_skips_it() {
    let subject = json!({"xs": []});
    let (_, failures, _) = walked(subject.clone(), &["xs", "a"], Options::default());
    assert_eq!(failures[0]["cause"], json!("value"));
    assert_eq!(failures[0]["path"], json!("xs"));
    assert_eq!(failures[0]["value"], json!([]));
    for options in [
        Options {
            if_any: true,
            empty_adds_nothing: false,
        },
        Options {
            if_any: false,
            empty_adds_nothing: true,
        },
    ] {
        let (items, failures, _) = walked(subject.clone(), &["xs", "a"], options);
        assert!(items.is_empty() && failures.is_empty());
    }
}

#[test]
fn a_list_that_is_missing_null_or_not_a_list_fails_where_another_is_walked() {
    let (items, failures, _) = walked(
        json!({"ps": [{"cs": [{"s": 1}]}, {}, {"cs": null}, {"cs": "none"}]}),
        &["ps", "cs", "s"],
        Options::default(),
    );
    assert_eq!(items, [json!(1)]);
    let causes: Vec<&Value> = failures.iter().map(|f| &f["cause"]).collect();
    assert_eq!(
        causes,
        [&json!("absent"), &json!("null"), &json!("unusable")]
    );
    assert_eq!(failures[0]["path"], json!("ps[1].cs"));
    assert_eq!(failures[0]["locations"], json!(["/s/ps/1"]));
    assert_eq!(failures[1]["locations"], json!(["/s/ps/2/cs"]));
    assert_eq!(failures[2]["value"], json!("none"));
}

#[test]
fn a_path_with_no_list_fails_once_where_it_stops_and_walks_nothing() {
    let (items, failures, name) = walked(json!({"x": {"y": 1}}), &["x", "y"], Options::default());
    assert!(items.is_empty());
    assert_eq!(name, "x.y");
    assert_eq!(failures.len(), 1);
    assert_eq!(failures[0]["path"], json!("x.y"));
    assert_eq!(failures[0]["cause"], json!("unusable"));
    assert_eq!(failures[0]["value"], json!(1));
    let (_, failures, _) = walked(json!({"x": null}), &["x", "y"], Options::default());
    assert_eq!(failures[0]["cause"], json!("null"));
    assert_eq!(failures[0]["path"], json!("x"));
    let (_, failures, _) = walked(json!({}), &["x", "y"], Options::default());
    assert_eq!(failures[0]["cause"], json!("absent"));
}

#[test]
fn a_position_is_read_and_never_walked() {
    let input = json!({});
    let subject = json!({"xs": [[1, 2], [3]]});
    let context = ctx(&subject, &input, None);
    let path = Path {
        start: Start::Subject,
        steps: vec![key("xs"), Step::Index(0)],
    };
    let result = walk(&path, &context, Options::default());
    let shown: Vec<Value> = result.items.iter().map(WalkItem::shown).collect();
    assert_eq!(shown, [json!(1), json!(2)]);
    assert_eq!(result.name, "xs[0][]");
    assert_eq!(
        result.items[0].item_segs,
        [Seg::Key("xs".into()), Seg::Index(0), Seg::Index(0)]
    );
}

#[test]
fn failures_are_in_path_order_with_positions_by_number() {
    let mut list = Vec::new();
    for at in 0..12 {
        list.push(if at == 2 || at == 10 {
            json!({"cs": null})
        } else {
            json!({"cs": [{"s": 1}]})
        });
    }
    let (_, failures, _) = walked(json!({"ps": list}), &["ps", "cs", "s"], Options::default());
    assert_eq!(failures[0]["path"], json!("ps[2].cs"));
    assert_eq!(failures[1]["path"], json!("ps[10].cs"));
}

#[test]
fn an_unreadable_ref_step_walks_nothing_and_says_why() {
    let input = json!({});
    let subject = json!({"xs": [1]});
    let context = ctx(&subject, &input, None);
    let path = Path {
        start: Start::Subject,
        steps: vec![key("xs"), Step::Ref(Box::new(at(Start::Params, &["k"])))],
    };
    let result = walk(&path, &context, Options::default());
    assert_eq!(result.unreadable, Some(Outcome::Absent));
    assert!(result.items.is_empty());
    assert_eq!(result.name, "xs named by $params.k");
}

#[test]
fn every_passes_when_each_item_passes_and_lists_nothing() {
    let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    let out = row(&walk, json!({"xs": [{"ok": true}, {"ok": true}]}));
    assert!(out.verdict.passed());
    assert!(out.failed_items.is_empty());
    assert_eq!(
        out.verdict.inputs[0].to_json(),
        json!({"name": "xs[].ok", "value": [true, true], "locations": ["/s/xs/0/ok", "/s/xs/1/ok"]})
    );
}

#[test]
fn every_fails_with_value_and_lists_each_item_that_failed_in_path_order() {
    let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    let out = row(
        &walk,
        json!({"xs": [{"ok": false}, {"ok": true}, {"ok": false}]}),
    );
    assert_eq!(out.verdict.cause, Cause::Value);
    assert_eq!(
        out.failed_items,
        [
            json!({"path": "xs[0].ok", "item": "item 1 of xs", "cause": "value", "value": false, "locations": ["/s/xs/0/ok"]}),
            json!({"path": "xs[2].ok", "item": "item 3 of xs", "cause": "value", "value": false, "locations": ["/s/xs/2/ok"]}),
        ]
    );
}

#[test]
fn a_value_missing_at_the_end_fails_the_item_as_absent_and_shows_null() {
    let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    let out = row(&walk, json!({"xs": [{"ok": true}, {}]}));
    assert_eq!(out.verdict.cause, Cause::Absent);
    assert_eq!(out.verdict.inputs[0].value, json!([true, null]));
    assert_eq!(out.failed_items[0]["value"], Value::Null);
    assert_eq!(out.failed_items[0]["locations"], json!(["/s/xs/1"]));
}

#[test]
fn every_over_no_items_fails_as_value_unless_if_any() {
    let strict = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    let lenient = every(&["xs", "ok"], vec![], equals(json!(true)), true);
    let subject = json!({"xs": []});
    assert_eq!(row(&strict, subject.clone()).verdict.cause, Cause::Value);
    let out = row(&lenient, subject);
    assert!(out.verdict.passed());
    assert!(out.failed_items.is_empty());
}

#[test]
fn an_item_that_is_not_an_object_misses_as_not_an_object_when_the_path_goes_on_into_it() {
    let input = json!({});
    let subject = json!({"xs": ["str", null, {"y": 1}, {"y": "s"}]});
    let context = ctx(&subject, &input, None);
    let result = walk(
        &at(Start::Subject, &["xs", "y"]),
        &context,
        Options::default(),
    );
    let misses: Vec<Option<Cause>> = result
        .items
        .iter()
        .map(|item| item.end.is_none().then_some(item.miss))
        .collect();
    assert_eq!(
        misses,
        [
            Some(Cause::NotAnObject),
            Some(Cause::NotAnObject),
            None,
            None
        ]
    );
    let ends = walk(&at(Start::Subject, &["xs"]), &context, Options::default());
    assert!(ends.items.iter().all(|item| item.end.is_some()));
}

#[test]
fn every_and_some_fail_an_item_that_is_not_an_object_as_not_an_object() {
    let subject = json!({"xs": ["str", {"y": 1}]});
    let walk = every(&["xs", "y"], vec![], equals(json!(1)), false);
    let out = row(&walk, subject.clone());
    assert_eq!(out.verdict.cause, Cause::NotAnObject);
    assert_eq!(out.failed_items[0]["cause"], json!("not_an_object"));
    assert_eq!(out.failed_items[0]["item"], json!("item 1 of xs"));
    let mut some = walk.clone();
    some.quantifier = Quantifier::Some;
    assert!(row(&some, subject).verdict.passed());
}

#[test]
fn every_fails_with_the_worst_cause_of_what_failed() {
    let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    let out = row(&walk, json!({"xs": [{"ok": false}, {}, {"ok": null}]}));
    assert_eq!(out.verdict.cause, Cause::Absent);
    let out = row(&walk, json!({"xs": [{"ok": false}, "s"]}));
    assert_eq!(out.verdict.cause, Cause::NotAnObject);
}

#[test]
fn some_passes_when_one_item_passes_and_fails_with_the_first_cause_otherwise() {
    let mut walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    walk.quantifier = Quantifier::Some;
    let out = row(&walk, json!({"xs": [{"ok": false}, {"ok": true}]}));
    assert!(out.verdict.passed());
    assert!(out.failed_items.is_empty());
    let out = row(&walk, json!({"xs": [{"ok": false}, {}]}));
    assert_eq!(out.verdict.cause, Cause::Absent);
    assert_eq!(out.failed_items.len(), 2);
    let out = row(&walk, json!({"xs": []}));
    assert_eq!(out.verdict.cause, Cause::Value);
}

#[test]
fn whose_reads_the_value_the_path_ends_at_and_leaves_out_an_item_that_fails_it() {
    let whose = Check::Equals(Equals {
        path: at(Start::Subject, &["k"]),
        value: json!("a"),
    });
    let walk = every(&["xs", "ok"], vec![whose], present(false), false);
    let subject = json!({"xs": [{"ok": {"k": "a"}}, {"k": "a", "ok": {"k": "b"}}]});
    let out = row(&walk, subject);
    assert!(out.verdict.passed());
    assert_eq!(out.verdict.inputs[0].value, json!([{"k": "a"}, {"k": "b"}]));
    let none = row(&walk, json!({"xs": [{"k": "a", "ok": {"k": "b"}}]}));
    assert_eq!(none.verdict.cause, Cause::Value);
    assert!(none.failed_items.is_empty());
}

#[test]
fn an_item_whose_cannot_decide_fails_the_check_with_its_cause_and_is_listed_by_the_whose_field_under_the_focus()
 {
    let whose = Check::Equals(Equals {
        path: at(Start::Subject, &["k"]),
        value: json!("a"),
    });
    let walk = every(&["xs", "ok"], vec![whose.clone()], present(false), false);
    let subject = json!({"xs": [{"ok": {"k": "a"}}, {"k": "a", "ok": {}}]});
    let out = row(&walk, subject.clone());
    assert_eq!(out.verdict.cause, Cause::Absent);
    assert_eq!(
        out.failed_items,
        [
            json!({"path": "xs[1].ok.k", "item": "item 2 of xs", "cause": "absent", "value": null, "locations": ["/s/xs/1/ok"]})
        ]
    );
    let mut some = walk.clone();
    some.quantifier = Quantifier::Some;
    assert!(row(&some, subject).verdict.passed());
}

#[test]
fn a_present_whose_that_finds_its_field_missing_leaves_the_item_out_and_does_not_undecide_it() {
    let whose = Check::Present(Present {
        path: at(Start::Subject, &["note"]),
        missing: false,
    });
    let walk = every(&["xs", "ok"], vec![whose], present(false), false);
    let out = row(
        &walk,
        json!({"xs": [{"ok": {"note": 1}}, {"note": 1, "ok": {}}]}),
    );
    assert!(out.verdict.passed());
}

#[test]
fn a_subject_that_is_not_an_object_fails_a_walk_that_starts_at_it_with_nothing_read() {
    let walk = every(&["xs", "ok"], vec![], equals(json!(true)), false);
    let out = row(&walk, json!("s"));
    assert_eq!(out.verdict.cause, Cause::NotAnObject);
    assert!(out.verdict.inputs.is_empty());
    assert!(out.failed_items.is_empty());
    let on_it = every(&[], vec![], equals(json!(1)), false);
    let out = row(&on_it, json!([1, 2]));
    assert_eq!(out.verdict.cause, Cause::Value);
    assert_eq!(out.verdict.inputs[0].name, "the subject[]");
}

#[test]
fn a_ref_step_that_cannot_be_read_fails_with_its_cause_and_shows_an_empty_list() {
    let mut walk = every(&["xs"], vec![], equals(json!(1)), false);
    walk.path
        .steps
        .push(Step::Ref(Box::new(at(Start::Params, &["k"]))));
    let out = row(&walk, json!({"xs": [1]}));
    assert_eq!(out.verdict.cause, Cause::Absent);
    assert!(out.failed_items.is_empty());
    assert_eq!(
        out.verdict.inputs[0].to_json(),
        json!({"name": "xs named by $params.k", "value": [], "locations": []})
    );
}

#[test]
fn a_path_read_from_outside_the_item_is_listed_once_and_params_are_not() {
    let input = json!({"staff": ["ann"]});
    let subject = json!({"xs": [{"n": "ann"}]});
    let params = json!({});
    let context = ctx(&subject, &input, Some(&params));
    let outside = Check::Compare(crate::ops::compare::Compare {
        left: crate::ops::compare::Side::Path(at(Start::Subject, &[])),
        right: crate::ops::compare::Side::Path(at(Start::Input, &["staff"])),
        cmp: crate::ops::compare::Cmp::Eq,
        within: None,
        ignoring: None,
    });
    let walk = every(&["xs", "n"], vec![], outside, false);
    let out = run(&walk, &context);
    let names: Vec<&str> = out.verdict.inputs.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, ["$input.staff", "xs[].n"]);
}

#[test]
fn the_inputs_of_a_walk_are_sorted_by_name_so_a_parent_that_sorts_first_comes_first() {
    let input = json!({"a": 1});
    let subject = json!({"xs": [{"n": 1}]});
    let params = json!({});
    let context = ctx(&subject, &input, Some(&params));
    let outside = Check::Compare(crate::ops::compare::Compare {
        left: crate::ops::compare::Side::Path(at(Start::Subject, &[])),
        right: crate::ops::compare::Side::Path(at(Start::Input, &["a"])),
        cmp: crate::ops::compare::Cmp::Eq,
        within: None,
        ignoring: None,
    });
    let walk = every(&["xs", "n"], vec![], outside, false);
    let out = run(&walk, &context);
    let names: Vec<&str> = out.verdict.inputs.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, ["$input.a", "xs[].n"]);
}

#[test]
fn present_inside_a_walk_reads_the_rest_of_the_path_on_each_item() {
    let walk = every(&["xs", "ok"], vec![], present(false), false);
    let out = row(&walk, json!({"xs": [{"ok": 1}, {}]}));
    assert_eq!(out.verdict.cause, Cause::Value);
    assert_eq!(out.failed_items.len(), 1);
    assert_eq!(out.failed_items[0]["path"], json!("xs[1].ok"));
}

#[test]
fn a_walk_through_a_part_names_its_entry_with_the_part_and_tags_it() {
    let subject = json!({"d": {"items": [{"x": 1}]}});
    let input = json!({});
    let context = ctx(&subject, &input, None);
    let start = Start::Part(Box::new(path::PartStart {
        name: "lst".into(),
        base: Start::Subject,
        steps: vec![key("d"), key("items")],
        id: None,
    }));
    let path = Path {
        start,
        steps: vec![key("x")],
    };
    let walk = Walk {
        quantifier: Quantifier::Every,
        path,
        distinct: false,
        whose: vec![],
        if_any: false,
        check: Box::new(equals(json!(2))),
        for_aliases: Vec::new(),
    };
    let out = run(&walk, &context);
    assert_eq!(
        out.verdict.inputs[0].to_json(),
        json!({"name": "lst[].x", "value": [1], "locations": ["/s/d/items/0/x"], "part": {"name": "lst", "id": null}})
    );
    assert_eq!(out.failed_items[0]["path"], json!("lst[0].x"));
}

#[test]
fn a_walk_through_a_list_inside_a_part_is_named_with_the_full_path() {
    let subject = json!({"prs": [{"rs": [{"s": "ok"}]}]});
    let input = json!({});
    let context = ctx(&subject, &input, None);
    let start = Start::Part(Box::new(path::PartStart {
        name: "rs".into(),
        base: Start::Subject,
        steps: vec![key("prs"), key("rs")],
        id: None,
    }));
    let walk = Walk {
        quantifier: Quantifier::Every,
        path: Path {
            start,
            steps: vec![key("s")],
        },
        distinct: false,
        whose: vec![],
        if_any: false,
        check: Box::new(equals(json!("bad"))),
        for_aliases: Vec::new(),
    };
    let out = run(&walk, &context);
    assert_eq!(out.verdict.inputs[0].name, "prs[].rs[].s");
    assert_eq!(out.failed_items[0]["path"], json!("prs[0].rs[0].s"));
}

fn lowered(sentence: &str) -> Check {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap()
}

fn own_said(
    sentence: &str,
    items: Value,
    params: Value,
    input: Value,
) -> Vec<Option<(Cause, String)>> {
    let Check::Walk(walk_check) = lowered(sentence) else {
        panic!("{sentence} is not every or some");
    };
    let subject = json!({"items": items});
    let context = ctx(&subject, &input, Some(&params));
    let outer = outer(&context);
    let walked = walk(&walk_check.path, &outer, Options::default());
    walked
        .items
        .iter()
        .map(|item| {
            item_own(&walk_check.whose[0], item, &walked, &outer).map(|said| {
                (
                    said.cause,
                    crate::ops::clause::text(std::slice::from_ref(&said)),
                )
            })
        })
        .collect()
}

#[test]
fn an_item_says_the_value_before_a_key_it_cant_read_and_not_the_key() {
    assert_eq!(
        own_said(
            "every items.v that is m named by $params.k is 1",
            json!([{"v": {}}, {"v": {"m": null}}]),
            json!({}),
            json!({}),
        ),
        [
            Some((
                Cause::Absent,
                "item 1 of items: v: m is missing".to_string()
            )),
            Some((Cause::Null, "item 2 of items: v: m is null".to_string())),
        ]
    );
}

#[test]
fn an_item_whose_focus_isnt_an_object_says_so_whatever_the_key() {
    for params in [json!({}), json!({"k": null}), json!({"k": 3})] {
        assert_eq!(
            own_said(
                "every items.v that is m named by $params.k is 1",
                json!([{"v": "s"}, {"v": null}]),
                params.clone(),
                json!({}),
            ),
            [
                Some((
                    Cause::NotAnObject,
                    "item 1 of items: v is \"s\", which isn't an object".to_string()
                )),
                Some((
                    Cause::NotAnObject,
                    "item 2 of items: v is null, which isn't an object".to_string()
                )),
            ],
            "{params}"
        );
    }
}

#[test]
fn an_item_whose_value_before_the_key_is_an_object_says_nothing() {
    assert_eq!(
        own_said(
            "every items.v that is m named by $params.k is 1",
            json!([{"v": {"m": {}}}]),
            json!({}),
            json!({}),
        ),
        [None]
    );
}

#[test]
fn an_item_says_each_of_its_own_reads_beside_a_key_it_cant_read() {
    assert_eq!(
        own_said(
            "every items whose zz is m named by $params.k exists",
            json!([{"v": 1}]),
            json!({"k": 3}),
            json!({}),
        ),
        [Some((
            Cause::Absent,
            "item 1 of items: zz is missing, and m is missing".to_string()
        ))]
    );
}

#[test]
fn an_item_says_its_own_key_when_the_root_before_it_cant_be_read() {
    assert_eq!(
        own_said(
            "every items whose tags contains $input.m named by key exists",
            json!([{"tags": ["x"]}, {"key": 3, "tags": ["x"]}]),
            json!({}),
            json!({"m": null}),
        ),
        [
            Some((Cause::Absent, "item 1 of items: key is missing".to_string())),
            Some((
                Cause::Unusable,
                "item 2 of items: key is 3, which isn't text".to_string()
            )),
        ]
    );
}

#[test]
fn an_item_says_its_own_value_beside_a_compare_root_it_cant_use() {
    assert_eq!(
        own_said(
            "every items whose v is at least $params.min exists",
            json!([{}, {"v": 1}, {"v": "x"}]),
            json!({"min": "s"}),
            json!({}),
        ),
        [
            Some((Cause::Absent, "item 1 of items: v is missing".to_string())),
            None,
            Some((
                Cause::Unusable,
                "item 3 of items: v is \"x\", which isn't a number".to_string()
            )),
        ]
    );
}

fn judged(sentence: &str, items: Value, params: Value) -> Vec<Option<(Cause, String)>> {
    let Check::Walk(walk_check) = lowered(sentence) else {
        panic!("{sentence} is not every or some");
    };
    let subject = json!({"items": items});
    let input = json!({});
    let context = ctx(&subject, &input, Some(&params));
    let outer = outer(&context);
    let walked = walk(&walk_check.path, &outer, Options::default());
    judge(&walk_check, &walked, &outer)
        .into_iter()
        .map(|said| {
            said.failure
                .map(|(failure, _)| (failure.cause, failure.msg))
        })
        .collect()
}

#[test]
fn item_own_is_what_the_item_says_with_a_readable_key_minus_the_key() {
    let sentence = "every items.v that is m named by $params.k is 1";
    let items = json!([{"v": "s"}, {"v": {}}, {"v": {"m": null}}]);
    let readable = judged(sentence, items.clone(), json!({"k": "a"}));
    assert_eq!(
        own_said(sentence, items.clone(), json!({"k": "a"}), json!({})),
        readable
    );
    let cut: Vec<Option<(Cause, String)>> = readable
        .into_iter()
        .map(|said| said.map(|(cause, text)| (cause, text.replace(" named by $params.k", ""))))
        .collect();
    for params in [json!({}), json!({"k": null}), json!({"k": 3})] {
        assert_eq!(
            own_said(sentence, items.clone(), params.clone(), json!({})),
            cut,
            "{params}"
        );
    }
}

#[test]
fn item_own_is_what_any_check_says_when_it_reads_no_root() {
    let sentence = "every items whose tags contains \"x\" exists";
    let items = json!([{}, {"tags": "x"}, {"tags": ["y"]}]);
    assert_eq!(
        own_said(sentence, items.clone(), json!({}), json!({})),
        judged(sentence, items, json!({}))
    );
}

#[test]
fn item_own_is_what_any_check_says_when_its_roots_can_be_read() {
    let sentence = "every items whose tags contains $params.m named by key exists";
    let items = json!([{"key": "a"}, {"tags": ["x"]}, {"key": "a", "tags": ["x"]}]);
    let params = json!({"m": {"a": "x"}});
    assert_eq!(
        own_said(sentence, items.clone(), params.clone(), json!({})),
        judged(sentence, items, params)
    );
}

#[test]
fn an_item_says_its_own_list_beside_a_root_before_its_key_it_cant_read() {
    let sentence = "every items whose tags contains $params.m named by key exists";
    let items = json!([{"key": "a"}, {"key": "a", "tags": "x"}]);
    let readable = judged(sentence, items.clone(), json!({"m": {"a": ["x"]}}));
    assert_eq!(
        readable,
        [
            Some((
                Cause::Absent,
                "item 1 of items: tags is missing".to_string()
            )),
            Some((
                Cause::Unusable,
                "item 2 of items: tags is \"x\", which isn't a list".to_string()
            )),
        ]
    );
    assert_eq!(
        own_said(sentence, items, json!({"m": null}), json!({})),
        readable
    );
}

#[test]
fn an_item_whose_list_mixes_kinds_beside_a_root_it_cant_read_names_no_kind_it_cant_know() {
    assert_eq!(
        own_said(
            "every items whose tags contains $params.m named by key exists",
            json!([{"key": "a", "tags": ["x", 1]}]),
            json!({"m": null}),
            json!({}),
        ),
        [None]
    );
}

#[test]
fn an_item_says_its_own_value_beside_a_list_root_before_its_key_it_cant_read() {
    let sentence = "every items whose v is in $params.m named by key exists";
    let items = json!([{"key": "a"}, {"key": "a", "v": null}]);
    let readable = judged(sentence, items.clone(), json!({"m": {"a": ["x"]}}));
    assert_eq!(
        readable,
        [
            Some((Cause::Absent, "item 1 of items: v is missing".to_string())),
            Some((Cause::Null, "item 2 of items: v is null".to_string())),
        ]
    );
    assert_eq!(
        own_said(sentence, items, json!({"m": null}), json!({})),
        readable
    );
}

#[test]
fn an_item_says_its_own_text_beside_a_pattern_root_before_its_key_it_cant_read() {
    let sentence = "every items whose v matches $params.m named by key exists";
    let items = json!([{"key": "a", "v": 4}, {"key": "a", "v": "y"}]);
    let readable = judged(sentence, items.clone(), json!({"m": {"a": ["x"]}}));
    assert_eq!(
        readable[0],
        Some((
            Cause::Unusable,
            "item 1 of items: v is 4, which isn't text".to_string()
        ))
    );
    assert_eq!(
        own_said(sentence, items, json!({"m": null}), json!({})),
        [readable[0].clone(), None]
    );
}

#[test]
fn an_item_leaves_out_a_key_from_an_input_that_is_a_list() {
    assert_eq!(
        own_said(
            "every items whose v equals m named by $input.k exists",
            json!([{"v": "a", "m": {"x": "a"}}, {"m": {"x": "a"}}]),
            json!({}),
            json!([{"k": "x"}]),
        ),
        [
            None,
            Some((Cause::Absent, "item 2 of items: v is missing".to_string()))
        ]
    );
}

#[test]
fn an_item_that_isnt_an_object_says_so_beside_a_root_from_the_subject_it_cant_read() {
    let tree = ergo_policy_sentences::parse_check(
        "every items whose tags contains pr.m named by key exists",
    )
    .unwrap();
    let scope = crate::lower::Scope::new().with_subject("pr");
    let Check::Walk(walk_check) =
        crate::lower::lower_assertion(&tree.assertions[0], &scope).unwrap()
    else {
        panic!("not a walk");
    };
    let subject = json!({"m": null, "items": [null]});
    let input = json!({});
    let params = json!({});
    let context = ctx(&subject, &input, Some(&params));
    let outer = outer(&context);
    let walked = walk(&walk_check.path, &outer, Options::default());
    let said: Vec<Option<String>> = walked
        .items
        .iter()
        .map(|item| {
            item_own(&walk_check.whose[0], item, &walked, &outer)
                .map(|said| crate::ops::clause::text(std::slice::from_ref(&said)))
        })
        .collect();
    assert_eq!(
        said,
        [Some(
            "item 1 of items is null, which isn't an object".to_string()
        )]
    );
}

#[test]
fn an_item_leaves_out_a_key_from_the_subject_it_cant_read() {
    let tree =
        ergo_policy_sentences::parse_check("every items whose v equals m named by pr.k exists")
            .unwrap();
    let scope = crate::lower::Scope::new().with_subject("pr");
    let Check::Walk(walk_check) =
        crate::lower::lower_assertion(&tree.assertions[0], &scope).unwrap()
    else {
        panic!("not a walk");
    };
    let subject = json!({"items": [{"v": 1, "m": {"z": 1}}, {"m": {"z": 1}}]});
    let input = json!({});
    let params = json!({});
    let context = ctx(&subject, &input, Some(&params));
    let outer = outer(&context);
    let walked = walk(&walk_check.path, &outer, Options::default());
    let said: Vec<Option<String>> = walked
        .items
        .iter()
        .map(|item| {
            item_own(&walk_check.whose[0], item, &walked, &outer)
                .map(|said| crate::ops::clause::text(std::slice::from_ref(&said)))
        })
        .collect();
    assert_eq!(
        said,
        [None, Some("item 2 of items: v is missing".to_string())]
    );
}

#[test]
fn an_item_whose_focus_cant_be_read_says_so_whatever_the_key() {
    let sentence = "every items.v that is m named by $params.k is 1";
    let items = json!([{}, {"w": 1}]);
    let readable = judged(sentence, items.clone(), json!({"k": "a"}));
    assert_eq!(
        readable,
        [
            Some((Cause::Absent, "item 1 of items: v is missing".to_string())),
            Some((Cause::Absent, "item 2 of items: v is missing".to_string())),
        ]
    );
    for params in [json!({}), json!({"k": "a"}), json!({"k": 3})] {
        assert_eq!(
            own_said(sentence, items.clone(), params.clone(), json!({})),
            readable,
            "{params}"
        );
    }
}

#[test]
fn an_item_says_its_own_list_beside_a_root_on_the_left_of_is_in_it_cant_read() {
    let sentence = "every items whose $params.k is in tags exists";
    let items = json!(["a", {"tags": 1}, {}, {"tags": ["x"]}, {"tags": null}]);
    let readable = judged(sentence, items.clone(), json!({"k": "x"}));
    assert_eq!(
        readable,
        [
            Some((
                Cause::NotAnObject,
                "item 1 of items is \"a\", which isn't an object".to_string()
            )),
            Some((
                Cause::Unusable,
                "item 2 of items: tags is 1, which isn't a list".to_string()
            )),
            Some((
                Cause::Absent,
                "item 3 of items: tags is missing".to_string()
            )),
            None,
            Some((Cause::Null, "item 5 of items: tags is null".to_string())),
        ]
    );
    for params in [json!({}), json!({"k": null})] {
        assert_eq!(
            own_said(sentence, items.clone(), params.clone(), json!({})),
            readable,
            "{params}"
        );
    }
}

#[test]
fn an_item_says_its_own_list_of_mixed_kinds_beside_a_root_on_the_left_of_is_in_it_cant_read() {
    let sentence = "every items whose $params.k is in tags exists";
    let items = json!([{"tags": [1, "x"]}]);
    let readable = judged(sentence, items.clone(), json!({"k": "x"}));
    assert_eq!(
        readable,
        [Some((
            Cause::Unusable,
            "item 1 of items: tags is [1, \"x\"], which isn't a list of one kind of value"
                .to_string()
        ))]
    );
    for params in [json!({}), json!({"k": null})] {
        assert_eq!(
            own_said(sentence, items.clone(), params.clone(), json!({})),
            readable,
            "{params}"
        );
    }
}

#[test]
fn an_item_that_isnt_an_object_says_so_beside_a_root_on_the_left_of_contains_or_matches_it_cant_read()
 {
    for (sentence, readable_params) in [
        (
            "every items whose $params.l contains v exists",
            json!({"l": ["a"]}),
        ),
        (
            "every items whose $params.l matches v exists",
            json!({"l": "a"}),
        ),
    ] {
        let items = json!(["s", null]);
        let readable = judged(sentence, items.clone(), readable_params);
        assert_eq!(
            readable,
            [
                Some((
                    Cause::NotAnObject,
                    "item 1 of items is \"s\", which isn't an object".to_string()
                )),
                Some((
                    Cause::NotAnObject,
                    "item 2 of items is null, which isn't an object".to_string()
                )),
            ],
            "{sentence}"
        );
        for params in [json!({}), json!({"l": null})] {
            assert_eq!(
                own_said(sentence, items.clone(), params.clone(), json!({})),
                readable,
                "{sentence} {params}"
            );
        }
    }
}

fn own_beside_broken_roots(
    sentence: &str,
    items: &Value,
    readable: Value,
    broken: &[Value],
) -> Vec<Option<(Cause, String)>> {
    let said = judged(sentence, items.clone(), readable);
    for params in broken {
        assert_eq!(
            own_said(sentence, items.clone(), params.clone(), json!({})),
            said,
            "{sentence} {params}"
        );
    }
    said
}

fn absent_null_and(rest: &[(Cause, &str)]) -> Vec<Option<(Cause, String)>> {
    let mut said = vec![
        Some((Cause::Absent, "item 1 of items: v is missing".to_string())),
        Some((Cause::Null, "item 2 of items: v is null".to_string())),
    ];
    said.extend(rest.iter().enumerate().map(|(at, (cause, text))| {
        (!text.is_empty()).then(|| (*cause, format!("item {} of items: {text}", at + 3)))
    }));
    said
}

#[test]
fn an_item_says_its_own_time_beside_a_time_root_on_either_side_it_cant_read() {
    for sentence in [
        "every items whose v is before $params.t exists",
        "every items whose $params.t is on or after v exists",
    ] {
        assert_eq!(
            own_beside_broken_roots(
                sentence,
                &json!([{}, {"v": null}, {"v": true}, {"v": "2026-01-01T00:00:00Z"}]),
                json!({"t": "2026-01-01T00:00:00Z"}),
                &[json!({}), json!({"t": null}), json!({"t": true})],
            ),
            absent_null_and(&[
                (Cause::Unusable, "v is true, which isn't a time"),
                (Cause::Satisfied, ""),
            ]),
            "{sentence}"
        );
    }
}

#[test]
fn an_item_says_its_own_value_beside_a_root_on_the_left_of_contains_it_cant_read() {
    for (sentence, items, rest) in [
        (
            "every items whose $params.l contains v exists",
            json!([{}, {"v": null}, {"v": "b"}]),
            vec![(Cause::Satisfied, "")],
        ),
        (
            "every items whose $params.l does not contain v exists",
            json!([{}, {"v": null}, {"v": "a"}]),
            vec![(Cause::Satisfied, "")],
        ),
        (
            "every items whose $params.l contains v.w exists",
            json!([{"v": {}}, {"v": null}, {"v": "s"}, {"v": {"w": "b"}}]),
            vec![
                (Cause::Unusable, "v is \"s\", which isn't an object"),
                (Cause::Satisfied, ""),
            ],
        ),
    ] {
        let mut want = absent_null_and(&rest);
        if sentence.contains("v.w") {
            want[0] = Some((Cause::Absent, "item 1 of items: v.w is missing".to_string()));
        }
        assert_eq!(
            own_beside_broken_roots(
                sentence,
                &items,
                json!({"l": ["a"]}),
                &[json!({}), json!({"l": null})],
            ),
            want,
            "{sentence}"
        );
    }
}

#[test]
fn an_item_says_its_own_list_beside_a_root_on_the_left_of_contains_all_some_or_none_of_it_cant_read()
 {
    for sentence in [
        "every items whose $params.l contains all of v exists",
        "every items whose $params.l contains some of v exists",
        "every items whose $params.l contains none of v exists",
        "every items whose $params.l does not contain all of v exists",
    ] {
        assert_eq!(
            own_beside_broken_roots(
                sentence,
                &json!([{}, {"v": null}, {"v": "s"}, {"v": [1, "x"]}, {"v": []}, {"v": ["b"]}]),
                json!({"l": ["a"]}),
                &[json!({}), json!({"l": null})],
            ),
            absent_null_and(&[
                (Cause::Unusable, "v is \"s\", which isn't a list"),
                (
                    Cause::Unusable,
                    "v is [1, \"x\"], which isn't a list of one kind of value"
                ),
                (
                    Cause::Unusable,
                    "v is [], which isn't a list with at least one value"
                ),
                (Cause::Satisfied, ""),
            ]),
            "{sentence}"
        );
    }
}

#[test]
fn an_item_says_its_own_patterns_beside_a_root_on_the_left_of_matches_it_cant_read() {
    for sentence in [
        "every items whose $params.s matches v exists",
        "every items whose $params.s does not match v exists",
    ] {
        assert_eq!(
            own_beside_broken_roots(
                sentence,
                &json!([{}, {"v": null}, {"v": "s"}, {"v": [1]}, {"v": ["["]}, {"v": ["^b"]}]),
                json!({"s": "a"}),
                &[json!({}), json!({"s": null})],
            ),
            absent_null_and(&[
                (Cause::Unusable, "v is \"s\", which isn't a list"),
                (Cause::Unusable, "v is [1], which isn't a list of patterns"),
                (
                    Cause::Unusable,
                    "v is [\"[\"], which isn't a list of patterns"
                ),
                (Cause::Satisfied, ""),
            ]),
            "{sentence}"
        );
    }
}

#[test]
fn an_item_walks_its_own_list_reached_through_a_list_beside_a_root_on_the_left_it_cant_read() {
    for sentence in [
        "every items whose $params.r is in v.w exists",
        "every items whose $params.r is not in v.w exists",
        "every items whose $params.r contains all of v.w exists",
        "every items whose $params.r matches v.w exists",
    ] {
        for params in [json!({}), json!({"r": null})] {
            assert_eq!(
                own_said(
                    sentence,
                    json!([{"v": ["a", "b"]}, {"v": [{"w": "a"}]}]),
                    params.clone(),
                    json!({}),
                ),
                [
                    Some((
                        Cause::Unusable,
                        "item 1 of items: item 1 of v is \"a\", which isn't an object; item 2 of v is \"b\", which isn't an object".to_string()
                    )),
                    None,
                ],
                "{sentence} {params}"
            );
        }
    }
}

#[test]
fn an_item_says_the_value_before_its_own_list_beside_a_root_on_the_left_it_cant_read() {
    for sentence in [
        "every items whose $params.l contains all of v.w exists",
        "every items whose $params.l contains some of v.w exists",
        "every items whose $params.s matches v.w exists",
    ] {
        assert_eq!(
            own_beside_broken_roots(
                sentence,
                &json!([{"v": "s"}, {"v": {"w": ["a"]}}]),
                json!({"l": ["a"], "s": "a"}),
                &[json!({})],
            ),
            [
                Some((
                    Cause::Unusable,
                    "item 1 of items: v is \"s\", which isn't an object".to_string()
                )),
                None,
            ],
            "{sentence}"
        );
    }
}

#[test]
fn an_item_whose_focus_cant_take_its_key_says_so_beside_a_map_it_cant_read() {
    let isnt = |at: usize, text: &str| {
        Some((
            Cause::NotAnObject,
            format!("item {at} of items: {text}, which isn't an object"),
        ))
    };
    for (items, said) in [
        (
            json!([{"v": "a"}, {"v": 3}, {"v": null}]),
            vec![
                isnt(1, "v is \"a\""),
                isnt(2, "v is 3"),
                isnt(3, "v is null"),
            ],
        ),
        (json!([{"v": ["a"]}]), vec![isnt(1, "item 1 of v is \"a\"")]),
    ] {
        assert_eq!(
            own_beside_broken_roots(
                "every items.v that is $params.m named by k is 1",
                &items,
                json!({"m": {"a": 1}}),
                &[json!({}), json!({"m": null}), json!({"m": "s"})],
            ),
            said
        );
        for input in [
            json!({"m": {"a": 1}}),
            json!({}),
            json!({"m": null}),
            json!({"m": "s"}),
        ] {
            assert_eq!(
                own_said(
                    "every items.v that is $input.m named by k is 1",
                    items.clone(),
                    json!({}),
                    input.clone()
                ),
                said,
                "{input}"
            );
        }
    }
}

#[test]
fn an_item_says_once_a_value_its_own_read_and_the_key_of_a_map_it_cant_read_both_stop_at() {
    assert_eq!(
        own_beside_broken_roots(
            "every items whose v.w is $params.m named by v.k exists",
            &json!([{"v": null}]),
            json!({"m": {"a": {"k": 1}}}),
            &[json!({}), json!({"m": null}), json!({"m": "s"})],
        ),
        [Some((
            Cause::Null,
            "item 1 of items: v is null".to_string()
        ))]
    );
}

fn row_of(sentence: &str, subject: Value, params: Value) -> Run {
    let Check::Walk(walk_check) = lowered(sentence) else {
        panic!("{sentence} is not every or some");
    };
    let input = json!({});
    let context = ctx(&subject, &input, Some(&params));
    run(&walk_check, &context)
}

#[test]
fn a_walk_row_keeps_roots_and_items_apart() {
    use crate::ops::clause::Kind;
    let out = row_of(
        "every xs.v is at least $params.min",
        json!({"xs": [{"v": 1}, {"v": 2}, {}]}),
        json!({"min": "s"}),
    );
    let kinds: Vec<Kind> = out.parts.iter().map(|part| part.kind).collect();
    assert_eq!(kinds, [Kind::Root, Kind::Item]);
    assert_eq!(
        out.parts[0].text,
        "$params.min is \"s\", which isn't a number"
    );
    assert_eq!(out.parts[1].name, "item 3 of xs");
    assert_eq!(out.parts[1].said[0].text, "v is missing");
    assert_eq!(
        out.message.as_deref(),
        Some("$params.min is \"s\", which isn't a number; item 3 of xs: v is missing")
    );
}

#[test]
fn an_item_value_that_holds_a_semicolon_or_an_and_stays_whole_in_its_clause() {
    use crate::ops::clause::Kind;
    let out = row_of(
        "every xs.v is \"a\"",
        json!({"xs": [{"v": "p; q, and r"}]}),
        json!({}),
    );
    assert_eq!(out.parts.len(), 1);
    assert_eq!(out.parts[0].kind, Kind::Item);
    assert_eq!(out.parts[0].name, "item 1 of xs");
    assert_eq!(out.parts[0].said.len(), 1);
    assert_eq!(out.parts[0].said[0].text, "v is \"p; q, and r\"");
}

fn thing_row(sentence: &str, subject: Value, params: Value) -> Run {
    let Check::Walk(walk_check) = lowered(sentence) else {
        panic!("{sentence} is not every or some");
    };
    let input = json!({});
    let mut context = ctx(&subject, &input, Some(&params));
    context.label = Some("thing".to_string());
    run(&walk_check, &context)
}

fn said_row(sentence: &str, subject: Value, params: Value) -> (Cause, String) {
    let out = thing_row(sentence, subject, params);
    (out.verdict.cause, out.message.unwrap_or_default())
}

const KEYS_THAT_CANT_BE_READ: [(&str, &str); 3] = [
    ("{}", "$params.k is missing"),
    ("{\"k\": null}", "$params.k is null"),
    ("{\"k\": 3}", "$params.k is 3, which isn't text"),
];

fn said_beside_each_key(form: &str, es: Value) -> Vec<(Cause, String)> {
    KEYS_THAT_CANT_BE_READ
        .iter()
        .map(|(params, _)| {
            said_row(
                &format!("{form} es.v that is m named by $params.k is 1"),
                json!({"es": es.clone()}),
                serde_json::from_str(params).unwrap(),
            )
        })
        .collect()
}

fn each_key_then(cause: Cause, items: &str) -> Vec<(Cause, String)> {
    KEYS_THAT_CANT_BE_READ
        .iter()
        .map(|(_, key)| (cause, format!("{key}; {items}")))
        .collect()
}

#[test]
fn an_every_says_a_that_key_it_cant_read_once_and_each_item_its_own_value() {
    assert_eq!(
        said_beside_each_key("every", json!([{"v": "s"}, {"v": {}}, {"v": {"m": null}}])),
        each_key_then(
            Cause::NotAnObject,
            "item 1 of es: v is \"s\", which isn't an object; item 2 of es: v: m is missing; item 3 of es: v: m is null"
        )
    );
}

#[test]
fn a_some_says_the_same_as_every() {
    assert_eq!(
        said_beside_each_key("some", json!([{"v": "s"}, {"v": {}}, {"v": {"m": null}}])),
        each_key_then(
            Cause::NotAnObject,
            "item 1 of es: v is \"s\", which isn't an object; item 2 of es: v: m is missing; item 3 of es: v: m is null"
        )
    );
    assert_eq!(
        said_beside_each_key("some", json!([{"v": {}}, {"v": {}}, {"v": {}}, {"v": {}}])),
        said_beside_each_key("every", json!([{"v": {}}, {"v": {}}, {"v": {}}, {"v": {}}]))
    );
    assert_eq!(
        said_beside_each_key("some", json!([{"v": {}}, {"v": {"m": null}}]))[0],
        (
            Cause::Absent,
            "$params.k is missing; item 1 of es: v: m is missing; item 2 of es: v: m is null"
                .to_string()
        )
    );
}

#[test]
fn an_every_says_a_root_after_the_phrase_and_then_its_items() {
    assert_eq!(
        said_row(
            "every xs.v is at least $params.min",
            json!({"xs": [{}, {}, {}, {}, {}]}),
            json!({"min": "s"}),
        ),
        (
            Cause::Unusable,
            "$params.min is \"s\", which isn't a number; item 1 of xs: v is missing; item 2 of xs: v is missing; item 3 of xs: v is missing; and 2 more"
                .to_string()
        )
    );
}

#[test]
fn a_value_that_holds_a_semicolon_stays_whole_in_a_walk_row() {
    use crate::ops::clause::Kind;
    let out = thing_row(
        "every xs whose v is at least $params.min, if any, exists",
        json!({"xs": [{"v": 1}, {}]}),
        json!({"min": "a; b"}),
    );
    let parts: Vec<(Kind, String)> = out
        .parts
        .iter()
        .map(|part| {
            (
                part.kind,
                crate::ops::clause::text(std::slice::from_ref(part)),
            )
        })
        .collect();
    assert_eq!(
        parts,
        [
            (
                Kind::Root,
                "$params.min is \"a; b\", which isn't a number".to_string()
            ),
            (Kind::Item, "item 2 of xs: v is missing".to_string()),
        ]
    );
}

#[test]
fn an_every_says_a_key_that_isnt_text_once_beside_an_item_that_says_nothing_of_its_own() {
    assert_eq!(
        said_row(
            "every es.v that is m named by $params.k exists",
            json!({"es": [{"v": {"m": {"a": 1}}}, {"v": {}}]}),
            json!({"k": 3}),
        ),
        (
            Cause::Unusable,
            "$params.k is 3, which isn't text; item 2 of es: v: m is missing".to_string()
        )
    );
}

fn records(sentence: &str, es: Value, params: Value) -> Vec<(Value, Value, Value)> {
    thing_row(sentence, json!({"es": es}), params)
        .rich
        .iter()
        .map(|record| {
            (
                record["path"].clone(),
                record["value"].clone(),
                record.get("ergo/outcome").cloned().unwrap_or(Value::Null),
            )
        })
        .collect()
}

#[test]
fn a_walk_item_beside_a_key_it_cant_read_holds_the_value_before_the_key_with_the_reads_outcome() {
    let sentence = "every es.v that is m named by $params.k is 1";
    assert_eq!(
        records(sentence, json!([{"v": {}}, {"v": {"m": null}}]), json!({})),
        [
            (json!("es[0].v.m"), json!(null), json!("absent")),
            (json!("es[1].v.m"), json!(null), json!("absent")),
        ]
    );
    assert_eq!(
        records(
            sentence,
            json!([{"v": {}}, {"v": {"m": null}}]),
            json!({"k": null})
        ),
        [
            (json!("es[0].v.m"), json!(null), json!("absent")),
            (json!("es[1].v.m"), json!(null), json!("null")),
        ]
    );
    assert_eq!(
        records(sentence, json!([{"v": {"m": "s"}}]), json!({"k": 3})),
        [(json!("es[0].v.m"), json!("s"), json!("unusable"))]
    );
}

#[test]
fn a_walk_row_says_a_root_its_items_cant_read_before_them() {
    assert_eq!(
        said_row(
            "every es whose v contains $params.x is an object",
            json!({"es": [{}, {"v": []}, {"v": 3}]}),
            json!({}),
        ),
        (
            Cause::Unusable,
            "$params.x is missing; item 1 of es: v is missing; item 3 of es: v is 3, which isn't a list"
                .to_string()
        )
    );
}

#[test]
fn an_every_keeps_its_items_beside_a_missing_key() {
    assert_eq!(
        said_row(
            "every es.v that is m named by $params.k is 1",
            json!({"es": [{"v": {}}, {"v": {"m": null}}]}),
            json!({}),
        ),
        (
            Cause::Absent,
            "$params.k is missing; item 1 of es: v: m is missing; item 2 of es: v: m is null"
                .to_string()
        )
    );
}

#[test]
fn a_root_value_that_holds_an_and_stays_one_clause_in_a_walk_row() {
    let out = thing_row(
        "every xs.v is at least $params.min",
        json!({"xs": [{"v": 1}, {}]}),
        json!({"min": "a, and b"}),
    );
    let parts: Vec<(Kind, String)> = out
        .parts
        .iter()
        .map(|part| (part.kind, clause::text(std::slice::from_ref(part))))
        .collect();
    assert_eq!(
        parts,
        [
            (
                Kind::Root,
                "$params.min is \"a, and b\", which isn't a number".to_string()
            ),
            (Kind::Item, "item 2 of xs: v is missing".to_string()),
        ]
    );
}

#[test]
fn a_walk_row_says_the_roots_then_the_lists_own_problem_then_the_items_with_the_worst_cause() {
    let item = Clause::item(
        "item 1 of xs",
        Cause::Absent,
        String::new(),
        vec![Clause::said(Cause::Absent, "v is missing".to_string())],
    );
    let list = Clause::list("ys", Cause::Value, "ys is []".to_string());
    let roots = vec![
        Clause::root("$params.b", Cause::Null, "$params.b is null".to_string()),
        Clause::root(
            "$params.a",
            Cause::Unusable,
            "$params.a is 3, which isn't text".to_string(),
        ),
    ];
    let (cause, parts) = row_clauses(roots, vec![list], vec![item]);
    assert_eq!(cause, Cause::Unusable);
    assert_eq!(
        clause::text(&clause::shown(&parts)),
        "$params.a is 3, which isn't text; $params.b is null; ys is []; item 1 of xs: v is missing"
    );
}

#[test]
fn an_item_that_isnt_a_time_says_so_beside_a_time_root_that_cant_be_read() {
    let items = json!([{"v": 2}, {"v": "2024-01-01T00:00:00Z"}, {}]);
    let not_a_time = (
        Cause::Unusable,
        "item 1 of items: v is 2, which isn't a time written like \"1970-01-01T00:00:00Z\""
            .to_string(),
    );
    for sentence in [
        "every items whose v is before $params.x exists",
        "every items whose v is on or after $params.x exists",
        "some items whose v is before $params.x exists",
    ] {
        for params in [json!({}), json!({"x": null}), json!({"x": "s"})] {
            assert_eq!(
                own_said(sentence, items.clone(), params, json!({})),
                vec![
                    Some(not_a_time.clone()),
                    None,
                    Some((Cause::Absent, "item 3 of items: v is missing".to_string())),
                ],
                "{sentence}"
            );
        }
    }
}

#[test]
fn an_item_a_that_root_leaves_undecided_still_says_what_the_phrase_cant_use_in_its_own_value() {
    assert_eq!(
        judged(
            "every items.v that is on or after $params.x is 1",
            json!([{"v": "2024-01-01T00:00:00Z"}, {"v": 2}]),
            json!({"x": null}),
        ),
        vec![
            Some((
                Cause::Unusable,
                "item 1 of items: v is \"2024-01-01T00:00:00Z\", which isn't a number".to_string()
            )),
            Some((
                Cause::Unusable,
                "item 2 of items: v is 2, which isn't a time written like \"1970-01-01T00:00:00Z\""
                    .to_string()
            )),
        ]
    );
}

#[test]
fn an_item_a_whose_that_doesnt_read_it_leaves_undecided_says_nothing_of_its_own() {
    assert_eq!(
        judged(
            "every items.b whose $params.z is 1 exists",
            json!([{"b": 1}, null, {"b": "s"}]),
            json!({}),
        ),
        vec![None, None, None]
    );
}

#[test]
fn a_whose_root_that_isnt_a_list_is_said_first_and_keeps_the_lists_own_problem() {
    let root = "$params.z is \"s\", which isn't a list";
    for form in ["every", "some"] {
        let sentence = format!("{form} es whose v is in $params.z exists");
        for (subject, list) in [
            (json!({}), "es is missing"),
            (json!({"es": null}), "es is null"),
            (json!({"es": []}), "es is []"),
            (json!({"es": 3}), "es is 3, which isn't a list or an object"),
        ] {
            assert_eq!(
                said_row(&sentence, subject, json!({"z": "s"})),
                (Cause::Unusable, format!("{root}; {list}")),
                "{sentence}"
            );
        }
    }
}

#[test]
fn a_whose_root_that_isnt_a_list_keeps_what_each_item_says_on_another_condition() {
    assert_eq!(
        said_row(
            "every xs whose v is at least $params.x and whose w is in $params.y exists",
            json!({"xs": [{"v": "s", "w": 1}, {"w": 1}, null]}),
            json!({"x": 2, "y": 3}),
        ),
        (
            Cause::NotAnObject,
            "$params.y is 3, which isn't a list; item 1 of xs: v is \"s\", which isn't a number; item 2 of xs: v is missing; item 3 of xs is null, which isn't an object".to_string()
        )
    );
}

#[test]
fn an_item_says_nothing_of_its_own_for_a_condition_whose_list_root_isnt_a_list() {
    assert_eq!(
        said_row(
            "every xs.v whose kind is not in $params.l, if any, is 1",
            json!({"xs": [{"v": 2, "kind": "a"}]}),
            json!({"l": "text"}),
        ),
        (
            Cause::Unusable,
            "$params.l is \"text\", which isn't a list".to_string()
        )
    );
}

#[test]
fn a_walk_row_takes_the_worst_cause_of_a_list_root_said_beside_its_items() {
    assert_eq!(
        said_row(
            "every rows whose v is in $params.a.name and whose v is in $params.os.name exists",
            json!({"rows": [{"v": "bob"}]}),
            json!({"a": [{"name": "bob"}, {}], "os": [{"name": "bob"}, {"name": 3}]}),
        ),
        (
            Cause::Unusable,
            "$params.os[].name is [\"bob\", 3], which isn't a list of one kind of value; item 2 of $params.a: name is missing".to_string()
        )
    );
}

#[test]
fn a_list_root_after_the_phrase_that_isnt_a_list_is_said_alone_whatever_the_list_holds() {
    let root = "$params.z is \"s\", which isn't a list".to_string();
    for sentence in [
        "every es.v is in $params.z",
        "some es.v is not in $params.z",
        "every es.v, if any, matches $params.z",
    ] {
        for subject in [
            json!({}),
            json!({"es": null}),
            json!({"es": []}),
            json!({"es": [{"v": "a"}, {}, null]}),
        ] {
            assert_eq!(
                said_row(sentence, subject, json!({"z": "s"})),
                (Cause::Unusable, root.clone()),
                "{sentence}"
            );
        }
        assert_eq!(
            said_row(sentence, json!({"es": "t"}), json!({"z": "s"})),
            (
                Cause::Unusable,
                format!("{root}; es is \"t\", which isn't an object")
            ),
            "{sentence}"
        );
    }
}

#[test]
fn a_list_root_after_the_phrase_is_said_with_the_roots_of_a_whose_and_the_list() {
    for (subject, list) in [
        (json!({}), "es is missing"),
        (json!({"es": null}), "es is null"),
    ] {
        assert_eq!(
            said_row(
                "some es whose v is in $params.z is in $params.y",
                subject,
                json!({"y": "s"}),
            ),
            (
                Cause::Unusable,
                format!("$params.y is \"s\", which isn't a list; $params.z is missing; {list}")
            )
        );
    }
}

#[test]
fn a_walk_whose_key_step_cant_be_read_says_the_key_then_each_root_after_the_phrase() {
    for (subject, root) in [
        (json!({"xs": []}), "q is missing"),
        (json!({"xs": [], "q": null}), "q is null"),
    ] {
        assert_eq!(
            said_row(
                "every xs named by $params.k, if any, equals q",
                subject.clone(),
                json!({}),
            ),
            (Cause::Absent, format!("$params.k is missing; {root}"))
        );
        assert_eq!(
            said_row("some xs named by $params.k equals q", subject, json!({})),
            (
                Cause::Absent,
                format!("$params.k is missing; {root}; xs is []")
            )
        );
    }
}

#[test]
fn an_empty_list_root_after_the_phrase_is_said_once_and_not_inside_each_item() {
    assert_eq!(
        said_row(
            "every rows.v is in $params.d.name",
            json!({"rows": [{"v": "a"}, {"v": "b"}]}),
            json!({"d": []}),
        ),
        (Cause::Value, "$params.d is []".to_string())
    );
}

#[test]
fn an_item_whose_own_list_is_empty_is_said_after_a_root_that_cant_be_used() {
    use crate::ops::clause::Kind;
    let out = thing_row(
        "every pkgs.licenses is in $params.allowed",
        json!({"pkgs": [{"licenses": ["MIT"]}, {"licenses": []}]}),
        json!({}),
    );
    assert_eq!(out.verdict.cause, Cause::Absent);
    assert_eq!(
        out.message.as_deref(),
        Some("$params.allowed is missing; item 2 of pkgs: licenses is []")
    );
    let kinds: Vec<Kind> = out.parts.iter().map(|part| part.kind).collect();
    assert_eq!(kinds, [Kind::Root, Kind::Item]);
    assert_eq!(out.parts[1].name, "item 2 of pkgs");
    assert_eq!(out.failed_items.len(), 1);
}

#[test]
fn a_some_says_an_item_whose_own_list_is_empty_after_a_root_that_cant_be_used() {
    assert_eq!(
        said_row(
            "some pkgs.licenses is in $params.allowed",
            json!({"pkgs": [{"licenses": ["MIT"]}, {"licenses": []}]}),
            json!({}),
        ),
        (
            Cause::Absent,
            "$params.allowed is missing; item 2 of pkgs: licenses is []".to_string()
        )
    );
}

#[test]
fn an_item_that_fails_only_because_of_a_root_that_cant_be_used_says_nothing() {
    for quantifier in ["every", "some"] {
        for pkgs in [
            json!([{"licenses": ["MIT"]}, {"licenses": ["GPL"]}]),
            json!([{"licenses": []}, {"licenses": []}]),
        ] {
            assert_eq!(
                said_row(
                    &format!("{quantifier} pkgs.licenses is in $params.allowed"),
                    json!({"pkgs": pkgs}),
                    json!({}),
                ),
                (Cause::Absent, "$params.allowed is missing".to_string()),
                "{quantifier} {pkgs}"
            );
        }
    }
}

#[test]
fn a_root_compared_ignoring_case_needs_text_so_it_is_said_once_before_the_items() {
    let check = Check::Compare(crate::ops::compare::Compare {
        left: crate::ops::compare::Side::Path(at(Start::Subject, &["v"])),
        right: crate::ops::compare::Side::Path(at(Start::Input, &["r"])),
        cmp: crate::ops::compare::Cmp::Eq,
        within: None,
        ignoring: Some(crate::ops::compare::Ignoring {
            case: true,
            spaces: false,
        }),
    });
    assert_eq!(right_needs(&check, &json!(3)), Some("text"));
    assert_eq!(right_needs(&check, &json!({"a": 1})), Some("text"));
    assert_eq!(right_needs(&check, &json!("A")), None);
}

#[test]
fn the_item_entry_of_copies_lists_the_location_of_each_item_not_the_end_of_its_path() {
    let mut walk = every(&["commits", "author"], vec![], equals(json!("ann")), false);
    walk.distinct = true;
    let subject = json!({"commits": [
        {"author": "ann"}, {"author": "bob"}, {"author": "bob"}, {"author": "bob"}
    ]});
    let run = row(&walk, subject);
    assert_eq!(run.rich.len(), 1);
    assert_eq!(
        run.rich[0]["ergo/item"]["locations"],
        json!(["/s/commits/1", "/s/commits/2", "/s/commits/3"])
    );
    assert_eq!(
        run.failed_items[0]["locations"],
        json!([
            "/s/commits/1/author",
            "/s/commits/2/author",
            "/s/commits/3/author"
        ])
    );
}

#[test]
fn a_list_after_is_in_ignoring_case_with_an_item_that_isnt_text_is_said_once_before_the_items_on_an_empty_list_too()
 {
    for (sentence, subject, params, cause, message) in [
        (
            "every xs.v is in ys ignoring case",
            json!({"xs": [{"v": "a"}, {"v": "b"}], "ys": ["A", 3]}),
            json!({}),
            Cause::Unusable,
            "item 2 of ys is 3, which isn't text",
        ),
        (
            "some xs.v is not in ys ignoring case",
            json!({"xs": [{"v": "a"}, {"v": "b"}], "ys": [3]}),
            json!({}),
            Cause::Unusable,
            "item 1 of ys is 3, which isn't text",
        ),
        (
            "every xs.v, if any, is in ys ignoring case",
            json!({"xs": [], "ys": [1, "a"]}),
            json!({}),
            Cause::Unusable,
            "item 1 of ys is 1, which isn't text",
        ),
        (
            "every xs.v, if any, is one of ys ignoring case",
            json!({"xs": [], "ys": ["a", null]}),
            json!({}),
            Cause::Null,
            "item 2 of ys is null",
        ),
        (
            "every xs.v, if any, is in $params.l ignoring case",
            json!({"xs": []}),
            json!({"l": ["a", null]}),
            Cause::Null,
            "item 2 of $params.l is null",
        ),
        (
            "every xs.v is in $params.l ignoring case",
            json!({"xs": [{"v": "a"}, {"v": "b"}]}),
            json!({"l": [null]}),
            Cause::Null,
            "item 1 of $params.l is null",
        ),
        (
            "every xs.v, if any, is in $params.l ignoring case",
            json!({"xs": []}),
            json!({"l": ["a", 3]}),
            Cause::Unusable,
            "item 2 of $params.l is 3, which isn't text",
        ),
    ] {
        let out = row_of(sentence, subject, params);
        assert_eq!(
            (out.verdict.cause, out.message.as_deref()),
            (cause, Some(message)),
            "{sentence}"
        );
    }
}

#[test]
fn a_list_after_is_in_ignoring_case_that_cant_be_used_doesnt_hide_the_items_whose_own_value_isnt_text()
 {
    for (sentence, subject, params, cause, message) in [
        (
            "every xs.v is in $params.l ignoring case",
            json!({"xs": [{"v": "a"}, {"v": 2}]}),
            json!({"l": [null]}),
            Cause::Unusable,
            "item 1 of $params.l is null; item 2 of xs: v is 2, which isn't text",
        ),
        (
            "every xs whose v is in $params.l ignoring case, if any, exists",
            json!({"xs": [{"v": "a"}, {"v": 2}]}),
            json!({"l": [null]}),
            Cause::Unusable,
            "item 1 of $params.l is null; item 2 of xs: v is 2, which isn't text",
        ),
        (
            "some xs.v is not in $params.l ignoring case",
            json!({"xs": [{"v": null}, {"v": "b"}]}),
            json!({"l": ["a", 3]}),
            Cause::Unusable,
            "item 2 of $params.l is 3, which isn't text; item 1 of xs: v is null",
        ),
        (
            "every xs.v is in ys ignoring case",
            json!({"xs": [{"v": "a"}, {"v": 1}, {}], "ys": ["A", 3]}),
            json!({}),
            Cause::Unusable,
            "item 2 of ys is 3, which isn't text; item 2 of xs: v is 1, which isn't text; item 3 of xs: v is missing",
        ),
        (
            "every xs whose v is in $params.l ignoring case, if any, exists",
            json!({"xs": [{"v": 1}, {"v": "b"}]}),
            json!({"l": ["A", 3]}),
            Cause::Unusable,
            "item 2 of $params.l is 3, which isn't text; item 1 of xs: v is 1, which isn't text",
        ),
    ] {
        let out = row_of(sentence, subject, params);
        assert_eq!(
            (out.verdict.cause, out.message.as_deref()),
            (cause, Some(message)),
            "{sentence}"
        );
    }
}
