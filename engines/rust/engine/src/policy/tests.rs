use super::*;
use serde_json::json;

fn read(policy: Value) -> Policy {
    Policy::read(&policy)
}

fn requirement_problems(policy: Value, name: &str) -> Vec<(String, Vec<String>)> {
    read(policy).requirements[name]
        .problems
        .iter()
        .map(|(n, p)| (n.clone(), p.iter().cloned().collect()))
        .collect()
}

fn problem(name: &str, texts: &[&str]) -> (String, Vec<String>) {
    (
        name.to_string(),
        texts.iter().map(|t| t.to_string()).collect(),
    )
}

fn one(requirement: Value) -> Value {
    json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things"}},
        "requirements": {"s": requirement}
    })
}

fn valid() -> Value {
    json!({"subject": "thing", "checks": {"c": "x exists"}})
}

#[test]
fn a_policy_that_is_written_right_has_no_problem() {
    let policy = read(one(valid()));
    assert!(policy.problems.is_empty());
    assert!(policy.requirements["s"].problems.is_empty());
}

#[test]
fn a_policy_that_is_not_an_object_has_no_requirement() {
    for policy in [json!(null), json!([]), json!("x"), json!(1)] {
        assert!(read(policy).requirements.is_empty());
    }
}

#[test]
fn requirements_that_are_not_an_object_leave_no_requirement() {
    let policy = read(json!({"ergo_spec": SPEC, "requirements": [1]}));
    assert!(policy.requirements.is_empty());
}

#[test]
fn requirements_are_read_in_name_order() {
    let policy = read(json!({"requirements": {"b": {}, "a": {}, "B": {}}}));
    let names: Vec<_> = policy.requirements.keys().cloned().collect();
    assert_eq!(names, ["B", "a", "b"]);
}

#[test]
fn a_missing_ergo_spec_is_missing() {
    let mut policy = one(valid());
    policy.as_object_mut().unwrap().remove("ergo_spec");
    assert_eq!(
        read(policy).problems,
        Problems::from([(
            "policy ergo_spec".to_string(),
            BTreeSet::from(["missing".to_string()])
        )])
    );
}

fn spec_problems(ergo_spec: Value) -> Vec<String> {
    let mut policy = one(valid());
    policy["ergo_spec"] = ergo_spec;
    read(policy)
        .problems
        .get("policy ergo_spec")
        .map(|p| p.iter().cloned().collect())
        .unwrap_or_default()
}

#[test]
fn ergo_spec_is_checked_as_policy_version_says() {
    assert_eq!(spec_problems(json!(null)), ["missing"]);
    assert_eq!(spec_problems(json!(0.1)), ["not a string"]);
    assert_eq!(spec_problems(json!(true)), ["not a string"]);
    assert_eq!(spec_problems(json!("V0.1")), ["not a version V0.1"]);
    assert_eq!(
        spec_problems(json!("v0.2-beta")),
        ["not a version v0.2-beta"]
    );
    assert_eq!(spec_problems(json!("v0.2-")), ["not a version v0.2-"]);
    assert_eq!(
        spec_problems(json!("v0.4-dev.1")),
        ["not a version v0.4-dev.1"]
    );
    assert_eq!(spec_problems(json!("v.2")), ["not a version v.2"]);
    assert_eq!(spec_problems(json!("")), ["not a version "]);
    assert_eq!(
        spec_problems(json!("v0.1")),
        [format!("unsupported version v0.1, expected {SPEC}")]
    );
    assert_eq!(
        spec_problems(json!("v0.2")),
        [format!("unsupported version v0.2, expected {SPEC}")]
    );
    assert_eq!(
        spec_problems(json!("v0.3-dev")),
        [format!("unsupported version v0.3-dev, expected {SPEC}")]
    );
    assert_eq!(
        spec_problems(json!("v9.9")),
        [format!("unsupported version v9.9, expected {SPEC}")]
    );
    assert!(spec_problems(json!(SPEC)).is_empty());
}

#[test]
fn an_ergo_spec_of_arabic_indic_digits_is_not_a_version() {
    assert_eq!(spec_problems(json!("v٠.٢")), ["not a version v٠.٢"]);
}

#[test]
fn policy_description_and_meta_take_text_and_an_object_or_null() {
    for (description, meta, bad) in [
        (json!(5), json!({}), true),
        (json!(null), json!(null), false),
        (json!("d"), json!({"k": 1}), false),
        (json!(null), json!("DEV"), true),
        (json!([]), json!([]), true),
    ] {
        let mut policy = one(valid());
        policy["description"] = description;
        policy["meta"] = meta;
        assert_eq!(!read(policy).problems.is_empty(), bad);
    }
}

#[test]
fn policy_problems_are_named_in_words_and_listed_by_name() {
    let mut policy = one(valid());
    policy["description"] = json!(5);
    policy["meta"] = json!("DEV");
    policy["ergo_spec"] = json!(1);
    let read = read(policy);
    let names: Vec<_> = read.problems.keys().cloned().collect();
    assert_eq!(
        names,
        ["policy description", "policy ergo_spec", "policy meta"]
    );
    assert_eq!(read.description, "");
    assert_eq!(read.meta, json!({}));
}

#[test]
fn policy_description_and_meta_are_kept_when_right() {
    let mut policy = one(valid());
    policy["description"] = json!("Every item has an x");
    policy["meta"] = json!({"control": "DEV-0401"});
    let read = read(policy);
    assert_eq!(read.description, "Every item has an x");
    assert_eq!(read.meta, json!({"control": "DEV-0401"}));
}

#[test]
fn a_requirement_with_no_subject_says_missing() {
    assert_eq!(
        requirement_problems(one(json!({"checks": {"c": "x exists"}})), "s"),
        [problem("subject", &["missing"])]
    );
}

#[test]
fn a_subject_that_is_not_in_subjects_says_so() {
    assert_eq!(
        requirement_problems(
            one(json!({"subject": "thng", "checks": {"c": "x exists"}})),
            "s"
        ),
        [problem("subject", &["not in subjects"])]
    );
    let policy = json!({"ergo_spec": SPEC, "requirements": {"s": valid()}});
    assert_eq!(
        requirement_problems(policy, "s"),
        [problem("subject", &["not in subjects"])]
    );
}

#[test]
fn a_subject_that_is_blank_or_not_a_string_says_empty_or_not_a_string() {
    for subject in [
        json!(""),
        json!(" "),
        json!(null),
        json!(5),
        json!(["thing"]),
    ] {
        assert_eq!(
            requirement_problems(one(json!({"subject": subject, "checks": {"c": "x"}})), "s"),
            [problem("subject", &["empty or not a string"])]
        );
    }
}

#[test]
fn subjects_that_are_not_an_object_fail_every_requirement_that_names_one() {
    for subjects in [json!(null), json!("thing"), json!(["thing"]), json!(1)] {
        let policy =
            json!({"ergo_spec": SPEC, "subjects": subjects, "requirements": {"s": valid()}});
        assert_eq!(
            requirement_problems(policy, "s"),
            [problem("subjects", &["not an object"])]
        );
    }
}

#[test]
fn a_subject_that_is_not_an_object_fails_the_requirements_that_name_it() {
    for def in [json!("things"), json!([]), json!(1), json!(true)] {
        let policy =
            json!({"ergo_spec": SPEC, "subjects": {"thing": def}, "requirements": {"s": valid()}});
        assert_eq!(
            requirement_problems(policy, "s"),
            [problem("subjects.thing", &["not an object"])]
        );
    }
}

#[test]
fn a_subject_with_nothing_under_it_is_read_without_problems() {
    let policy =
        json!({"ergo_spec": SPEC, "subjects": {"thing": null}, "requirements": {"s": valid()}});
    let read = read(policy);
    assert!(read.requirements["s"].problems.is_empty());
    let def = read.subject("thing").unwrap().def.as_ref().unwrap();
    assert_eq!(def.from, Text::Missing);
    assert_eq!(def.identified_by, Text::Missing);
}

#[test]
fn the_problems_of_a_subject_nobody_names_are_left_out() {
    let policy = json!({"ergo_spec": SPEC, "subjects": {"thing": {"from": "t"}, "bad": {"from": 5}}, "requirements": {"s": valid()}});
    assert!(read(policy).requirements["s"].problems.is_empty());
}

#[test]
fn a_subject_called_it_is_written_right_like_any_other_name() {
    let policy = json!({"ergo_spec": SPEC, "subjects": {"it": {"from": "t"}}, "requirements": {"s": {"subject": "it", "checks": {"c": "x"}}}});
    assert!(requirement_problems(policy, "s").is_empty());
}

#[test]
fn subject_fields_of_the_wrong_type_are_not_a_string() {
    let policy = json!({"ergo_spec": SPEC, "subjects": {"thing": {"from": 5, "identified_by": ["id"], "description": 5}}, "requirements": {"s": valid()}});
    assert_eq!(
        requirement_problems(policy, "s"),
        [
            problem("subjects.thing.description", &["not a string"]),
            problem("subjects.thing.from", &["not a string"]),
            problem("subjects.thing.identified_by", &["not a string"]),
        ]
    );
}

#[test]
fn a_null_from_is_not_a_string() {
    let policy = json!({"ergo_spec": SPEC, "subjects": {"thing": {"from": null}}, "requirements": {"s": valid()}});
    assert_eq!(
        requirement_problems(policy, "s"),
        [problem("subjects.thing.from", &["not a string"])]
    );
}

#[test]
fn a_subject_field_it_does_not_take_is_unknown_and_quoted_when_the_name_needs_it() {
    let policy = json!({"ergo_spec": SPEC, "subjects": {"pull request": {"from": "t", "applies_to": {}, "id": ["id"]}}, "requirements": {"s": {"subject": "pull request", "checks": {"c": "x"}}}});
    assert_eq!(
        requirement_problems(policy, "s"),
        [
            problem("subjects.\"pull request\".applies_to", &["unknown field"]),
            problem("subjects.\"pull request\".id", &["unknown field"]),
        ]
    );
}

fn has_problems(has: Value) -> Vec<(String, Vec<String>)> {
    let policy = json!({"ergo_spec": SPEC, "subjects": {"round": {"from": "t", "has": has}}, "requirements": {"s": {"subject": "round", "checks": {"c": "x"}}}});
    requirement_problems(policy, "s")
}

#[test]
fn has_that_is_not_an_object_is_listed_under_has() {
    for has in [json!("x"), json!([]), json!(null), json!(1)] {
        assert_eq!(
            has_problems(has),
            [problem("subjects.round.has", &["not an object"])]
        );
    }
}

#[test]
fn parts_written_as_a_string_or_an_object_have_no_shape_problem() {
    assert!(
        has_problems(json!({
            "a": "x.y",
            "b": {"from": "x"},
            "c": {"from": "x", "identified_by": "id"}
        }))
        .is_empty()
    );
}

#[test]
fn a_part_that_is_neither_a_string_nor_an_object_says_so() {
    for part in [json!(1), json!(null), json!([]), json!(true)] {
        assert_eq!(
            has_problems(json!({"a": part})),
            [problem(
                "subjects.round.has.a",
                &["not a string or an object"]
            )]
        );
    }
}

#[test]
fn a_part_object_is_checked_field_by_field() {
    assert_eq!(
        has_problems(json!({
            "no_from": {"identified_by": "id"},
            "extra": {"from": "x", "zz": 1},
            "wrong_from": {"from": 5},
            "wrong_id": {"from": "x", "identified_by": null}
        })),
        [
            problem("subjects.round.has.extra", &["unknown field zz"]),
            problem("subjects.round.has.no_from", &["missing from"]),
            problem("subjects.round.has.wrong_from", &["invalid from"]),
            problem("subjects.round.has.wrong_id", &["invalid identified_by"]),
        ]
    );
}

#[test]
fn a_part_with_several_things_wrong_lists_them_sorted() {
    assert_eq!(
        has_problems(json!({"a": {"from": 1, "identified_by": 2, "zz": 3}})),
        [problem(
            "subjects.round.has.a",
            &["invalid from", "invalid identified_by", "unknown field zz"]
        )]
    );
}

#[test]
fn parts_keep_what_was_written() {
    let policy = read(
        json!({"ergo_spec": SPEC, "subjects": {"round": {"from": "t", "has": {
            "a": "x.y", "b": {"from": "x", "identified_by": "id"}, "c": 1
        }}}}),
    );
    let Has::Parts(parts) = &policy.subject("round").unwrap().def.as_ref().unwrap().has else {
        panic!("no parts")
    };
    assert_eq!(
        parts["a"],
        Part {
            from: Text::Written("x.y".to_string()),
            identified_by: Text::Missing
        }
    );
    assert_eq!(
        parts["b"],
        Part {
            from: Text::Written("x".to_string()),
            identified_by: Text::Written("id".to_string())
        }
    );
    assert_eq!(
        parts["c"],
        Part {
            from: Text::Invalid,
            identified_by: Text::Missing
        }
    );
}

#[test]
fn require_takes_every_or_some_and_is_every_by_default() {
    let req = |r: Value| {
        let mut v = valid();
        v["require"] = r;
        requirement_problems(one(v), "s")
    };
    assert!(req(json!("every")).is_empty());
    assert!(req(json!("some")).is_empty());
    for bad in [
        json!("most"),
        json!(null),
        json!(1),
        json!(["some"]),
        json!("Every"),
    ] {
        assert_eq!(req(bad), [problem("require", &["neither every nor some"])]);
    }
    let read = read(one(valid()));
    assert_eq!(read.requirements["s"].require, json!("every"));
}

#[test]
fn a_wrong_require_is_kept_as_written() {
    let mut v = valid();
    v["require"] = json!("most");
    assert_eq!(read(one(v)).requirements["s"].require, json!("most"));
}

#[test]
fn min_subjects_is_a_whole_number_from_zero_to_a_million_and_one_by_default() {
    let min = |m: Value| {
        let mut v = valid();
        v["min_subjects"] = m;
        read(one(v)).requirements["s"].clone()
    };
    assert_eq!(read(one(valid())).requirements["s"].min_subjects_count, 1);
    for (good, count) in [
        (json!(0), 0),
        (json!(2), 2),
        (json!(3.0), 3),
        (json!(1e2), 100),
        (json!(1000000), 1000000),
        (serde_json::from_str::<Value>("1e6").unwrap(), 1000000),
        (serde_json::from_str::<Value>("1.0e6").unwrap(), 1000000),
        (serde_json::from_str::<Value>("1000000.0").unwrap(), 1000000),
    ] {
        let r = min(good);
        assert!(r.problems.is_empty());
        assert_eq!(r.min_subjects_count, count);
    }
    for bad in [
        json!(-1),
        json!(1.5),
        json!(1000001),
        serde_json::from_str::<Value>("1e308").unwrap(),
        serde_json::from_str::<Value>("1000000.5").unwrap(),
        json!("1"),
        json!(null),
        json!(true),
        json!([1]),
    ] {
        let r = min(bad.clone());
        assert_eq!(
            r.problems
                .get("min_subjects")
                .map(|p| p.iter().cloned().collect::<Vec<_>>()),
            Some(vec!["not a whole number from 0 to 1000000".to_string()]),
            "{bad}"
        );
        assert_eq!(r.min_subjects, bad);
    }
}

#[test]
fn a_min_subjects_with_more_than_15_significant_digits_is_written_wrong() {
    for text in [
        "9007199254740993",
        "1.0000000000000000001",
        "5.000000000000000000001",
    ] {
        let mut v = valid();
        v["min_subjects"] = serde_json::from_str(text).unwrap();
        let r = read(one(v)).requirements["s"].clone();
        assert_eq!(
            r.problems
                .get("min_subjects")
                .map(|p| p.iter().cloned().collect::<Vec<_>>()),
            Some(vec![
                "number with more than 15 significant digits".to_string()
            ]),
            "{text}"
        );
    }
}

#[test]
fn a_min_subjects_past_a_float_is_written_wrong_as_out_of_range() {
    for text in ["1e400", "1e-400", "-1e400", "1e0400", "0.00000001e400"] {
        let mut v = valid();
        v["min_subjects"] = serde_json::from_str(text).unwrap();
        let r = read(one(v)).requirements["s"].clone();
        assert_eq!(
            r.problems
                .get("min_subjects")
                .map(|p| p.iter().cloned().collect::<Vec<_>>()),
            Some(vec!["number out of range".to_string()]),
            "{text}"
        );
    }
}

#[test]
fn checks_that_are_missing_empty_or_not_an_object_are_listed_under_checks() {
    assert_eq!(
        requirement_problems(one(json!({"subject": "thing"})), "s"),
        [problem("checks", &["missing"])]
    );
    assert_eq!(
        requirement_problems(one(json!({"subject": "thing", "checks": {}})), "s"),
        [problem("checks", &["empty"])]
    );
    for checks in [json!([]), json!("x"), json!(null), json!(1)] {
        assert_eq!(
            requirement_problems(one(json!({"subject": "thing", "checks": checks})), "s"),
            [problem("checks", &["not an object"])]
        );
    }
}

#[test]
fn the_checks_count_is_zero_unless_checks_is_an_object() {
    assert_eq!(read(one(valid())).requirements["s"].checks_count, 1);
    let r = read(one(json!({"subject": "thing", "checks": "x"})));
    assert_eq!(r.requirements["s"].checks_count, 0);
}

#[test]
fn a_field_the_requirement_does_not_take_is_unknown_under_its_own_name() {
    let mut v = valid();
    v["requires"] = json!("x");
    v["from"] = json!("t");
    v["a b"] = json!(1);
    assert_eq!(
        requirement_problems(one(v), "s"),
        [
            problem("\"a b\"", &["unknown field"]),
            problem("from", &["unknown field"]),
            problem("requires", &["unknown field"]),
        ]
    );
}

#[test]
fn requirement_description_and_meta_take_text_and_an_object_or_null() {
    let mut v = valid();
    v["description"] = json!(5);
    v["meta"] = json!("x");
    assert_eq!(
        requirement_problems(one(v.clone()), "s"),
        [
            problem("description", &["not a string"]),
            problem("meta", &["not an object"]),
        ]
    );
    let r = read(one(v));
    assert_eq!(r.requirements["s"].description, "");
    assert_eq!(r.requirements["s"].meta, json!({}));
    let mut v = valid();
    v["description"] = json!(null);
    v["meta"] = json!(null);
    assert!(requirement_problems(one(v), "s").is_empty());
}

#[test]
fn requirement_description_and_meta_are_kept_when_right() {
    let mut v = valid();
    v["description"] = json!("Every deployment is approved");
    v["meta"] = json!({"control": "C-1", "v": 1.5});
    let r = read(one(v)).requirements["s"].clone();
    assert_eq!(r.description, "Every deployment is approved");
    assert_eq!(r.meta, json!({"control": "C-1", "v": 1.5}));
}

#[test]
fn a_requirement_that_is_not_an_object_keeps_what_was_written() {
    for req in [json!("x"), json!(null), json!([1]), json!(5)] {
        let read = read(one(req.clone()));
        let r = &read.requirements["s"];
        assert_eq!(r.not_an_object, Some(req));
        assert_eq!(r.checks_count, 0);
        assert_eq!(r.require, json!("every"));
    }
}

#[test]
fn checks_named_like_ergos_own_rows_are_reserved() {
    let policy = one(json!({"subject": "thing", "checks": {
        "$well_formed": "x is 2", "$min_subjects": "x is 2", "$unique_ids": "x is 2", "$applies": "x is 2", "$other": "x is 2"
    }}));
    assert_eq!(
        requirement_problems(policy, "s"),
        [
            problem("checks.$applies", &["a name can't start with $"]),
            problem("checks.$min_subjects", &["a name can't start with $"]),
            problem("checks.$other", &["a name can't start with $"]),
            problem("checks.$unique_ids", &["a name can't start with $"]),
            problem("checks.$well_formed", &["a name can't start with $"]),
        ]
    );
}

#[test]
fn a_check_with_an_empty_name_is_written_wrong_and_quoted() {
    let policy = one(json!({"subject": "thing", "checks": {"": "x is 2"}}));
    assert_eq!(
        requirement_problems(policy, "s"),
        [problem("checks.\"\"", &["a name can't be empty"])]
    );
}

#[test]
fn a_reserved_check_that_is_also_written_wrong_lists_both_sorted() {
    let policy = one(json!({"subject": "thing", "checks": {"$unique_ids": {"op": "x"}}}));
    assert_eq!(
        requirement_problems(policy, "s"),
        [problem(
            "checks.$unique_ids",
            &[
                "a name can't start with $",
                "missing assert",
                "unknown field op"
            ]
        )]
    );
}

#[test]
fn a_check_name_that_is_not_a_plain_key_is_quoted() {
    let policy = one(json!({"subject": "thing", "checks": {"a b": 5, "ok-1": 5, "1x": 5}}));
    let names: Vec<_> = requirement_problems(policy, "s")
        .into_iter()
        .map(|(n, _)| n)
        .collect();
    assert_eq!(names, ["checks.\"1x\"", "checks.\"a b\"", "checks.ok-1"]);
}

fn check_problems(check: Value) -> Vec<String> {
    read_check(&check).problems.into_iter().collect()
}

#[test]
fn a_check_that_is_a_string_or_a_proper_object_has_no_problem() {
    for check in [
        json!("x exists"),
        json!({"assert": "x exists"}),
        json!({"assert": ["x exists", "y exists"], "description": "d", "meta": {"k": 1}}),
        json!({"assert": "x exists", "for": "every xs as x"}),
        json!({"any_of": {"a": "x exists", "b": ["y exists"]}, "description": null, "meta": null}),
    ] {
        assert!(check_problems(check.clone()).is_empty(), "{check}");
    }
}

#[test]
fn a_check_object_with_op_is_missing_assert_and_has_unknown_fields() {
    assert_eq!(
        check_problems(json!({"op": "present", "path": ["x"]})),
        ["missing assert", "unknown field op", "unknown field path"]
    );
    assert_eq!(
        read_check(&json!({"op": "present"})).form,
        Form::MissingAssert
    );
}

#[test]
fn an_assert_check_with_another_field_has_an_unknown_field() {
    assert_eq!(
        check_problems(json!({"assert": "x", "zz": 1, "any_of": {"a": "x"}})),
        ["unknown field any_of", "unknown field zz"]
    );
}

#[test]
fn an_assert_that_is_not_a_string_or_a_list_of_strings_is_invalid() {
    for assert in [
        json!(5),
        json!(null),
        json!({"a": 1}),
        json!([1]),
        json!(["x", null]),
    ] {
        assert_eq!(
            check_problems(json!({"assert": assert})),
            ["invalid assert"]
        );
    }
    assert_eq!(check_problems(json!({"assert": []})), ["empty assert"]);
}

#[test]
fn a_for_that_is_not_a_string_is_invalid() {
    assert_eq!(
        check_problems(json!({"assert": "x", "for": 5})),
        ["invalid for"]
    );
}

#[test]
fn a_check_that_is_neither_a_string_nor_an_object_is_invalid() {
    for check in [json!(5), json!(null), json!([]), json!(true)] {
        assert_eq!(check_problems(check.clone()), ["invalid check"]);
        assert_eq!(read_check(&check).form, Form::Invalid);
    }
}

#[test]
fn a_check_description_and_meta_of_the_wrong_type_are_invalid() {
    assert_eq!(
        check_problems(json!({"assert": "x", "description": 5, "meta": "m"})),
        ["invalid description", "invalid meta"]
    );
    let check = read_check(&json!({"assert": "x", "description": 5, "meta": "m"}));
    assert_eq!(check.description, "");
    assert_eq!(check.meta, json!({}));
}

#[test]
fn a_number_out_of_range_or_too_long_in_meta_is_written_wrong_at_every_level() {
    let meta: Value =
        serde_json::from_str(r#"{"a": [1e400], "b": {"c": 1234567890.1209567890}, "d": 1.5}"#)
            .unwrap();
    let both = [
        "number out of range",
        "number with more than 15 significant digits",
    ];
    assert_eq!(
        check_problems(json!({"assert": "x", "meta": meta.clone()})),
        both
    );
    assert_eq!(
        read_check(&json!({"assert": "x", "meta": meta.clone()})).meta,
        json!({})
    );
    let mut v = valid();
    v["meta"] = meta.clone();
    assert_eq!(
        requirement_problems(one(v.clone()), "s"),
        [problem("meta", &both)]
    );
    assert_eq!(
        read(one(v)).requirements["s"].meta,
        json!({}),
        "a requirement meta written wrong is reported as {{}}"
    );
    let mut policy = one(valid());
    policy["meta"] = meta;
    let read_policy = read(policy);
    assert_eq!(
        read_policy.problems["policy meta"],
        BTreeSet::from(both.map(String::from))
    );
    assert_eq!(read_policy.meta, json!({}));
}

#[test]
fn a_check_keeps_its_description_and_meta() {
    let check = read_check(&json!({"assert": "x", "description": "Approved", "meta": {"k": 1}}));
    assert_eq!(check.description, "Approved");
    assert_eq!(check.meta, json!({"k": 1}));
}

#[test]
fn any_of_is_checked_option_by_option() {
    assert_eq!(check_problems(json!({"any_of": []})), ["invalid any_of"]);
    assert_eq!(check_problems(json!({"any_of": "x"})), ["invalid any_of"]);
    assert_eq!(check_problems(json!({"any_of": {}})), ["empty any_of"]);
    assert_eq!(
        check_problems(json!({"any_of": {"a": [], "b": 5, "c": ["x", 1], "d": null, "e": "x"}})),
        [
            "empty option a",
            "invalid option b",
            "invalid option c",
            "invalid option d"
        ]
    );
    assert_eq!(
        check_problems(json!({"any_of": {"a": "x"}, "for": "every xs as x", "zz": 1})),
        ["unknown field for", "unknown field zz"]
    );
}

#[test]
fn an_any_of_that_is_an_object_without_an_any_of_key_is_not_one() {
    assert_eq!(
        read_check(&json!({"description": "d"})).form,
        Form::MissingAssert
    );
}

#[test]
fn subject_of_finds_the_named_subject_only() {
    let policy = read(one(valid()));
    let req = &policy.requirements["s"];
    assert_eq!(policy.subject_of(req).map(|(n, _)| n), Some("thing"));
    let policy = read(one(json!({"subject": "nope", "checks": {"c": "x"}})));
    assert!(policy.subject_of(&policy.requirements["s"]).is_none());
}

#[test]
fn problems_merge_by_name_and_keep_their_texts_sorted() {
    let mut a = Problems::new();
    add_problem(&mut a, "x".to_string(), "b");
    let mut b = Problems::new();
    add_problem(&mut b, "x".to_string(), "a");
    add_problem(&mut b, "w".to_string(), "c");
    merge_problems(&mut a, &b);
    assert_eq!(
        a,
        Problems::from([
            ("w".to_string(), BTreeSet::from(["c".to_string()])),
            (
                "x".to_string(),
                BTreeSet::from(["a".to_string(), "b".to_string()])
            ),
        ])
    );
}

#[test]
fn field_names_quote_keys_that_are_not_plain() {
    assert_eq!(field_name(&["checks", "c"]), "checks.c");
    assert_eq!(field_name(&["checks", "$applies"]), "checks.$applies");
    assert_eq!(
        field_name(&["subjects", "pull request", "from"]),
        "subjects.\"pull request\".from"
    );
    assert_eq!(field_name(&["a\"b"]), "\"a\\\"b\"");
    assert_eq!(field_name(&[""]), "\"\"");
    assert_eq!(field_name(&["x-1", "_y"]), "x-1._y");
}
