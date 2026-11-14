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
        in_option: false,
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
