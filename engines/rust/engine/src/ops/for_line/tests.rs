use crate::SPEC;
use serde_json::{Value, json};

fn row(for_line: &str, assertions: Value, subject: Value) -> Value {
    row_with(
        for_line,
        assertions,
        subject,
        json!({"k": "a", "list": ["x"], "kinds": "code", "need": {"b": 1}}),
    )
}

fn row_with(for_line: &str, assertions: Value, subject: Value, params: Value) -> Value {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": for_line, "assert": assertions}}}}
    });
    let mut subject = subject;
    subject["id"] = json!(1);
    let input = json!({"things": [subject]});
    let report = crate::report::keeping_stash(|| crate::report(&input, &policy, &params));
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
    let report = crate::report::keeping_stash(|| crate::report(&input, &policy, &json!({})));
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
        json!([{"name": "x.ok", "value": false, "locations": ["/things/0/xs/1/ok"], "outcome": "usable"}])
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
            "item 1 of approvers: ap.state is missing; item 2 of approvers: ap.state is \"REJECTED\""
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
        "w is missing; y is \"s\", which isn't a number; z is 3"
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
    let report = crate::report::keeping_stash(|| {
        crate::report(&json!({"things": ["text"]}), &policy, &json!({}))
    });
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
        let report = crate::report::keeping_stash(|| {
            crate::report(&json!({"xs": [subject]}), &policy, &json!({}))
        });
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
    let report = crate::report::keeping_stash(|| crate::report(&input, &policy, &json!({})));
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
    let report = crate::report::keeping_stash(|| crate::report(&input, &policy, &json!({})));
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

fn for_row_message(for_line: &str, assertion: &str, subject: Value, params: Value) -> String {
    let line = ergo_policy_sentences::parse_for(for_line).unwrap();
    let tree = ergo_policy_sentences::parse_check(assertion).unwrap();
    let checked = super::lower_for(
        &line,
        &tree.assertions,
        &["p".to_string()],
        &crate::lower::Scope::new(),
    )
    .unwrap();
    let crate::ops::Check::For(line) = checked else {
        panic!("{for_line} is not a for line");
    };
    let input = json!({"things": [subject]});
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: crate::path::Located {
            value: &input["things"][0],
            location: crate::path::Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    line.run(&ctx).message.unwrap_or_default()
}

#[test]
fn a_count_on_a_for_line_says_every_item_of_each_alias_or_counts_it_in_and_n_more_beside_a_missing_key()
 {
    let assertion = "count of g.es.v that is m named by $params.k is 0";
    for (gs, said) in [
        (
            json!([{"es": [{"v": {}}, {"v": {}}, {"v": {}}, {"v": {}}, {"v": {}}]}]),
            "$params.k is missing; item 1 of gs: item 1 of g.es: v: m is missing; item 1 of gs: item 2 of g.es: v: m is missing; item 1 of gs: item 3 of g.es: v: m is missing; and 2 more",
        ),
        (
            json!([{"es": [{"v": {}}, {"v": {}}]}, {"es": [{"v": {}}, {"v": {}}]}]),
            "$params.k is missing; item 1 of gs: item 1 of g.es: v: m is missing; item 1 of gs: item 2 of g.es: v: m is missing; item 2 of gs: item 1 of g.es: v: m is missing; and 1 more",
        ),
    ] {
        assert_eq!(
            for_row_message("every gs as g", assertion, json!({"gs": gs}), json!({})),
            said
        );
    }
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
        "item 1 of rs: m: s is missing; item 2 of rs: m.by is missing"
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
        json!([{"path": "item 2 of rs", "item": "item 2 of rs", "cause": "absent", "value": null, "locations": ["/things/0/rs/1"], "failed_assertions": [], "ergo/said": "item 2 of rs: m", "ergo/text": "item 2 of rs: m is missing"}])
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
        json!([{"cause": "absent", "item": "x.subs", "path": "x.subs", "value": null, "locations": [], "ergo/said": "x.subs", "ergo/text": "x.subs is missing"}])
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
    assert_eq!(
        found["message"],
        "$params.p is missing; item 1 of ws: item 1 of w.items: lo is missing"
    );
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
fn a_param_key_that_isnt_text_names_the_value_before_it_but_not_an_item_that_isnt_an_object() {
    let found = row(
        "every ws as w",
        json!("w.k named by $params.need is 1"),
        json!({"ws": [{"k": 1}, 2]}),
    );
    assert_eq!(
        found["message"],
        "$params.need is {\"b\": 1}, which isn't text; item 1 of ws: w.k is 1, which isn't an object"
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
        "item 1 of ws: item 1 of w.items: i is {\"a\": 1}, which isn't text"
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
    let report =
        crate::report::keeping_stash(|| crate::report(&json!({"prs": [pr]}), &policy, &params));
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
    let report =
        crate::report::keeping_stash(|| crate::report(&input, &policy, &json!({"os": os})));
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
fn two_roots_in_one_whose_are_named_worst_cause_first_and_then_by_name() {
    let kinds = "which isn't a list of one kind of value";
    let pos = format!("pos[].name is [\"bob\", 3], {kinds}");
    let params = format!("$params.os[].name is [\"bob\", 3], {kinds}");
    let missing = "item 2 of pos: name is missing";
    let mixed = json!([{"name": "bob"}, {"name": 3}]);
    let unusable = |text: String| ("unusable".to_string(), json!(text));
    assert_eq!(
        two_roots_rows(mixed.clone(), mixed.clone()),
        vec![
            unusable(format!("{params}; {pos}")),
            unusable(format!("{params}; {pos}")),
            unusable(format!("{params}; {pos}")),
        ]
    );
    assert_eq!(
        two_roots_rows(json!([{"name": "bob"}, {}]), mixed),
        vec![
            unusable(format!("{params}; {missing}")),
            unusable(format!("{params}; {missing}")),
            unusable(format!("{params}; {missing}")),
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
        "item 1 of xs is \"s\", which isn't an object; item 2 of xs: m.v is \"x\", which isn't a number"
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

fn for_roots(for_line: &str, assertions: &[&str], subject: Value, params: Value) -> String {
    let clauses = for_root_clauses(for_line, assertions, subject, params);
    crate::ops::clause::text(&crate::ops::clause::shown(&clauses))
}

fn for_root_clauses(
    for_line: &str,
    assertions: &[&str],
    subject: Value,
    params: Value,
) -> Vec<crate::ops::clause::Clause> {
    let line = ergo_policy_sentences::parse_for(for_line).unwrap();
    let parsed: Vec<_> = assertions
        .iter()
        .flat_map(|assertion| {
            ergo_policy_sentences::parse_check(assertion)
                .unwrap()
                .assertions
        })
        .collect();
    let places: Vec<String> = assertions.iter().map(|_| "p".to_string()).collect();
    let checked = super::lower_for(&line, &parsed, &places, &crate::lower::Scope::new()).unwrap();
    let crate::ops::Check::For(line) = checked else {
        panic!("{for_line} is not a for line");
    };
    let input = json!({"things": [subject]});
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: crate::path::Located {
            value: &input["things"][0],
            location: crate::path::Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    line.root_clauses(&ctx)
}

#[test]
fn root_clauses_say_each_sentences_roots_in_turn() {
    assert_eq!(
        for_roots(
            "every xs as x",
            &["x.v is at least $params.b", "x.w is at least $params.a"],
            json!({"xs": [{"v": 1, "w": 1}]}),
            json!({"a": "s"}),
        ),
        "$params.b is missing; $params.a is \"s\", which isn't a number"
    );
}

#[test]
fn root_clauses_say_the_lines_whose_roots_first() {
    assert_eq!(
        for_roots(
            "every xs whose v is at least $params.min as x",
            &["x.w is at least $params.a"],
            json!({"xs": [{"v": 1, "w": 1}]}),
            json!({"a": "s"}),
        ),
        "$params.min is missing; $params.a is \"s\", which isn't a number"
    );
}

#[test]
fn the_lists_unreadable_key_comes_before_the_roots_of_the_sentences() {
    assert_eq!(
        for_roots(
            "every xs named by $params.k as x",
            &["x.w is at least $params.a"],
            json!({"xs": [{"w": 1}]}),
            json!({"a": "s"}),
        ),
        "$params.k is missing; $params.a is \"s\", which isn't a number"
    );
}

#[test]
fn a_root_whose_value_holds_a_semicolon_is_one_clause() {
    let line = ergo_policy_sentences::parse_for("every xs as x").unwrap();
    let tree = ergo_policy_sentences::parse_check("x.v is at least $params.min").unwrap();
    let crate::ops::Check::For(line) = super::lower_for(
        &line,
        &tree.assertions,
        &["p".to_string()],
        &crate::lower::Scope::new(),
    )
    .unwrap() else {
        panic!("not a for line");
    };
    let input = json!({"things": [{"xs": [{"v": "a; b"}]}]});
    let params = json!({"min": "s; t"});
    let ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: crate::path::Located {
            value: &input["things"][0],
            location: crate::path::Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    let clauses = crate::ops::clause::shown(&line.root_clauses(&ctx));
    assert_eq!(clauses.len(), 1);
    assert_eq!(
        clauses[0].text,
        "$params.min is \"s; t\", which isn't a number"
    );
}

#[test]
fn root_clauses_give_the_roots_the_row_says_today() {
    for (for_line, assertions, subject, params) in [
        (
            "every xs as x",
            vec!["x.v is at least $params.b"],
            json!({"xs": [{"v": 1}]}),
            json!({}),
        ),
        (
            "every xs whose v is at least $params.min as x",
            vec!["x.w is at least $params.a"],
            json!({"xs": [{"v": 1, "w": 1}]}),
            json!({"a": "s"}),
        ),
    ] {
        let roots = for_roots(for_line, &assertions, subject.clone(), params.clone());
        let message = for_row_message(for_line, assertions[0], subject, params);
        assert!(!roots.is_empty(), "{for_line}: no roots");
        assert!(
            message.starts_with(&roots),
            "{for_line}: {message} does not start with {roots}"
        );
    }
}

fn item_clauses(
    for_line: &str,
    assertions: &[&str],
    subject: Value,
    params: Value,
    item: usize,
    sentence: usize,
) -> (crate::cause::Cause, Vec<crate::ops::clause::Clause>) {
    let line = ergo_policy_sentences::parse_for(for_line).unwrap();
    let parsed: Vec<_> = assertions
        .iter()
        .flat_map(|assertion| {
            ergo_policy_sentences::parse_check(assertion)
                .unwrap()
                .assertions
        })
        .collect();
    let places: Vec<String> = assertions.iter().map(|_| "p".to_string()).collect();
    let checked = super::lower_for(&line, &parsed, &places, &crate::lower::Scope::new()).unwrap();
    let crate::ops::Check::For(line) = checked else {
        panic!("{for_line} is not a for line");
    };
    let input = json!({"things": [subject]});
    let list = crate::name::name(&line.items[0].path);
    let mut ctx = crate::path::Ctx {
        label: None,
        item_by_item: false,
        subject: crate::path::Located {
            value: &input["things"][0],
            location: crate::path::Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    ctx.aliases.insert(
        line.items[0].alias.clone(),
        crate::path::Located {
            value: &input["things"][0][&list][item],
            location: crate::path::Location::input_root()
                .key("things")
                .index(0)
                .key(&list)
                .index(item as u64),
        },
    );
    line.sentence_clauses(sentence, &ctx)
}

fn item_text(
    for_line: &str,
    assertions: &[&str],
    subject: Value,
    params: Value,
    item: usize,
    sentence: usize,
) -> String {
    let (_, clauses) = item_clauses(for_line, assertions, subject, params, item, sentence);
    crate::ops::clause::text(&clauses)
}

#[test]
fn a_sentence_says_its_own_read_without_the_root() {
    let subject = json!({"xs": [{"v": "a"}, {}]});
    let params = json!({"min": "s"});
    let said = |item| {
        item_text(
            "every xs as x",
            &["x.v is at least $params.min"],
            subject.clone(),
            params.clone(),
            item,
            0,
        )
    };
    assert_eq!(said(0), "x.v is \"a\", which isn't a number");
    assert_eq!(said(1), "x.v is missing");
}

#[test]
fn a_sentence_keeps_a_value_that_holds_a_semicolon_whole() {
    let (_, clauses) = item_clauses(
        "every xs as x",
        &["x.v is at least $params.min"],
        json!({"xs": [{"v": "a; b"}, {}]}),
        json!({"min": "s; t"}),
        0,
        0,
    );
    let texts: Vec<&str> = clauses.iter().map(|clause| clause.text.as_str()).collect();
    assert_eq!(texts, ["x.v is \"a; b\", which isn't a number"]);
}

#[test]
fn a_count_under_the_line_gives_its_items_as_clauses() {
    let (_, clauses) = item_clauses(
        "every gs as g",
        &["count of g.es whose v is at least $params.min is 0"],
        json!({"gs": [{"es": [{}, {}]}, {"es": [{}, {"v": 2}]}]}),
        json!({"min": "s"}),
        0,
        0,
    );
    let items: Vec<(crate::ops::clause::Kind, &str)> = clauses
        .iter()
        .map(|clause| (clause.kind, clause.name.as_str()))
        .collect();
    assert_eq!(
        items,
        [
            (crate::ops::clause::Kind::Item, "item 1 of g.es"),
            (crate::ops::clause::Kind::Item, "item 2 of g.es"),
        ]
    );
    assert_eq!(
        crate::ops::clause::text(&clauses),
        "item 1 of g.es: v is missing; item 2 of g.es: v is missing"
    );
}

#[test]
fn a_sum_under_the_line_gives_its_items_as_clauses() {
    let subject = json!({"gs": [{"rs": [{"n": "a"}, {}]}, {"rs": [{"n": null}]}]});
    let said = |item| {
        item_text(
            "every gs as g",
            &["sum of g.rs.n is 3"],
            subject.clone(),
            json!({}),
            item,
            0,
        )
    };
    assert_eq!(
        said(0),
        "item 1 of g.rs: n is \"a\", which isn't a number; item 2 of g.rs: n is missing"
    );
    assert_eq!(said(1), "item 1 of g.rs: n is null");
}

#[test]
fn a_key_from_params_is_left_out_of_the_items_of_a_count_under_the_line() {
    assert_eq!(
        item_text(
            "every gs as g",
            &["count of g.es.v that is m named by $params.k is 0"],
            json!({"gs": [{"es": [{"v": {}}]}, {"es": [{"v": {}}]}]}),
            json!({}),
            0,
            0,
        ),
        "item 1 of g.es: v: m is missing"
    );
}

#[test]
fn two_sentences_walking_one_list_give_their_own_items_as_clauses() {
    let assertions = ["every x.ys.n is 1", "every x.ys.m is 1"];
    let subject = json!({"xs": [{"ys": [{"n": 1, "m": 2}, {"m": 1}]}]});
    let said = |sentence| {
        item_text(
            "every xs as x",
            &assertions,
            subject.clone(),
            json!({}),
            0,
            sentence,
        )
    };
    assert_eq!(said(0), "item 2 of x.ys: n is missing");
    assert_eq!(said(1), "item 1 of x.ys: m is 2");
}

#[test]
fn a_sentence_whose_only_problems_are_roots_says_nothing_for_the_item() {
    let assertions = [
        "x.v is at least $params.a",
        "x.v is at most $params.b",
        "x.w is $params.c",
        "x.u is in $params.d",
    ];
    for sentence in 0..assertions.len() {
        let (cause, clauses) = item_clauses(
            "every xs as x",
            &assertions,
            json!({"xs": [{"v": 1, "w": 1, "u": 1}]}),
            json!({}),
            0,
            sentence,
        );
        assert_eq!(
            cause,
            crate::cause::Cause::Absent,
            "{}",
            assertions[sentence]
        );
        assert!(clauses.is_empty(), "{}: {clauses:?}", assertions[sentence]);
    }
}

#[test]
fn a_sentence_says_what_it_says_as_a_check_of_its_own() {
    let subject = json!({"xs": [{"v": 2, "es": [{"v": 2}, {}, {"v": 1}]}]});
    for assertion in [
        "x.v is 1",
        "count of x.es whose v is 1 is 3",
        "sum of x.es.v is 1",
        "every x.es.v is 1",
    ] {
        let line = ergo_policy_sentences::parse_for("every xs as x").unwrap();
        let tree = ergo_policy_sentences::parse_check(assertion).unwrap();
        let crate::ops::Check::For(line) = super::lower_for(
            &line,
            &tree.assertions,
            &["p".to_string()],
            &crate::lower::Scope::new(),
        )
        .unwrap() else {
            panic!("not a for line");
        };
        let input = json!({"things": [subject.clone()]});
        let params = json!({});
        let mut ctx = crate::path::Ctx {
            label: None,
            item_by_item: false,
            subject: crate::path::Located {
                value: &input["things"][0],
                location: crate::path::Location::input_root().key("things").index(0),
            },
            input: &input,
            params: Some(&params),
            aliases: std::collections::BTreeMap::new(),
        };
        ctx.aliases.insert(
            "x".to_string(),
            crate::path::Located {
                value: &input["things"][0]["xs"][0],
                location: crate::path::Location::input_root()
                    .key("things")
                    .index(0)
                    .key("xs")
                    .index(0),
            },
        );
        let check = &line.sentences[0].check;
        let ran = crate::ops::run_full(check, &ctx);
        let own = match &ran.parts {
            Some(parts) if !parts.is_empty() => {
                crate::ops::clause::text(&crate::ops::clause::shown(parts))
            }
            _ => crate::ops::message::said_text(&crate::ops::message::row_said(
                check,
                &ctx,
                &ran.verdict,
            )),
        };
        let (cause, clauses) = line.sentence_clauses(0, &ctx);
        assert_eq!(cause, ran.verdict.cause, "{assertion}");
        assert_eq!(crate::ops::clause::text(&clauses), own, "{assertion}");
    }
}

#[test]
fn a_sentence_says_the_value_before_a_key_it_cant_read_after_leaving_out_the_key() {
    let subject = json!({"xs": [{"m": 3}, {"m": {}}]});
    let said = |item| {
        let (cause, clauses) = item_clauses(
            "every xs as x",
            &["x.m named by $params.k is 1"],
            subject.clone(),
            json!({}),
            item,
            0,
        );
        (cause, crate::ops::clause::text(&clauses))
    };
    assert_eq!(
        said(0),
        (
            crate::cause::Cause::Unusable,
            "x.m is 3, which isn't an object".to_string()
        )
    );
    assert_eq!(said(1), (crate::cause::Cause::Absent, String::new()));
}

#[test]
fn each_root_of_one_sentence_keeps_its_own_cause() {
    assert_eq!(
        for_roots(
            "every xs as x",
            &["$params.a is at least $params.b"],
            json!({"xs": [{}]}),
            json!({"b": "s"}),
        ),
        "$params.b is \"s\", which isn't a number; $params.a is missing"
    );
}

#[test]
fn a_sentence_says_an_item_once_when_two_of_its_whose_clauses_cant_read_it() {
    assert_eq!(
        item_text(
            "every xs as x",
            &["count of x.es whose v is at least $params.a and whose v is at most $params.b is 0"],
            json!({"xs": [{"es": [{"v": 1}, {}]}]}),
            json!({"a": "s"}),
            0,
            0,
        ),
        "item 2 of x.es: v is missing"
    );
}

fn for_line_cases() -> Vec<(String, Value, Value, Value)> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let mut topics: Vec<std::path::PathBuf> = std::fs::read_dir(root.join("../../spec/cases"))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.is_dir())
        .collect();
    topics.sort();
    let mut out = Vec::new();
    for topic in topics {
        let name = topic.file_name().unwrap().to_string_lossy().into_owned();
        let text = std::fs::read_to_string(topic.join("cases.json"))
            .unwrap()
            .replace("{{spec}}", SPEC);
        let groups: Value = serde_json::from_str(&text).unwrap();
        for group in groups.as_array().unwrap() {
            if !group["policy"].to_string().contains("\"for\"") {
                continue;
            }
            for case in group["cases"].as_array().unwrap() {
                let id = format!(
                    "{name} / {} / {}",
                    group["description"].as_str().unwrap(),
                    case["description"].as_str().unwrap()
                );
                let params = group.get("params").cloned().unwrap_or_else(|| json!({}));
                out.push((id, case["input"].clone(), group["policy"].clone(), params));
            }
        }
    }
    out
}

const ENTRY_CAUSE: &str = "the tree gives an item the cause the case gives its entry and Rust's entry doesn't, until R5-7 builds the entries from the clauses";

const OTHER_SUBJECTS_CAUSE: &str = "the tree gives item 1 of ys its own cause, absent, as for.try says, in a subject where neither engine gives it an entry, and this test compares it with the entries of the same name in the case's other subjects, which are unusable and null";

const SAID_NOWHERE: &str = "the row fails from something it says nowhere, a subject that isn't an object or an item of the first list that picks nothing, as for.pick says, so no clause of the tree carries that cause, and the row takes that cause from the line";

const ROW_LEAVES_OUT_AN_ITEM: &str = "the row and the tree leave out the item of the second list that the whose can't read, which the case says and which gives the row its cause, and the case is in known-failures.txt until the Rust engine says that item";

const ROWS_THE_CLAUSES_DONT_SAY_YET: &[(&str, usize, &str)] = &[
    (
        "for / a for line on a subject that isn't an object / fails as not_an_object when the first path starts at the subject",
        1,
        SAID_NOWHERE,
    ),
    (
        "for / a for line on a subject that isn't an object names the subject / the message names thing, never the subject",
        1,
        SAID_NOWHERE,
    ),
    (
        "for / a for line sorted by a key from $params that is missing says the key once and gives an item an entry only for its own problem / an item whose m is a list and an item without m",
        1,
        ENTRY_CAUSE,
    ),
    (
        "for / a for line walks a subject that is a list / an empty list fails as value, and a null subject as not_an_object",
        2,
        SAID_NOWHERE,
    ),
    (
        "for / a for line whose second list has a named by key from $params that is missing / says the key once and then each item's list that fails whatever the key",
        1,
        ENTRY_CAUSE,
    ),
    (
        "for / a for line whose second list has a named by key from $params that isn't text / says the key once on the row, after the sentence that doesn't read x",
        1,
        ENTRY_CAUSE,
    ),
    (
        "for / a for line walks a subject that is a list / an empty list fails as value, and a null subject as not_an_object",
        5,
        SAID_NOWHERE,
    ),
    (
        "for / a for line walks a subject that is a list / an empty list fails as value, and a null subject as not_an_object",
        6,
        SAID_NOWHERE,
    ),
    (
        "for / a for line walks a subject that is a list / an empty list fails as value, and a null subject as not_an_object",
        7,
        SAID_NOWHERE,
    ),
    (
        "for / a for line walks a subject that is a list / an empty list fails as value, and a null subject as not_an_object",
        8,
        SAID_NOWHERE,
    ),
    (
        "for / a for line walks a subject that is a list / every and some walk the stages, and an item with a position fails as not_an_object",
        2,
        SAID_NOWHERE,
    ),
    (
        "for / a for line whose item path is the subject's own name walks a subject that is a list, and fails one that isn't an object / a text subject is not an object",
        1,
        SAID_NOWHERE,
    ),
    (
        "for / a second for item picking after the first alias lists nothing when it picks nothing / a first item that fails its check is listed and one that matches nothing is not",
        1,
        SAID_NOWHERE,
    ),
    (
        "for / an item of a second list that the whose can't read is said beside an item that fails the sentence / one deploy and one approver fail the sentence, and one of each has no key",
        1,
        ROW_LEAVES_OUT_AN_ITEM,
    ),
    (
        "for / an item of a second list that the whose can't read is said beside an item that fails the sentence / one deploy and one approver fail the sentence, and one of each has no key",
        2,
        ROW_LEAVES_OUT_AN_ITEM,
    ),
    (
        "messages / a for item with a whose that reads a part over items that aren't all objects / names the part first, once, then each item in turn",
        1,
        ENTRY_CAUSE,
    ),
    (
        "messages / a root that reads the alias of the first item of a for line, in the second item / fails before any item of the second list, naming each first item, on an empty list too",
        5,
        OTHER_SUBJECTS_CAUSE,
    ),
    (
        "for / a walk through a for line's alias leaves a root after the phrase to the assertion, and each item keeps its own cause and the items of its list / an item whose list holds five items without v",
        1,
        ENTRY_CAUSE,
    ),
    (
        "for / a walk through a for line's alias leaves a root after the phrase to the assertion, and each item keeps its own cause and the items of its list / an item whose list holds five items without v",
        2,
        ENTRY_CAUSE,
    ),
];

fn item_entries(failures: &Value, out: &mut Vec<(String, String)>) {
    for failure in failures.as_array().into_iter().flatten() {
        if failure["kind"] == "item" {
            out.push((
                failure["name"].as_str().unwrap_or("").to_string(),
                failure["cause"].as_str().unwrap_or("").to_string(),
            ));
        }
        item_entries(&failure["failures"], out);
    }
}

fn item_causes(clauses: &[crate::ops::clause::Clause], out: &mut Vec<(String, String)>) {
    for clause in clauses {
        if clause.kind == crate::ops::clause::Kind::Item {
            out.push((clause.name.clone(), clause.cause.name().to_string()));
        }
        item_causes(&clause.said, out);
    }
}

fn tree_causes(clauses: &[crate::ops::clause::Clause]) -> Vec<crate::cause::Cause> {
    clauses
        .iter()
        .flat_map(|clause| std::iter::once(clause.cause).chain(tree_causes(&clause.said)))
        .collect()
}

#[test]
fn the_clauses_of_every_for_row_say_what_the_row_and_its_entries_say_today() {
    let mut differ: Vec<String> = Vec::new();
    let mut compared = 0;
    let mut listed: Vec<(&str, usize)> = Vec::new();
    for (id, input, policy, params) in for_line_cases() {
        super::RAN.with(|ran| ran.borrow_mut().clear());
        let report = crate::report(&input, &policy, &params);
        let mut entries: Vec<(String, String)> = Vec::new();
        for result in report["results"].as_array().into_iter().flatten() {
            item_entries(&result["failures"], &mut entries);
        }
        for (at, (cause, message, clauses)) in
            super::RAN.with(|ran| ran.take()).into_iter().enumerate()
        {
            let row = at + 1;
            let message = message.unwrap_or_default();
            let shown = crate::ops::clause::shown(&clauses);
            let said = crate::ops::clause::text(&shown);
            let mut causes: Vec<(String, String)> = Vec::new();
            item_causes(&shown, &mut causes);
            let mut wrong: Vec<String> = causes
                .iter()
                .filter(|(name, cause)| {
                    let same: Vec<&String> = entries
                        .iter()
                        .filter(|(entry, _)| entry == name)
                        .map(|(_, cause)| cause)
                        .collect();
                    !same.is_empty() && !same.contains(&cause)
                })
                .map(|(name, cause)| format!("{name} is {cause}"))
                .collect();
            let worst = crate::cause::Cause::worst(tree_causes(&clauses))
                .unwrap_or(crate::cause::Cause::Satisfied);
            if worst != cause {
                wrong.push(format!(
                    "the clauses fail as {} and the row as {}",
                    worst.name(),
                    cause.name()
                ));
            }
            if said == message && wrong.is_empty() {
                if cause != crate::cause::Cause::Satisfied {
                    compared += 1;
                }
                continue;
            }
            match ROWS_THE_CLAUSES_DONT_SAY_YET
                .iter()
                .find(|(listed, listed_row, _)| *listed == id && *listed_row == row)
            {
                Some((listed_id, listed_row, _)) => listed.push((*listed_id, *listed_row)),
                None => differ.push(format!(
                    "{id}, row {row}\n  row:   {message}\n  items: {said}\n  causes: {}\n  tree: {}",
                    wrong.join(", "),
                    self::causes(&clauses).join(", ")
                )),
            }
        }
    }
    assert!(
        differ.is_empty(),
        "{} rows differ, {compared} say what the row says:\n{}",
        differ.len(),
        differ.join("\n")
    );
    let said: Vec<String> = ROWS_THE_CLAUSES_DONT_SAY_YET
        .iter()
        .filter(|(id, row, _)| !listed.contains(&(*id, *row)))
        .map(|(id, row, reason)| format!("{id}, row {row} ({reason})"))
        .collect();
    assert!(
        said.is_empty(),
        "{} listed rows say what the row says:\n{}",
        said.len(),
        said.join("\n")
    );
    assert!(compared > 0);
}

fn for_items(
    for_line: &str,
    assertions: &[&str],
    subject: Value,
    params: Value,
) -> Vec<crate::ops::clause::Clause> {
    for_run(for_line, assertions, subject, params).items
}

fn for_row(for_line: &str, assertions: &[&str], subject: Value, params: Value) -> (String, String) {
    let run = for_run(for_line, assertions, subject, params);
    (
        run.verdict.cause.name().to_string(),
        run.message.unwrap_or_default(),
    )
}

fn for_run(for_line: &str, assertions: &[&str], subject: Value, params: Value) -> super::Run {
    let line = ergo_policy_sentences::parse_for(for_line).unwrap();
    let parsed: Vec<_> = assertions
        .iter()
        .flat_map(|assertion| {
            ergo_policy_sentences::parse_check(assertion)
                .unwrap()
                .assertions
        })
        .collect();
    let places: Vec<String> = assertions.iter().map(|_| "p".to_string()).collect();
    let checked = super::lower_for(&line, &parsed, &places, &crate::lower::Scope::new()).unwrap();
    let crate::ops::Check::For(line) = checked else {
        panic!("{for_line} is not a for line");
    };
    let input = json!({"things": [subject]});
    let ctx = crate::path::Ctx {
        label: Some("thing".to_string()),
        item_by_item: false,
        subject: crate::path::Located {
            value: &input["things"][0],
            location: crate::path::Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: std::collections::BTreeMap::new(),
    };
    line.run(&ctx)
}

#[test]
fn an_item_of_an_earlier_line_that_isnt_an_object_still_fails_what_a_later_line_reads_of_it_whole()
{
    let said = |line: &str, assertion: &str, subject: Value| {
        for_row(line, &[assertion], subject, json!({}))
    };
    assert_eq!(
        said(
            "every deps as d, every rows whose v is in d.name, if any, as r",
            "r.n is 1",
            json!({"rows": [], "deps": [[{"name": "bob"}, {}]]}),
        ),
        (
            "absent".to_string(),
            "item 1 of deps: item 2 of d: name is missing".to_string()
        )
    );
    assert_eq!(
        said(
            "every deps as d, every rows, if any, as r",
            "count of r.tags that is in d.name is 0",
            json!({"rows": [], "deps": [[{"name": "bob"}, {"name": 3}]]}),
        ),
        (
            "unusable".to_string(),
            "item 1 of deps: d[].name is [\"bob\", 3], which isn't a list of one kind of value"
                .to_string()
        )
    );
    assert_eq!(
        said(
            "every ks as k, every xs, if any, as m",
            "m.t named by k is 1",
            json!({"ks": [3], "xs": []}),
        ),
        (
            "unusable".to_string(),
            "item 1 of ks: k is 3, which isn't text".to_string()
        )
    );
    assert_eq!(
        said(
            "every deps as d, every rows whose v is in d.name, if any, as r",
            "r.n is 1",
            json!({"rows": [], "deps": [null]}),
        )
        .0,
        "satisfied"
    );
}

#[test]
fn a_key_read_from_a_field_isnt_said_when_the_list_before_it_is_null() {
    for p in [json!("k"), json!(3), json!(["k"]), Value::Null] {
        assert_eq!(
            for_row(
                "every rows.w named by p as w",
                &["w is \"xy\""],
                json!({"p": p, "rows": null}),
                json!({}),
            ),
            ("null".to_string(), "rows is null".to_string()),
            "{p}"
        );
    }
}

#[test]
fn a_sentence_that_reads_the_alias_only_as_a_key_of_a_count_is_said_for_each_item() {
    for (for_line, assertion, subject, said) in [
        (
            "every ks as k",
            "count of es whose zz is m named by k is 0",
            json!({"ks": ["a", 3, null], "es": [{"zz": 1}]}),
            "item 1 of ks: item 1 of es: m named by k is missing; item 2 of ks: k is 3, which isn't text; item 2 of ks: item 1 of es: m is missing; item 3 of ks: k is null; item 3 of ks: item 1 of es: m is missing",
        ),
        (
            "every ks as k",
            "count of es whose zz is m named by k is 0",
            json!({"ks": [3], "es": [{"zz": 1, "m": {"a": 1}}]}),
            "item 1 of ks: k is 3, which isn't text",
        ),
    ] {
        assert_eq!(
            for_row(for_line, &[assertion], subject, json!({})),
            ("unusable".to_string(), said.to_string()),
            "{for_line} {assertion}"
        );
    }
    assert_eq!(
        for_row(
            "every xs as x",
            &["count of es whose zz is m named by x.k is 0"],
            json!({"xs": [{"k": 3}], "es": [{"zz": 1, "m": {"a": 1}}]}),
            json!({}),
        ),
        (
            "unusable".to_string(),
            "item 1 of xs: x is {\"k\": 3}, which isn't text".to_string()
        )
    );
}

#[test]
fn a_sentence_that_reads_the_alias_only_as_a_key_of_a_count_isnt_run_on_an_empty_list() {
    for (for_line, cause) in [("every xs as x", "null"), ("first of xs as x", "absent")] {
        assert_eq!(
            for_row(
                for_line,
                &["count of es whose zz is m named by x.k is 0", "z is 1"],
                json!({"xs": [], "es": [null, {"zz": null, "m": null}], "z": null}),
                json!({}),
            ),
            (cause.to_string(), "z is null; xs is []".to_string()),
            "{for_line}"
        );
    }
}

#[test]
fn a_for_line_says_every_root_and_caps_only_items() {
    assert_eq!(
        for_row(
            "every xs as x",
            &[
                "x.v is at least $params.a",
                "x.v is at most $params.b",
                "x.w is $params.c",
                "x.u is in $params.d",
            ],
            json!({"xs": [{"v": 1, "w": 1, "u": 1}]}),
            json!({}),
        ),
        (
            "absent".to_string(),
            "$params.a is missing; $params.b is missing; $params.c is missing; $params.d is missing"
                .to_string()
        )
    );
}

#[test]
fn a_count_under_the_line_names_the_outer_item_before_each_inner_item() {
    assert_eq!(
        for_row(
            "every gs as g",
            &["count of g.es whose v is at least $params.min is 0"],
            json!({"gs": [{"es": [{}, {}]}, {"es": [{}, {"v": 2}]}]}),
            json!({"min": "s"}),
        ),
        (
            "unusable".to_string(),
            "$params.min is \"s\", which isn't a number; item 1 of gs: item 1 of g.es: v is missing; item 1 of gs: item 2 of g.es: v is missing; item 2 of gs: item 1 of g.es: v is missing"
                .to_string()
        )
    );
    assert_eq!(
        for_row(
            "every gs as g",
            &["sum of g.rs.n is 3"],
            json!({"gs": [{"rs": [{"n": "a"}, {}]}, {"rs": [{"n": null}]}]}),
            json!({}),
        ),
        (
            "unusable".to_string(),
            "item 1 of gs: item 1 of g.rs: n is \"a\", which isn't a number; item 1 of gs: item 2 of g.rs: n is missing; item 2 of gs: item 1 of g.rs: n is null"
                .to_string()
        )
    );
}

#[test]
fn two_sentences_walking_one_list_say_its_items_in_list_order() {
    assert_eq!(
        for_row(
            "every xs as x",
            &["every x.ys.n is 1", "every x.ys.m is 1"],
            json!({"xs": [{"ys": [{"n": 1, "m": 2}, {"m": 1}]}]}),
            json!({}),
        )
        .1,
        "item 1 of xs: item 1 of x.ys: m is 2; item 1 of xs: item 2 of x.ys: n is missing"
    );
}

#[test]
fn a_value_that_holds_a_semicolon_stays_whole_on_a_second_list() {
    assert_eq!(
        for_row(
            "every ws as w, some ys whose n is at least w.z and whose n is at most u as y",
            &["y.n exists"],
            json!({"ws": [{"z": "p; q"}], "ys": [{"n": 1}, {"n": 2}]}),
            json!({}),
        )
        .1,
        "item 1 of ws: w.z is \"p; q\", which isn't a number; item 1 of ws: item 1 of ys: u is missing; item 1 of ws: item 2 of ys: u is missing"
    );
}

#[test]
fn a_key_from_params_is_said_once_before_the_items_of_a_count_under_the_line() {
    let gs: Vec<Value> = (0..5).map(|_| json!({"es": [{"v": {}}]})).collect();
    assert_eq!(
        for_row(
            "every gs as g",
            &["count of g.es.v that is m named by $params.k is 0"],
            json!({ "gs": gs }),
            json!({}),
        )
        .1,
        "$params.k is missing; item 1 of gs: item 1 of g.es: v: m is missing; item 2 of gs: item 1 of g.es: v: m is missing; item 3 of gs: item 1 of g.es: v: m is missing; and 2 more"
    );
}

#[test]
fn the_roots_of_two_sentences_keep_their_order() {
    assert_eq!(
        for_row(
            "every xs as x",
            &["x.v is $params.a", "x.v is $params.b"],
            json!({"xs": [{"v": 1}]}),
            json!({"a": null}),
        ),
        (
            "absent".to_string(),
            "$params.a is null; $params.b is missing".to_string()
        )
    );
    assert_eq!(
        for_row(
            "every xs as x",
            &["x.v is at least $params.b", "x.w is at least $params.a"],
            json!({"xs": [{"v": 1, "w": 1}]}),
            json!({"a": "s"}),
        )
        .1,
        "$params.b is missing; $params.a is \"s\", which isn't a number"
    );
}

fn tree(clauses: &[crate::ops::clause::Clause]) -> Vec<String> {
    clauses
        .iter()
        .map(|clause| {
            let said = tree(&clause.said);
            if said.is_empty() {
                format!("{}|{}", clause.name, clause.text)
            } else {
                format!("{}[{}]", clause.name, said.join(", "))
            }
        })
        .collect()
}

#[test]
fn a_sentence_of_the_first_list_rides_with_the_first_pair() {
    let items = for_items(
        "every prs as pr, every pr.as as ap",
        &["ap.state is 1", "ap.user is 1", "pr.ok is true"],
        json!({"prs": [{"ok": false, "as": [{"state": 2, "user": 1}, {"state": 1, "user": 3}]}]}),
        json!({}),
    );
    assert_eq!(
        tree(&items),
        [
            "item 1 of prs[item 1 of pr.as[ap.state is 2|ap.state is 2, pr.ok is false|pr.ok is false], item 2 of pr.as[ap.user is 3|ap.user is 3]]"
        ]
    );
}

#[test]
fn two_sentences_walking_one_list_merge_by_item() {
    let items = for_items(
        "every xs as x",
        &["every x.ys.n is 1", "every x.ys.m is 1"],
        json!({"xs": [{"ys": [{"n": 1, "m": 2}, {"m": 1}]}]}),
        json!({}),
    );
    assert_eq!(
        tree(&items),
        ["item 1 of xs[item 1 of x.ys[m is 2|m is 2], item 2 of x.ys[n is missing|n is missing]]"]
    );
}

fn causes(clauses: &[crate::ops::clause::Clause]) -> Vec<String> {
    clauses
        .iter()
        .flat_map(|clause| {
            std::iter::once(format!("{}: {}", clause.name, clause.cause.name()))
                .chain(causes(&clause.said))
        })
        .collect()
}

#[test]
fn an_item_beside_a_root_takes_only_its_own_cause() {
    let items = for_items(
        "every xs as x",
        &["count of x.es whose v is at least $params.a is $params.b"],
        json!({"xs": [{"es": [{"v": 1}, {}]}]}),
        json!({"a": "s", "b": 0}),
    );
    assert_eq!(
        causes(&items),
        [
            "item 1 of xs: absent",
            "item 2 of x.es: absent",
            "v is missing: absent"
        ]
    );
}

fn for_tree(for_line: &str, assertions: &[&str], subject: Value, params: Value) -> String {
    super::RAN.with(|ran| ran.borrow_mut().clear());
    for_items(for_line, assertions, subject, params);
    let (_, _, clauses) = super::RAN
        .with(|ran| ran.take())
        .pop()
        .expect("the line ran");
    crate::ops::clause::text(&crate::ops::clause::shown(&clauses))
}

#[test]
fn the_list_before_a_key_that_cant_be_read_comes_after_the_key() {
    assert_eq!(
        for_tree(
            "every o named by $params.k as x",
            &["x is 1"],
            json!({"o": "s"}),
            json!({}),
        ),
        "$params.k is missing; o is \"s\", which isn't a list or an object"
    );
}

#[test]
fn a_sentence_that_reads_no_alias_comes_before_a_key_that_cant_be_read() {
    let said = |o: Value| {
        for_tree(
            "every o named by $params.k as x",
            &["x is 1", "z is 3"],
            json!({"z": 2, "o": o}),
            json!({}),
        )
    };
    assert_eq!(said(json!({"a": [1]})), "z is 2; $params.k is missing");
    assert_eq!(
        said(json!("s")),
        "z is 2; $params.k is missing; o is \"s\", which isn't a list or an object"
    );
}

#[test]
fn an_item_takes_no_cause_from_a_root_a_later_line_reads_through_its_alias() {
    let items = for_items(
        "every items as i, every $params.l whose v is at least i.t as x",
        &["x.v is 1"],
        json!({"items": [{"t": "s"}]}),
        json!({"l": [{"w": 1}]}),
    );
    assert_eq!(causes(&items)[0], "item 1 of items: absent");
}

#[test]
fn an_item_whose_path_goes_through_a_key_that_cant_be_read_takes_the_keys_cause() {
    let items = for_items(
        "every rs as r",
        &["r.x.y named by $params.i does not exist"],
        json!({"rs": [{}]}),
        json!({"i": [1]}),
    );
    assert_eq!(
        causes(&items),
        ["item 1 of rs: unusable", "r.x.y is missing: unusable"]
    );
}

#[test]
fn a_sentence_that_reads_no_alias_is_a_clause_on_an_empty_list_the_line_tolerates() {
    assert_eq!(
        for_tree(
            "every xs, if any, as x",
            &["x.w is 1", "z is 3"],
            json!({"xs": [], "z": 2}),
            json!({}),
        ),
        "z is 2"
    );
}

#[test]
fn a_root_that_a_sentence_reading_no_alias_gives_is_said_once_on_an_empty_list() {
    assert_eq!(
        for_tree(
            "every ys, if any, as m",
            &["count of zb is count of za"],
            json!({"id": "p0", "zb": "s", "za": 3, "ys": []}),
            json!({}),
        ),
        "za is 3, which isn't a list or an object; zb is \"s\", which isn't a list or an object"
    );
}

#[test]
fn a_path_whose_key_cant_be_read_isnt_said_again_after_the_key() {
    let said = |assertion: &str, subject: Value, params: Value| {
        for_tree("every rs as r", &[assertion], subject, params)
    };
    let things = json!({"m": {"a": "a"}, "rs": [{"v": "a"}, {"v": 4}]});
    assert_eq!(
        said(
            "r.zz is m named by $params.k",
            things.clone(),
            json!({"k": null})
        ),
        "$params.k is null; item 1 of rs: r.zz is missing; item 2 of rs: r.zz is missing"
    );
    assert_eq!(
        said("k is m named by $params.k", things, json!({"k": null})),
        "k is missing; $params.k is null"
    );
    let rows = json!({"m": {"k": [1]}, "rs": [{"v": [1]}, {"v": "no"}]});
    assert_eq!(said("r.v is m named by p", rows, json!({})), "p is missing");
    assert_eq!(
        said(
            "r.v is zz.x named by p",
            json!({"zz": "str", "p": 3, "rs": [{"v": 1}]}),
            json!({})
        ),
        "p is 3, which isn't text, and zz is \"str\", which isn't an object"
    );
    assert_eq!(
        for_tree(
            "every ks as k",
            &["count of n named by k is at most 5"],
            json!({"ks": [null], "n": {"q": [1]}}),
            json!({}),
        ),
        "item 1 of ks: k is null"
    );
}

#[test]
fn a_key_that_sorts_the_line_is_said_once_before_the_items_own_problems() {
    let said = |rows: Value| {
        for_tree(
            "first of rows sorted by m named by $params.km as r",
            &["r.v is 1"],
            json!({ "rows": rows }),
            json!({}),
        )
    };
    assert_eq!(
        said(json!([{"m": {"q": 2}, "v": 2}, {"m": {"q": 1}, "v": 1}])),
        "$params.km is missing"
    );
    assert_eq!(
        said(json!([{"m": [5, 1]}, {"m": {"a": 1}}, {"v": 1}])),
        "$params.km is missing; item 1 of rows: m is [5, 1], which isn't an object; item 3 of rows: m is missing"
    );
    assert_eq!(
        for_tree(
            "first of rows sorted by m named by $params.kn as r",
            &["r.v is 1"],
            json!({"rows": [{"m": [5, 1], "v": 1}]}),
            json!({"kn": 1}),
        ),
        "$params.kn is 1, which isn't text; item 1 of rows: m is [5, 1], which isn't an object"
    );
}

#[test]
fn a_key_read_from_a_field_of_the_subject_on_the_first_list_is_a_root_clause() {
    let said = |p: Option<Value>| {
        let mut subject = json!({"rows": [{"w": {"k": "xy"}}]});
        if let Some(p) = p {
            subject["p"] = p;
        }
        for_tree(
            "every rows.w named by p as w",
            &["w is \"xy\""],
            subject,
            json!({}),
        )
    };
    assert_eq!(said(None), "p is missing");
    assert_eq!(said(Some(Value::Null)), "p is null");
    assert_eq!(said(Some(json!(3))), "p is 3, which isn't text");
}

#[test]
fn a_sentence_that_reads_no_alias_comes_before_the_key_of_the_lines_whose() {
    assert_eq!(
        for_tree(
            "every es whose zz is m named by $params.k as e",
            &["e.v exists", "z is 1"],
            json!({"z": 2}),
            json!({"k": 3}),
        ),
        "z is 2; $params.k is 3, which isn't text; es is missing"
    );
}

#[test]
fn a_clause_an_earlier_sentence_gave_for_the_item_is_left_out() {
    assert_eq!(
        for_tree(
            "every xs as x",
            &["x.e exists", "x.e is after x.a"],
            json!({"xs": [{}]}),
            json!({}),
        ),
        "item 1 of xs: x.e is missing, and x.a is missing"
    );
}

#[test]
fn a_sentence_that_reads_no_alias_keeps_its_message_whole() {
    assert_eq!(
        for_tree(
            "every xs as x",
            &["count of rows is at least m"],
            json!({"m": 3, "rows": [{"n": 1}], "xs": [{"v": 5}]}),
            json!({}),
        ),
        "count of rows is 1, and m is 3"
    );
}

#[test]
fn a_walk_over_the_second_list_under_the_first_item_gives_its_items_beside_the_pairs() {
    let said = |assertions: &[&str]| {
        for_tree(
            "every ws as w, every w.items as i",
            assertions,
            json!({"ws": [{"items": [{"k": 2, "m": 1}, {"k": 1}]}]}),
            json!({}),
        )
    };
    let want =
        "item 1 of ws: item 1 of w.items: i.k is 2; item 1 of ws: item 2 of w.items: m is missing";
    assert_eq!(said(&["every w.items.m is 1", "i.k is 1"]), want);
    assert_eq!(said(&["i.k is 1", "every w.items.m is 1"]), want);
}

#[test]
fn a_sentence_that_reads_only_the_first_alias_is_said_before_a_second_list_that_fails() {
    let said = |assertion: &str, items: Value| {
        for_tree(
            "every ws as w, every w.items as i",
            &[assertion, "i.k is 1"],
            json!({"ws": [{"items": items, "zs": [{}]}]}),
            json!({}),
        )
    };
    assert_eq!(
        said("w.n is 1", json!(null)),
        "item 1 of ws: w.n is missing; item 1 of ws: w.items is null"
    );
    assert_eq!(
        said("every w.zs.m is 1", json!({})),
        "item 1 of ws: item 1 of w.zs: m is missing; item 1 of ws: w.items is {}, which isn't a list"
    );
    assert_eq!(
        said("every w.zs.m is 1", json!([])),
        "item 1 of ws: item 1 of w.zs: m is missing; item 1 of ws: w.items is []"
    );
}

#[test]
fn a_root_read_through_the_first_alias_fails_the_item_when_nothing_is_checked_for_it() {
    assert_eq!(
        for_tree(
            "every ks as k, every xs, if any, as m",
            &["m.t named by k is 1"],
            json!({"ks": [{}], "xs": []}),
            json!({}),
        ),
        "item 1 of ks: k is {}, which isn't text"
    );
    assert_eq!(
        for_tree(
            "every ys as m, every xs whose w is in m.q and whose v is in $params.l, if any, as n",
            &["n.v is 1"],
            json!({"xs": [], "ys": [{"q": 1}, {}]}),
            json!({}),
        ),
        "$params.l is missing; item 1 of ys: m.q is 1, which isn't a list; item 2 of ys: m.q is missing"
    );
}

#[test]
fn a_root_that_lists_items_is_said_once_with_its_own_count_before_the_items_of_the_line() {
    let os = json!([{"name": "bob"}, {"v": 0}, {"v": 1}, {"v": 2}, {"v": 3}, {"v": 4}]);
    let root = "item 2 of $params.os: name is missing; item 3 of $params.os: name is missing; item 4 of $params.os: name is missing; and 2 more";
    let said = |rows: Value| {
        for_tree(
            "every rows whose n is count of $params.os.name as r",
            &["r.n is 1"],
            json!({ "rows": rows }),
            json!({ "os": os.clone() }),
        )
    };
    assert_eq!(said(json!([{"n": 1}])), root);
    assert_eq!(
        said(json!([{"n": 1}, {}, {}])),
        format!("{root}; item 2 of rows: n is missing; item 3 of rows: n is missing")
    );
}

#[test]
fn a_root_walked_by_a_sentence_that_walks_a_list_under_the_item_is_said_once_with_no_item() {
    assert_eq!(
        for_tree(
            "every ms as m",
            &["every m.ys.v is in $params.os.name"],
            json!({"ms": [{"ys": [{"v": "bob"}]}, {"ys": [{"v": "ann"}]}]}),
            json!({"os": [{"name": "bob"}, {"k": 1}]}),
        ),
        "item 2 of $params.os: name is missing"
    );
}

#[test]
fn an_item_whose_second_list_reads_a_missing_name_through_its_alias_fails_as_absent_on_an_empty_list()
 {
    let items = for_items(
        "some approvers as approver, every commits whose author does not equal approver.u as commit",
        &["commit.signed is true"],
        json!({
            "approvers": [{"username": "ada"}, {"username": "grace", "u": "grace", "state": "APPROVED"}],
            "commits": []
        }),
        json!({}),
    );
    assert_eq!(
        causes(&items),
        [
            "commits: value",
            "item 1 of approvers: absent",
            "approver.u is missing: absent"
        ]
    );
}

#[test]
fn a_root_list_walked_through_a_list_in_its_items_sorts_by_the_path_it_starts_at() {
    assert_eq!(
        for_roots(
            "every rows whose n is count of $params.os.tags.n and whose m is $params.ot as r",
            &["r.n is 1"],
            json!({"rows": [{"n": 1, "m": 1}]}),
            json!({"os": [{"tags": [{"n": 1}, {}]}]}),
        ),
        "item 1 of $params.os: item 2 of tags: n is missing; $params.ot is missing"
    );
}

#[test]
fn two_root_lists_whose_inner_lists_have_the_same_name_are_two_roots_named_by_their_paths() {
    let names: Vec<String> = for_root_clauses(
        "every rows whose n is count of $params.os.tags.n and whose m is count of $params.ps.tags.n as r",
        &["r.n is 1"],
        json!({"rows": [{"n": 1, "m": 1}]}),
        json!({"os": [{"tags": [{}]}], "ps": [{"tags": [{}]}]}),
    )
    .into_iter()
    .map(|clause| clause.name)
    .collect();
    assert_eq!(names, ["$params.os.tags.n", "$params.ps.tags.n"]);
}

#[test]
fn a_root_list_whose_name_holds_a_colon_is_named_whole() {
    assert_eq!(
        for_roots(
            "every rows whose n is count of $params.\"x: y\".n and whose m is $params.a as r",
            &["r.n is 1"],
            json!({"rows": [{"n": 1, "m": 1}]}),
            json!({"x: y": [{}]}),
        ),
        "item 1 of $params.\"x: y\": n is missing; $params.a is missing"
    );
}

#[test]
fn a_whose_item_says_only_its_own_read_beside_a_root() {
    let items = for_items(
        "every xs whose v is at least $params.min as x",
        &["x.w is 1"],
        json!({"xs": [{"v": 1}, {}]}),
        json!({"min": "s"}),
    );
    assert_eq!(
        crate::ops::clause::text(&items),
        "item 2 of xs: v is missing"
    );
}

#[test]
fn a_whose_item_says_each_own_read_beside_a_key_that_isnt_text() {
    let items = for_items(
        "every es whose zz is m named by $params.k as e",
        &["e.v exists"],
        json!({"es": [{"v": 1}, {"v": 2, "zz": 1, "m": {"a": 1}}, {"v": 3, "m": null}]}),
        json!({"k": 3}),
    );
    assert_eq!(
        crate::ops::clause::text(&items),
        "item 1 of es: zz is missing, and m is missing; item 3 of es: zz is missing, and m is null"
    );
}

fn entries(failures: &Value) -> Vec<String> {
    let mut out = Vec::new();
    for entry in failures.as_array().into_iter().flatten() {
        out.push(format!(
            "{} {} {}: {}",
            entry["kind"].as_str().unwrap_or_default(),
            entry["name"].as_str().unwrap_or_default(),
            entry["cause"].as_str().unwrap_or_default(),
            entry["message"].as_str().unwrap_or_default()
        ));
        out.extend(
            entries(&entry["failures"])
                .into_iter()
                .map(|e| format!("  {e}")),
        );
    }
    out
}

#[test]
fn a_whose_key_that_cant_be_read_is_an_input_of_the_row_and_no_list_entry() {
    for (params, outcome, key) in [
        (
            json!({"k": 3}),
            "unusable",
            "$params.k is 3, which isn't text",
        ),
        (json!({"k": null}), "null", "$params.k is null"),
        (json!({}), "absent", "$params.k is missing"),
    ] {
        let row = row_with(
            "every xs whose v is m named by $params.k as x",
            json!("x.v is 1"),
            json!({"xs": [{"v": 1}, {"v": 1, "m": null}, {"v": 1, "m": {}}]}),
            params,
        );
        assert_eq!(
            row["message"],
            format!("{key}; item 1 of xs: m is missing; item 2 of xs: m is null")
        );
        assert_eq!(
            entries(&row["failures"]),
            [
                "item item 1 of xs absent: m is missing",
                "item item 2 of xs null: m is null"
            ],
            "{key}"
        );
        let inputs: Vec<&Value> = row["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|input| input["name"] == "$params.k")
            .collect();
        assert_eq!(inputs.len(), 1, "{key}");
        assert_eq!(inputs[0]["outcome"], outcome, "{key}");
    }
}

#[test]
fn a_second_lines_whose_names_a_key_that_isnt_text_once_and_each_item_its_own_read() {
    for (for_line, subject) in [
        (
            "every ms as m, every m.es whose zz is m named by $params.k as e",
            json!({"ms": [{"es": [{"n": 2}, {"n": 2, "zz": 1}]}]}),
        ),
        (
            "every ms as m, every es whose zz is m named by $params.k as e",
            json!({"ms": [{"a": 1}], "es": [{"n": 2}, {"n": 2, "zz": 1}]}),
        ),
    ] {
        let list = if for_line.contains("m.es") {
            "m.es"
        } else {
            "es"
        };
        for (params, key) in [
            (json!({"k": 3}), "$params.k is 3, which isn't text"),
            (json!({"k": null}), "$params.k is null"),
        ] {
            assert_eq!(
                for_row_message(for_line, "e.n is 2", subject.clone(), params),
                format!("{key}; item 1 of ms: item 1 of {list}: zz is missing"),
                "{for_line}"
            );
        }
    }
}

#[test]
fn a_first_item_whose_second_items_fail_only_on_a_whose_key_has_no_entry() {
    let row = row_with(
        "every ms as m, every m.es whose zz is m named by $params.k as e",
        json!("e.n is 2"),
        json!({"ms": [{"es": [{"n": 2, "zz": 1}]}, {"es": [{"n": 2}]}]}),
        json!({"k": 3}),
    );
    assert_eq!(
        row["message"],
        "$params.k is 3, which isn't text; item 2 of ms: item 1 of m.es: zz is missing"
    );
    assert_eq!(
        entries(&row["failures"]),
        [
            "item item 2 of ms absent: ",
            "  item item 1 of m.es absent: zz is missing"
        ]
    );
}

#[test]
fn a_second_lines_whose_key_that_is_the_first_alias_is_said_under_its_first_item() {
    let m = r#"m is {"es": [{"n": 2, "zz": 1}], "q": 3}, which isn't text"#;
    for (for_line, rest) in [
        (
            "every ms as m, every m.es whose zz is q named by m.q as e",
            "q is missing",
        ),
        (
            "every ms as m, every m.es whose zz is q named by m as e",
            "q is missing",
        ),
    ] {
        let row = row(
            for_line,
            json!("e.n is 2"),
            json!({"ms": [{"q": 3, "es": [{"n": 2, "zz": 1}]}]}),
        );
        assert_eq!(row["cause"], "unusable", "{for_line}");
        assert_eq!(
            row["message"],
            format!("item 1 of ms: {m}; item 1 of ms: item 1 of m.es: {rest}"),
            "{for_line}"
        );
        assert_eq!(
            entries(&row["failures"]),
            [
                format!("assertion e.n is 2 unusable: item 1 of ms: {m}"),
                "item item 1 of ms absent: ".to_string(),
                format!("  item item 1 of m.es absent: {rest}"),
            ],
            "{for_line}"
        );
    }
}

#[test]
fn a_second_lines_whose_key_that_is_the_first_alias_fails_the_row_on_an_empty_list() {
    for (for_line, message) in [
        (
            "every ms as m, every es whose zz is q named by m as e",
            "es is []; item 1 of ms: m is 3, which isn't text",
        ),
        (
            "every ms as m, every es whose zz is q named by m, if any, as e",
            "item 1 of ms: m is 3, which isn't text",
        ),
    ] {
        let row = row(for_line, json!("e.n is 2"), json!({"ms": [3], "es": []}));
        assert_eq!(row["cause"], "unusable", "{for_line}");
        assert_eq!(row["message"], message, "{for_line}");
    }
}

#[test]
fn a_sentence_that_reads_only_the_first_alias_says_each_items_own_read_beside_a_root_on_two_lists()
{
    let items = "item 1 of xs: x.v is \"s\", which isn't a number; item 2 of xs: x.v is null; item 3 of xs: x.v is missing";
    for (for_line, assertion, root, params) in [
        (
            "every xs as x, every es as e",
            "x.v is at least z",
            "z is missing",
            json!({}),
        ),
        (
            "every xs as x, every x.ys, if any, as y",
            "x.v is at least z",
            "z is missing",
            json!({}),
        ),
        (
            "some xs as x, every es, if any, as e",
            "x.v is at least z",
            "z is missing",
            json!({}),
        ),
        (
            "every xs as x, every es as e",
            "x.v is at least $params.min",
            "$params.min is missing",
            json!({}),
        ),
        (
            "every xs as x, every es as e",
            "x.v is at least $params.min",
            "$params.min is null",
            json!({"min": null}),
        ),
    ] {
        assert_eq!(
            for_row(
                for_line,
                &[assertion],
                json!({"xs": [{"v": "s", "ys": [1]}, {"v": null, "ys": [1]}, {"ys": [1]}], "es": [{"n": 1}]}),
                params,
            ),
            ("unusable".to_string(), format!("{root}; {items}")),
            "{for_line} {assertion}"
        );
    }
}

#[test]
fn a_list_that_a_sentence_and_the_line_both_cant_walk_is_said_once() {
    assert_eq!(
        for_row(
            "every xs as x, every x.ys as y",
            &["every x.ys.n is 1"],
            json!({"xs": [{"ys": []}, {"ys": null}]}),
            json!({}),
        ),
        (
            "null".to_string(),
            "item 1 of xs: x.ys is []; item 2 of xs: x.ys is null".to_string()
        )
    );
    assert_eq!(
        for_row(
            "every xs as x, every es as e",
            &["every es.zz is 1"],
            json!({"xs": [{"v": 1}], "es": null}),
            json!({}),
        ),
        ("null".to_string(), "es is null".to_string())
    );
}

#[test]
fn a_list_the_line_picks_nothing_from_is_said_after_a_sentence_that_reads_no_alias() {
    let kept = json!({"xs": [{"v": 3}], "z": 3});
    for (for_line, subject, cause, list) in [
        (
            "every xs whose v is 1 as x",
            &kept,
            "value",
            "xs is [{\"v\": 3}]",
        ),
        (
            "some xs whose v is 1 as x",
            &kept,
            "value",
            "xs is [{\"v\": 3}]",
        ),
        (
            "first of xs whose v is 1 as x",
            &kept,
            "absent",
            "xs is [{\"v\": 3}]",
        ),
        (
            "first of xs sorted by v as x",
            &json!({"xs": [], "z": 3}),
            "absent",
            "xs is []",
        ),
    ] {
        assert_eq!(
            for_row(
                for_line,
                &["x.v is 1", "z is 1"],
                subject.clone(),
                json!({})
            ),
            (cause.to_string(), format!("z is 3; {list}")),
            "{for_line}"
        );
    }
}

#[test]
fn a_sentence_that_reads_params_that_arent_an_object_says_only_the_params_beside_a_tie() {
    assert_eq!(
        for_row(
            "first of xs sorted by v as x",
            &[
                "x.v is at least $params.min",
                "count of es whose zz is m named by $params.k is 0",
            ],
            json!({"xs": [{"v": 1}, {"v": 1}], "es": [null, {"zz": 2, "m": 3}]}),
            json!(3),
        ),
        (
            "ambiguous".to_string(),
            "$params is 3, which isn't an object; item 1 and item 2 of xs tie on v".to_string()
        )
    );
}

#[test]
fn an_item_that_isnt_an_object_is_named_without_a_colon_beside_a_second_list_that_fails() {
    for for_line in [
        "some xs as x, every es, if any, as e",
        "every xs as x, every es, if any, as e",
        "every xs as x, every es as e",
        "some xs as x, every es whose zz is x.v, if any, as e",
    ] {
        assert_eq!(
            for_row(
                for_line,
                &["x.v exists"],
                json!({"xs": [{}, [1]], "es": null}),
                json!({}),
            ),
            (
                "not_an_object".to_string(),
                "es is null; item 1 of xs: x.v is missing; item 2 of xs is [1], which isn't an object"
                    .to_string()
            ),
            "{for_line}"
        );
    }
}

#[test]
fn an_item_that_isnt_an_object_isnt_named_for_a_later_lines_whose_that_reads_it_through_a_field() {
    assert_eq!(
        for_row(
            "some xs as x, every es whose zz is x.v, if any, as e",
            &["e.n exists"],
            json!({"xs": [{"v": null}, [1]], "es": null}),
            json!({}),
        ),
        (
            "null".to_string(),
            "es is null; item 1 of xs: x.v is null".to_string()
        )
    );
}

#[test]
fn a_pairs_part_says_its_sentences_in_the_order_they_are_written() {
    for (assertions, es, said) in [
        (
            &["x.v is 1", "e.n is 1"][..],
            json!([{"n": 1}, {"n": 2}]),
            "item 1 of xs: item 2 of es: x.v is 2, and e.n is 2",
        ),
        (
            &["e.n is 1", "x.v is 1"][..],
            json!([{"n": 1}, {"n": 2}]),
            "item 1 of xs: item 2 of es: e.n is 2, and x.v is 2",
        ),
        (
            &["x.v is 1", "e.n is 1"][..],
            json!([{"n": 3}, {"n": 2}]),
            "item 1 of xs: item 1 of es: x.v is 2, and e.n is 3; item 1 of xs: item 2 of es: e.n is 2",
        ),
        (
            &["e.m is 1", "x.v is 1", "e.n is 1"][..],
            json!([{"n": 3, "m": 2}]),
            "item 1 of xs: item 1 of es: e.m is 2, and x.v is 2, and e.n is 3",
        ),
    ] {
        assert_eq!(
            for_row(
                "every xs as x, every es as e",
                assertions,
                json!({"xs": [{"v": 2}], "es": es}),
                json!({}),
            ),
            ("value".to_string(), said.to_string()),
            "{assertions:?}"
        );
    }
}

#[test]
fn a_pairs_part_that_holds_a_sentence_that_doesnt_read_the_second_item_gives_no_list_entry() {
    let row = row(
        "every xs as x, every es as e",
        json!(["x.v is 1", "e.n is 1"]),
        json!({"xs": [{"v": 2}], "es": [{"n": 1}, {"n": 2}]}),
    );
    assert_eq!(
        row["message"],
        "item 1 of xs: item 2 of es: x.v is 2, and e.n is 2"
    );
    let said = entries(&row["failures"]);
    assert!(
        !said.iter().any(|entry| entry.starts_with("list ")),
        "{said:#?}"
    );
}

#[test]
fn a_list_a_sentence_walks_joins_the_items_own_part_where_the_lines_second_list_has_its_own() {
    assert_eq!(
        for_row(
            "every ws as w",
            &["every es whose v is in w.z, if any, exists"],
            json!({"es": null, "ws": [{}]}),
            json!({}),
        ),
        (
            "absent".to_string(),
            "item 1 of ws: w.z is missing, and es is null".to_string()
        )
    );
    assert_eq!(
        for_row(
            "every ws as w, every w.items as i",
            &["w.n is 1", "i.k is 1"],
            json!({"ws": [{"items": null}]}),
            json!({}),
        ),
        (
            "absent".to_string(),
            "item 1 of ws: w.n is missing; item 1 of ws: w.items is null".to_string()
        )
    );
}

#[test]
fn a_count_whose_walked_part_cant_be_read_is_null_in_the_rows_inputs_on_an_empty_list() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {
            "c": {"from": "cs", "identified_by": "id", "has": {"pos": "os"}},
            "k": {"from": "every c.kids", "identified_by": "id"}
        },
        "requirements": {"r": {"subject": "k", "checks": {"count": {
            "for": "every rows, if any, as r",
            "assert": "count of rows whose v is in c.os.name is 0"
        }}}}
    });
    let input = json!({"cs": [{"id": "c1", "os": [{"name": "bob"}, {}], "kids": [{"id": "k1", "rows": []}]}]});
    let report = crate::report(&input, &policy, &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "count")
        .unwrap();
    assert_eq!(row["cause"], "absent");
    let count = row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|input| input["name"] == "count of rows whose v is in c.os.name")
        .unwrap();
    assert_eq!(count["value"], Value::Null, "{count}");
}

#[test]
fn a_params_key_of_the_second_list_that_cant_be_read_is_said_once_after_the_sentence_that_doesnt_read_it()
 {
    assert_eq!(
        for_row(
            "every ws as w, every w.o named by $params.k as x",
            &["x is 1", "w.n is 1"],
            json!({"ws": [{"o": {"a": [1]}, "n": 2}, {"o": {"a": [1]}, "n": 1}]}),
            json!({"k": 3}),
        ),
        (
            "unusable".to_string(),
            "item 1 of ws: w.n is 2; $params.k is 3, which isn't text".to_string()
        )
    );
}

#[test]
fn a_params_key_of_the_second_list_that_cant_be_read_is_said_once_before_each_items_list_that_fails_whatever_the_key()
 {
    assert_eq!(
        for_row(
            "every ws as w, every w.o named by $params.k as x",
            &["x is 1"],
            json!({"ws": [{"o": {"a": [1]}}, {"o": "s"}, {}]}),
            json!({}),
        ),
        (
            "unusable".to_string(),
            "$params.k is missing; item 2 of ws: w.o is \"s\", which isn't a list or an object; item 3 of ws: w.o is missing"
                .to_string()
        )
    );
}

#[test]
fn a_list_the_line_cant_walk_isnt_counted_as_an_item() {
    let zz = |n: usize| {
        (1..=n)
            .map(|at| json!({"zz": at + 1}))
            .collect::<Vec<Value>>()
    };
    for (for_line, assertion, subject, said) in [
        (
            "every xs as x, every es as e",
            "x.v is 1",
            json!({"xs": [{"v": 2}, {"v": 3}, {"v": 4}], "es": null}),
            (
                "null",
                "es is null; item 1 of xs: x.v is 2; item 2 of xs: x.v is 3; item 3 of xs: x.v is 4",
            ),
        ),
        (
            "every ks, if any, as k",
            "every es.zz is 1",
            json!({"ks": null, "es": zz(3)}),
            (
                "null",
                "item 1 of es: zz is 2; item 2 of es: zz is 3; item 3 of es: zz is 4; ks is null",
            ),
        ),
        (
            "every ks, if any, as k",
            "every es.zz is 1",
            json!({"ks": null, "es": zz(4)}),
            (
                "null",
                "item 1 of es: zz is 2; item 2 of es: zz is 3; item 3 of es: zz is 4; ks is null; and 1 more",
            ),
        ),
        (
            "every ks as k",
            "every es.zz is 1",
            json!({"ks": [], "es": zz(3)}),
            (
                "value",
                "item 1 of es: zz is 2; item 2 of es: zz is 3; item 3 of es: zz is 4; ks is []",
            ),
        ),
    ] {
        assert_eq!(
            for_row(for_line, &[assertion], subject, json!({})),
            (said.0.to_string(), said.1.to_string()),
            "{for_line} {assertion}"
        );
    }
}

#[test]
fn sentences_that_read_no_alias_are_said_first_in_the_order_they_are_written_with_their_roots() {
    let subject =
        |ks: Value| json!({"ks": ks, "xs": [{"v": 2, "w": 3}], "es": [{"zz": 2}], "z": 2});
    for (for_line, assertions, ks, said) in [
        (
            "every ks as k",
            &["every es.zz is 1", "z is 1"][..],
            json!(["a"]),
            ("value", "item 1 of es: zz is 2; z is 2"),
        ),
        (
            "every ks as k",
            &["every es.zz is 1", "z is 1"][..],
            json!([]),
            ("value", "item 1 of es: zz is 2; z is 2; ks is []"),
        ),
        (
            "every ks, if any, as k",
            &["every es.zz is 1", "z is 1"][..],
            json!([]),
            ("value", "item 1 of es: zz is 2; z is 2"),
        ),
        (
            "every ks as k",
            &["some es.zz is 5", "z is 1"][..],
            json!(["a"]),
            ("value", "item 1 of es: zz is 2; z is 2"),
        ),
        (
            "every ks as k",
            &["every es.zz is 1", "z is 1", "k is 1"][..],
            json!(["a"]),
            (
                "unusable",
                "item 1 of es: zz is 2; z is 2; item 1 of ks: k is \"a\", which isn't a number",
            ),
        ),
        (
            "every ks as k",
            &["every es.zz is 1", "z is 1", "z is at least $params.min"][..],
            json!(["a"]),
            (
                "unusable",
                "item 1 of es: zz is 2; z is 2; $params.min is \"s\", which isn't a number",
            ),
        ),
        (
            "every xs as x",
            &["x.v is 1", "x.w is at least $params.min"][..],
            json!(["a"]),
            (
                "unusable",
                "$params.min is \"s\", which isn't a number; item 1 of xs: x.v is 2",
            ),
        ),
        (
            "every xs as x",
            &[
                "x.v is 1",
                "every es.zz is 1",
                "x.w is at least $params.min",
                "z is 1",
            ][..],
            json!(["a"]),
            (
                "unusable",
                "item 1 of es: zz is 2; z is 2; $params.min is \"s\", which isn't a number; item 1 of xs: x.v is 2",
            ),
        ),
    ] {
        assert_eq!(
            for_row(for_line, assertions, subject(ks), json!({"min": "s"})),
            (said.0.to_string(), said.1.to_string()),
            "{for_line} {assertions:?}"
        );
    }
}

#[test]
fn a_root_of_a_sentence_that_reads_the_first_alias_stays_before_the_second_list_when_the_first_is_empty()
 {
    assert_eq!(
        for_row(
            "every xs, if any, as x, every es as e",
            &["x.v is at least $params.min", "z is 1", "e.n is 1"],
            json!({"xs": [], "es": [{"n": 2}], "z": 2}),
            json!({"min": "s"}),
        ),
        (
            "unusable".to_string(),
            "z is 2; $params.min is \"s\", which isn't a number; item 1 of es: e.n is 2"
                .to_string()
        )
    );
}

#[test]
fn root_clauses_say_a_key_that_isnt_text_once_and_not_again_with_the_path_it_reads() {
    assert_eq!(
        for_roots(
            "every xs as x",
            &["m named by $params.k is 1"],
            json!({"xs": [{"m": {"a": 1}}], "m": null}),
            json!({"k": 3}),
        ),
        "$params.k is 3, which isn't text"
    );
}

#[test]
fn a_key_that_isnt_text_is_said_once_and_each_item_says_only_its_own_problem() {
    let xs = json!([{"m": {"a": 1}, "ys": [{}]}, {"m": null, "ys": [{}]}, {"ys": [{}]}]);
    let said =
        "$params.k is 3, which isn't text; item 2 of xs: x.m is null; item 3 of xs: x.m is missing";
    for (for_line, assertion, subject, message) in [
        (
            "every xs as x, every es as e",
            "x.m named by $params.k is 1",
            json!({"xs": xs, "es": [{"zz": 1}]}),
            said,
        ),
        (
            "some xs as x, every es as e",
            "x.m named by $params.k is 1",
            json!({"xs": xs, "es": [{"zz": 1}]}),
            said,
        ),
        (
            "every xs as x, every x.ys as y",
            "x.m named by $params.k is 1",
            json!({"xs": xs}),
            said,
        ),
        (
            "every xs as x, every es as e",
            "x.m named by z is 1",
            json!({"xs": [{"m": {"a": 1}}, {"m": null}], "es": [{"zz": 1}], "z": 1}),
            "z is 1, which isn't text; item 2 of xs: x.m is null",
        ),
        (
            "every xs as x",
            "m named by $params.k is 1",
            json!({"xs": [{"m": {"a": 1}}], "m": null}),
            "$params.k is 3, which isn't text; m is null",
        ),
    ] {
        assert_eq!(
            for_row(for_line, &[assertion], subject, json!({"k": 3})),
            ("unusable".to_string(), message.to_string()),
            "{for_line} {assertion}"
        );
    }
}

#[test]
fn a_root_of_a_sentence_that_reads_the_alias_comes_before_the_list_the_line_cant_walk() {
    assert_eq!(
        for_row(
            "every o named by $params.k as x",
            &["every x.ys.n is 1", "x.v is at least z"],
            json!({"z": "s"}),
            json!({}),
        ),
        (
            "unusable".to_string(),
            "$params.k is missing; z is \"s\", which isn't a number; o is missing".to_string()
        )
    );
}

#[test]
fn an_item_that_isnt_an_object_isnt_said_again_as_a_walk_of_its_alias_by_the_second_list() {
    let xs = json!([[1], {"m": {"a": 1}, "ys": [{}]}]);
    for (for_line, assertion, message) in [
        (
            "every xs as x, every x.ys as y",
            "x.m named by z is 1",
            "item 1 of xs is [1], which isn't an object",
        ),
        (
            "every xs as x, every x.ys as y",
            "x.v exists",
            "item 1 of xs is [1], which isn't an object; item 2 of xs: x.v is missing",
        ),
        (
            "every xs as x, every x.m named by $params.k as y",
            "x.v is at least $params.min",
            "item 1 of xs is [1], which isn't an object; item 2 of xs: x.v is missing; item 2 of xs: x.m.a is 1, which isn't a list or an object",
        ),
    ] {
        assert_eq!(
            for_row(
                for_line,
                &[assertion],
                json!({"xs": xs, "z": "a"}),
                json!({"k": "a", "min": 0}),
            ),
            ("not_an_object".to_string(), message.to_string()),
            "{for_line} {assertion}"
        );
    }
}

#[test]
fn sentences_that_read_no_alias_and_walk_one_list_each_keep_their_own_parts() {
    let es = json!([{"m": null}, {"zz": "s", "m": null}]);
    for (assertions, cause, message) in [
        (
            [
                "count of es whose zz is at least $params.min is 1",
                "count of es whose zz is m named by $params.k is 0",
            ],
            "unusable",
            "$params.min is missing; item 1 of es: zz is missing; item 2 of es: zz is \"s\", which isn't a number; $params.k is missing; item 1 of es: zz is missing, and m is null; and 1 more",
        ),
        (
            ["every es.zz is 1", "every es.m is 1"],
            "unusable",
            "item 1 of es: zz is missing; item 2 of es: zz is \"s\", which isn't a number; item 1 of es: m is null; and 1 more",
        ),
    ] {
        assert_eq!(
            for_row(
                "every ks as k",
                &assertions,
                json!({"ks": ["a"], "es": es}),
                json!({}),
            ),
            (cause.to_string(), message.to_string()),
            "{assertions:?}"
        );
    }
}

#[test]
fn a_root_that_a_sentence_reading_no_alias_reads_is_said_with_that_sentence() {
    for (for_line, assertions, subject, params, message) in [
        (
            "every xs as x",
            vec!["x.v is at least zb", "zb is at least 1", "w is 1"],
            json!({"zb": "s", "xs": [{"v": 1}]}),
            json!({}),
            "zb is \"s\", which isn't a number; w is missing",
        ),
        (
            "every o named by $params.k as x",
            vec!["$params.k is \"a\"", "w is 1", "x is 1"],
            json!({"o": {"a": [1]}}),
            json!({"k": 3}),
            "$params.k is 3, which isn't text; w is missing",
        ),
        (
            "every xs whose v is in $params.l as x",
            vec![
                "x.v is at least $params.min",
                "count of es whose zz is at least $params.min is 1",
            ],
            json!({"xs": [{"v": 1}], "es": []}),
            json!({"min": "s", "l": null}),
            "$params.min is \"s\", which isn't a number; $params.l is null",
        ),
    ] {
        assert_eq!(
            for_row(for_line, &assertions, subject, params),
            ("unusable".to_string(), message.to_string()),
            "{for_line} {assertions:?}"
        );
    }
}

#[test]
fn a_problem_a_sentence_that_reads_no_alias_gave_isnt_said_again_under_an_item() {
    for assertions in [
        ["count of es is 1", "every es.m named by k is 1"],
        ["every es.m named by k is 1", "count of es is 1"],
    ] {
        assert_eq!(
            for_row(
                "every ks as k",
                &assertions,
                json!({"ks": ["v"], "es": null}),
                json!({}),
            ),
            ("null".to_string(), "es is null".to_string()),
            "{assertions:?}"
        );
    }
}

#[test]
fn an_item_that_isnt_an_object_is_said_when_the_sort_key_cant_be_read() {
    for (params, key) in [
        (json!({}), "$params.k is missing"),
        (json!({"k": 3}), "$params.k is 3, which isn't text"),
    ] {
        for assertion in ["x.v exists", "count of es whose zz is m named by x.k is 0"] {
            assert_eq!(
                for_row(
                    "first of xs sorted by m named by $params.k as x",
                    &[assertion],
                    json!({"xs": [{"v": 1}, "str"], "es": [{"zz": 1}]}),
                    params.clone(),
                ),
                (
                    "not_an_object".to_string(),
                    format!(
                        "{key}; item 1 of xs: m is missing; item 2 of xs is \"str\", which isn't an object"
                    )
                ),
                "{params} {assertion}"
            );
        }
    }
}

#[test]
fn an_items_own_problem_is_said_beside_a_second_list_whose_items_arent_objects_when_a_key_isnt_text()
 {
    let xs = json!([{"v": "s", "k": "a"}, {"v": 1, "m": [5]}]);
    let by_z = "z is 3, which isn't text; item 1 of xs: x.m named by z is missing; item 1 of xs: item 1 of es is 3, which isn't an object; item 2 of xs: item 1 of es is 3, which isn't an object";
    for (for_line, assertion, params, message) in [
        (
            "every xs as x, every es as e",
            "x.m named by z is 1",
            json!({}),
            by_z,
        ),
        (
            "some xs as x, every es, if any, as e",
            "x.m named by z is 1",
            json!({}),
            by_z,
        ),
        (
            "every xs as x, every es as e",
            "x.m named by $params.k is 1",
            json!({"k": 3}),
            "$params.k is 3, which isn't text; item 1 of xs: x.m is missing; item 1 of xs: item 1 of es is 3, which isn't an object; item 2 of xs: x.m is [5], which isn't an object; item 2 of xs: item 1 of es is 3, which isn't an object",
        ),
    ] {
        assert_eq!(
            for_row(
                for_line,
                &[assertion, "e.zz is x.v"],
                json!({"xs": xs, "es": [3], "z": 3}),
                params,
            ),
            ("not_an_object".to_string(), message.to_string()),
            "{for_line} {assertion}"
        );
    }
}

#[test]
fn a_problem_two_sentences_that_read_no_alias_give_is_said_with_the_first() {
    for (assertions, message) in [
        (
            [
                "every es.zz is 1",
                "count of es whose zz is m named by $params.k is 0",
            ],
            "es is null; $params.k is 3, which isn't text",
        ),
        (
            [
                "count of es whose zz is m named by $params.k is 0",
                "every es.zz is 1",
            ],
            "$params.k is 3, which isn't text; es is null",
        ),
    ] {
        assert_eq!(
            for_row(
                "every ks as k",
                &assertions,
                json!({"ks": ["a"], "es": null}),
                json!({"k": 3}),
            ),
            ("unusable".to_string(), message.to_string()),
            "{assertions:?}"
        );
    }
}

#[test]
fn an_item_a_second_lines_whose_cant_decide_is_said_beside_what_else_fails() {
    for (assertion, message) in [
        (
            "x.v is at least zb",
            "zb is [1], which isn't a number; item 1 of xs is [1], which isn't an object; item 2 of xs: item 1 of x.ys: n is \"s\", which isn't a number",
        ),
        (
            "y.n is 1",
            "item 1 of xs is [1], which isn't an object; item 2 of xs: item 1 of x.ys: n is \"s\", which isn't a number; item 2 of xs: item 2 of x.ys: y.n is 3",
        ),
    ] {
        assert_eq!(
            for_row(
                "every xs as x, every x.ys whose n is at least x.v as y",
                &[assertion],
                json!({"xs": [[1], {"v": 1, "ys": [{"n": "s"}, {"n": 3}]}], "zb": [1]}),
                json!({}),
            ),
            ("not_an_object".to_string(), message.to_string()),
            "{assertion}"
        );
    }
}

#[test]
fn a_sort_key_from_params_that_arent_an_object_says_only_the_params_once() {
    for (assertion, message) in [
        ("x.v exists", "$params is 3, which isn't an object"),
        (
            "w exists",
            "w is missing; $params is 3, which isn't an object",
        ),
    ] {
        assert_eq!(
            for_row(
                "first of xs sorted by m named by $params.k as x",
                &[assertion],
                json!({"xs": [{"v": 1, "m": null}, {"v": 2, "m": null}]}),
                json!(3),
            ),
            ("unusable".to_string(), message.to_string()),
            "{assertion}"
        );
    }
}

#[test]
fn a_root_is_said_with_the_sentence_that_cant_read_it_and_not_with_a_sentence_that_reads_no_alias_and_reads_it_fine()
 {
    for (for_line, assertions, subject, params, message) in [
        (
            "every o named by $params.k as x",
            vec!["x.m named by z is 1", "z is in $params.l"],
            json!({"z": 1, "o": {"a": [{"m": {"a": 1}}]}}),
            json!({}),
            "$params.l is missing; $params.k is missing; z is 1, which isn't text",
        ),
        (
            "every o named by $params.k as x",
            vec!["z is in $params.l", "x.m named by z is 1"],
            json!({"z": 1, "o": {"a": [{"m": {"a": 1}}]}}),
            json!({}),
            "$params.l is missing; $params.k is missing; z is 1, which isn't text",
        ),
        (
            "every ks as k",
            vec!["z is in $params.l", "w is 1", "z is at least 1"],
            json!({"ks": ["a"], "z": "s"}),
            json!({}),
            "$params.l is missing; w is missing; z is \"s\", which isn't a number",
        ),
        (
            "every xs as x",
            vec!["z is in $params.l", "w is 1", "x.m named by z is 1"],
            json!({"z": 1, "xs": [{"m": {"a": 1}}]}),
            json!({"l": [1, 2]}),
            "w is missing; z is 1, which isn't text",
        ),
        (
            "every xs as x",
            vec!["w is 1", "z is in $params.l", "x.m named by z is 1"],
            json!({"z": 1, "xs": [{"m": {"a": 1}}]}),
            json!({"l": [1, 2]}),
            "w is missing; z is 1, which isn't text",
        ),
        (
            "every xs as x",
            vec!["z is 1", "w is 1", "x.m named by z is 1"],
            json!({"z": 1, "xs": [{"m": {"a": 1}}]}),
            json!({}),
            "w is missing; z is 1, which isn't text",
        ),
        (
            "every xs as x",
            vec!["z exists", "w is 1", "x.m named by z is 1"],
            json!({"z": 1, "xs": [{"m": {"a": 1}}]}),
            json!({}),
            "w is missing; z is 1, which isn't text",
        ),
        (
            "every xs as x",
            vec![
                "count of es whose zz is z is 0",
                "w is 1",
                "x.m named by z is 1",
            ],
            json!({"z": 1, "xs": [{"m": {"a": 1}}], "es": []}),
            json!({}),
            "w is missing; z is 1, which isn't text",
        ),
    ] {
        assert_eq!(
            for_row(for_line, &assertions, subject, params),
            ("unusable".to_string(), message.to_string()),
            "{for_line} {assertions:?}"
        );
    }
}

#[test]
fn a_walked_list_is_a_root_named_by_its_path_so_its_own_sentence_says_it_first() {
    assert_eq!(
        for_row(
            "every xs as x",
            &[
                "x.v is 1",
                "every es.m named by $params.k is 1",
                "count of es whose zz is at least z is 0"
            ],
            json!({"xs": [{"v": 1}], "es": "s", "z": 3}),
            json!({"k": 3}),
        ),
        (
            "unusable".to_string(),
            "$params.k is 3, which isn't text; es is \"s\", which isn't an object; es is \"s\", which isn't a list or an object".to_string()
        )
    );
}

#[test]
fn a_value_a_sentence_that_reads_no_alias_already_said_isnt_said_again_under_each_item() {
    for (assertions, said) in [
        (["z is 1", "x.v is at least z"], "z is 5"),
        (["x.v is at least z", "z is 1"], "z is 5"),
        (
            ["$params.q is 1", "x.v is at least $params.q"],
            "$params.q is 5",
        ),
        (
            ["count of es is 1", "x.v is at least count of es"],
            "count of es is 4",
        ),
        (
            ["sum of es is 1", "x.v is at least sum of es"],
            "sum of es is 10",
        ),
    ] {
        assert_eq!(
            for_tree(
                "every xs as x",
                &assertions,
                json!({"xs": [{"v": 1}, {"v": 3}], "es": [1, 2, 3, 4], "z": 5}),
                json!({"q": 5}),
            ),
            format!("{said}; item 1 of xs: x.v is 1; item 2 of xs: x.v is 3"),
            "{assertions:?}"
        );
    }
}

#[test]
fn a_list_a_sentence_that_reads_no_alias_already_said_isnt_said_again_under_each_item() {
    for assertions in [
        ["every es.zz is 1", "sum of es.m named by k is 1"],
        ["every es.zz is 1", "count of es.m named by k is 1"],
        ["sum of es.m named by k is 1", "every es.zz is 1"],
    ] {
        assert_eq!(
            for_tree(
                "every ks as k",
                &assertions,
                json!({"es": null, "ks": ["a", "v"]}),
                json!({}),
            ),
            "es is null",
            "{assertions:?}"
        );
    }
}

#[test]
fn an_item_merged_with_one_of_the_same_name_keeps_each_text_once() {
    use crate::cause::Cause;
    use crate::ops::clause::Clause;
    let null =
        |text: &str| Clause::item("item 2 of x.ys", Cause::Null, text.to_string(), Vec::new());
    let mut said = vec![null("item 2 of x.ys is null")];
    for text in [
        "item 2 of x.ys is null, which isn't an object",
        "item 2 of x.ys is null",
        "item 2 of x.ys is null, which isn't an object",
    ] {
        super::merge_clause(&mut said, &null(text));
    }
    assert_eq!(
        crate::ops::clause::lines(&said),
        [
            "item 2 of x.ys is null",
            "item 2 of x.ys is null, which isn't an object"
        ]
    );
}

#[test]
fn two_sentences_that_say_different_problems_of_one_item_of_a_list_under_the_item_say_both() {
    assert_eq!(
        for_tree(
            "every xs as x",
            &["every x.ys exists", "sum of x.ys.n is 3"],
            json!({"xs": [{"v": 2, "ys": [{"n": 1}, null]}]}),
            json!({}),
        ),
        "item 1 of xs: item 2 of x.ys is null, and item 2 of x.ys is null, which isn't an object"
    );
    assert_eq!(
        for_tree(
            "every xs as x",
            &["sum of x.ys.n is 3", "every x.ys exists"],
            json!({"xs": [{"v": 2, "ys": [{"n": 1}, null]}]}),
            json!({}),
        ),
        "item 1 of xs: item 2 of x.ys is null, which isn't an object, and item 2 of x.ys is null"
    );
}

#[test]
fn sentences_that_say_two_problems_of_one_item_of_a_list_under_the_item_say_each_once() {
    for (assertions, said) in [
        (
            vec![
                "every x.ys exists",
                "sum of x.ys.n is 3",
                "every x.ys.n is 1",
            ],
            "item 1 of xs: item 2 of x.ys is null, and item 2 of x.ys is null, which isn't an object",
        ),
        (
            vec![
                "sum of x.ys.n is 3",
                "every x.ys exists",
                "sum of x.ys.n is 4",
            ],
            "item 1 of xs: item 2 of x.ys is null, which isn't an object, and item 2 of x.ys is null",
        ),
        (
            vec!["every x.ys exists", "every x.ys.n is 1"],
            "item 1 of xs: item 2 of x.ys is null, and item 2 of x.ys is null, which isn't an object",
        ),
        (
            vec!["every x.ys exists", "sum of x.ys.n is 3", "x.v is 1"],
            "item 1 of xs: item 2 of x.ys is null, and item 2 of x.ys is null, which isn't an object; item 1 of xs: x.v is 2",
        ),
    ] {
        assert_eq!(
            for_tree(
                "every xs as x",
                &assertions,
                json!({"xs": [{"v": 2, "ys": [{"n": 1}, null]}]}),
                json!({}),
            ),
            said,
            "{assertions:?}"
        );
    }
}

#[test]
fn an_alias_read_whole_keeps_its_problem_beside_an_item_a_later_lines_whose_cant_read() {
    for for_line in [
        "every xs as x, every es whose zz is x.v as e",
        "every xs as x, some es whose zz is x.v as e",
        "every xs as x, first of es whose zz is x.v as e",
        "some xs as x, every es whose zz is x.v as e",
        "first of xs as x, every es whose zz is x.v as e",
    ] {
        for (assertions, said) in [
            (&["m named by x is 1"][..], "x is 3, which isn't text"),
            (&["x.m named by x.k is 1"][..], "x is 3, which isn't text"),
            (
                &["m named by x is 1", "count of x.ys is 1"][..],
                "x is 3, which isn't text",
            ),
            (
                &["count of x.ys is 1", "m named by x is 1"][..],
                "x is 3, which isn't text",
            ),
        ] {
            assert_eq!(
                for_row(
                    for_line,
                    assertions,
                    json!({"xs": [3], "es": [{"zz": 1}], "m": {"a": 1}}),
                    json!({}),
                ),
                (
                    "not_an_object".to_string(),
                    format!("item 1 of xs: {said}; item 1 of xs is 3, which isn't an object")
                ),
                "{for_line} {assertions:?}"
            );
        }
    }
}

#[test]
fn an_alias_read_whole_that_can_be_read_isnt_said_beside_an_item_a_later_lines_whose_cant_read() {
    for assertions in [
        &["x is 1"][..],
        &["x is m"][..],
        &["m named by x is 1", "x is 1"][..],
    ] {
        let said = if assertions.len() == 2 {
            "item 1 of xs: x is 3, which isn't text; item 1 of xs is 3, which isn't an object"
        } else {
            "item 1 of xs is 3, which isn't an object"
        };
        assert_eq!(
            for_row(
                "every xs as x, every es whose zz is x.v as e",
                assertions,
                json!({"xs": [3], "es": [{"zz": 1}], "m": {"a": 1}}),
                json!({}),
            ),
            ("not_an_object".to_string(), said.to_string()),
            "{assertions:?}"
        );
    }
}

#[test]
fn an_alias_read_whole_keeps_its_problem_beside_an_item_a_later_lines_path_cant_walk() {
    for for_line in [
        "every xs as x, every x.ys as y",
        "every xs as x, some x.ys as y",
        "every xs as x, first of x.ys as y",
        "every xs as x, every x.ys whose n is 1 as y",
        "some xs as x, every x.ys as y",
    ] {
        for assertions in [
            &["m named by x is 1"][..],
            &["x.m named by x.k is 1"][..],
            &["m named by x is 1", "y.n is 1"][..],
            &["x is 1", "m named by x is 1"][..],
        ] {
            assert_eq!(
                for_row(
                    for_line,
                    assertions,
                    json!({"xs": [3], "m": {"a": 1}}),
                    json!({}),
                ),
                (
                    "not_an_object".to_string(),
                    "item 1 of xs: x is 3, which isn't text; item 1 of xs is 3, which isn't an object"
                        .to_string()
                ),
                "{for_line} {assertions:?}"
            );
        }
    }
}

#[test]
fn an_alias_read_whole_is_said_before_an_item_that_only_a_sentence_finds_isnt_an_object() {
    for for_line in [
        "every xs as x, every es as e",
        "every xs as x, every es whose zz is 1 as e",
    ] {
        assert_eq!(
            for_row(
                for_line,
                &["m named by x is 1", "x.v is 1"],
                json!({"xs": [3], "es": [{"zz": 1}], "m": {"a": 1}}),
                json!({}),
            ),
            (
                "not_an_object".to_string(),
                "item 1 of xs: x is 3, which isn't text; item 1 of xs is 3, which isn't an object"
                    .to_string()
            ),
            "{for_line}"
        );
    }
}
