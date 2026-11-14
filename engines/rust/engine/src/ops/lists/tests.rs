use super::*;
use crate::path::{Located, Location, Step};
use serde_json::json;
use std::collections::BTreeMap;

fn key_path(start: Start, keys: &[&str]) -> Path {
    Path {
        start,
        steps: keys.iter().map(|k| Step::Key(k.to_string())).collect(),
    }
}

fn x() -> Path {
    key_path(Start::Subject, &["x"])
}

fn on(subject: Value, params: Option<Value>, run: impl Fn(&Ctx) -> Verdict) -> Verdict {
    let input = json!({"things": [subject]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: params.as_ref(),
        aliases: BTreeMap::new(),
    };
    run(&ctx)
}

fn is_in(subject: Value, values: Right, not: bool) -> Cause {
    let check = In {
        path: x(),
        values,
        not,
    };
    on(subject, None, |ctx| run_in(&check, ctx)).cause
}

fn written(values: Value) -> Right {
    Right::Written(values)
}

#[test]
fn in_passes_on_one_of_the_values_by_value() {
    let values = written(json!([1, 2]));
    assert_eq!(
        is_in(
            serde_json::from_str(r#"{"x": 1.0}"#).unwrap(),
            values.clone(),
            false
        ),
        Cause::Satisfied
    );
    assert_eq!(is_in(json!({"x": 3}), values.clone(), false), Cause::Value);
    assert_eq!(is_in(json!({"x": "1"}), values, false), Cause::Unusable);
}

#[test]
fn not_in_passes_on_none_of_the_values_and_on_an_empty_list() {
    let values = written(json!(["prod", "staging"]));
    assert_eq!(
        is_in(json!({"x": "dev"}), values.clone(), true),
        Cause::Satisfied
    );
    assert_eq!(
        is_in(json!({"x": "prod"}), values.clone(), true),
        Cause::Value
    );
    assert_eq!(is_in(json!({"x": 5}), values, true), Cause::Unusable);
    assert_eq!(
        is_in(json!({"x": 5}), written(json!([])), true),
        Cause::Satisfied
    );
    assert_eq!(
        is_in(json!({"x": 5}), written(json!([])), false),
        Cause::Value
    );
}

#[test]
fn a_missing_or_null_field_fails_in_even_when_the_values_hold_null() {
    let values = written(json!(["a", null]));
    assert_eq!(is_in(json!({}), values.clone(), false), Cause::Absent);
    assert_eq!(
        is_in(json!({"x": null}), values.clone(), false),
        Cause::Null
    );
    assert_eq!(is_in(json!({"x": "a"}), values, false), Cause::Satisfied);
}

#[test]
fn values_read_from_a_field_that_are_not_one_list_of_one_type_fail_as_unusable_first() {
    let field = Right::Field(key_path(Start::Subject, &["ys"]));
    assert_eq!(
        is_in(json!({"ys": "a"}), field.clone(), false),
        Cause::Unusable
    );
    assert_eq!(
        is_in(json!({"x": "a", "ys": ["a", 1]}), field.clone(), false),
        Cause::Unusable
    );
    assert_eq!(
        is_in(json!({"ys": ["a", 1]}), field.clone(), false),
        Cause::Unusable
    );
    assert_eq!(
        is_in(json!({"x": "a"}), field.clone(), false),
        Cause::Absent
    );
    assert_eq!(
        is_in(json!({"x": "a", "ys": ["b", "a"]}), field, false),
        Cause::Satisfied
    );
}

#[test]
fn a_field_and_a_ref_on_the_right_are_both_inputs() {
    let field = In {
        path: x(),
        values: Right::Field(key_path(Start::Subject, &["ys"])),
        not: false,
    };
    let names = |v: Verdict| v.inputs.into_iter().map(|i| i.name).collect::<Vec<_>>();
    assert_eq!(
        names(on(json!({"x": "a", "ys": ["a"]}), None, |ctx| run_in(
            &field, ctx
        ))),
        ["x", "ys"]
    );
    let reference = In {
        path: x(),
        values: Right::Ref(key_path(Start::Params, &["k"])),
        not: false,
    };
    let v = on(json!({"x": "a"}), Some(json!({"k": ["a"]})), |ctx| {
        run_in(&reference, ctx)
    });
    assert_eq!(v.cause, Cause::Satisfied);
    assert_eq!(names(v), ["x", "$params.k"]);
}

#[test]
fn a_ref_that_is_missing_or_null_fails_with_its_outcome_whatever_the_field_holds() {
    let check = In {
        path: x(),
        values: Right::Ref(key_path(Start::Params, &["k"])),
        not: false,
    };
    assert_eq!(
        on(json!({}), Some(json!({})), |ctx| run_in(&check, ctx)).cause,
        Cause::Absent
    );
    assert_eq!(
        on(json!({"x": 1}), Some(json!({"k": null})), |ctx| run_in(
            &check, ctx
        ))
        .cause,
        Cause::Null
    );
}

#[test]
fn a_ref_after_in_contains_and_matches_is_listed_after_the_field_whatever_the_cause() {
    let ref_k = || Right::Ref(key_path(Start::Params, &["k"]));
    let names = |v: Verdict| v.inputs.into_iter().map(|i| i.name).collect::<Vec<_>>();
    let subjects_and_params = [
        (json!({"x": "a"}), json!({"k": ["a"]})),
        (json!({"x": "a"}), json!({"k": "text"})),
        (json!({"x": ["a"]}), json!({})),
        (json!({"x": ["a"]}), json!({"k": null})),
        (json!({}), json!({"k": ["a"]})),
        (json!({"x": null}), json!({"k": ["a"]})),
    ];
    for (subject, params) in subjects_and_params {
        let in_check = In {
            path: x(),
            values: ref_k(),
            not: false,
        };
        let contains_check = Contains {
            path: x(),
            wanted: Wanted::All(ref_k()),
            not: false,
        };
        let matches_check = Matches {
            path: x(),
            patterns: ref_k(),
            not: false,
        };
        let verdicts = [
            on(subject.clone(), Some(params.clone()), |ctx| {
                run_in(&in_check, ctx)
            }),
            on(subject.clone(), Some(params.clone()), |ctx| {
                run_contains(&contains_check, ctx)
            }),
            on(subject.clone(), Some(params.clone()), |ctx| {
                run_matches(&matches_check, ctx)
            }),
        ];
        for verdict in verdicts {
            assert_eq!(names(verdict), ["x", "$params.k"]);
        }
    }
}

fn contains(subject: Value, wanted: Wanted, not: bool) -> Cause {
    let check = Contains {
        path: x(),
        wanted,
        not,
    };
    on(subject, None, |ctx| run_contains(&check, ctx)).cause
}

#[test]
fn includes_and_excludes_need_a_list() {
    let one = Wanted::One(written(json!("a")));
    assert_eq!(
        contains(json!({"x": ["b", "a"]}), one.clone(), false),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["b"]}), one.clone(), false),
        Cause::Value
    );
    assert_eq!(contains(json!({"x": []}), one.clone(), false), Cause::Value);
    assert_eq!(
        contains(json!({"x": []}), one.clone(), true),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": "abc"}), one.clone(), false),
        Cause::Unusable
    );
    assert_eq!(
        contains(json!({"x": {"a": "a"}}), one.clone(), false),
        Cause::Unusable
    );
    assert_eq!(contains(json!({}), one.clone(), true), Cause::Absent);
    assert_eq!(contains(json!({"x": null}), one, false), Cause::Null);
}

#[test]
fn items_and_values_of_more_than_one_type_fail_as_unusable_leaving_null_aside() {
    let one = Wanted::One(written(json!(1)));
    assert_eq!(
        contains(json!({"x": ["1", 1]}), one.clone(), false),
        Cause::Unusable
    );
    assert_eq!(
        contains(json!({"x": ["1"]}), one.clone(), false),
        Cause::Unusable
    );
    assert_eq!(
        contains(json!({"x": [1, null]}), one.clone(), false),
        Cause::Satisfied
    );
    assert_eq!(contains(json!({"x": [2]}), one, true), Cause::Satisfied);
}

#[test]
fn contains_all_of_and_none_of_take_every_value() {
    let all = Wanted::All(written(json!(["b", "a"])));
    assert_eq!(
        contains(json!({"x": ["a", "c", "b"]}), all.clone(), false),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["a"]}), all.clone(), false),
        Cause::Value
    );
    assert_eq!(
        contains(json!({"x": ["c"]}), all.clone(), true),
        Cause::Satisfied
    );
    assert_eq!(contains(json!({"x": ["c", "a"]}), all, true), Cause::Value);
}

#[test]
fn contains_a_joined_string_looks_for_the_pieces_put_together() {
    let joined = || {
        Wanted::One(Right::Join(vec![
            written(json!("x")),
            Right::Field(key_path(Start::Subject, &["y"])),
        ]))
    };
    assert_eq!(
        contains(json!({"x": ["x1", "b"], "y": "1"}), joined(), false),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["x1", "b"], "y": "1"}), joined(), true),
        Cause::Value
    );
    assert_eq!(
        contains(json!({"x": ["a"], "y": "1"}), joined(), true),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["a"], "y": 1}), joined(), false),
        Cause::Unusable
    );
    assert_eq!(
        contains(json!({"x": ["a"]}), joined(), false),
        Cause::Absent
    );
    assert_eq!(
        contains(json!({"x": "a", "y": null}), joined(), false),
        Cause::Null
    );
    assert_eq!(
        contains(json!({"x": "a", "y": "1"}), joined(), false),
        Cause::Unusable
    );
}

#[test]
fn contains_some_of_needs_one_value_and_not_all_of_needs_one_missing() {
    let some = Wanted::Some(written(json!(["b", "a"])));
    assert_eq!(
        contains(json!({"x": ["a", "c"]}), some.clone(), false),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["c"]}), some.clone(), false),
        Cause::Value
    );
    assert_eq!(
        contains(json!({"x": []}), some.clone(), false),
        Cause::Value
    );
    assert_eq!(
        contains(json!({"x": ["a", "c"]}), some.clone(), true),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": []}), some.clone(), true),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["b", "a", "c"]}), some, true),
        Cause::Value
    );
}

#[test]
fn contains_some_of_and_not_all_of_never_pass_on_a_field_that_cannot_be_read_as_a_list() {
    let some = Wanted::Some(written(json!(["a"])));
    for not in [false, true] {
        assert_eq!(
            contains(json!({"x": "a"}), some.clone(), not),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": ["a", 1]}), some.clone(), not),
            Cause::Unusable
        );
        assert_eq!(contains(json!({}), some.clone(), not), Cause::Absent);
        assert_eq!(contains(json!({"x": null}), some.clone(), not), Cause::Null);
    }
}

#[test]
fn a_field_of_values_for_contains_some_of_fails_as_unusable_when_empty_or_not_a_list() {
    let field = || Wanted::Some(Right::Field(key_path(Start::Subject, &["ys"])));
    for ys in [json!([]), json!("a"), json!(["a", 1])] {
        for not in [false, true] {
            assert_eq!(
                contains(json!({"x": ["a"], "ys": ys.clone()}), field(), not),
                Cause::Unusable,
                "{ys}"
            );
        }
    }
}

#[test]
fn values_read_as_an_empty_list_a_non_list_or_mixed_types_fail_as_unusable() {
    let field = || Wanted::All(Right::Field(key_path(Start::Subject, &["ys"])));
    for ys in [json!([]), json!("a"), json!(["a", 1])] {
        assert_eq!(
            contains(json!({"x": ["a"], "ys": ys.clone()}), field(), true),
            Cause::Unusable,
            "{ys}"
        );
        assert_eq!(
            contains(json!({"ys": ys.clone()}), field(), false),
            Cause::Unusable,
            "{ys}"
        );
    }
}

#[test]
fn one_value_that_is_a_list_is_looked_for_as_a_list() {
    let one = Wanted::One(Right::Field(key_path(Start::Subject, &["y"])));
    assert_eq!(
        contains(json!({"x": [["a"]], "y": ["a"]}), one.clone(), false),
        Cause::Satisfied
    );
    assert_eq!(
        contains(json!({"x": ["a"], "y": ["a"]}), one, false),
        Cause::Unusable
    );
}

fn matches(text: Value, patterns: Value, not: bool) -> Cause {
    let check = Matches {
        path: x(),
        patterns: written(patterns),
        not,
    };
    on(json!({"x": text}), None, |ctx| run_matches(&check, ctx)).cause
}

#[test]
fn a_pattern_matches_anywhere_unless_anchored() {
    assert_eq!(
        matches(json!("my_svc_x"), json!(["z", "^b", "svc_"]), false),
        Cause::Satisfied
    );
    assert_eq!(matches(json!("a"), json!(["z", "^b"]), false), Cause::Value);
    assert_eq!(matches(json!("bob"), json!(["^b"]), true), Cause::Value);
    assert_eq!(matches(json!("a"), json!(["^b"]), true), Cause::Satisfied);
    assert_eq!(matches(json!("a"), json!([]), false), Cause::Value);
    assert_eq!(matches(json!("a"), json!([]), true), Cause::Satisfied);
}

#[test]
fn matching_works_as_re2_does() {
    assert_eq!(
        matches(json!("a\nb"), json!(["^a.b$"]), false),
        Cause::Value
    );
    assert_eq!(matches(json!("a\n"), json!(["a$"]), false), Cause::Value);
    assert_eq!(
        matches(json!("abc"), json!(["(?i)^A"]), false),
        Cause::Satisfied
    );
    assert_eq!(
        matches(json!("été"), json!([r"^\p{L}+$"]), false),
        Cause::Satisfied
    );
    assert_eq!(
        matches(json!("\u{212a}"), json!(["(?i)^k$"]), false),
        Cause::Satisfied
    );
    assert_eq!(
        matches(json!("a+b"), json!([r"\Qa+b\E"]), false),
        Cause::Satisfied
    );
}

#[test]
fn digit_word_space_and_boundary_classes_are_ascii_as_in_re2() {
    assert_eq!(matches(json!("٣"), json!([r"^\d$"]), false), Cause::Value);
    assert_eq!(matches(json!("٣"), json!([r"^[\d]$"]), false), Cause::Value);
    assert_eq!(
        matches(json!("٣"), json!([r"^\D$"]), false),
        Cause::Satisfied
    );
    assert_eq!(matches(json!("é"), json!([r"^\w$"]), false), Cause::Value);
    assert_eq!(
        matches(json!("\u{b}"), json!([r"^\s$"]), false),
        Cause::Value
    );
    assert_eq!(
        matches(json!("\u{a0}"), json!([r"^\s$"]), false),
        Cause::Value
    );
    assert_eq!(
        matches(json!("aé"), json!([r"a\b"]), false),
        Cause::Satisfied
    );
    assert_eq!(
        matches(json!("é"), json!(["^[[:alpha:]]$"]), false),
        Cause::Value
    );
}

#[test]
fn a_pattern_that_cannot_be_used_fails_as_unusable() {
    assert_eq!(matches(json!("a"), json!(["("]), false), Cause::Unusable);
    assert_eq!(matches(json!("a"), json!([1]), false), Cause::Unusable);
    assert_eq!(matches(json!("a"), json!("a"), false), Cause::Unusable);
    assert_eq!(
        matches(json!("a"), json!(["a", r"a\Z"]), true),
        Cause::Unusable
    );
}

#[test]
fn matching_anything_but_a_string_fails_as_unusable() {
    assert_eq!(matches(json!(1), json!(["1"]), false), Cause::Unusable);
    assert_eq!(matches(json!(["a"]), json!(["a"]), true), Cause::Unusable);
}

#[test]
fn a_whole_ref_is_listed_in_refs_and_a_params_path_with_a_field_step_only_by_its_ref_steps() {
    let k = key_path(Start::Params, &["k"]);
    assert_eq!(Right::Ref(k.clone()).refs(), vec![k.clone()]);
    let named = Path {
        start: Start::Params,
        steps: vec![Step::Key("lists".into()), Step::Ref(Box::new(k.clone()))],
    };
    assert_eq!(Right::Ref(named).refs(), vec![k.clone()]);
    let by_field = Path {
        start: Start::Params,
        steps: vec![
            Step::Key("lists".into()),
            Step::Field(Box::new(key_path(Start::Subject, &["y"]))),
        ],
    };
    assert!(Right::Ref(by_field).refs().is_empty());
    assert!(
        Right::Field(key_path(Start::Subject, &["ys"]))
            .refs()
            .is_empty()
    );
    assert!(written(json!(["a"])).refs().is_empty());
}

#[test]
fn a_piece_of_a_join_from_the_params_is_in_refs_with_the_ref_steps_of_the_others() {
    let k = key_path(Start::Params, &["k"]);
    let y = key_path(Start::Params, &["x", "y"]);
    let named = Path {
        start: Start::Subject,
        steps: vec![Step::Key("m".into()), Step::Ref(Box::new(k.clone()))],
    };
    let join = Right::Join(vec![
        Right::Field(key_path(Start::Subject, &["v"])),
        Right::Ref(y.clone()),
        Right::Field(named),
        written(json!("-")),
    ]);
    assert_eq!(join.refs(), vec![y.clone(), k]);
    assert_eq!(join.ref_paths(), vec![&y]);
}

fn lowered(sentence: &str) -> Option<Result<Check, Vec<String>>> {
    let check = tree::parse_check(sentence).unwrap();
    match &check.assertions[0] {
        tree::Assertion::Plain { path, phrase } => {
            lower_phrase(path, phrase, &Scope::new().on_subject())
        }
        other => panic!("{sentence} isn't a plain assertion: {other:?}"),
    }
}

fn lowered_check(sentence: &str) -> Check {
    lowered(sentence).unwrap().unwrap()
}

#[test]
fn one_of_reads_into_in_with_written_values_a_ref_or_a_field() {
    match lowered_check("x is not one of \"a\", \"b\"") {
        Check::In(c) => {
            assert!(c.not);
            assert_eq!(c.values, written(json!(["a", "b"])));
        }
        other => panic!("{other:?}"),
    }
    assert!(matches!(
        lowered_check("x is in $params.k"),
        Check::In(In {
            values: Right::Ref(_),
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x is in $input.k"),
        Check::In(In {
            values: Right::Ref(_),
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x is in ys"),
        Check::In(In {
            values: Right::Field(_),
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x is in $params.lists named by $params.k"),
        Check::In(In {
            values: Right::Ref(_),
            ..
        })
    ));
}

#[test]
fn each_contains_phrase_reads_into_contains() {
    for (sentence, all, not) in [
        ("x contains \"a\"", false, false),
        ("x does not contain $params.v", false, true),
        ("x contains all of \"a\", \"b\"", true, false),
        ("x contains none of ys", true, true),
    ] {
        match lowered_check(sentence) {
            Check::Contains(c) => {
                assert_eq!(matches!(c.wanted, Wanted::All(_)), all, "{sentence}");
                assert_eq!(c.not, not, "{sentence}");
            }
            other => panic!("{sentence}: {other:?}"),
        }
    }
}

#[test]
fn contains_some_of_and_does_not_contain_all_of_read_into_contains_some() {
    for (sentence, not) in [
        ("x contains some of \"a\", \"b\"", false),
        ("x does not contain all of ys", true),
    ] {
        match lowered_check(sentence) {
            Check::Contains(c) => {
                assert!(matches!(c.wanted, Wanted::Some(_)), "{sentence}");
                assert_eq!(c.not, not, "{sentence}");
            }
            other => panic!("{sentence}: {other:?}"),
        }
    }
}

#[test]
fn is_not_a_type_and_is_not_a_non_empty_string_read_into_their_checks() {
    assert!(matches!(
        lowered_check("x is not a list"),
        Check::HasType(HasType {
            kind: Kind::List,
            not: true,
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x is not an object"),
        Check::HasType(HasType {
            kind: Kind::Object,
            not: true,
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x is not a non-empty string"),
        Check::NonEmptyString(NonEmptyString { not: true, .. })
    ));
}

#[test]
fn matches_type_non_empty_string_and_empty_read_into_their_checks() {
    assert!(matches!(
        lowered_check("x does not match \"^a\""),
        Check::Matches(Matches { not: true, .. })
    ));
    assert!(matches!(
        lowered_check("x is an object"),
        Check::HasType(HasType {
            kind: Kind::Object,
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x is a non-empty string"),
        Check::NonEmptyString(_)
    ));
    assert!(matches!(
        lowered_check("x is not empty"),
        Check::Empty(Empty { not: true, .. })
    ));
}

#[test]
fn a_phrase_compare_reads_or_a_count_on_the_right_is_not_read_here() {
    for sentence in [
        "x is 1",
        "x is at least 2",
        "x exists",
        "x contains count of ys",
    ] {
        assert!(lowered(sentence).is_none(), "{sentence}");
    }
}

#[test]
fn written_values_of_mixed_types_are_written_wrong_leaving_null_aside() {
    for sentence in [
        "x is one of \"a\", 1",
        "x is not one of true, 1e2",
        "x contains all of true, 1",
        "x contains none of \"a\", false",
    ] {
        assert_eq!(
            lowered(sentence).unwrap().unwrap_err(),
            ["values of mixed types"],
            "{sentence}"
        );
    }
    assert!(lowered("x is one of \"a\", null").unwrap().is_ok());
    assert!(lowered("x contains all of 1, 2").unwrap().is_ok());
}

fn flawed_with(check: &Check, params: Value) -> bool {
    let input = json!({"things": [{"x": "a"}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    check.flawed(&ctx)
}

#[test]
fn a_ref_that_reads_the_wrong_kind_of_value_is_a_flaw_and_a_missing_one_is_not() {
    let in_list = lowered_check("x is in $params.l");
    assert!(flawed_with(&in_list, json!({"l": "a"})));
    assert!(flawed_with(&in_list, json!({"l": ["a", 1]})));
    assert!(!flawed_with(&in_list, json!({"l": []})));
    assert!(!flawed_with(&in_list, json!({"l": ["a"]})));
    assert!(!flawed_with(&in_list, json!({})));
    assert!(!flawed_with(&in_list, json!({"l": null})));
    let all = lowered_check("x contains all of $params.l");
    assert!(flawed_with(&all, json!({"l": []})));
    assert!(flawed_with(&all, json!({"l": "a"})));
    assert!(!flawed_with(&all, json!({"l": ["a"]})));
    let one = lowered_check("x contains $params.v");
    assert!(!flawed_with(&one, json!({"v": [1, "a"]})));
    let patterns = lowered_check("x matches $params.p");
    assert!(flawed_with(&patterns, json!({"p": ["("]})));
    assert!(flawed_with(&patterns, json!({"p": "a"})));
    assert!(!flawed_with(&patterns, json!({"p": ["^a"]})));
}

#[test]
fn a_written_list_or_a_field_on_the_right_is_never_a_flaw() {
    assert!(!flawed_with(
        &lowered_check("x is one of \"a\", \"b\""),
        json!({})
    ));
    assert!(!flawed_with(&lowered_check("x is in ys"), json!({})));
}

fn deps_name() -> Right {
    Right::Field(key_path(Start::Subject, &["deps", "name"]))
}

fn params_deps_name() -> Right {
    Right::Ref(key_path(Start::Params, &["deps", "name"]))
}

fn with_deps(deps: Value) -> Value {
    json!({"x": "click", "deps": deps})
}

#[test]
fn a_field_that_walks_a_list_of_objects_compares_with_what_it_reads_from_each_item() {
    let deps = json!([{"name": "click"}, {"name": "jinja2"}]);
    assert_eq!(
        is_in(with_deps(deps.clone()), deps_name(), false),
        Cause::Satisfied
    );
    assert_eq!(
        is_in(json!({"x": "attrs", "deps": deps}), deps_name(), false),
        Cause::Value
    );
}

#[test]
fn a_walk_fails_every_row_as_absent_when_an_item_has_no_value() {
    let deps = json!([{"name": "click"}, {}]);
    assert_eq!(
        is_in(with_deps(deps.clone()), deps_name(), false),
        Cause::Absent
    );
    assert_eq!(is_in(with_deps(deps), deps_name(), true), Cause::Absent);
}

#[test]
fn a_walk_fails_as_null_when_an_item_has_a_null_value() {
    let deps = json!([{"name": null}]);
    assert_eq!(is_in(with_deps(deps), deps_name(), false), Cause::Null);
}

#[test]
fn a_walk_fails_as_value_when_the_list_is_empty_even_after_is_not_in() {
    assert_eq!(is_in(with_deps(json!([])), deps_name(), true), Cause::Value);
    assert_eq!(
        is_in(with_deps(json!([])), deps_name(), false),
        Cause::Value
    );
}

#[test]
fn a_walk_fails_as_unusable_when_an_item_is_not_an_object_or_the_values_have_more_than_one_type() {
    assert_eq!(
        is_in(with_deps(json!(["click"])), deps_name(), false),
        Cause::Unusable
    );
    assert_eq!(
        is_in(
            with_deps(json!([{"name": "click"}, {"name": 3}])),
            deps_name(),
            false
        ),
        Cause::Unusable
    );
}

#[test]
fn a_path_that_meets_no_list_is_read_as_before() {
    assert_eq!(
        is_in(with_deps(json!("text")), deps_name(), false),
        Cause::Unusable
    );
    assert_eq!(
        is_in(with_deps(json!(null)), deps_name(), false),
        Cause::Null
    );
    assert_eq!(
        is_in(json!({"x": "click"}), deps_name(), false),
        Cause::Absent
    );
}

#[test]
fn a_ref_that_walks_a_list_of_objects_reads_the_params_the_same_way() {
    let check = In {
        path: x(),
        values: params_deps_name(),
        not: false,
    };
    let params = Some(json!({"deps": [{"name": "click"}, {"name": "jinja2"}]}));
    assert_eq!(
        on(json!({"x": "click"}), params.clone(), |ctx| run_in(
            &check, ctx
        ))
        .cause,
        Cause::Satisfied
    );
    assert_eq!(
        on(json!({"x": "attrs"}), params, |ctx| run_in(&check, ctx)).cause,
        Cause::Value
    );
    assert_eq!(
        on(
            json!({"x": "click"}),
            Some(json!({"deps": [{"name": "click"}, {}]})),
            |ctx| run_in(&check, ctx)
        )
        .cause,
        Cause::Absent
    );
}

#[test]
fn a_walk_names_the_path_with_brackets_and_lists_where_each_value_was_read() {
    let input = json!({"things": [with_deps(json!([{"name": "click"}, {}]))]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let walk = walked(&key_path(Start::Subject, &["deps", "name"]), &ctx).unwrap();
    assert_eq!(walk.name, "deps[].name");
    assert_eq!(walk.value, vec![json!("click"), Value::Null]);
    assert_eq!(
        walk.locations,
        vec!["/things/0/deps/0/name", "/things/0/deps/1"]
    );
    assert_eq!(walk.cause, Some(Cause::Absent));
    assert_eq!(walk.text, "item 2 of deps: name is missing");
}

fn position_walk(w: Value) -> Walked {
    steps_walk(w, vec![Step::Index(0)])
}

fn steps_walk(w: Value, after_x: Vec<Step>) -> Walked {
    let input = json!({"things": [{"x": "a", "w": w}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let mut steps = vec![Step::Key("w".into()), Step::Key("X".into())];
    steps.extend(after_x);
    let path = Path {
        start: Start::Subject,
        steps,
    };
    walked(&path, &ctx).unwrap()
}

#[test]
fn a_position_on_a_value_that_is_not_a_list_fails_as_unusable_and_names_the_value() {
    for (held, shown) in [
        (json!("ab"), "\"ab\""),
        (json!(3), "3"),
        (json!({"y": 1}), "{\"y\": 1}"),
        (json!(true), "true"),
    ] {
        let walk = position_walk(json!([{"X": ["a"]}, {"X": held}]));
        assert_eq!(walk.cause, Some(Cause::Unusable));
        assert_eq!(
            walk.text,
            format!("item 2 of w: X is {shown}, which isn't a list")
        );
    }
}

#[test]
fn a_position_on_a_missing_or_null_value_fails_as_absent_like_the_rego_engine() {
    for held in [json!({}), json!({"X": null})] {
        let walk = position_walk(json!([{"X": ["a"]}, held]));
        assert_eq!(walk.cause, Some(Cause::Absent));
        assert_eq!(walk.text, "item 2 of w: item 1 of X is missing");
    }
}

#[test]
fn a_position_on_lists_in_every_item_walks_without_a_fault() {
    let walk = position_walk(json!([{"X": ["a"]}, {"X": ["b"]}]));
    assert_eq!(walk.cause, None);
}

#[test]
fn a_position_after_a_position_fails_as_unusable_and_names_the_value_that_is_not_a_list() {
    let steps = || vec![Step::Index(0), Step::Index(0)];
    let walk = steps_walk(json!([{"X": [["a"]]}, {"X": ["x"]}]), steps());
    assert_eq!(walk.cause, Some(Cause::Unusable));
    assert_eq!(
        walk.text,
        "item 2 of w: item 1 of X is \"x\", which isn't a list"
    );
    let walk = steps_walk(json!([{"X": [["a"]]}, {"X": "x"}]), steps());
    assert_eq!(walk.cause, Some(Cause::Unusable));
    assert_eq!(walk.text, "item 2 of w: X is \"x\", which isn't a list");
    let walk = steps_walk(json!([{"X": [["a"]]}, {"X": [["b"]]}]), steps());
    assert_eq!(walk.cause, None);
}

#[test]
fn a_key_after_a_position_fails_as_unusable_when_another_item_holds_no_object_there() {
    let key = |name: &str| Step::Key(name.into());
    let walk = steps_walk(
        json!([{"X": [{"k": ["a"]}]}, {"X": ["x"]}]),
        vec![Step::Index(0), key("k")],
    );
    assert_eq!(walk.cause, Some(Cause::Unusable));
    let walk = steps_walk(
        json!([{"X": [{"k": [["a"]]}]}, {"X": [{"k": "s"}]}]),
        vec![Step::Index(0), key("k"), Step::Index(0)],
    );
    assert_eq!(walk.cause, Some(Cause::Unusable));
    let walk = steps_walk(
        json!([{"X": [{"k": ["a"]}]}, {"X": [{"k": ["b"]}]}]),
        vec![Step::Index(0), key("k")],
    );
    assert_eq!(walk.cause, None);
}
