use crate::SPEC;
use serde_json::{Value, json};

fn row(for_line: &str, assertions: Value, subject: Value) -> Value {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": for_line, "assert": assertions}}}}
    });
    let mut subject = subject;
    subject["id"] = json!(1);
    let input = json!({"things": [subject]});
    let report = crate::report(
        &input,
        &policy,
        &json!({"k": "a", "list": ["x"], "kinds": "code", "need": {"b": 1}}),
    );
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

fn cause(for_line: &str, assertions: Value, subject: Value) -> String {
    row(for_line, assertions, subject)["cause"]
        .as_str()
        .unwrap()
        .to_string()
}

fn problems(for_line: &str) -> Value {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": for_line, "assert": "x exists"}}}}
    });
    let input = json!({"things": [{"id": 1, "xs": {"a": 1}, "x": "a", "ys": ["a"]}]});
    let report = crate::report(&input, &policy, &json!({}));
    let rows = report["results"].as_array().unwrap();
    assert!(rows.iter().all(|row| row["check"] != "c"));
    let well_formed = rows
        .iter()
        .find(|row| row["check"] == "$well_formed")
        .unwrap();
    well_formed["inputs"][2]["value"].clone()
}

#[test]
fn a_for_item_that_names_its_own_alias_in_its_path_is_written_wrong() {
    assert_eq!(
        problems("every xs named by x as x"),
        json!(["for: unknown alias x"])
    );
}

#[test]
fn a_for_item_that_names_a_later_alias_in_its_path_is_written_wrong() {
    assert_eq!(
        problems("every xs named by q as p, every ys as q"),
        json!(["for: unknown alias q"])
    );
}

#[test]
fn a_for_item_that_names_its_own_alias_in_a_whose_is_written_wrong() {
    assert_eq!(
        problems("every xs whose v named by x is 1 as x"),
        json!(["for: unknown alias x"])
    );
}

#[test]
fn a_for_item_that_names_an_earlier_alias_in_its_path_is_read() {
    let found = row(
        "every ys as y, every xs named by y as x",
        json!("x is 1"),
        json!({"xs": {"a": [1]}, "ys": ["a"]}),
    );
    assert_eq!(found["cause"], "satisfied");
}

fn items(row: &Value) -> Vec<String> {
    row["failed_items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["item"].as_str().unwrap().to_string())
        .collect()
}

fn names(row: &Value) -> Vec<String> {
    row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["name"].as_str().unwrap().to_string())
        .collect()
}

#[test]
fn every_passes_when_all_items_pass_and_lists_the_failures_otherwise() {
    let line = "every xs as x";
    let sentence = json!("x.ok is true");
    let all = row(
        line,
        sentence.clone(),
        json!({"xs": [{"ok": true}, {"ok": true}]}),
    );
    assert_eq!(all["cause"], "satisfied");
    assert_eq!(all["failed_items"], json!([]));
    let some = row(line, sentence, json!({"xs": [{"ok": true}, {"ok": false}]}));
    assert_eq!(some["cause"], "value");
    assert_eq!(items(&some), ["item 2 of xs"]);
    assert_eq!(
        some["failed_items"][0]["failed_assertions"][0]["inputs"],
        json!([{"name": "x.ok", "value": false, "locations": ["/things/0/xs/1/ok"]}])
    );
}

#[test]
fn an_item_whose_path_goes_on_into_a_value_that_is_not_an_object_fails_as_not_an_object() {
    for item in [json!("s"), json!(null), json!(3)] {
        let subject = json!({"xs": [item, {"t": "a"}]});
        assert_eq!(
            cause("every xs.t as t", json!("t is \"a\""), subject.clone()),
            "not_an_object"
        );
        assert_eq!(
            cause("some xs.t as t", json!("t is \"b\""), subject),
            "not_an_object"
        );
    }
}

#[test]
fn an_object_item_whose_path_goes_on_into_a_text_still_fails_as_unusable() {
    let subject = json!({"xs": [{"meta": "text"}]});
    assert_eq!(
        cause("every xs.meta.k as k", json!("k is 1"), subject),
        "unusable"
    );
}

#[test]
fn some_passes_with_one_passing_item_and_lists_nothing() {
    let subject = json!({"xs": [{"ok": false}, {"ok": true}]});
    let passing = row("some xs as x", json!("x.ok is true"), subject);
    assert_eq!(passing["cause"], "satisfied");
    assert_eq!(passing["failed_items"], json!([]));
    let failing = row(
        "some xs as x",
        json!("x.ok is true"),
        json!({"xs": [{"ok": false}]}),
    );
    assert_eq!(failing["cause"], "value");
    assert_eq!(items(&failing), ["item 1 of xs"]);
}

#[test]
fn an_empty_list_fails_every_and_some_as_value_unless_if_any() {
    let subject = json!({"xs": []});
    assert_eq!(
        cause("every xs as x", json!("x is 1"), subject.clone()),
        "value"
    );
    assert_eq!(
        cause("some xs as x", json!("x is 1"), subject.clone()),
        "value"
    );
    assert_eq!(
        cause("every xs, if any, as x", json!("x is 1"), subject.clone()),
        "satisfied"
    );
    let listed = row("every xs as x", json!("x is 1"), subject);
    assert_eq!(items(&listed), ["xs"]);
    assert_eq!(listed["inputs"][0]["name"], "xs[]");
}

#[test]
fn an_empty_list_a_for_line_tolerates_still_runs_the_sentences_that_dont_read_it() {
    let subject = json!({
        "approvers": [{"u": "ada", "subs": []}, {"u": "g", "state": "REJECTED"}],
        "commits": []
    });
    for line in [
        "some approvers as ap, every commits, if any, as c",
        "every approvers as ap, every commits, if any, as c",
    ] {
        let failed = row(line, json!("ap.state is \"APPROVED\""), subject.clone());
        assert_eq!(failed["cause"], "absent");
        assert_eq!(
            items(&failed),
            ["item 1 of approvers", "item 2 of approvers"]
        );
        assert_eq!(
            failed["message"],
            "item 1 of approvers: ap.state is missing; item 2 of approvers: ap.state is \"REJECTED\""
        );
    }
}

#[test]
fn a_sentence_that_reads_the_alias_of_an_empty_list_a_for_line_tolerates_has_nothing_to_check() {
    let line = "some approvers as ap, every commits, if any, as c";
    let approved = json!({"approvers": [{"u": "ada", "state": "APPROVED"}], "commits": []});
    assert_eq!(
        cause(
            line,
            json!(["ap.state is \"APPROVED\"", "c.author does not equal ap.u"]),
            approved
        ),
        "satisfied"
    );
    let rejected = json!({"approvers": [{"u": "ada", "state": "REJECTED"}], "commits": []});
    assert_eq!(
        cause(
            line,
            json!("c.author does not equal ap.u"),
            rejected.clone()
        ),
        "satisfied"
    );
    assert_eq!(
        cause(
            line,
            json!(["ap.state is \"APPROVED\"", "c.author does not equal ap.u"]),
            rejected
        ),
        "value"
    );
}

#[test]
fn an_empty_first_list_a_for_line_tolerates_still_runs_the_sentences_that_dont_read_it() {
    let approvers = json!([{"u": "ada"}, {"u": "g", "state": "REJECTED"}]);
    for line in [
        "every commits, if any, as c, some approvers as ap",
        "every commits, if any, as c, every approvers as ap",
    ] {
        let failed = row(
            line,
            json!(["c.author is ap.u", "ap.state is \"APPROVED\""]),
            json!({"approvers": approvers, "commits": []}),
        );
        assert_eq!(failed["cause"], "absent");
        assert_eq!(
            items(&failed),
            ["item 1 of approvers", "item 2 of approvers"]
        );
        assert_eq!(
            failed["message"],
            "item 1 of approvers: state is missing; item 2 of approvers: state is \"REJECTED\""
        );
        assert_eq!(names(&failed), ["approvers[]", "commits[]"]);
    }
    let filtered = row(
        "every commits whose n is 1, if any, as c, some approvers as ap",
        json!("ap.state is \"APPROVED\""),
        json!({"approvers": approvers, "commits": [{"n": 2}]}),
    );
    assert_eq!(filtered["cause"], "absent");
    assert_eq!(
        cause(
            "every commits, if any, as c, some approvers as ap",
            json!("c.author is ap.u"),
            json!({"approvers": [{"u": "ada"}], "commits": []})
        ),
        "satisfied"
    );
    assert_eq!(
        cause(
            "every commits, if any, as c, some approvers as ap",
            json!("c.author is ap.u"),
            json!({"commits": []})
        ),
        "satisfied"
    );
}

#[test]
fn an_empty_list_a_one_item_for_line_tolerates_still_runs_the_sentences_that_dont_read_it() {
    for line in [
        "every xs, if any, as m",
        "every xs whose k is 1, if any, as m",
    ] {
        let failed = row(
            line,
            json!(["m.v is 1", "z is 1"]),
            json!({"xs": [], "z": 3}),
        );
        assert_eq!(failed["cause"], "value");
        assert_eq!(failed["message"], "z is 3");
        assert_eq!(failed["failed_items"], json!([]));
        assert_eq!(
            cause(
                line,
                json!(["m.v is 1", "z is 1"]),
                json!({"xs": [], "z": 1})
            ),
            "satisfied"
        );
    }
    assert_eq!(
        row(
            "every commits, if any, as c, every c.files as f",
            json!(["f.n is 1", "z is 1"]),
            json!({"commits": [], "z": 3})
        )["message"],
        "z is 3"
    );
    let mixed = row(
        "every xs, if any, as m",
        json!(["w exists", "y is at least 1", "z is 1"]),
        json!({"xs": [], "z": 3, "y": "s"}),
    );
    assert_eq!(mixed["cause"], "unusable");
    assert_eq!(
        mixed["message"],
        "y is \"s\", which isn't a number; w is missing; z is 3"
    );
}

#[test]
fn a_path_that_is_missing_null_or_not_a_list_fails_as_absent_null_or_unusable() {
    for (subject, wanted) in [
        (json!({}), "absent"),
        (json!({"xs": null}), "null"),
        (json!({"xs": "abc"}), "unusable"),
    ] {
        let found = row("every xs as x", json!("x is 1"), subject);
        assert_eq!(found["cause"], wanted);
        assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
        assert_eq!(names(&found), ["xs"]);
    }
}

#[test]
fn a_subject_that_is_not_an_object_fails_as_not_an_object_with_nothing_listed() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every xs as x", "assert": "x is 1"}}}}
    });
    let report = crate::report(&json!({"things": ["text"]}), &policy, &json!({}));
    let found = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap();
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(found["inputs"], json!([]));
    assert_eq!(found["failed_items"], json!([]));
}

#[test]
fn a_for_line_over_the_subject_by_its_name_fails_as_not_an_object_on_a_subject_that_is_not_an_object_or_a_list()
 {
    for subject in [json!("text"), json!(3), json!(null)] {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "every xs"}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every thing as k", "assert": "k is 1"}}}}
        });
        let report = crate::report(&json!({"xs": [subject]}), &policy, &json!({}));
        let found = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(found["inputs"], json!([]));
        assert_eq!(found["failed_items"], json!([]));
    }
}

#[test]
fn a_failed_assertion_keeps_the_dot_of_a_field_named_like_the_subject() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "every xs"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every ys as k", "assert": ".thing is 1"}}}}
    });
    let input = json!({"xs": [{"thing": 2, "ys": [1]}]});
    let report = crate::report(&input, &policy, &json!({}));
    let found = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap();
    assert_eq!(
        found["failed_items"][0]["failed_assertions"][0]["assertion"],
        ".thing is 1"
    );
}

#[test]
fn a_whose_leaves_an_item_out_on_value_and_fails_the_check_when_it_cannot_decide() {
    let line = "every xs whose kind is \"code\" as x";
    let sentence = json!("x.ok is true");
    let left_out = row(
        line,
        sentence.clone(),
        json!({"xs": [{"kind": "doc", "ok": false}, {"kind": "code", "ok": true}]}),
    );
    assert_eq!(left_out["cause"], "satisfied");
    let none_left = row(
        line,
        sentence.clone(),
        json!({"xs": [{"kind": "doc", "ok": true}]}),
    );
    assert_eq!(none_left["cause"], "value");
    let undecided = row(
        line,
        sentence.clone(),
        json!({"xs": [{"ok": true}, {"kind": "code", "ok": true}]}),
    );
    assert_eq!(undecided["cause"], "absent");
    assert_eq!(items(&undecided), ["item 1 of xs"]);
    assert_eq!(undecided["failed_items"][0]["failed_assertions"], json!([]));
    let null = row(line, sentence, json!({"xs": [{"kind": null, "ok": true}]}));
    assert_eq!(null["cause"], "null");
}

#[test]
fn an_item_that_ends_at_a_missing_value_fails_without_its_sentences_being_run() {
    let found = row(
        "every xs.title as t",
        json!("t is not \"WIP\""),
        json!({"xs": [{"title": "a"}, {}]}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(items(&found), ["item 2 of xs"]);
    assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
    assert_eq!(found["failed_items"][0]["value"], Value::Null);
    assert_eq!(found["inputs"][0]["name"], "xs[].title");
    assert_eq!(found["inputs"][0]["value"], json!(["a", null]));
}

#[test]
fn an_alias_hides_a_field_of_the_subject_and_a_dot_reads_the_field() {
    let subject = json!({"xs": [{"ok": true}], "x": {"ok": false}});
    assert_eq!(
        cause("every xs as x", json!("x.ok is true"), subject.clone()),
        "satisfied"
    );
    assert_eq!(
        cause("every xs as x", json!(".x.ok is true"), subject),
        "value"
    );
}

#[test]
fn a_bare_key_in_assert_is_a_subject_field_and_is_listed_sorted_with_the_list() {
    let found = row(
        "every xs as x",
        json!("x.a does not equal owner"),
        json!({"xs": [{"a": "bob"}], "owner": "ann"}),
    );
    assert_eq!(names(&found), ["owner", "xs[]"]);
}

#[test]
fn a_bare_key_in_an_items_whose_is_the_items_field() {
    let found = row(
        "some xs whose role is \"qa\" as x",
        json!("x.at is before started"),
        json!({"xs": [{"role": "qa", "at": 1}], "started": 2}),
    );
    assert_eq!(found["cause"], "satisfied");
    assert_eq!(names(&found), ["started", "xs[]"]);
}

#[test]
fn a_second_item_is_walked_for_each_item_of_the_first() {
    let line = "every ps as p, some p.ws whose s is \"A\" as w";
    let sentence = json!("w.n does not equal p.n");
    let subject = json!({"ps": [
        {"n": "ann", "ws": [{"n": "bob", "s": "A"}]},
        {"n": "eve", "ws": [{"n": "eve", "s": "A"}]}
    ]});
    let found = row(line, sentence, subject);
    assert_eq!(found["cause"], "value");
    assert_eq!(items(&found), ["item 2 of ps"]);
    let assertion = &found["failed_items"][0]["failed_assertions"][0];
    assert_eq!(assertion["assertion"], "w.n does not equal p.n");
    assert_eq!(assertion["items"][0]["item"], "item 1 of p.ws");
    assert_eq!(names(&found), ["p.ws[]", "ps[]"]);
}

#[test]
fn a_sentence_that_does_not_read_the_second_alias_shows_its_inputs_directly() {
    let found = row(
        "every ps as p, every p.ws as w",
        json!(["p.n is 1", "w.n is 1"]),
        json!({"ps": [{"n": 2, "ws": [{"n": 1}]}]}),
    );
    let assertions = found["failed_items"][0]["failed_assertions"]
        .as_array()
        .unwrap();
    assert!(assertions[0].get("inputs").is_some());
    assert!(assertions[0].get("items").is_none());
}

#[test]
fn a_failed_count_whose_whose_reads_a_part_lists_the_parts_value_with_its_location() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id", "has": {"pa": "meta"}}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {
            "for": "every groups as g",
            "assert": "count of items whose w is pa.w is 5"
        }}}}
    });
    let input = json!({"things": [{"id": "t", "groups": [1], "items": [{"w": 1}, {"w": 2}], "meta": {"w": 2}}]});
    let report = crate::report(&input, &policy, &json!({}));
    let found = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap();
    let failed = &found["failed_items"][0]["failed_assertions"][0]["inputs"];
    for inputs in [failed, &found["inputs"]] {
        let part = inputs
            .as_array()
            .unwrap()
            .iter()
            .find(|i| i["name"] == "pa.w")
            .unwrap();
        assert_eq!(part["value"], json!(2));
        assert_eq!(part["locations"], json!(["/things/0/meta/w"]));
        assert_eq!(part["part"], json!({"id": null, "name": "pa"}));
    }
}

#[test]
fn an_empty_second_list_is_listed_under_the_first_item() {
    let found = row(
        "every ps as p, every p.ws as w",
        json!("w is 1"),
        json!({"ps": [{"ws": []}]}),
    );
    assert_eq!(found["cause"], "value");
    assert_eq!(found["failed_items"][0]["failed_items"][0]["item"], "p.ws");
    assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
}

#[test]
fn a_second_item_whose_whose_leaves_nothing_in_lists_the_first_item_with_no_sentences() {
    let found = row(
        "every xs as p, every ys whose k is 1 as q",
        json!("q.n is 1"),
        json!({"xs": [{"v": 1}], "ys": [{"k": 2}]}),
    );
    assert_eq!(found["cause"], "value");
    assert_eq!(items(&found), ["item 1 of xs"]);
    assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
}

#[test]
fn a_failure_of_a_second_list_that_does_not_read_the_first_alias_is_listed_once() {
    let found = row(
        "some ps as p, every bs as b",
        json!("p.n is more than b.n"),
        json!({"ps": [{"n": 1}, {"n": 2}], "bs": "text"}),
    );
    assert_eq!(found["cause"], "unusable");
    assert_eq!(items(&found), ["bs"]);
    assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
}

#[test]
fn a_picked_item_is_named_where_it_is_and_the_list_shows_only_it() {
    let found = row(
        "last of xs sorted by t as x",
        json!("x.ok is true"),
        json!({"xs": [{"t": 2, "ok": false}, {"t": 1, "ok": true}]}),
    );
    assert_eq!(found["cause"], "value");
    assert_eq!(items(&found), ["item 1 of xs"]);
    assert_eq!(names(&found), ["item 1 of xs"]);
}

#[test]
fn a_pick_takes_the_position_from_the_start_or_the_end_in_the_order_of_the_field() {
    let subject = json!({"xs": [{"t": 3, "n": "c"}, {"t": 1, "n": "a"}, {"t": 2, "n": "b"}]});
    for (line, wanted) in [
        ("first of xs sorted by t as x", "a"),
        ("last of xs sorted by t as x", "c"),
        ("item 2 of xs sorted by t as x", "b"),
        ("item 2 from last of xs sorted by t as x", "b"),
        ("first of xs as x", "c"),
        ("last of xs as x", "b"),
    ] {
        assert_eq!(
            cause(line, json!(format!("x.n is \"{wanted}\"")), subject.clone()),
            "satisfied",
            "{line}"
        );
    }
}

#[test]
fn a_pick_sorts_strings_alphabetically_by_code_point() {
    let subject = json!({"xs": [{"n": "adam"}, {"n": "Zoe"}]});
    assert_eq!(
        cause(
            "first of xs sorted by n alphabetically as x",
            json!("x.n is \"Zoe\""),
            subject.clone()
        ),
        "satisfied"
    );
    assert_eq!(
        cause(
            "first of xs sorted by n as x",
            json!("x.n is \"Zoe\""),
            subject.clone()
        ),
        "unusable"
    );
    assert_eq!(
        cause(
            "first of xs sorted by n alphabetically as x",
            json!("x.n is 1"),
            json!({"xs": [{"n": 1}]})
        ),
        "unusable"
    );
}

#[test]
fn a_pick_sorts_numbers_times_and_dates_each_in_their_own_order() {
    assert_eq!(
        cause(
            "last of xs sorted by t as x",
            json!("x.t is \"2026-10-02T00:00:00Z\""),
            json!({"xs": [{"t": "2026-10-02T00:00:00Z"}, {"t": "2026-10-01T00:00:00Z"}]})
        ),
        "satisfied"
    );
    assert_eq!(
        cause(
            "last of xs sorted by t as x",
            json!("x.t is \"2026-10-02\""),
            json!({"xs": [{"t": "2026-10-02"}, {"t": "2026-09-30"}]})
        ),
        "satisfied"
    );
}

#[test]
fn mixed_kinds_keep_the_first_kind_and_fail_the_others_as_unusable() {
    let found = row(
        "last of xs sorted by t as x",
        json!("x.t is 1"),
        json!({"xs": [{"t": 1}, {"t": "2026-10-02T00:00:00Z"}]}),
    );
    assert_eq!(found["cause"], "unusable");
    assert_eq!(items(&found), ["item 2 of xs"]);
    assert_eq!(found["failed_items"][0]["value"], "2026-10-02T00:00:00Z");
}

#[test]
fn a_tie_at_the_picked_position_fails_every_tied_item_as_ambiguous() {
    let found = row(
        "last of xs sorted by t as x",
        json!("x.ok is true"),
        json!({"xs": [{"t": 2}, {"t": 2}, {"t": 1}]}),
    );
    assert_eq!(found["cause"], "ambiguous");
    assert_eq!(items(&found), ["item 1 of xs", "item 2 of xs"]);
    assert_eq!(found["failed_items"][0]["value"], 2);
}

#[test]
fn a_tie_elsewhere_does_not_matter() {
    assert_eq!(
        cause(
            "last of xs sorted by t as x",
            json!("x.ok is true"),
            json!({"xs": [{"t": 1}, {"t": 1}, {"t": 3, "ok": true}]})
        ),
        "satisfied"
    );
}

#[test]
fn a_missing_null_or_wrong_typed_sort_field_fails_the_item_and_nothing_is_picked() {
    for (field, wanted) in [
        (json!({}), "absent"),
        (json!({"t": null}), "null"),
        (json!({"t": "yesterday"}), "unusable"),
    ] {
        let found = row(
            "last of xs sorted by t as x",
            json!("x.ok is true"),
            json!({"xs": [{"t": 1}, field]}),
        );
        assert_eq!(found["cause"], wanted);
        assert_eq!(items(&found), ["item 2 of xs"]);
    }
}

#[test]
fn a_position_past_the_end_fails_as_absent() {
    assert_eq!(
        cause("item 3 of xs as x", json!("x is 1"), json!({"xs": [1, 2]})),
        "absent"
    );
    assert_eq!(
        cause("first of xs as x", json!("x is 1"), json!({"xs": []})),
        "absent"
    );
    assert_eq!(
        cause("last of xs as x", json!("x is 1"), json!({"xs": []})),
        "absent"
    );
}

#[test]
fn an_items_whose_reads_the_value_its_path_ends_at() {
    let line = "every rs.m whose s is \"A\" as m";
    assert_eq!(
        cause(
            line,
            json!("m.by exists"),
            json!({"rs": [{"m": {"s": "A", "by": "x"}}, {"s": "A", "m": {"s": "B"}}]})
        ),
        "satisfied"
    );
    let found = row(
        line,
        json!("m.by exists"),
        json!({"rs": [{"s": "A", "m": {"t": 1}}, {"m": {"s": "A", "t": 1}}]}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(
        found["message"],
        "item 1 of rs: m: s is missing; item 2 of rs: by is missing"
    );
}

#[test]
fn an_items_whose_fails_as_absent_when_the_value_its_path_ends_at_is_missing() {
    let found = row(
        "every rs.m whose s is \"A\" as m",
        json!("m.by exists"),
        json!({"rs": [{"m": {"s": "A", "by": "x"}}, {"s": "A"}]}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(found["message"], "item 2 of rs: m is missing");
    assert_eq!(
        found["failed_items"],
        json!([{"path": "item 2 of rs", "item": "item 2 of rs", "cause": "absent", "value": null, "locations": ["/things/0/rs/1"], "failed_assertions": []}])
    );
}

#[test]
fn an_items_whose_fails_as_not_an_object_when_the_value_its_path_ends_at_is_null() {
    let found = row(
        "every rs.m whose s is \"A\" as m",
        json!("m.by exists"),
        json!({"rs": [{"s": "A", "m": null}, {"m": {"s": "A", "by": "x"}}]}),
    );
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(
        found["message"],
        "item 1 of rs: m is null, which isn't an object"
    );
}

#[test]
fn a_pick_sorts_by_a_field_of_the_value_its_path_ends_at() {
    let subject = json!({"rs": [
        {"t": 9, "m": {"s": "A", "by": "x", "t": 2}},
        {"t": 0, "m": {"s": "B", "by": "y", "t": 1}},
        {"t": 1, "m": {"s": "A", "by": "z", "t": 3}}
    ]});
    assert_eq!(
        cause(
            "first of rs.m whose s is \"A\" sorted by t as m",
            json!("m.by is \"x\""),
            subject.clone()
        ),
        "satisfied"
    );
    assert_eq!(
        cause(
            "last of rs.m sorted by t as m",
            json!("m.by is \"z\""),
            subject
        ),
        "satisfied"
    );
    let found = row(
        "last of rs.m sorted by t as m",
        json!("m.by exists"),
        json!({"rs": [{"t": 1, "m": {"t": "zz"}}, {"m": {"t": 1}}]}),
    );
    assert_eq!(found["cause"], "unusable");
    assert_eq!(
        found["message"],
        "item 1 of rs: m: t is \"zz\", which isn't a number, a time or a date"
    );
}

#[test]
fn a_first_item_that_isnt_an_object_is_not_named_when_only_a_second_items_whose_failed_under_it() {
    let found = row(
        "every xs as x, every ys whose q is 1 as y",
        json!("y.q is 1"),
        json!({"xs": [{"n": 1}, 5], "ys": [{"q": 1}, "s"]}),
    );
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(
        found["message"],
        "item 2 of ys is \"s\", which isn't an object"
    );
}

#[test]
fn a_value_past_the_list_that_isnt_an_object_is_named_after_its_item_and_the_rest_of_the_path() {
    let found = row(
        "every ys.z as z",
        json!("z.q is 1"),
        json!({"ys": [{"z": {"q": 1}}, {"z": "s"}, {}]}),
    );
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(
        found["message"],
        "item 2 of ys: z is \"s\", which isn't an object; item 3 of ys: z is missing"
    );
}

#[test]
fn a_sort_on_a_value_that_isnt_an_object_names_the_item() {
    let found = row(
        "last of rs.m sorted by t as m",
        json!("m.by exists"),
        json!({"rs": [{"t": 1, "m": null}, {"m": {"t": 1}}]}),
    );
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(
        found["message"],
        "item 1 of rs is null, which isn't an object"
    );
}

#[test]
fn a_pick_keeps_the_items_its_whose_keeps_before_sorting() {
    assert_eq!(
        cause(
            "item 2 from last of xs whose s is \"A\" sorted by t as x",
            json!("x.n is \"b\""),
            json!({"xs": [{"s": "A", "t": 1, "n": "a"}, {"s": "A", "t": 2, "n": "b"}, {"s": "B", "t": 3, "n": "c"}, {"s": "A", "t": 4, "n": "d"}]})
        ),
        "satisfied"
    );
    assert_eq!(
        cause(
            "item 2 from last of xs whose s is \"A\" sorted by t as x",
            json!("x.n is \"b\""),
            json!({"xs": [{"s": "A", "t": 1, "n": "a"}, {"s": "A", "t": 2, "n": "b"}, {"s": "B", "t": 3, "n": "c"}]})
        ),
        "value"
    );
}

#[test]
fn a_whose_a_pick_cannot_decide_fails_the_check_and_nothing_is_picked() {
    let found = row(
        "first of xs whose s is \"A\" as x",
        json!("x.n is 1"),
        json!({"xs": [{"n": 1}, {"s": "A", "n": 1}]}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(items(&found), ["item 1 of xs"]);
}

#[test]
fn a_path_named_by_a_for_alias_reads_the_key_the_item_holds() {
    let line = "every ks as k";
    let sentence = json!("m named by k is 1");
    let subject = json!({"ks": ["a", "b"], "m": {"a": 1, "b": 2}});
    let found = row(line, sentence.clone(), subject);
    assert_eq!(found["cause"], "value");
    assert_eq!(items(&found), ["item 2 of ks"]);
    assert_eq!(names(&found), ["ks[]", "m"]);
    let null = row(line, sentence.clone(), json!({"ks": [null], "m": {"a": 1}}));
    assert_eq!(null["cause"], "null");
    let number = row(line, sentence, json!({"ks": [5], "m": {"a": 1}}));
    assert_eq!(number["cause"], "unusable");
}

#[test]
fn a_path_named_by_a_param_that_is_missing_fails_with_the_list_shown_as_empty() {
    let found = row(
        "every m named by $params.nope as x",
        json!("x is 1"),
        json!({"m": {"a": [1]}}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(found["failed_items"], json!([]));
    assert_eq!(found["inputs"][0]["value"], json!([]));
}

#[test]
fn a_count_under_a_for_line_reads_the_alias_and_lists_the_number_then_the_list() {
    let found = row(
        "every xs as x",
        json!("count of x.fs is at least 1"),
        json!({"xs": [{"fs": ["a"]}, {"fs": []}]}),
    );
    assert_eq!(found["cause"], "value");
    let inputs = &found["failed_items"][0]["failed_assertions"][0]["inputs"];
    assert_eq!(inputs[0]["name"], "count of x.fs");
    assert_eq!(inputs[0]["value"], 0);
    assert_eq!(inputs[1]["name"], "x.fs[]");
}

#[test]
fn a_failed_sentence_lists_each_value_it_read_in_the_order_it_reads_them() {
    let found = row(
        "every xs as x",
        json!("x.a is at least y"),
        json!({"xs": [{"a": 1}], "y": 5}),
    );
    let inputs = found["failed_items"][0]["failed_assertions"][0]["inputs"]
        .as_array()
        .unwrap();
    let names: Vec<&str> = inputs.iter().map(|i| i["name"].as_str().unwrap()).collect();
    assert_eq!(names, ["x.a", "y"]);
}

#[test]
fn inputs_with_the_same_name_are_ordered_by_value_before_their_locations() {
    let found = row(
        "some approvals.approver as approver",
        json!(".approver equals approver"),
        json!({"approver": "", "approvals": [{"approver": "grace"}]}),
    );
    let inputs = found["failed_items"][0]["failed_assertions"][0]["inputs"]
        .as_array()
        .unwrap();
    let values: Vec<&str> = inputs
        .iter()
        .map(|i| i["value"].as_str().unwrap())
        .collect();
    assert_eq!(values, ["", "grace"]);
}

#[test]
fn two_sentences_both_failing_are_listed_in_the_order_written() {
    let found = row(
        "every xs as x",
        json!(["x.b is 1", "x.a is 1"]),
        json!({"xs": [{"a": 2, "b": 2}]}),
    );
    let assertions: Vec<&str> = found["failed_items"][0]["failed_assertions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["assertion"].as_str().unwrap())
        .collect();
    assert_eq!(assertions, ["x.b is 1", "x.a is 1"]);
}

#[test]
fn a_whose_ref_that_is_not_a_list_fails_the_check_as_unusable_and_lists_the_items_it_cant_decide() {
    let found = row(
        "every xs whose kind is in $params.kinds as x",
        json!("x.ok is true"),
        json!({"xs": [{"kind": "code", "ok": false}]}),
    );
    assert_eq!(found["cause"], "unusable");
    assert_eq!(items(&found), ["item 1 of xs"]);
    assert_eq!(names(&found), ["xs[]"]);
    let usable = row(
        "every xs whose kind is in $params.list as x",
        json!("x.ok is true"),
        json!({"xs": [{"kind": "x", "ok": true}]}),
    );
    assert_eq!(usable["cause"], "satisfied");
}

#[test]
fn a_second_path_whose_ref_step_cannot_be_read_fails_the_first_item_with_the_refs_cause() {
    let found = row(
        "every gs as g, every g.ss named by $params.nope as s",
        json!("s.ok is true"),
        json!({"gs": [{"ss": {"a": [{"ok": true}]}}]}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(items(&found), ["item 1 of gs"]);
    let inner = &found["failed_items"][0]["failed_items"][0];
    assert_eq!(inner["item"], "g.ss named by $params.nope");
    assert_eq!(inner["cause"], "absent");
    assert_eq!(inner["value"], Value::Null);
    assert_eq!(inner["locations"], json!(["/things/0/gs/0/ss"]));
    assert_eq!(found["inputs"][0]["name"], "g.ss named by $params.nope");
    assert_eq!(found["inputs"][0]["value"], json!([]));
}

#[test]
fn a_second_item_reading_into_a_first_item_that_is_not_an_object_fails_it_as_not_an_object() {
    let found = row(
        "every ps as p, some p.as as w",
        json!("w.n does not equal p.n"),
        json!({"ps": [1, null, {"as": [{"n": "b"}], "n": "a"}]}),
    );
    assert_eq!(found["cause"], "not_an_object");
    assert_eq!(items(&found), ["item 1 of ps", "item 2 of ps"]);
    assert_eq!(found["failed_items"][0]["failed_assertions"], json!([]));
    assert!(found["failed_items"][0].get("failed_items").is_none());
    assert_eq!(found["failed_items"][1]["value"], Value::Null);
}

#[test]
fn a_path_named_by_an_alias_is_named_as_the_sentence_writes_it() {
    let found = row(
        "every ks as k",
        json!("m named by k is 1"),
        json!({"ks": ["b"], "m": {"b": 2}}),
    );
    assert_eq!(
        found["failed_items"][0]["failed_assertions"][0]["inputs"][0]["name"],
        "m named by k"
    );
}

#[test]
fn a_walk_through_an_alias_adds_nothing_read_on_the_item_to_the_rows_inputs() {
    let found = row(
        "every xs as x",
        json!("every x.fs is a string"),
        json!({"xs": [null]}),
    );
    assert_eq!(found["cause"], "null");
    assert_eq!(names(&found), ["xs[]"]);
}

#[test]
fn a_second_list_that_is_empty_in_one_item_and_missing_in_another_is_shown_by_its_walked_name() {
    let found = row(
        "every ms as m, every m.cs as c",
        json!("c.ok is true"),
        json!({"ms": [{"n": 1}, {"cs": []}]}),
    );
    assert_eq!(names(&found), ["m.cs[]", "ms[]"]);
}

#[test]
fn a_sum_that_reads_no_alias_is_listed_with_the_row_and_one_that_does_is_not() {
    let found = row(
        "every xs as x",
        json!("x.t is at least p plus q"),
        json!({"xs": [{"t": 1}], "p": 1, "q": 1}),
    );
    assert_eq!(names(&found), ["p", "p plus q", "q", "xs[]"]);
    let aliased = row(
        "every xs as x",
        json!("x.t is at least x.u plus 1"),
        json!({"xs": [{"t": 1, "u": 1}]}),
    );
    assert_eq!(names(&aliased), ["xs[]"]);
}

#[test]
fn a_walk_in_a_sentence_lists_its_own_list_unless_it_reads_through_an_alias() {
    let own = row(
        "every ks as k",
        json!("every rs.n is at least 1"),
        json!({"ks": ["a"], "rs": [{"n": 1}]}),
    );
    assert_eq!(names(&own), ["ks[]", "rs[].n"]);
    let through = row(
        "every ks as k",
        json!("some m named by k is at least 1"),
        json!({"ks": ["a"], "m": {"a": [1]}}),
    );
    assert_eq!(names(&through), ["ks[]", "m"]);
}

#[test]
fn a_row_lists_the_params_value_a_sentence_compares_with() {
    let found = row(
        "every items as x",
        json!("x.v equals $params.k"),
        json!({"items": [{"v": 1}]}),
    );
    assert_eq!(names(&found), ["$params.k", "items[]"]);
}

#[test]
fn a_row_lists_the_params_value_in_a_sentence_that_reads_no_alias() {
    let found = row(
        "every items as x",
        json!(["x.v exists", "n is $params.k"]),
        json!({"items": [{"v": 1}], "n": 1}),
    );
    assert_eq!(names(&found), ["$params.k", "items[]", "n"]);
}

#[test]
fn a_row_lists_the_params_value_a_count_is_compared_with_and_the_count() {
    let found = row(
        "every items as x",
        json!("count of items is $params.k"),
        json!({"items": [{"v": 1}]}),
    );
    assert_eq!(names(&found), ["$params.k", "count of items", "items[]"]);
}

#[test]
fn a_row_lists_the_count_on_the_right_of_a_sentence_that_reads_an_alias() {
    let found = row(
        "every items as x",
        json!("x.v is at most count of items"),
        json!({"items": [{"v": 1}]}),
    );
    assert_eq!(names(&found), ["count of items", "items[]"]);
}

#[test]
fn a_row_lists_the_elapsed_time_of_a_sentence_that_reads_no_alias() {
    let found = row(
        "every items as x",
        json!("fc is days elapsed from fa to fb"),
        json!({"items": [{"v": 1}], "fa": "2026-10-01T00:00:00Z", "fb": "2026-10-02T00:00:00Z", "fc": 1}),
    );
    assert_eq!(
        names(&found),
        ["days elapsed from fa to fb", "fa", "fb", "fc", "items[]"]
    );
}

#[test]
fn a_row_leaves_out_the_other_terms_of_a_plus_that_reads_an_alias() {
    let found = row(
        "every items as x",
        json!("x.v plus n is 5"),
        json!({"items": [{"v": 1}], "n": 4}),
    );
    assert_eq!(names(&found), ["items[]"]);
}

#[test]
fn a_row_leaves_out_the_input_a_whose_on_the_for_line_reads() {
    let found = row(
        "every items whose v is at least $input.things as x",
        json!("x.v exists"),
        json!({"items": [{"v": 1}]}),
    );
    assert_eq!(names(&found), ["items[]"]);
}

#[test]
fn a_row_leaves_out_the_params_of_a_walk_and_of_a_whose_on_the_for_line() {
    let found = row(
        "every items whose v is $params.k as x",
        json!("every items.v is at least $params.k"),
        json!({"items": [{"v": 1}]}),
    );
    assert_eq!(names(&found), ["items[]", "items[].v"]);
}

#[test]
fn a_pick_that_starts_at_the_first_alias_is_one_entry_holding_every_value_picked() {
    let found = row(
        "every items as x, last of x.subs as y",
        json!("y.w is 1"),
        json!({"items": [{"subs": [{"w": 1}, {"w": 2}]}, {"subs": [{"w": 3}]}]}),
    );
    let inputs = found["inputs"].as_array().unwrap();
    let picked: Vec<&Value> = inputs.iter().filter(|i| i["name"] == "x.subs[]").collect();
    assert_eq!(picked.len(), 1);
    assert_eq!(picked[0]["value"], json!([{"w": 2}, {"w": 3}]));
    assert_eq!(
        picked[0]["locations"],
        json!(["/things/0/items/0/subs/1", "/things/0/items/1/subs/0"])
    );
    assert!(!names(&found).iter().any(|n| n.starts_with("item ")));
}

#[test]
fn a_pick_that_finds_nothing_lists_the_list_it_looked_in_as_a_failure_of_its_own() {
    let found = row(
        "every items as x, last of x.subs as y",
        json!("y.w is 1"),
        json!({"items": [{"subs": [{"w": 1}]}, {"subs": []}]}),
    );
    assert_eq!(
        found["failed_items"][0]["failed_items"],
        json!([{"cause": "absent", "item": "x.subs", "path": "x.subs", "value": null, "locations": []}])
    );
    let past_the_end = row(
        "every items as x, item 2 of x.subs as y",
        json!("y.w is 1"),
        json!({"items": [{"subs": [{"w": 1}]}]}),
    );
    assert_eq!(
        past_the_end["failed_items"][0]["failed_items"][0]["item"],
        "x.subs"
    );
    assert_eq!(names(&past_the_end), ["items[]", "x.subs[]"]);
}

#[test]
fn a_pick_that_starts_at_another_list_still_names_the_item_where_it_is() {
    let found = row(
        "every items as x, last of ps as y",
        json!("y.w is 1"),
        json!({"items": [{"v": 1}], "ps": [{"w": 1}, {"w": 2}]}),
    );
    assert_eq!(names(&found), ["item 2 of ps", "items[]"]);
}

#[test]
fn an_empty_first_list_fails_as_the_second_items_pick_does_when_that_pick_fails() {
    let line = "every items as x, first of ps as y";
    let fails = |subject: Value, cause: &str| {
        let found = row(line, json!("y exists"), subject);
        assert_eq!(found["cause"], cause);
        assert_eq!(found["failed_items"], json!([]));
    };
    fails(json!({"items": []}), "absent");
    fails(json!({"items": [], "ps": null}), "null");
    fails(json!({"items": [], "ps": 5}), "unusable");
    fails(json!({"items": [], "ps": []}), "absent");
}

#[test]
fn an_empty_first_list_still_fails_as_value_when_the_second_pick_works() {
    let found = row(
        "every items as x, first of ps as y",
        json!("y exists"),
        json!({"items": [], "ps": [1]}),
    );
    assert_eq!(found["cause"], "value");
}

#[test]
fn an_empty_first_list_lists_the_items_a_second_pick_tied_on() {
    let found = row(
        "every items as x, first of ps sorted by t as y",
        json!("y exists"),
        json!({"items": [], "ps": [{"t": 1}, {"t": 1}]}),
    );
    assert_eq!(found["cause"], "ambiguous");
    assert_eq!(found["failed_items"].as_array().unwrap().len(), 2);
}

#[test]
fn a_first_pick_that_finds_nothing_keeps_its_own_cause_over_the_second_pick() {
    let found = row(
        "first of items as x, first of ps as y",
        json!("y exists"),
        json!({"items": [], "ps": 5}),
    );
    assert_eq!(found["cause"], "absent");
}

#[test]
fn a_params_path_named_by_an_alias_lists_the_part_before_the_name() {
    let found = row(
        "every ks as k",
        json!("$params.need named by k exists"),
        json!({"ks": ["b"]}),
    );
    assert_eq!(names(&found), ["$params.need", "ks[]"]);
}

#[test]
fn a_count_whose_list_does_not_start_at_an_alias_lists_that_list() {
    let found = row(
        "every cs as c",
        json!("count of ps whose n is c.a is at least 1"),
        json!({"cs": [{"a": 1}], "ps": [{"n": 1}]}),
    );
    assert_eq!(names(&found), ["cs[]", "ps[]"]);
}

#[test]
fn an_item_read_beside_a_param_keeps_its_alias() {
    let found = row(
        "every cs as c",
        json!("c.a is in $params.list"),
        json!({"cs": [{"a": "y"}]}),
    );
    assert_eq!(
        found["message"],
        "item 1 of cs: c.a is \"y\", and $params.list is [\"x\"]"
    );
}

#[test]
fn a_missing_param_in_an_inner_whose_is_named_once_with_no_item() {
    let found = row(
        "every ws as w",
        json!("every w.items whose lo is at least $params.p exists"),
        json!({"ws": [{"items": [{"hi": 2}, {"lo": 5}]}]}),
    );
    assert_eq!(found["message"], "$params.p is missing");
}

#[test]
fn a_sentence_root_that_cant_be_read_fails_once_before_any_item_on_an_empty_list() {
    for (subject, cause, message) in [
        (json!({"xs": []}), "absent", "z is missing"),
        (json!({"xs": [], "z": null}), "null", "z is null"),
        (
            json!({"xs": [], "z": "s"}),
            "unusable",
            "z is \"s\", which isn't a number",
        ),
        (
            json!({"xs": [{"v": 1}, {"v": 2}], "z": "s"}),
            "unusable",
            "z is \"s\", which isn't a number",
        ),
    ] {
        let found = row(
            "every xs, if any, as m",
            json!("m.v is at least z"),
            subject,
        );
        assert_eq!(found["cause"], cause);
        assert_eq!(found["message"], message);
    }
}

#[test]
fn a_sentence_root_that_cant_be_read_comes_before_an_empty_list_without_if_any() {
    let found = row(
        "every xs as m",
        json!("m.v is at least $params.missing"),
        json!({"xs": []}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(found["message"], "$params.missing is missing; xs is []");
}

#[test]
fn a_sentence_root_named_by_the_lines_alias_is_read_for_each_item() {
    let found = row(
        "every ks as k",
        json!("m named by k is 1"),
        json!({"ks": ["a", "b"], "m": {"a": 1}}),
    );
    assert_eq!(found["cause"], "absent");
    assert_eq!(found["message"], "item 2 of ks: m named by k is missing");
}

#[test]
fn a_param_key_that_isnt_text_doesnt_name_an_item_that_isnt_an_object() {
    let found = row(
        "every ws as w",
        json!("w.k named by $params.need is 1"),
        json!({"ws": [{"k": 1}, 2]}),
    );
    assert_eq!(
        found["message"],
        "$params.need is {\"b\": 1}, which isn't text"
    );
}

#[test]
fn a_key_read_from_the_item_keeps_the_alias_and_names_an_item_that_isnt_an_object() {
    let found = row(
        "every ws as w",
        json!("w.k named by w.j is 1"),
        json!({"ws": [{"k": 1, "j": "k"}, 2]}),
    );
    assert_eq!(
        found["message"],
        "item 1 of ws: w is {\"j\": \"k\", \"k\": 1}, which isn't text; item 2 of ws: w is 2, which isn't text, and w is 2, which isn't an object"
    );
}

#[test]
fn an_item_that_lacks_the_field_is_still_an_object() {
    let found = row(
        "every ws as w, last of w.items as i",
        json!("i.k named by i.j is 1"),
        json!({"ws": [{"items": [{"a": 1}]}]}),
    );
    assert_eq!(
        found["message"],
        "item 1 of ws: item 1 of items: i is {\"a\": 1}, which isn't text"
    );
}

#[test]
fn a_failed_assertion_lists_the_alias_before_the_path_through_it() {
    let found = row(
        "every ts as ok",
        json!("every ok.fs.k is in ok"),
        json!({"ts": [{"fs": [{"k": 1}]}]}),
    );
    let names: Vec<&Value> = found["failed_items"][0]["failed_assertions"][0]["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|input| &input["name"])
        .collect();
    assert_eq!(names, [&json!("ok"), &json!("ok.fs[].k")]);
}

fn pr_row(
    has: Value,
    for_line: &str,
    assertions: Value,
    fields: Value,
    params: Value,
) -> (String, Value) {
    let mut subject = json!({"from": "prs", "identified_by": "id"});
    if !has.is_null() {
        subject["has"] = has;
    }
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"pr": subject},
        "requirements": {"r": {"subject": "pr", "checks": {"c": {"for": for_line, "assert": assertions}}}}
    });
    let mut pr = fields;
    pr["id"] = json!("p0");
    let report = crate::report(&json!({"prs": [pr]}), &policy, &params);
    let found = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap();
    (
        found["cause"].as_str().unwrap().to_string(),
        found["message"].clone(),
    )
}

#[test]
fn an_empty_part_is_walked_on_the_right_of_a_list_phrase_and_named_as_not_an_object_elsewhere() {
    for (assertion, cause, message) in [
        (
            "m.v is in pl.z",
            "value",
            "item 1 of xs: m.v is 1, and pl is []",
        ),
        (
            "m.v matches pl.z",
            "value",
            "item 1 of xs: m.v is 1, and pl is []",
        ),
        (
            "pl.z contains m.v",
            "unusable",
            "pl is [], which isn't an object",
        ),
        (
            "m.v is at least pl.z",
            "unusable",
            "pl is [], which isn't an object",
        ),
    ] {
        let found = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!(assertion),
            json!({"c": [], "xs": [{"v": 1}]}),
            json!({}),
        );
        assert_eq!(found, (cause.to_string(), json!(message)), "{assertion}");
    }
}

fn two_roots_rows(pos: Value, os: Value) -> Vec<(String, Value)> {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"pr": {"from": "prs", "identified_by": "id", "has": {"pos": "os"}}},
        "requirements": {"r": {"subject": "pr", "checks": {
            "every": "every rows whose v is in pos.name and whose v is in $params.os.name exists",
            "every_rev": "every rows whose v is in $params.os.name and whose v is in pos.name exists",
            "for_count": {"for": "every ms as m", "assert": "count of m.ws whose v is in pos.name and whose v is in $params.os.name is 1"}
        }}}
    });
    let input = json!({"prs": [{"id": "p0", "os": pos, "rows": [{"v": "bob"}], "ms": [{"ws": [{"v": "bob"}]}]}]});
    let report = crate::report(&input, &policy, &json!({"os": os}));
    ["every", "every_rev", "for_count"]
        .iter()
        .map(|check| {
            let row = report["results"]
                .as_array()
                .unwrap()
                .iter()
                .find(|row| row["check"] == *check)
                .unwrap();
            (
                row["cause"].as_str().unwrap().to_string(),
                row["message"].clone(),
            )
        })
        .collect()
}

#[test]
fn two_roots_in_one_whose_are_each_named_in_the_order_the_sentence_reads_them() {
    let kinds = "which isn't a list of one kind of value";
    let pos = format!("pos[].name is [\"bob\", 3], {kinds}");
    let params = format!("$params.os[].name is [\"bob\", 3], {kinds}");
    let missing = "item 2 of pos: name is missing";
    let mixed = json!([{"name": "bob"}, {"name": 3}]);
    let unusable = |text: String| ("unusable".to_string(), json!(text));
    assert_eq!(
        two_roots_rows(mixed.clone(), mixed.clone()),
        vec![
            unusable(format!("{pos}; {params}")),
            unusable(format!("{params}; {pos}")),
            unusable(format!("{pos}; {params}")),
        ]
    );
    assert_eq!(
        two_roots_rows(json!([{"name": "bob"}, {}]), mixed),
        vec![
            unusable(format!("{missing}; {params}")),
            unusable(format!("{params}; {missing}")),
            unusable(format!("{missing}; {params}")),
        ]
    );
}

#[test]
fn a_part_that_is_a_list_of_objects_is_walked_on_the_right_of_a_list_phrase_but_not_before_contains()
 {
    for (assertion, cause, message) in [
        ("m.v is in pl.z", "satisfied", Value::Null),
        (
            "pl.z contains m.v",
            "unusable",
            json!("pl is [{\"z\": 1}], which isn't an object"),
        ),
        (
            "m.v matches pl.z",
            "unusable",
            json!(
                "pl[].z is [1], which isn't a list of patterns; item 1 of xs: m.v is 1, which isn't text"
            ),
        ),
    ] {
        let found = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!(assertion),
            json!({"c": [{"z": 1}], "xs": [{"v": 1}]}),
            json!({}),
        );
        assert_eq!(found, (cause.to_string(), message), "{assertion}");
    }
}

#[test]
fn a_part_that_is_text_or_null_on_the_right_of_a_list_phrase_says_so() {
    for (part, cause, message) in [
        (json!("s"), "unusable", "pl is \"s\", which isn't an object"),
        (json!(null), "null", "pl is null"),
    ] {
        let found = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!("m.v is in pl.z"),
            json!({"c": part, "xs": [{"v": 1}]}),
            json!({}),
        );
        assert_eq!(found, (cause.to_string(), json!(message)));
    }
}

#[test]
fn a_part_that_is_an_object_with_a_list_still_works_on_the_right_of_a_list_phrase() {
    let (cause, _) = pr_row(
        json!({"pl": "c"}),
        "every xs as m",
        json!("m.v is in pl.z"),
        json!({"c": {"z": [1]}, "xs": [{"v": 1}]}),
        json!({}),
    );
    assert_eq!(cause, "satisfied");
}

#[test]
fn a_walk_through_a_field_of_the_subject_or_the_item_is_still_read_on_the_right_of_a_list_phrase() {
    let fields = json!({"ws": [{"z": 1}], "xs": [{"v": 1, "ws": [{"z": 1}]}]});
    for assertion in ["m.v is in ws.z", "m.v is in m.ws.z", "m.v is in .ws.z"] {
        let (cause, _) = pr_row(
            json!(null),
            "every xs as m",
            json!(assertion),
            fields.clone(),
            json!({}),
        );
        assert_eq!(cause, "satisfied", "{assertion}");
    }
}

#[test]
fn params_that_are_not_an_object_make_a_for_line_unusable_even_when_its_items_are_not_objects() {
    for params in [json!([]), json!(3), json!("s"), json!(true)] {
        for (for_line, assertion) in [
            ("every xs as m", "m.v is at least 1"),
            ("every xs as m", "m.v is at least $params.n"),
            ("some xs as m", "m.v is 1"),
            (
                "every xs whose k is 1 and whose v is in $params.l as m",
                "m.v is 1",
            ),
        ] {
            for xs in [json!(["s", {"v": "x"}]), json!([null])] {
                let (cause, _) = pr_row(
                    json!(null),
                    for_line,
                    json!(assertion),
                    json!({"xs": xs}),
                    params.clone(),
                );
                assert_eq!(cause, "unusable", "{params} {for_line} {assertion} {xs}");
            }
        }
    }
}

#[test]
fn params_that_are_not_an_object_leave_the_items_messages_of_a_for_line_that_does_not_read_them() {
    let (cause, message) = pr_row(
        json!(null),
        "every xs as m",
        json!("m.v is at least 1"),
        json!({"xs": ["s", {"v": "x"}]}),
        json!(3),
    );
    assert_eq!(cause, "unusable");
    assert_eq!(
        message,
        "item 1 of xs is \"s\", which isn't an object; item 2 of xs: v is \"x\", which isn't a number"
    );
    let (_, message) = pr_row(
        json!(null),
        "every xs as m",
        json!("m.v is at least $params.n"),
        json!({"xs": [null, "s"]}),
        json!(3),
    );
    assert_eq!(message, "$params is 3, which isn't an object");
}

#[test]
fn missing_or_empty_params_leave_items_that_are_not_objects_as_not_an_object() {
    for params in [json!(null), json!({})] {
        let (cause, _) = pr_row(
            json!(null),
            "every xs as m",
            json!("m.v is at least 1"),
            json!({"xs": ["s", {"v": "x"}]}),
            params,
        );
        assert_eq!(cause, "not_an_object");
    }
}

#[test]
fn a_null_item_under_a_named_by_key_says_it_is_null_once_beside_the_item_that_is_not_text() {
    for for_line in ["every xs as m", "every xs, if any, as m"] {
        let (cause, message) = pr_row(
            json!(null),
            for_line,
            json!("m.k named by m.k is 1"),
            json!({"xs": [null, {"k": "a"}]}),
            json!({}),
        );
        assert_eq!(cause, "unusable");
        assert_eq!(
            message,
            "item 1 of xs: m is null; item 2 of xs: m is {\"k\": \"a\"}, which isn't text"
        );
    }
    let (_, message) = pr_row(
        json!(null),
        "every xs as m",
        json!(["m is $params.l", "m.v named by m.v is 1"]),
        json!({"xs": [null, {"k": "a"}]}),
        json!({}),
    );
    assert_eq!(
        message,
        "$params.l is missing; item 1 of xs: m is null; item 2 of xs: m is {\"k\": \"a\"}, which isn't text"
    );
}

const TIED: &str = "item 1 of xs: item 1 and item 2 of xs tie on v; item 2 of xs: item 1 and item 2 of xs tie on v";
const TIE_LINE: &str = "every xs as p, first of xs whose k is p.k sorted by v as m";

#[test]
fn params_that_are_not_an_object_leave_a_tie_ambiguous_when_the_check_does_not_read_them() {
    for params in [
        json!(3),
        json!([]),
        json!("s"),
        json!(true),
        json!({}),
        json!(null),
    ] {
        let (cause, message) = pr_row(
            json!(null),
            TIE_LINE,
            json!("m.v is 1"),
            json!({"xs": [{"k": "a", "v": 1}, {"k": "a", "v": 1}]}),
            params,
        );
        assert_eq!(cause, "ambiguous");
        assert_eq!(message, TIED);
    }
}

#[test]
fn params_that_are_not_an_object_are_named_before_a_tie_when_the_check_reads_them() {
    for (params, said) in [
        (json!(3), "$params is 3, which isn't an object"),
        (json!([]), "$params is [], which isn't an object"),
        (json!("s"), "$params is \"s\", which isn't an object"),
        (json!(true), "$params is true, which isn't an object"),
        (json!({}), "$params.n is missing"),
        (json!(null), "$params.n is missing"),
    ] {
        let (cause, message) = pr_row(
            json!(null),
            TIE_LINE,
            json!("m.v is at least $params.n"),
            json!({"xs": [{"k": "a", "v": 1}, {"k": "a", "v": 1}]}),
            params,
        );
        assert_eq!(cause, "ambiguous");
        assert_eq!(message, format!("{said}; {TIED}"));
    }
}

#[test]
fn params_that_are_not_an_object_still_fail_a_check_without_a_tie_as_unusable() {
    for params in [json!(3), json!([]), json!("s"), json!(true)] {
        for assertion in ["m.v is at least 1", "m.v is at least $params.n"] {
            let (cause, _) = pr_row(
                json!(null),
                "every xs as m",
                json!(assertion),
                json!({"xs": ["s", null]}),
                params.clone(),
            );
            assert_eq!(cause, "unusable");
        }
    }
}

#[test]
fn a_part_that_holds_a_list_is_walked_by_a_count_of_whose_under_a_for_line() {
    let xs = json!([{"v": 1, "ys": [{"v": 1}]}]);
    for (part, assertion, cause) in [
        (
            json!([]),
            "count of xs whose v is in pl.z is 0",
            "satisfied",
        ),
        (
            json!([]),
            "count of m.ys whose v is in pl.z is 0",
            "satisfied",
        ),
        (
            json!([{"z": 1}]),
            "count of xs whose v is in pl.z is 0",
            "value",
        ),
        (
            json!([{"z": 1}]),
            "count of m.ys whose v is in pl.z is 0",
            "value",
        ),
        (
            json!([{"z": 1}]),
            "count of xs whose v is in pl.z is at least 0",
            "satisfied",
        ),
    ] {
        let (found, _) = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!(assertion),
            json!({"c": part, "xs": xs}),
            json!({}),
        );
        assert_eq!(found, cause, "{assertion}");
    }
}

#[test]
fn a_part_that_is_text_null_missing_or_an_object_with_a_list_is_read_as_before_in_a_count_of_whose()
{
    let xs = json!([{"v": 1}]);
    for (fields, cause, said) in [
        (
            json!({"c": "s", "xs": xs}),
            "unusable",
            "pl is \"s\", which isn't an object",
        ),
        (json!({"c": null, "xs": xs}), "null", "pl is null"),
        (json!({"xs": xs}), "absent", "pl.z is missing"),
        (
            json!({"c": {"z": [1]}, "xs": xs}),
            "value",
            "count of xs whose v is in pl.z is 1",
        ),
        (json!({"c": {"z": [2]}, "xs": xs}), "satisfied", ""),
    ] {
        let (found, message) = pr_row(
            json!({"pl": "c"}),
            "every xs as m",
            json!("count of xs whose v is in pl.z is 0"),
            fields,
            json!({}),
        );
        assert_eq!(found, cause);
        assert_eq!(message.as_str().unwrap_or(""), said);
    }
}
