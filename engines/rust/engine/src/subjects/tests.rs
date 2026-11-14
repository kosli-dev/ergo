use crate::SPEC;
use crate::report;
use serde_json::{Value, json};

fn policy(subjects: Value, min: Value) -> Value {
    json!({
        "ergo_spec": SPEC,
        "subjects": subjects,
        "requirements": {"s": {"subject": "thing", "min_subjects": min, "checks": {"c": "x exists"}}}
    })
}

fn rows(report: &Value, check: &str) -> Vec<Value> {
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["check"] == check)
        .cloned()
        .collect()
}

fn run(subjects: Value, input: Value) -> Value {
    report(&input, &policy(subjects, json!(0)), &json!({}))
}

fn input_of(row: &Value, at: usize) -> Value {
    row["inputs"][at].clone()
}

#[test]
fn each_item_of_the_list_is_a_subject_with_its_id_and_location() {
    let r = run(
        json!({"thing": {"from": "every data.ds", "identified_by": "id"}}),
        json!({"data": {"ds": [{"id": "b"}, {"id": 7}]}}),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(
        input_of(min, 0),
        json!({"name": "in-scope thing count", "value": 2, "locations": ["/data/ds/0", "/data/ds/1"]})
    );
    assert_eq!(
        r["requirements"]["s"]["subjects"],
        json!({"total": 2, "matching": 2})
    );
}

#[test]
fn a_missing_path_fails_min_subjects_with_the_outcome_even_with_min_zero() {
    let r = run(json!({"thing": {"from": "ds"}}), json!({}));
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(min["cause"], json!("absent"));
    assert_eq!(min["passed"], json!(false));
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
}

#[test]
fn a_from_line_that_ends_on_a_number_gives_it_as_one_subject_and_null_is_null() {
    let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": 3}));
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("satisfied"));
    let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": null}));
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("null"));
}

#[test]
fn an_object_is_the_only_subject() {
    let r = run(
        json!({"thing": {"identified_by": "id"}}),
        json!({"thing": {"id": 1}}),
    );
    assert_eq!(
        r["requirements"]["s"]["subjects"],
        json!({"total": 1, "matching": 1})
    );
    assert_eq!(
        input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
        json!(["/thing"])
    );
}

#[test]
fn the_whole_input_is_one_subject_when_it_is_an_object_and_a_list_of_subjects_when_it_is_a_list() {
    let r = run(json!({"thing": {"from": "$input"}}), json!({"x": 1}));
    assert_eq!(
        input_of(&rows(&r, "$min_subjects")[0], 0),
        json!({"name": "in-scope thing count", "value": 1, "locations": [""]})
    );
    let r = run(
        json!({"thing": {"from": "$input"}}),
        json!([{"a": 1}, {"a": 2}]),
    );
    assert_eq!(
        r["requirements"]["s"]["subjects"],
        json!({"total": 2, "matching": 2})
    );
    let p = policy(json!({"thing": {"from": "$input"}}), json!(1));
    let r = report(&json!([]), &p, &json!({}));
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("value"));
    let r = run(json!({"thing": {"from": "$input"}}), json!("x"));
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
    let r = run(json!({"thing": {"from": "$input"}}), Value::Null);
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("null"));
}

#[test]
fn a_from_that_reaches_a_list_of_subjects_through_a_param_key() {
    let p = policy(
        json!({"thing": {"from": "every ds named by $params.k"}}),
        json!(1),
    );
    let r = report(&json!({"ds": {"a": [1, 2]}}), &p, &json!({"k": "a"}));
    assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(2));
    let r = report(&json!({"ds": {"a": [1, 2]}}), &p, &json!({"k": "b"}));
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("absent"));
}

#[test]
fn a_subject_without_a_readable_id_has_a_null_id_and_points_at_where_the_read_stopped() {
    let r = run(
        json!({"thing": {"from": "ds", "identified_by": "meta.id"}}),
        json!({"ds": [{"meta": {}}, {"x": 1}]}),
    );
    let unique = &rows(&r, "$unique_ids")[0];
    assert_eq!(unique["passed"], json!(false));
    assert_eq!(
        input_of(unique, 0),
        json!({"name": "repeated thing ids", "value": [null], "locations": ["/ds/0/meta", "/ds/1"]})
    );
}

#[test]
fn an_item_that_is_not_an_object_is_its_own_id_when_nothing_names_the_id() {
    let r = run(
        json!({"thing": {"from": "ds"}}),
        json!({"ds": ["a", "a", 1]}),
    );
    let unique = &rows(&r, "$unique_ids")[0];
    assert_eq!(input_of(unique, 0)["value"], json!(["a"]));
    assert_eq!(input_of(unique, 0)["locations"], json!(["/ds/0", "/ds/1"]));
}

#[test]
fn repeated_ids_are_sorted_by_their_json_text() {
    let r = run(
        json!({"thing": {"from": "ds", "identified_by": "id"}}),
        json!({"ds": [{"id": 3}, {"id": 10}, {"id": "b"}, {"id": 3}, {"id": 10}, {"id": "b"}]}),
    );
    assert_eq!(
        input_of(&rows(&r, "$unique_ids")[0], 0)["value"],
        json!(["b", 10, 3])
    );
}

#[test]
fn the_places_of_repeated_ids_follow_the_order_of_the_list_within_each_id() {
    let r = run(
        json!({"thing": {"from": "ds", "identified_by": "id"}}),
        json!({"ds": [{"id": "b"}, {"id": "a"}, {"id": "b"}, {"id": "a"}, {"id": "c"}, {"id": "b"}]}),
    );
    let row = &rows(&r, "$unique_ids")[0];
    assert_eq!(input_of(row, 0)["value"], json!(["a", "b"]));
    assert_eq!(
        input_of(row, 0)["locations"],
        json!(["/ds/1/id", "/ds/3/id", "/ds/0/id", "/ds/2/id", "/ds/5/id"])
    );
}

#[test]
fn two_ids_that_are_the_same_number_written_differently_are_repeated() {
    let r = run(
        json!({"thing": {"from": "ds", "identified_by": "id"}}),
        serde_json::from_str(r#"{"ds": [{"id": 1}, {"id": 1.0}]}"#).unwrap(),
    );
    assert_eq!(rows(&r, "$unique_ids")[0]["passed"], json!(false));
}

#[test]
fn ids_that_are_out_of_scope_still_count_for_unique_ids() {
    let r = run(
        json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
        json!({"ds": [{"id": 1, "keep": 1}, {"id": 1}]}),
    );
    assert_eq!(rows(&r, "$unique_ids")[0]["passed"], json!(false));
    assert_eq!(
        r["requirements"]["s"]["subjects"],
        json!({"total": 2, "matching": 1})
    );
}

#[test]
fn a_filter_row_is_listed_for_every_subject_and_out_of_scope_ones_fail_with_value() {
    let r = run(
        json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
        json!({"ds": [{"id": "a", "keep": 1}, {"id": "b"}]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies.len(), 2);
    assert_eq!(applies[0]["passed"], json!(true));
    assert_eq!(applies[0]["subject"], json!({"type": "thing", "id": "a"}));
    assert_eq!(applies[1]["cause"], json!("value"));
    assert_eq!(
        input_of(&applies[1], 0),
        json!({"name": "keep", "value": null, "locations": ["/ds/1"]})
    );
    assert_eq!(
        input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
        json!(["/ds/0"])
    );
}

#[test]
fn a_filter_that_cannot_read_its_subject_fails_the_requirement_even_with_min_zero() {
    let r = run(
        json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
        json!({"ds": [1]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies[0]["cause"], json!("not_an_object"));
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
}

#[test]
fn a_present_filter_that_finds_its_field_missing_rules_the_subject_out_whatever_the_others_say() {
    let r = run(
        json!({"thing": {"from": "ds whose keep exists and whose b.c exists"}}),
        json!({"ds": [{"b": 1}]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies[0]["cause"], json!("value"));
    assert_eq!(
        applies[0]["failed_assertions"],
        json!([
            {"assertion": "keep exists", "cause": "value"},
            {"assertion": "b.c exists", "cause": "unusable"}
        ])
    );
    assert_eq!(r["requirements"]["s"]["status"], json!("not_applicable"));
}

#[test]
fn several_filters_give_failed_assertions_and_one_filter_gives_none() {
    let r = run(
        json!({"thing": {"from": "ds whose fa exists and whose fb exists"}}),
        json!({"ds": [{"fa": 1, "fb": 1}]}),
    );
    assert_eq!(rows(&r, "$applies")[0]["failed_assertions"], json!([]));
    let r = run(
        json!({"thing": {"from": "ds whose fa exists"}}),
        json!({"ds": [{"fa": 1}]}),
    );
    assert!(rows(&r, "$applies")[0].get("failed_assertions").is_none());
}

#[test]
fn an_applies_row_lists_a_field_read_twice_once_sorted_by_name() {
    let r = run(
        json!({"thing": {"from": "ds whose fb exists and whose fa exists and whose fb does not exist"}}),
        json!({"ds": [{"fa": 1, "fb": 1}]}),
    );
    let row = &rows(&r, "$applies")[0];
    assert_eq!(row["inputs"].as_array().unwrap().len(), 2);
    assert_eq!(row["inputs"][0]["name"], json!("fa"));
    assert_eq!(row["inputs"][1]["name"], json!("fb"));
}

#[test]
fn a_subject_with_no_filters_has_no_applies_row() {
    let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": [{}]}));
    assert!(rows(&r, "$applies").is_empty());
}

#[test]
fn named_by_each_of_makes_each_sorted_key_a_subject_and_a_missing_key_points_at_the_object() {
    let p = policy(
        json!({"thing": {"from": "scans named by each of $params.l"}}),
        json!(1),
    );
    let input = json!({"scans": {"sast": {"name": "other"}, "sca": {}}});
    let r = report(&input, &p, &json!({"l": ["sca", "zzz", "sast", "sca"]}));
    assert_eq!(
        input_of(&rows(&r, "$min_subjects")[0], 0),
        json!({"name": "in-scope thing count", "value": 3,
            "locations": ["/scans/sast", "/scans/sca", "/scans"]})
    );
    assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(3));
}

#[test]
fn a_key_with_a_slash_is_escaped_in_the_location() {
    let p = policy(
        json!({"thing": {"from": "scans named by each of $params.l"}}),
        json!(1),
    );
    let r = report(&json!({"scans": {"a/b": {}}}), &p, &json!({"l": ["a/b"]}));
    assert_eq!(
        input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
        json!(["/scans/a~1b"])
    );
}

#[test]
fn keys_that_are_not_a_list_of_strings_fail_min_subjects_as_unusable() {
    let p = policy(
        json!({"thing": {"from": "scans named by each of $params.l"}}),
        json!(0),
    );
    for params in [json!({"l": "a"}), json!({"l": [1]}), json!({"l": {"a": 1}})] {
        let r = report(&json!({"scans": {}}), &p, &params);
        assert_eq!(
            rows(&r, "$min_subjects")[0]["cause"],
            json!("unusable"),
            "{params}"
        );
    }
    let r = report(&json!({"scans": {}}), &p, &json!({}));
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("absent"));
}

#[test]
fn every_reads_one_flat_list_from_every_list_along_the_path() {
    let r = run(
        json!({"thing": {"from": "every arts.prs", "identified_by": "url"}}),
        json!({"arts": [{"prs": [{"url": "a"}, {"url": "b"}]}, {"prs": []}, {"prs": [{"url": "c"}]}]}),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(min["failed_items"], json!([]));
    assert_eq!(
        input_of(min, 0)["locations"],
        json!(["/arts/0/prs/0", "/arts/0/prs/1", "/arts/2/prs/0"])
    );
    assert!(min["subject"].get("in").is_none());
}

#[test]
fn every_over_only_empty_lists_finds_none_without_failing_anything() {
    let r = report(
        &json!({"arts": [{"prs": []}]}),
        &policy(json!({"thing": {"from": "every arts.prs"}}), json!(1)),
        &json!({}),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(min["cause"], json!("value"));
    assert_eq!(min["failed_items"], json!([]));
}

#[test]
fn every_lists_each_place_it_broke_with_the_worst_cause_and_keeps_the_subjects_it_read() {
    let r = run(
        json!({"thing": {"from": "every arts.prs"}}),
        json!({"arts": [{"prs": [{"u": 1}]}, {}, {"prs": null}, {"prs": "none"}]}),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(min["cause"], json!("unusable"));
    assert_eq!(
        min["failed_items"],
        json!([
            {"path": "arts[0].prs", "item": "arts[0].prs", "cause": "unusable", "value": [{"u": 1}], "locations": ["/arts/0/prs"]},
            {"path": "item 1 of arts[0].prs", "item": "item 1 of arts[0].prs", "cause": "unusable", "value": {"u": 1}, "locations": ["/arts/0/prs/0"]},
            {"path": "arts[1].prs", "item": "arts[1].prs", "cause": "absent", "value": null, "locations": ["/arts/1"]},
            {"path": "arts[2].prs", "item": "arts[2].prs", "cause": "null", "value": null, "locations": ["/arts/2/prs"]},
            {"path": "arts[3].prs", "item": "arts[3].prs", "cause": "unusable", "value": "none", "locations": ["/arts/3/prs"]}
        ])
    );
    assert_eq!(
        min["message"],
        json!(
            "item 2 of arts: prs is missing; item 3 of arts: prs is null; prs is a list in item 1 of arts but \"none\" in item 4; and 1 more"
        )
    );
    assert_eq!(input_of(min, 0)["value"], json!(2));
}

#[test]
fn every_names_a_broken_walk_from_a_list_input_from_dollar_input() {
    let r = run(
        json!({"thing": {"from": "every $input.commits"}}),
        json!([{"commits": [{"x": 1}]}, {"commits": null}]),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(
        min["failed_items"],
        json!([{"path": "$input[1].commits", "item": "$input[1].commits", "cause": "null", "value": null, "locations": ["/1/commits"]}])
    );
    let r = run(
        json!({"thing": {"from": "every $input[1].commits"}}),
        json!([{"commits": []}, 5]),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(min["failed_items"][0]["path"], json!("item 2 of $input"));
    assert_eq!(min["failed_items"][0]["item"], json!("item 2 of $input"));
}

#[test]
fn every_dollar_input_names_an_input_that_is_not_a_list_dollar_input() {
    let r = run(json!({"thing": {"from": "every $input"}}), json!({"x": 1}));
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(
        min["failed_items"],
        json!([{"path": "$input", "item": "$input", "cause": "unusable", "value": {"x": 1}, "locations": [""]}])
    );
}

#[test]
fn a_position_on_a_list_input_is_named_from_dollar_input_in_expressions() {
    let cases = [
        ("$input[0]", "item 1 of $input"),
        ("$input[1]", "item 2 of $input"),
        ("first of $input", "item 1 of $input"),
        ("every $input[1].commits", "every $input[1].commits"),
        ("every $input.commits", "every commits"),
        ("$input", "$input"),
        ("every $input", "every $input"),
    ];
    for (from, name) in cases {
        let r = report(
            &json!([]),
            &policy(json!({"thing": {"from": from}}), json!(1)),
            &json!({}),
        );
        let checks = &r["requirements"]["s"]["checks"];
        assert_eq!(
            checks["$min_subjects"]["expression"],
            json!(format!("count(matching({name})) >= 1")),
            "{from}"
        );
        assert_eq!(
            checks["$unique_ids"]["expression"],
            json!(format!("count(repeated(ids({name}))) == 0")),
            "{from}"
        );
    }
}

#[test]
fn every_with_no_list_along_the_path_fails_unusable_at_the_value_it_ends_at() {
    let r = run(
        json!({"thing": {"from": "every arts.prs"}}),
        json!({"arts": {"prs": {"u": 1}}}),
    );
    let min = &rows(&r, "$min_subjects")[0];
    assert_eq!(min["cause"], json!("unusable"));
    assert_eq!(
        min["failed_items"],
        json!([{"path": "arts.prs", "item": "arts.prs", "cause": "unusable", "value": {"u": 1}, "locations": ["/arts/prs"]}])
    );
    assert_eq!(input_of(min, 0)["value"], json!(0));
}

#[test]
fn every_whose_named_by_reads_a_param_that_is_missing_keeps_the_requirement_and_fails_absent() {
    let subjects = json!({"thing": {"from": "every x named by $params.k"}});
    for (params, cause) in [
        (json!({}), "absent"),
        (json!({"k": null}), "null"),
        (json!({"k": ["x"]}), "unusable"),
    ] {
        let r = report(
            &json!({"x": [{"id": 1}]}),
            &policy(subjects.clone(), json!(1)),
            &params,
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["cause"], json!(cause));
        assert_eq!(min["failed_items"], json!([]));
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    }
}

#[test]
fn a_position_under_a_keyed_parent_the_object_lacks_fails_absent_and_not_unusable() {
    for from in ["p[0]", "first of p", "p[0].x"] {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"p": {"from": "m named by each of $params.ks"}, "k": {"from": from}},
            "requirements": {"r": {"subject": "k", "checks": {"c": "x exists"}}}
        });
        let r = report(
            &json!({"m": {"a": [{"x": 1}]}}),
            &policy,
            &json!({"ks": ["c"]}),
        );
        let causes: Vec<Value> = rows(&r, "$min_subjects")
            .iter()
            .map(|row| row["cause"].clone())
            .collect();
        assert_eq!(causes, vec![json!("absent")], "{from}");
    }
}

#[test]
fn a_key_the_object_lacks_reads_as_missing_in_every_check() {
    let cases = [
        ("it exists", false, "value"),
        ("it does not exist", true, "satisfied"),
        ("it is an object", false, "absent"),
        ("it is empty", false, "absent"),
        ("x exists", false, "value"),
        ("x does not exist", true, "satisfied"),
    ];
    for (check, passed, cause) in cases {
        let p = json!({
            "ergo_spec": SPEC,
            "subjects": {"s": {"from": "things named by each of $params.k"}},
            "requirements": {"r": {"subject": "s", "checks": {"c": check}}}
        });
        let r = report(
            &json!({"things": {"b": {"x": 1}}}),
            &p,
            &json!({"k": ["a"]}),
        );
        let row = &rows(&r, "c")[0];
        assert_eq!(row["passed"], json!(passed), "{check}");
        assert_eq!(row["cause"], json!(cause), "{check}");
        assert_eq!(row["inputs"][0]["value"], Value::Null, "{check}");
        assert_eq!(row["inputs"][0]["locations"], json!(["/things"]), "{check}");
    }
}

#[test]
fn a_missing_key_fails_its_check_when_the_input_is_not_an_object() {
    let p = json!({
        "ergo_spec": SPEC,
        "subjects": {"s": {"from": "$input named by each of $params.k"}},
        "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}
    });
    for input in [json!([{"id": 1}]), json!("text")] {
        let r = report(&input, &p, &json!({"k": ["a"]}));
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["cause"], json!("unusable"), "{input}");
        assert_eq!(input_of(min, 0)["value"], json!(1), "{input}");
        let row = &rows(&r, "c")[0];
        assert_eq!(row["passed"], json!(false), "{input}");
        assert_eq!(row["subject"]["id"], json!("a"), "{input}");
    }
}

#[test]
fn every_counts_ids_across_every_list() {
    let r = run(
        json!({"thing": {"from": "every arts.prs", "identified_by": "url"}}),
        json!({"arts": [{"prs": [{"url": "x"}]}, {"prs": [{"url": "x"}]}]}),
    );
    assert_eq!(
        input_of(&rows(&r, "$unique_ids")[0], 0)["locations"],
        json!(["/arts/0/prs/0/url", "/arts/1/prs/0/url"])
    );
}

#[test]
fn every_takes_a_list_of_scalars_as_subjects() {
    let r = run(
        json!({"thing": {"from": "every xs"}}),
        json!({"xs": ["a", "b"]}),
    );
    assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(2));
    assert_eq!(rows(&r, "$min_subjects")[0]["failed_items"], json!([]));
}

fn chain() -> Value {
    json!({
        "art": {"from": "arts whose live exists", "identified_by": "id"},
        "thing": {"from": "every art.prs", "identified_by": "id"}
    })
}

#[test]
fn a_child_subject_is_read_from_each_parent_and_every_row_carries_the_parents_id() {
    let r = run(
        chain(),
        json!({"arts": [
            {"id": "a1", "live": 1, "prs": [{"id": 1}, {"id": 2}]},
            {"id": "a2", "live": 1, "prs": [{"id": 1}]}
        ]}),
    );
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 2);
    assert_eq!(
        min[0]["subject"],
        json!({"type": "thing", "id": null, "in": {"art": "a1"}})
    );
    assert_eq!(input_of(&min[1], 0)["locations"], json!(["/arts/1/prs/0"]));
    let unique = rows(&r, "$unique_ids");
    assert_eq!(unique.len(), 2);
    assert!(unique.iter().all(|row| row["passed"] == json!(true)));
    assert_eq!(
        r["requirements"]["s"]["subjects"],
        json!({"total": 3, "matching": 3})
    );
}

#[test]
fn a_repeated_parent_id_fails_one_ancestor_row_counting_the_parents_left_out() {
    let r = run(
        chain(),
        json!({"arts": [
            {"id": "a1", "live": 1, "prs": [{"id": 1}]},
            {"id": "a1", "prs": [{"id": 2}]}
        ]}),
    );
    let ancestors = rows(&r, "$unique_ancestor_ids");
    assert_eq!(ancestors.len(), 1);
    assert_eq!(ancestors[0]["subject"], json!({"type": "art", "id": null}));
    assert_eq!(
        input_of(&ancestors[0], 0),
        json!({"name": "repeated art ids", "value": ["a1"], "locations": ["/arts/0/id", "/arts/1/id"]})
    );
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    assert_eq!(
        r["requirements"]["s"]["checks"]["$unique_ancestor_ids"]["expression"],
        json!("count(repeated(ids(arts))) == 0")
    );
}

#[test]
fn a_subject_with_no_parent_has_no_ancestor_row_and_no_ancestor_check() {
    let r = run(
        json!({"thing": {"from": "ds", "identified_by": "id"}}),
        json!({"ds": [{"id": 1}]}),
    );
    assert!(rows(&r, "$unique_ancestor_ids").is_empty());
    assert!(
        r["requirements"]["s"]["checks"]
            .get("$unique_ancestor_ids")
            .is_none()
    );
}

#[test]
fn a_parent_its_filters_leave_out_gives_no_rows_at_all() {
    let r = run(
        chain(),
        json!({"arts": [
            {"id": "a1", "prs": [{"id": 1}, {"id": 1}]},
            {"id": "a2", "live": 1, "prs": [{"id": 5}]}
        ]}),
    );
    assert_eq!(rows(&r, "$min_subjects").len(), 1);
    assert_eq!(rows(&r, "$unique_ids").len(), 1);
    assert!(rows(&r, "$applies").is_empty());
}

#[test]
fn a_parent_a_filter_cannot_decide_gets_one_failing_min_row_and_nothing_below_it() {
    let r = run(chain(), json!({"arts": [5, 6]}));
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 2);
    assert_eq!(min[1]["cause"], json!("not_an_object"));
    assert_eq!(min[1]["subject"]["in"], json!({"art": 6}));
    assert_eq!(rows(&r, "$unique_ids").len(), 0);
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
}

#[test]
fn with_no_parent_at_all_one_min_row_without_in_fails_as_value_or_passes_with_min_zero() {
    let p = |min: Value| policy(chain(), min);
    let r = report(&json!({"arts": []}), &p(json!(1)), &json!({}));
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 1);
    assert_eq!(min[0]["cause"], json!("value"));
    assert!(min[0]["subject"].get("in").is_none());
    assert_eq!(rows(&r, "$unique_ids").len(), 1);
    let r = report(&json!({"arts": []}), &p(json!(0)), &json!({}));
    assert_eq!(rows(&r, "$min_subjects")[0]["passed"], json!(true));
}

#[test]
fn a_parent_that_cannot_be_read_fails_min_subjects_with_its_cause_on_one_row_without_in() {
    let r = run(chain(), json!({}));
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 1);
    assert_eq!(min[0]["cause"], json!("absent"));
    assert!(min[0]["subject"].get("in").is_none());
}

#[test]
fn a_child_whose_own_list_is_missing_fails_on_the_row_of_its_parent() {
    let r = run(chain(), json!({"arts": [{"id": "a1", "live": 1}]}));
    let min = rows(&r, "$min_subjects");
    assert_eq!(min[0]["cause"], json!("absent"));
    assert_eq!(min[0]["subject"]["in"], json!({"art": "a1"}));
}

#[test]
fn three_levels_carry_every_ancestors_id_and_count_per_direct_parent() {
    let r = run(
        json!({
            "art": {"from": "arts", "identified_by": "id"},
            "pr": {"from": "every art.prs", "identified_by": "id"},
            "thing": {"from": "every pr.cs", "identified_by": "sha"},
        }),
        json!({"arts": [{"id": "a", "prs": [{"id": 1, "cs": [{"sha": "x"}]}, {"id": 2, "cs": [{"sha": "x"}, {"sha": "y"}]}]}]}),
    );
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 2);
    assert_eq!(min[1]["subject"]["in"], json!({"art": "a", "pr": 2}));
    assert_eq!(input_of(&min[1], 0)["value"], json!(2));
    assert_eq!(
        r["requirements"]["s"]["subjects"],
        json!({"total": 3, "matching": 3})
    );
}

#[test]
fn a_subject_out_of_scope_at_any_level_leaves_out_everything_below_it() {
    let r = run(
        json!({
            "art": {"from": "arts whose live exists", "identified_by": "id"},
            "pr": {"from": "every art.prs whose open exists", "identified_by": "id"},
            "thing": {"from": "every pr.cs", "identified_by": "sha"},
        }),
        json!({"arts": [{"id": "a", "live": 1, "prs": [
            {"id": 1, "cs": [{"sha": "x"}]}, {"id": 2, "open": 1, "cs": [{"sha": "y"}]}
        ]}]}),
    );
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 1);
    assert_eq!(min[0]["subject"]["in"], json!({"art": "a", "pr": 2}));
}

#[test]
fn an_undecidable_middle_level_gets_a_row_with_in_up_to_that_ancestor() {
    let r = run(
        json!({
            "art": {"from": "arts", "identified_by": "id"},
            "pr": {"from": "every art.prs whose open exists", "identified_by": "id"},
            "thing": {"from": "every pr.cs"},
        }),
        json!({"arts": [{"id": "a", "prs": [7]}]}),
    );
    let min = rows(&r, "$min_subjects");
    assert_eq!(min.len(), 1);
    assert_eq!(min[0]["cause"], json!("not_an_object"));
    assert_eq!(min[0]["subject"]["in"], json!({"art": "a", "pr": 7}));
}

#[test]
fn a_child_is_read_from_a_part_of_its_parent() {
    let r = run(
        json!({
            "art": {"from": "arts", "identified_by": "id", "has": {"att": {"from": "x.b", "identified_by": "aid"}}},
            "thing": {"from": "every art.att.prs whose id exists", "identified_by": "id"},
        }),
        json!({"arts": [{"id": "a1", "x": {"b": {"aid": 9, "prs": [{"id": 1}]}}}]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies[0]["passed"], json!(true));
    assert_eq!(
        input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
        json!(["/arts/0/x/b/prs/0"])
    );
    assert_eq!(
        rows(&r, "$min_subjects")[0]["subject"]["in"],
        json!({"art": "a1"})
    );
    assert_eq!(
        r["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
        json!("every art.att.prs can be read")
    );
}

#[test]
fn the_left_of_a_condition_reads_the_childs_own_field_even_when_a_parent_has_that_name() {
    let r = run(
        json!({
            "b": {"from": "bs", "identified_by": "id"},
            "thing": {"from": "every b.kids whose b.x exists", "identified_by": "id"},
        }),
        json!({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 2}}, {"id": "k2"}]}]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies[0]["passed"], json!(true));
    assert_eq!(
        input_of(&applies[0], 0)["locations"],
        json!(["/bs/0/kids/0/b/x"])
    );
    assert_eq!(applies[1]["cause"], json!("value"));
    assert_eq!(
        input_of(&applies[1], 0)["locations"],
        json!(["/bs/0/kids/1"])
    );
}

fn kid_report(subjects: Value, input: Value) -> Value {
    report(
        &input,
        &json!({
            "ergo_spec": SPEC,
            "subjects": subjects,
            "requirements": {"s": {"subject": "kid", "checks": {"c": "id exists"}}}
        }),
        &json!({}),
    )
}

#[test]
fn a_from_line_prints_a_key_named_like_a_parent_without_a_dot_and_its_filter_with_one() {
    let r = kid_report(
        json!({
            "b": {"from": "bs", "identified_by": "id"},
            "kid": {"from": "every b.kids whose b.x equals v", "identified_by": "id"}
        }),
        json!({"bs": [{"id": "b1", "kids": [{"id": "k1", "v": 1}]}]}),
    );
    assert_eq!(
        r["subjects"]["kid"]["from"],
        json!("every b.kids whose b.x equals v")
    );
    assert_eq!(
        r["requirements"]["s"]["checks"]["$applies"]["expression"],
        json!(".b.x equals v")
    );
}

#[test]
fn a_filter_keeps_the_dot_of_a_field_named_like_a_part() {
    let r = kid_report(
        json!({"kid": {
            "from": "kids whose .att.id is 1",
            "identified_by": "id",
            "has": {"att": {"from": "atts.pr", "identified_by": "id"}}
        }}),
        json!({"kids": [{"id": "k1", "att": {"id": 1}, "atts": {"pr": [{"id": 1}]}}]}),
    );
    assert_eq!(
        r["requirements"]["s"]["checks"]["$applies"]["expression"],
        json!(".att.id is 1")
    );
    assert_eq!(
        r["subjects"]["kid"]["from"],
        json!("kids whose .att.id is 1")
    );
}

#[test]
fn a_subject_that_narrows_another_has_its_id_and_every_condition_outermost_first() {
    let r = run(
        json!({
            "defect": {"from": "defects whose status exists", "identified_by": "id"},
            "thing": {"from": "defect whose severity exists"},
        }),
        json!({"defects": [
            {"id": "d1", "status": 1, "severity": 1},
            {"id": "d2", "severity": 1},
            {"id": "d3", "status": 1}
        ]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies.len(), 3);
    assert_eq!(applies[0]["subject"]["id"], json!("d1"));
    assert_eq!(
        applies[2]["failed_assertions"],
        json!([{"assertion": "severity exists", "cause": "value"}])
    );
    assert_eq!(
        r["requirements"]["s"]["checks"]["$applies"]["expression"],
        json!("status exists and severity exists")
    );
    assert_eq!(r["subjects"]["thing"]["identified_by"], json!("id"));
    assert_eq!(
        r["subjects"]["defect"]["from"],
        json!("defects whose status exists")
    );
}

#[test]
fn a_part_in_a_condition_names_the_alias_and_tags_the_input_with_the_parts_id() {
    let r = run(
        json!({"thing": {"from": "ds whose cov.x exists", "identified_by": "id",
            "has": {"cov": {"from": "d.b", "identified_by": "cid"}}}}),
        json!({"ds": [{"id": "a", "d": {"b": {"x": 1, "cid": "c1"}}}]}),
    );
    assert_eq!(
        input_of(&rows(&r, "$applies")[0], 0),
        json!({"name": "cov.x", "value": 1, "locations": ["/ds/0/d/b/x"],
            "part": {"name": "cov", "id": "c1"}})
    );
}

#[test]
fn a_dot_reads_the_field_and_not_the_part_and_the_name_keeps_the_dot() {
    let r = run(
        json!({"thing": {"from": "ds whose .att.id exists", "has": {"att": "atts.pr"}}}),
        json!({"ds": [{"att": {"id": 1}, "atts": {"pr": {"id": 2}}}, {"atts": {"pr": {"id": 1}}}]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies[0]["passed"], json!(true));
    assert_eq!(input_of(&applies[0], 0)["name"], json!(".att.id"));
    assert!(input_of(&applies[0], 0).get("part").is_none());
    assert_eq!(applies[1]["cause"], json!("value"));
}

#[test]
fn a_part_that_is_missing_fails_the_condition_as_the_full_path_would() {
    let r = run(
        json!({"thing": {"from": "ds whose cov.x exists", "has": {"cov": "d.b"}}}),
        json!({"ds": [{"d": {}}, 3]}),
    );
    let applies = rows(&r, "$applies");
    assert_eq!(applies[0]["cause"], json!("value"));
    assert_eq!(input_of(&applies[0], 0)["locations"], json!(["/ds/0/d"]));
    assert_eq!(applies[1]["cause"], json!("not_an_object"));
}

#[test]
fn a_requirement_that_names_no_subject_gets_no_subjects() {
    let policy = json!({
        "ergo_spec": SPEC, "subjects": {"thing": {}},
        "requirements": {"s": {"checks": {"c": "x exists"}}}
    });
    let r = report(&json!({}), &policy, &json!({}));
    assert!(rows(&r, "$min_subjects").is_empty());
}

#[test]
fn params_that_are_not_an_object_keep_the_subjects_and_fail_min_subjects() {
    let r = report(
        &json!({"ds": [1]}),
        &policy(json!({"thing": {"from": "ds"}}), json!(0)),
        &json!([1]),
    );
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
    assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(1));
}

#[test]
fn a_condition_with_a_count_on_the_right_keeps_the_subjects_that_pass_it() {
    let r = run(
        json!({"thing": {"from": "ds whose x is at least count of ys"}}),
        json!({"ds": [{"x": 2, "ys": [1, 2]}, {"x": 1, "ys": [1, 2]}, {"x": 3}]}),
    );
    assert_eq!(r["requirements"]["s"]["subjects"]["matching"], json!(1));
    assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(3));
    assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(true));
}

#[test]
fn a_child_of_a_subject_with_a_count_on_the_right_reads_under_the_parents_that_pass() {
    let r = run(
        json!({"art": {"from": "arts whose x is at least count of ys"}, "thing": {"from": "every art.prs"}}),
        json!({"arts": [{"x": 1, "ys": [1], "prs": [{}]}, {"x": 0, "ys": [1], "prs": [{}]}]}),
    );
    assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("satisfied"));
    assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(1));
}

#[test]
fn a_requirement_whose_subject_is_written_wrong_reads_no_subjects() {
    let r = run(json!({"thing": {"from": "ds whose"}}), json!({"ds": [1]}));
    assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(false));
    assert!(rows(&r, "$min_subjects").is_empty());
}

#[test]
fn a_subjects_entry_is_listed_for_every_subject_the_requirement_uses_and_no_other() {
    let r = run(
        json!({"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "every art.prs"}, "other": {}}),
        json!({"arts": []}),
    );
    let names: Vec<&String> = r["subjects"].as_object().unwrap().keys().collect();
    assert_eq!(names, ["art", "thing"]);
    assert_eq!(r["subjects"]["thing"]["from"], json!("every art.prs"));
    assert_eq!(
        r["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
        json!("every art.prs can be read")
    );
}

fn with_checks(subjects: Value, checks: Value, input: Value) -> Value {
    let policy = json!({
        "ergo_spec": SPEC, "subjects": subjects,
        "requirements": {"s": {"subject": "thing", "checks": checks}}
    });
    report(&input, &policy, &json!({}))
}

fn checked(r: &Value) -> Vec<(String, String, String)> {
    rows(r, "a")
        .into_iter()
        .chain(rows(r, "b"))
        .map(|row| {
            (
                row["check"].as_str().unwrap().to_string(),
                row["subject"]["id"].to_string(),
                row["cause"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

#[test]
fn every_in_scope_subject_gets_a_row_for_each_check_in_name_order() {
    let r = with_checks(
        json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
        json!({"b": "x exists", "a": "x exists"}),
        json!({"ds": [{"id": 1, "keep": 1, "x": 1}, {"id": 2}, {"id": 3, "keep": 1}]}),
    );
    let order: Vec<(String, String)> = r["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| !row["check"].as_str().unwrap().starts_with('$'))
        .map(|row| (row["check"].to_string(), row["subject"]["id"].to_string()))
        .collect();
    assert_eq!(
        order,
        [
            ("\"a\"".into(), "1".into()),
            ("\"b\"".into(), "1".into()),
            ("\"a\"".into(), "3".into()),
            ("\"b\"".into(), "3".into())
        ]
    );
    let causes: Vec<String> = checked(&r).into_iter().map(|c| c.2).collect();
    assert_eq!(causes, ["satisfied", "value", "satisfied", "value"]);
}

#[test]
fn a_check_row_reads_the_subject_and_a_requirement_with_a_failing_check_is_not_met() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "x exists"}),
        json!({"ds": [{"x": 1}, {}]}),
    );
    let a = rows(&r, "a");
    assert_eq!(a[0]["passed"], json!(true));
    assert_eq!(
        a[1]["inputs"],
        json!([{"name": "x", "value": null, "locations": ["/ds/1"]}])
    );
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    assert_eq!(
        r["requirements"]["s"]["causes"],
        json!([{"cause": "value", "rows": 1}])
    );
}

#[test]
fn several_assertions_are_one_row_with_failed_assertions_the_worst_cause_and_merged_inputs() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "x exists and y.z exists and x exists"}),
        json!({"ds": [{"x": 1, "y": 5}, {"x": 1, "y": {"z": 1}}]}),
    );
    let a = rows(&r, "a");
    assert_eq!(a[0]["cause"], json!("unusable"));
    assert_eq!(
        a[0]["failed_assertions"],
        json!([{"assertion": "y.z exists", "cause": "unusable"}])
    );
    assert_eq!(a[0]["inputs"].as_array().unwrap().len(), 2);
    assert_eq!(a[0]["inputs"][0]["name"], json!("x"));
    assert_eq!(a[1]["failed_assertions"], json!([]));
    assert_eq!(a[1]["passed"], json!(true));
}

#[test]
fn one_assertion_keeps_its_inputs_in_the_order_it_read_them_left_then_right() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "x is less than $input.limit"}),
        json!({"limit": 5, "ds": [{"x": 1}]}),
    );
    let names: Vec<_> = rows(&r, "a")[0]["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["name"].clone())
        .collect();
    assert_eq!(names, [json!("x"), json!("$input.limit")]);
}

#[test]
fn several_assertions_sort_their_inputs_by_name() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "x is less than $input.limit and x exists"}),
        json!({"limit": 5, "ds": [{"x": 1}]}),
    );
    let names: Vec<_> = rows(&r, "a")[0]["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["name"].clone())
        .collect();
    assert_eq!(names, [json!("$input.limit"), json!("x")]);
}

#[test]
fn one_assertion_has_no_failed_assertions() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "x exists"}),
        json!({"ds": [{}]}),
    );
    assert!(rows(&r, "a")[0].get("failed_assertions").is_none());
}

#[test]
fn a_check_written_with_a_count_after_every_fails_the_requirement_so_nothing_passes_by_accident() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "every xs.y is at least count of zs"}),
        json!({"ds": [{"xs": [{"y": 1}]}]}),
    );
    assert_eq!(rows(&r, "a").len(), 0);
    assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(false));
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    assert_eq!(r["compliant"], json!(false));
}

#[test]
fn a_for_check_is_run_and_fails_as_absent_when_its_list_is_missing() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": {"for": "every xs as x", "assert": "x.y exists"}}),
        json!({"ds": [{}]}),
    );
    assert_eq!(rows(&r, "a")[0]["cause"], json!("absent"));
}

#[test]
fn an_any_of_row_passes_with_one_option_and_lists_its_inputs_sorted() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": {"any_of": {"o": "z exists", "p": ["y exists", "x exists"]}}}),
        json!({"ds": [{"y": 1, "x": 2}]}),
    );
    let row = &rows(&r, "a")[0];
    assert_eq!(row["cause"], json!("satisfied"));
    let names: Vec<&Value> = row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| &i["name"])
        .collect();
    assert_eq!(names, [&json!("x"), &json!("y"), &json!("z")]);
    assert!(row.get("failed_assertions").is_none());
}

#[test]
fn a_check_read_through_a_part_tags_its_input() {
    let r = with_checks(
        json!({"thing": {"from": "ds", "has": {"cov": {"from": "d", "identified_by": "cid"}}}}),
        json!({"a": "cov.x exists"}),
        json!({"ds": [{"d": {"x": 1, "cid": 4}}]}),
    );
    assert_eq!(
        rows(&r, "a")[0]["inputs"][0]["part"],
        json!({"name": "cov", "id": 4})
    );
}

#[test]
fn a_check_written_wrong_gives_the_requirement_no_check_rows_and_lists_the_problem() {
    let r = with_checks(
        json!({"thing": {"from": "ds"}}),
        json!({"a": "x exists", "b": "y is \"a"}),
        json!({"ds": [{"x": 1}]}),
    );
    assert!(rows(&r, "a").is_empty());
    let well = &rows(&r, "$well_formed")[0];
    assert_eq!(
        well["inputs"][2],
        json!({"name": "checks.b", "value": ["unclosed quote at column 6"], "locations": []})
    );
    assert_eq!(
        r["requirements"]["s"]["checks"]["b"]["expression"],
        json!("y is \"a")
    );
}

#[test]
fn a_check_row_of_a_child_subject_carries_the_parents_id_and_reads_the_parent() {
    let r = with_checks(
        json!({"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "every art.ps", "identified_by": "id"}}),
        json!({"a": "art.owner exists"}),
        json!({"arts": [{"id": "a1", "owner": 1, "ps": [{"id": 1}]}]}),
    );
    let a = rows(&r, "a");
    assert_eq!(
        a[0]["subject"],
        json!({"type": "thing", "id": 1, "in": {"art": "a1"}})
    );
    assert_eq!(a[0]["passed"], json!(true));
    assert_eq!(a[0]["inputs"][0]["locations"], json!(["/arts/0/owner"]));
}

#[test]
fn a_keyed_parent_with_identified_by_is_written_wrong_under_the_childs_requirement() {
    let mut p = policy(
        json!({
            "suite": {"from": "suites named by each of $params.names", "identified_by": "aid"},
            "thing": {"from": "every suite.items", "identified_by": "id"}
        }),
        json!(0),
    );
    p["requirements"]["s"]["checks"] = json!({"c": "ok is true"});
    let input = json!({"suites": {"unit": {"aid": "att-u", "items": [{"id": 1, "ok": true}]}}});
    let r = report(&input, &p, &json!({"names": ["unit"]}));
    assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    let well_formed = &rows(&r, "$well_formed")[0];
    assert_eq!(well_formed["passed"], json!(false));
    assert_eq!(
        well_formed["inputs"][2],
        json!({
            "name": "subjects.suite.identified_by",
            "value": ["not allowed with named by each of: the key is the id"],
            "locations": []
        })
    );
    assert_eq!(rows(&r, "c").len(), 0);
}

#[test]
fn identified_by_that_is_not_a_string_next_to_named_by_each_of_lists_both_problems() {
    for bad in [json!(5), json!(null), json!(["id"])] {
        let r = run(
            json!({"thing": {"from": "suites named by each of $params.names", "identified_by": bad}}),
            json!({}),
        );
        let well_formed = &rows(&r, "$well_formed")[0];
        assert_eq!(
            well_formed["inputs"][2],
            json!({
                "name": "subjects.thing.identified_by",
                "value": [
                    "not a string",
                    "not allowed with named by each of: the key is the id"
                ],
                "locations": []
            }),
            "{bad}"
        );
        assert_eq!(
            r["subjects"]["thing"]["identified_by"],
            json!("<invalid identified_by>")
        );
    }
}

fn min_message(subjects: Value, input: Value) -> Value {
    rows(&run(subjects, input), "$min_subjects")[0]["message"].clone()
}

fn deep_message(subjects: Value, input: Value) -> Value {
    let r = report(
        &input,
        &json!({
            "ergo_spec": SPEC,
            "subjects": subjects,
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        }),
        &json!({}),
    );
    rows(&r, "$min_subjects")[0]["message"].clone()
}

#[test]
fn a_position_on_the_input_names_the_list_without_dollar_input() {
    assert_eq!(
        min_message(
            json!({"thing": {"from": "item 2 of things"}}),
            json!({"things": [{"x": 1}]})
        ),
        json!("item 2 of things is missing")
    );
    assert_eq!(
        min_message(
            json!({"thing": {"from": "item 2 of things"}}),
            json!({"things": [{"x": 1}, null]})
        ),
        json!("item 2 of things is null")
    );
    assert_eq!(
        min_message(
            json!({"thing": {"from": "first of things"}}),
            json!({"things": []})
        ),
        json!("item 1 of things is missing")
    );
}

#[test]
fn a_child_names_the_path_it_walks_in_its_parent_without_the_parent() {
    let subjects = |from: &str| json!({"p": {"from": "ps"}, "thing": {"from": from}});
    let said = |from: &str, parent: Value| deep_message(subjects(from), json!({"ps": [parent]}));
    assert_eq!(said("p.ws", json!({"id": 1})), json!("ws is missing"));
    assert_eq!(said("p.ws", json!({"ws": null})), json!("ws is null"));
    assert_eq!(
        said("p.ws", json!({"ws": [5]})),
        json!("ws is a list: write every p.ws to read each item")
    );
    assert_eq!(
        said("first of p.ws", json!({"ws": []})),
        json!("item 1 of ws is missing")
    );
    assert_eq!(
        said("item 2 of p.ws", json!({"ws": [{"x": 1}]})),
        json!("item 2 of ws is missing")
    );
    assert_eq!(
        said("p.meta.owner", json!({"meta": {}})),
        json!("meta.owner is missing")
    );
    assert_eq!(
        said("p.meta.owner", json!({"meta": 5})),
        json!("meta is 5, which isn't a list or an object")
    );
}

#[test]
fn a_grandchild_names_the_path_in_its_nearest_parent() {
    assert_eq!(
        deep_message(
            json!({
                "t": {"from": "ts"},
                "w": {"from": "every t.ws"},
                "thing": {"from": "every w.kids"}
            }),
            json!({"ts": [{"ws": [{"id": 1}]}]})
        ),
        json!("kids is missing")
    );
}

#[test]
fn a_name_in_a_child_filter_that_reads_a_grandparent_is_unknown_when_the_parent_is_written_wrong() {
    let r = report(
        &json!({"ts": []}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {
                "t": {"from": "ts"},
                "w": {"from": "every t.ws named by zz"},
                "thing": {"from": "every w.kids whose lo is at least t.cov.x"}
            },
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        }),
        &json!({}),
    );
    let inputs = rows(&r, "$well_formed")[0]["inputs"].clone();
    let listed: Vec<(String, Value)> = inputs
        .as_array()
        .unwrap()
        .iter()
        .filter(|input| {
            input["name"]
                .as_str()
                .is_some_and(|n| n.starts_with("subjects."))
        })
        .map(|input| {
            (
                input["name"].as_str().unwrap().to_string(),
                input["value"].clone(),
            )
        })
        .collect();
    assert_eq!(
        listed,
        [
            ("subjects.w.from".to_string(), json!(["unknown alias zz"])),
            (
                "subjects.thing.from".to_string(),
                json!(["unknown alias $t"])
            ),
        ]
    );
}

#[test]
fn a_name_in_a_child_filter_that_reads_a_grandparent_is_known_when_the_parent_is_fine() {
    let r = report(
        &json!({"ts": []}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {
                "t": {"from": "ts"},
                "w": {"from": "every t.ws"},
                "thing": {"from": "every w.kids whose lo is at least t.cov.x"}
            },
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        }),
        &json!({}),
    );
    assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(true));
}

#[test]
fn a_filter_comparing_two_unusable_sides_names_both() {
    let r = report(
        &json!({"ts": [{"cov": 5, "ws": [{"lo": true}]}]}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {
                "t": {"from": "ts"},
                "thing": {"from": "every t.ws whose lo is at least t.cov.x"}
            },
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        }),
        &json!({}),
    );
    assert_eq!(
        rows(&r, "$applies")[0]["message"],
        json!("t.cov is 5, which isn't an object, and lo is true, which isn't a number")
    );
}

#[test]
fn an_any_of_tags_an_input_with_the_part_that_reads_the_same_path() {
    let r = report(
        &json!({"things": [{"id": "a", "name": 1}]}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "has": {"cv": "name"}}},
            "requirements": {"s": {"subject": "thing", "checks": {
                "c": {"any_of": {"a": "name is 2", "b": "cv is 2"}}
            }}}
        }),
        &json!({}),
    );
    let inputs = rows(&r, "c")[0]["inputs"].clone();
    assert_eq!(
        inputs,
        json!([
            {"name": "cv", "value": 1, "locations": ["/things/0/name"], "part": {"name": "cv", "id": null}},
            {"name": "name", "value": 1, "locations": ["/things/0/name"], "part": {"name": "cv", "id": null}}
        ])
    );
}

#[test]
fn a_from_name_that_is_a_word_of_the_grammar_gets_one_problem() {
    let r = run(
        json!({"p": {"from": "ps"}, "thing": {"from": "every p.ws named by one"}}),
        json!({}),
    );
    let texts: Vec<Value> = rows(&r, "$well_formed")[0]["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|input| input["name"] == json!("subjects.thing.from"))
        .map(|input| input["value"].clone())
        .collect();
    assert_eq!(texts, [json!(["one can't be an alias"])]);
}

fn from_problems_of(from: &str, parent: &str) -> Vec<Value> {
    let r = report(
        &json!({"ts": []}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {
                "t": {"from": "ts"},
                "w": {"from": parent},
                "thing": {"from": from}
            },
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        }),
        &json!({}),
    );
    rows(&r, "$well_formed")[0]["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|input| {
            input["name"]
                .as_str()
                .is_some_and(|n| n.starts_with("subjects."))
        })
        .map(|input| json!([input["name"], input["value"]]))
        .collect()
}

#[test]
fn a_dotted_right_side_reads_the_input_field_so_it_never_names_a_grandparent() {
    let listed = from_problems_of("w.kids whose lo is at least .t.cov.x", "t.ws named by zz");
    assert_eq!(listed, [json!(["subjects.w.from", ["unknown alias zz"]])]);
}

#[test]
fn a_from_line_whose_that_compares_a_field_with_itself_is_written_wrong() {
    assert_eq!(
        from_problems_of("w.kids whose lo is at least lo", "t.ws"),
        [json!([
            "subjects.thing.from",
            ["whose: lo is compared with itself"]
        ])]
    );
}

#[test]
fn a_from_whose_that_reads_the_parent_on_both_sides_is_accepted() {
    for whose in ["t.lo is at least t.lo", "t is t", "t.lo is not t.lo"] {
        assert_eq!(
            from_problems_of(&format!("t.ws whose {whose}"), "t.ws"),
            Vec::<Value>::new(),
            "{whose}"
        );
    }
}

#[test]
fn a_from_whose_that_reads_the_item_field_on_both_sides_is_written_wrong() {
    for (whose, said) in [
        ("t.lo is at most .t.lo", ".t.lo"),
        ("t is .t", ".t"),
        (".t.lo ends with .t.lo", ".t.lo"),
        ("x is x", "x"),
    ] {
        assert_eq!(
            from_problems_of(&format!("t.ws whose {whose}"), "t.ws"),
            [json!([
                "subjects.thing.from",
                [format!("whose: {said} is compared with itself")]
            ])],
            "{whose}"
        );
    }
}

#[test]
fn a_parent_written_wrong_by_comparing_with_itself_blocks_the_grandparent_for_its_child() {
    let listed = from_problems_of(
        "w.kids whose lo is at least t.cov.x",
        "t.ws whose lo is at least lo",
    );
    assert_eq!(
        listed,
        [
            json!(["subjects.w.from", ["whose: lo is compared with itself"]]),
            json!(["subjects.thing.from", ["unknown alias $t"]])
        ]
    );
}

#[test]
fn a_child_blocked_by_an_unknown_grandparent_is_an_invalid_from_in_the_report() {
    let r = report(
        &json!({"ts": []}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {
                "t": {"from": "ts"},
                "w": {"from": "every t.ws whose x is x"},
                "thing": {"from": "every w.kids whose t.lo is more than t.lo"}
            },
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
        }),
        &json!({}),
    );
    assert_eq!(r["subjects"]["thing"]["from"], json!("<invalid from>"));
    assert_eq!(r["subjects"]["w"]["from"], json!("<invalid from>"));
}

fn message_of(check: Value, input: Value, params: Value) -> Value {
    let r = report(
        &input,
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": check}}}
        }),
        &params,
    );
    rows(&r, "c")[0]["message"].clone()
}

#[test]
fn a_for_line_that_reads_params_that_arent_an_object_names_them() {
    let input = json!({"things": [{"id": "t", "ws": [1]}]});
    for check in [
        json!({"for": "every $params as p", "assert": "p.v is 1"}),
        json!({"for": "every $params.v as p", "assert": "p is 1"}),
        json!({"for": "every ws as w", "assert": "w is in $params.v"}),
    ] {
        assert_eq!(
            message_of(check, input.clone(), json!(3)),
            json!("$params is 3, which isn't an object")
        );
    }
}

#[test]
fn a_named_by_or_a_whose_that_reads_params_that_arent_an_object_names_them() {
    let input = json!({"things": [{"id": "t", "x": {"a": 1}, "ws": [{"x": 1}]}]});
    for check in [
        "x named by $params.v is 1",
        "every ws whose x is $params.v is 1",
    ] {
        assert_eq!(
            message_of(json!(check), input.clone(), json!("s")),
            json!("$params is \"s\", which isn't an object")
        );
    }
}

#[test]
fn a_count_whose_whose_reads_params_that_are_a_list_names_them_not_the_digits() {
    assert_eq!(
        message_of(
            json!("count of $params whose v is 1 is 1"),
            json!({"things": [{"id": "t"}]}),
            json!([3])
        ),
        json!("$params is [3], which isn't an object")
    );
}

#[test]
fn a_ref_on_the_right_is_named_after_the_left_side_and_a_subject_field_before_it() {
    let input = json!({"things": [{"id": "t", "zz": "v", "y": 3}], "y": 3});
    assert_eq!(
        message_of(json!("zz contains $params.v"), input.clone(), json!(3)),
        json!("zz is \"v\", which isn't a list, and $params is 3, which isn't an object")
    );
    assert_eq!(
        message_of(json!("zz contains $input.y.v"), input.clone(), json!({})),
        json!("zz is \"v\", which isn't a list, and $input.y is 3, which isn't an object")
    );
    assert_eq!(
        message_of(json!("zz contains y.v"), input, json!({})),
        json!("y is 3, which isn't an object, and zz is \"v\", which isn't a list")
    );
}

#[test]
fn a_key_after_a_position_of_params_holding_a_list_names_the_item() {
    assert_eq!(
        message_of(
            json!("x is in $params[0].v"),
            json!({"things": [{"id": "t", "x": 1}]}),
            json!([[1]])
        ),
        json!("item 1 of $params is [1], which isn't an object")
    );
}

#[test]
fn a_count_through_a_position_names_the_item_once() {
    let input = json!({"things": [{"id": "t", "y": [{"v": 1}]}], "y": [{"v": 1}]});
    assert_eq!(
        message_of(json!("count of y[0].v is 1"), input.clone(), json!({})),
        json!("item 1 of y: v is 1, which isn't a list or an object")
    );
    assert_eq!(
        message_of(json!("count of $input.y[0].v is 1"), input, json!({})),
        json!("item 1 of $input.y: v is 1, which isn't a list or an object")
    );
    assert_eq!(
        message_of(
            json!("count of $params[0].v is 1"),
            json!({"things": [{"id": "t"}]}),
            json!([{"v": 1}])
        ),
        json!("item 1 of $params: v is 1, which isn't a list or an object")
    );
}

fn from_rows(line: &str, params: Value) -> Vec<(String, String, Value)> {
    let r = report(
        &json!({"things": {"k": {"id": "t"}}}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"s": {"from": line}},
            "requirements": {"r": {"subject": "s", "checks": {"c": "id exists"}}}
        }),
        &params,
    );
    r["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["check"] != "$well_formed" && row["check"] != "$unique_ids")
        .map(|row| {
            (
                row["check"].as_str().unwrap().to_string(),
                row["cause"].as_str().unwrap().to_string(),
                row["message"].clone(),
            )
        })
        .collect()
}

fn min_subjects(cause: &str, message: &str) -> Vec<(String, String, Value)> {
    vec![(
        "$min_subjects".to_string(),
        cause.to_string(),
        json!(message),
    )]
}

#[test]
fn a_from_line_that_reads_params_that_arent_an_object_names_the_params_and_not_the_object() {
    for (params, shown) in [
        (json!(3), "3"),
        (json!("s"), "\"s\""),
        (json!(true), "true"),
        (json!([]), "[]"),
        (json!([3]), "[3]"),
        (json!([[1]]), "[[1]]"),
        (json!([{"v": 1}]), "[{\"v\": 1}]"),
        (json!([["k"]]), "[[\"k\"]]"),
    ] {
        let said = format!("$params is {shown}, which isn't an object");
        for line in [
            "things named by each of $params.ks",
            "things named by $params.env named by each of $params.ks",
            "every things named by $params.env",
        ] {
            assert_eq!(
                from_rows(line, params.clone()),
                min_subjects("unusable", &said),
                "{line} with {params}"
            );
        }
    }
}

#[test]
fn a_from_line_that_reads_a_position_of_the_params_names_what_it_found_there() {
    assert_eq!(
        from_rows("things named by each of $params[0]", json!(3)),
        min_subjects("unusable", "$params is 3, which isn't a list")
    );
    assert_eq!(
        from_rows("things named by each of $params[0]", json!([3])),
        min_subjects(
            "unusable",
            "item 1 of $params is 3, which isn't a list of text"
        )
    );
    assert_eq!(
        from_rows("things named by each of $params[0].ks", json!([3])),
        min_subjects("unusable", "item 1 of $params is 3, which isn't an object")
    );
    assert_eq!(
        from_rows("things named by each of $params[0].ks", json!([{"ks": 3}])),
        min_subjects("unusable", "$params[0].ks is 3, which isn't a list of text")
    );
}

#[test]
fn a_from_line_that_reads_the_input_and_params_that_arent_an_object_names_both() {
    assert_eq!(
        from_rows(
            "things named by $input.nope named by each of $params.ks",
            json!(3)
        ),
        min_subjects(
            "unusable",
            "$input.nope is missing; $params is 3, which isn't an object"
        )
    );
}

#[test]
fn a_from_line_makes_no_subjects_from_keys_in_params_that_arent_an_object() {
    assert_eq!(
        from_rows("things named by each of $params[0]", json!([["k"]])),
        min_subjects("unusable", "$params is [[\"k\"]], which isn't an object")
    );
    assert_eq!(
        from_rows(
            "things named by each of $params[0].ks",
            json!([{"ks": ["k"]}])
        ),
        min_subjects(
            "unusable",
            "$params is [{\"ks\": [\"k\"]}], which isn't an object"
        )
    );
}

#[test]
fn a_from_line_that_reads_null_params_says_the_param_is_missing() {
    assert_eq!(
        from_rows("things named by each of $params.ks", Value::Null),
        min_subjects("absent", "$params.ks is missing")
    );
    assert_eq!(
        from_rows("things named by $params.env", Value::Null),
        min_subjects("absent", "$params.env is missing")
    );
}
