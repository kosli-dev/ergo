use super::*;
use crate::path::{Located, Location, Start, Step};
use serde_json::json;
use std::collections::BTreeMap;

fn field(name: &str) -> Side {
    Side::Path(Path {
        start: Start::Subject,
        steps: vec![Step::Key(name.to_string())],
    })
}

fn check(cmp: Cmp, right: Side) -> Compare {
    Compare {
        left: field("a"),
        right,
        cmp,
        within: None,
    }
}

fn number(text: &str) -> Number {
    match serde_json::from_str::<Value>(text).unwrap() {
        Value::Number(n) => n,
        _ => panic!("{text} isn't a number"),
    }
}

fn run_on(subject: Value, check: &Compare) -> Verdict {
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
        params: None,
        aliases: BTreeMap::new(),
    };
    run(check, &ctx)
}

fn cause(subject: Value, check: &Compare) -> Cause {
    run_on(subject, check).cause
}

fn parsed(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

#[test]
fn eq_compares_by_value() {
    let eq = check(Cmp::Eq, field("b"));
    assert_eq!(
        cause(parsed(r#"{"a": 1, "b": 1.0}"#), &eq),
        Cause::Satisfied
    );
    assert_eq!(
        cause(parsed(r#"{"a": {"n": 1}, "b": {"n": 1.0}}"#), &eq),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": 1, "b": 2}), &eq), Cause::Value);
}

#[test]
fn eq_and_ne_fail_as_unusable_when_the_types_differ() {
    for cmp in [Cmp::Eq, Cmp::Ne] {
        assert_eq!(
            cause(json!({"a": "1", "b": 1}), &check(cmp, field("b"))),
            Cause::Unusable
        );
    }
}

#[test]
fn ne_passes_on_different_values_of_one_type() {
    assert_eq!(
        cause(json!({"a": "x", "b": "y"}), &check(Cmp::Ne, field("b"))),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "x", "b": "x"}), &check(Cmp::Ne, field("b"))),
        Cause::Value
    );
}

#[test]
fn two_null_fields_fail_as_null_even_with_eq() {
    assert_eq!(
        cause(json!({"a": null, "b": null}), &check(Cmp::Eq, field("b"))),
        Cause::Null
    );
}

#[test]
fn the_worse_outcome_of_the_two_sides_wins() {
    let eq = check(Cmp::Eq, field("b"));
    assert_eq!(cause(json!({"b": null}), &eq), Cause::Absent);
    assert_eq!(cause(json!({"a": null}), &eq), Cause::Absent);
    assert_eq!(
        cause(
            json!({"a": {"x": 1}, "b": "s"}),
            &check(
                Cmp::Eq,
                Side::Path(Path {
                    start: Start::Subject,
                    steps: vec![Step::Key("b".into()), Step::Key("c".into())],
                })
            )
        ),
        Cause::Unusable
    );
}

#[test]
fn order_only_works_on_two_numbers() {
    let lt = check(Cmp::Lt, field("b"));
    assert_eq!(cause(json!({"a": 1, "b": 2}), &lt), Cause::Satisfied);
    assert_eq!(cause(json!({"a": 2, "b": 1}), &lt), Cause::Value);
    assert_eq!(cause(json!({"a": "80", "b": "9"}), &lt), Cause::Unusable);
    assert_eq!(cause(json!({"a": false, "b": true}), &lt), Cause::Unusable);
    assert_eq!(
        cause(json!({"a": {"n": 1}, "b": {"o": 1}}), &lt),
        Cause::Unusable
    );
    assert_eq!(cause(json!({"a": 1, "b": "2"}), &lt), Cause::Unusable);
}

#[test]
fn each_order_cmp_compares_by_value() {
    let subject = parsed(r#"{"a": 2, "b": 2.0, "c": 3}"#);
    let to_b = |cmp| cause(subject.clone(), &check(cmp, field("b")));
    let to_c = |cmp| cause(subject.clone(), &check(cmp, field("c")));
    assert_eq!(to_b(Cmp::Gte), Cause::Satisfied);
    assert_eq!(to_b(Cmp::Lte), Cause::Satisfied);
    assert_eq!(to_b(Cmp::Gt), Cause::Value);
    assert_eq!(to_b(Cmp::Lt), Cause::Value);
    assert_eq!(to_c(Cmp::Lt), Cause::Satisfied);
    assert_eq!(to_c(Cmp::Gt), Cause::Value);
}

#[test]
fn a_written_value_on_the_right_has_no_input() {
    let v = run_on(json!({"a": 6}), &check(Cmp::Gte, Side::Value(json!(5))));
    assert_eq!(v.cause, Cause::Satisfied);
    assert_eq!(v.inputs.len(), 1);
    assert_eq!(v.inputs[0].name, ".a");
}

#[test]
fn inputs_are_left_then_right() {
    let v = run_on(json!({"a": 1, "b": 2}), &check(Cmp::Lt, field("b")));
    let names: Vec<_> = v.inputs.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, [".a", "b"]);
    assert_eq!(v.inputs[0].locations, ["/things/0/a"]);
}

#[test]
fn a_missing_side_still_has_its_input() {
    let v = run_on(json!({"b": 5}), &check(Cmp::Lt, field("b")));
    assert_eq!(v.cause, Cause::Absent);
    assert_eq!(v.inputs[0].value, Value::Null);
    assert_eq!(v.inputs[0].locations, ["/things/0"]);
}

#[test]
fn starts_with_and_ends_with_take_two_strings() {
    let starts = check(Cmp::StartsWith, field("b"));
    let ends = check(Cmp::EndsWith, field("b"));
    assert_eq!(
        cause(json!({"a": "release/1", "b": "release/"}), &starts),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "main", "b": "release/"}), &starts),
        Cause::Value
    );
    assert_eq!(
        cause(json!({"a": "a.md", "b": ".md"}), &ends),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": 12, "b": 1}), &starts), Cause::Unusable);
    assert_eq!(cause(json!({"a": "1", "b": 1}), &ends), Cause::Unusable);
}

#[test]
fn does_not_start_with_and_does_not_end_with_pass_only_on_two_strings() {
    let starts = check(Cmp::NotStartsWith, field("b"));
    let ends = check(Cmp::NotEndsWith, field("b"));
    assert_eq!(
        cause(json!({"a": "main", "b": "release/"}), &starts),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "release/1", "b": "release/"}), &starts),
        Cause::Value
    );
    assert_eq!(
        cause(json!({"a": "a.txt", "b": ".md"}), &ends),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": "a.md", "b": ".md"}), &ends), Cause::Value);
    assert_eq!(cause(json!({"a": 12, "b": 1}), &starts), Cause::Unusable);
    assert_eq!(cause(json!({"a": "1", "b": 1}), &ends), Cause::Unusable);
    assert_eq!(cause(json!({"b": "r"}), &starts), Cause::Absent);
    assert_eq!(cause(json!({"a": null, "b": "r"}), &ends), Cause::Null);
    assert_eq!(cause(json!({"a": "x"}), &ends), Cause::Absent);
}

#[test]
fn alphabetical_on_or_before_and_on_or_after_include_equal_strings() {
    let before = check(Cmp::AlphabeticallyOnOrBefore, field("b"));
    let after = check(Cmp::AlphabeticallyOnOrAfter, field("b"));
    assert_eq!(
        cause(json!({"a": "m", "b": "m"}), &before),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": "m", "b": "m"}), &after), Cause::Satisfied);
    assert_eq!(
        cause(json!({"a": "a", "b": "b"}), &before),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": "a", "b": "b"}), &after), Cause::Value);
    assert_eq!(
        cause(json!({"a": "Z", "b": "a"}), &before),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": "b", "b": "a"}), &before), Cause::Value);
    assert_eq!(cause(json!({"a": 1, "b": 2}), &after), Cause::Unusable);
    assert_eq!(cause(json!({"b": "a"}), &before), Cause::Absent);
    assert_eq!(cause(json!({"a": null, "b": "a"}), &after), Cause::Null);
}

#[test]
fn ne_with_within_passes_only_on_numbers_further_apart() {
    let far = Compare {
        left: field("a"),
        right: field("b"),
        cmp: Cmp::Ne,
        within: Some(number("1")),
    };
    assert_eq!(cause(json!({"a": 1, "b": 5}), &far), Cause::Satisfied);
    assert_eq!(cause(json!({"a": 1, "b": 2}), &far), Cause::Value);
    assert_eq!(cause(json!({"a": 1, "b": 1.5}), &far), Cause::Value);
    assert_eq!(
        cause(
            json!({"a": 0.3, "b": 0.1}),
            &Compare {
                within: Some(number("0.2")),
                ..far.clone()
            }
        ),
        Cause::Value
    );
    assert_eq!(cause(json!({"a": 1, "b": "1"}), &far), Cause::Unusable);
    assert_eq!(cause(json!({"a": "1", "b": "9"}), &far), Cause::Unusable);
    assert_eq!(cause(json!({"a": 1}), &far), Cause::Absent);
    assert_eq!(cause(json!({"a": null, "b": 1}), &far), Cause::Null);
}

fn joined(pieces: Vec<Side>) -> Side {
    Side::Join(pieces)
}

#[test]
fn a_join_puts_its_pieces_next_to_each_other_in_order() {
    let right = joined(vec![Side::Value(json!("x")), field("b"), field("c")]);
    let eq = check(Cmp::Eq, right);
    assert_eq!(
        cause(json!({"a": "x1.2-dev", "b": "1.2", "c": "-dev"}), &eq),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "x1.2", "b": "1.2", "c": "-dev"}), &eq),
        Cause::Value
    );
    let v = run_on(json!({"a": "x", "b": "1", "c": "2"}), &eq);
    let names: Vec<_> = v.inputs.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, [".a", "b", "c"]);
}

#[test]
fn a_join_fails_as_the_first_piece_that_cannot_be_read_whatever_the_left_side_is() {
    let eq = check(
        Cmp::Eq,
        joined(vec![Side::Value(json!("x")), field("b"), field("c")]),
    );
    assert_eq!(cause(json!({"a": "x", "c": null}), &eq), Cause::Absent);
    assert_eq!(cause(json!({"a": "x", "b": null}), &eq), Cause::Null);
    assert_eq!(cause(json!({"a": "x", "b": 1}), &eq), Cause::Unusable);
    assert_eq!(
        cause(json!({"a": "x", "b": 1, "c": null}), &eq),
        Cause::Unusable
    );
    assert_eq!(
        cause(json!({"a": "x", "b": null, "c": 1}), &eq),
        Cause::Null
    );
    assert_eq!(cause(json!({"b": 1, "c": "z"}), &eq), Cause::Unusable);
    assert_eq!(
        cause(json!({"a": null, "b": "1", "c": "2"}), &eq),
        Cause::Null
    );
    assert_eq!(cause(json!({"b": "1", "c": "2"}), &eq), Cause::Absent);
    assert_eq!(
        cause(json!({"a": 3, "b": "1", "c": "2"}), &eq),
        Cause::Unusable
    );
}

#[test]
fn a_join_after_a_text_comparison_joins_before_it_compares() {
    let starts = check(
        Cmp::StartsWith,
        joined(vec![Side::Value(json!("re")), field("b")]),
    );
    assert_eq!(
        cause(json!({"a": "release/1", "b": "lease/"}), &starts),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "main", "b": "lease/"}), &starts),
        Cause::Value
    );
}

#[test]
fn alphabetical_order_is_by_code_point() {
    let before = check(Cmp::AlphabeticallyBefore, field("b"));
    let after = check(Cmp::AlphabeticallyAfter, field("b"));
    assert_eq!(
        cause(json!({"a": "Zoe", "b": "adam"}), &before),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "\u{ff01}", "b": "\u{1f600}"}), &before),
        Cause::Satisfied
    );
    assert_eq!(
        cause(json!({"a": "\u{1f600}", "b": "\u{ff01}"}), &after),
        Cause::Satisfied
    );
    assert_eq!(cause(json!({"a": "x", "b": "x"}), &before), Cause::Value);
    assert_eq!(cause(json!({"a": "x", "b": "x"}), &after), Cause::Value);
    assert_eq!(cause(json!({"a": 1, "b": 2}), &before), Cause::Unusable);
}

#[test]
fn within_passes_on_numbers_at_most_that_far_apart() {
    let near = |a: &str, b: &str, w: &str| {
        let c = Compare {
            left: field("a"),
            right: Side::Value(parsed(b)),
            cmp: Cmp::Eq,
            within: Some(number(w)),
        };
        cause(json!({"a": parsed(a)}), &c)
    };
    assert_eq!(near("1.4", "1", "0.5"), Cause::Satisfied);
    assert_eq!(near("1.5", "1", "0.5"), Cause::Satisfied);
    assert_eq!(near("0.5", "1", "0.5"), Cause::Satisfied);
    assert_eq!(near("1.6", "1", "0.5"), Cause::Value);
    assert_eq!(near("0.3", "0.1", "0.2"), Cause::Satisfied);
    assert_eq!(near("-1", "1", "2"), Cause::Satisfied);
    assert_eq!(near("-1", "1", "1.9"), Cause::Value);
    assert_eq!(near("1e2", "99", "1"), Cause::Satisfied);
    assert_eq!(near("5", "5", "0"), Cause::Satisfied);
}

#[test]
fn within_fails_as_unusable_when_the_numbers_are_too_far_apart_to_work_out_exactly() {
    let c = Compare {
        left: field("a"),
        right: Side::Value(parsed("1e-9000")),
        cmp: Cmp::Eq,
        within: Some(number("1")),
    };
    assert_eq!(cause(json!({"a": parsed("1e9000")}), &c), Cause::Unusable);
    assert_eq!(cause(json!({"a": parsed("0.5")}), &c), Cause::Unusable);
}

#[test]
fn within_fails_as_unusable_on_anything_but_two_numbers() {
    let c = Compare {
        left: field("a"),
        right: field("b"),
        cmp: Cmp::Eq,
        within: Some(number("1")),
    };
    assert_eq!(cause(json!({"a": "1", "b": 1}), &c), Cause::Unusable);
    assert_eq!(cause(json!({"a": "1", "b": "1"}), &c), Cause::Unusable);
    assert_eq!(cause(json!({"b": 1}), &c), Cause::Absent);
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
fn is_with_a_written_value_reads_into_equals() {
    assert!(
        matches!(lowered_check("x is \"a\""), Check::Equals(Equals { value, .. }) if value == json!("a"))
    );
    assert!(matches!(
        lowered_check("x is null"),
        Check::Equals(Equals {
            value: Value::Null,
            ..
        })
    ));
}

#[test]
fn is_not_with_a_written_value_reads_into_compare_ne() {
    assert!(matches!(
        lowered_check("x is not 1"),
        Check::Compare(Compare {
            cmp: Cmp::Ne,
            right: Side::Value(_),
            within: None,
            ..
        })
    ));
}

#[test]
fn within_reads_into_compare_eq_with_the_distance() {
    match lowered_check("x is 5 within 0.5") {
        Check::Compare(c) => {
            assert_eq!(c.cmp, Cmp::Eq);
            assert_eq!(c.within.map(|n| n.to_string()), Some("0.5".to_string()));
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn is_not_with_within_reads_into_compare_ne_with_the_distance() {
    match lowered_check("x is not 5 within 0.5") {
        Check::Compare(c) => {
            assert_eq!(c.cmp, Cmp::Ne);
            assert_eq!(c.within.map(|n| n.to_string()), Some("0.5".to_string()));
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_field_on_the_right_reads_into_compare_with_two_paths() {
    assert!(matches!(
        lowered_check("x equals y"),
        Check::Compare(Compare {
            cmp: Cmp::Eq,
            right: Side::Path(_),
            ..
        })
    ));
    assert!(matches!(
        lowered_check("x does not equal y"),
        Check::Compare(Compare {
            cmp: Cmp::Ne,
            right: Side::Path(_),
            ..
        })
    ));
}

#[test]
fn each_order_phrase_reads_into_its_cmp() {
    for (sentence, cmp) in [
        ("x is at least 1", Cmp::Gte),
        ("x is at most 1", Cmp::Lte),
        ("x is more than 1", Cmp::Gt),
        ("x is less than 1", Cmp::Lt),
        ("x starts with \"a\"", Cmp::StartsWith),
        ("x ends with \"a\"", Cmp::EndsWith),
        ("x does not start with \"a\"", Cmp::NotStartsWith),
        ("x does not end with \"a\"", Cmp::NotEndsWith),
        (
            "x is alphabetically on or before \"a\"",
            Cmp::AlphabeticallyOnOrBefore,
        ),
        (
            "x is alphabetically on or after \"a\"",
            Cmp::AlphabeticallyOnOrAfter,
        ),
        (
            "x is alphabetically before \"a\"",
            Cmp::AlphabeticallyBefore,
        ),
        ("x is alphabetically after \"a\"", Cmp::AlphabeticallyAfter),
    ] {
        match lowered_check(sentence) {
            Check::Compare(c) => assert_eq!(c.cmp, cmp, "{sentence}"),
            other => panic!("{sentence}: {other:?}"),
        }
    }
}

#[test]
fn between_reads_into_range() {
    match lowered_check("x is between 1.5 and 20") {
        Check::Range(r) => {
            assert_eq!(r.min.to_string(), "1.5");
            assert_eq!(r.max.to_string(), "20");
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn each_time_phrase_reads_into_compare_time() {
    for (sentence, order) in [
        ("x is before y", Order::Before),
        ("x is after y", Order::After),
        ("x is on or before \"2024-01-01\"", Order::OnOrBefore),
        ("x is on or after 3", Order::OnOrAfter),
    ] {
        match lowered_check(sentence) {
            Check::CompareTime(c) => assert_eq!(c.order, order, "{sentence}"),
            other => panic!("{sentence}: {other:?}"),
        }
    }
}

#[test]
fn a_phrase_that_is_not_one_of_these_is_left_to_another_operator() {
    for sentence in [
        "x exists",
        "x is empty",
        "x is a string",
        "x is one of 1, 2",
        "x contains 1",
        "x matches \"a\"",
    ] {
        assert!(lowered(sentence).is_none(), "{sentence}");
    }
}

#[test]
fn a_count_sum_plus_or_elapsed_on_the_right_is_left_to_tally() {
    for sentence in [
        "x is at least count of ys",
        "x is at most y plus 1",
        "x is less than days elapsed from p to q",
    ] {
        assert!(lowered(sentence).is_none(), "{sentence}");
    }
}

#[test]
fn a_path_scope_rejects_on_either_side_is_written_wrong() {
    for sentence in [
        "x is less than item 9007199254740993 of y",
        "item 9007199254740993 of x is at least 1",
    ] {
        let problems = lowered(sentence).unwrap().unwrap_err();
        assert_eq!(problems.len(), 1, "{sentence}");
        assert!(
            problems[0].ends_with("can't be a list position"),
            "{sentence}: {problems:?}"
        );
    }
    assert!(lowered("x is at least $params.y").unwrap().is_ok());
}

#[test]
fn a_compare_or_tally_side_is_never_a_ref_itself_but_its_named_by_refs_are() {
    use crate::ops::tally::{Derived, Tally, Term, Test};
    let key = |k: &str| Step::Key(k.to_string());
    let i = Path {
        start: Start::Params,
        steps: vec![key("i")],
    };
    let named = Path {
        start: Start::Subject,
        steps: vec![key("z"), Step::Ref(Box::new(i.clone()))],
    };
    let params_hi = Path {
        start: Start::Params,
        steps: vec![key("hi")],
    };
    let compare = |right: Path| {
        Check::Compare(Compare {
            left: field("n"),
            right: Side::Path(right),
            cmp: Cmp::Lte,
            within: None,
        })
    };
    assert!(compare(params_hi.clone()).refs().is_empty());
    assert_eq!(compare(named.clone()).refs(), vec![i.clone()]);
    let tally = Check::Tally(Tally {
        left: crate::ops::tally::Side::Plain(field("n")),
        right: Some(crate::ops::tally::Side::Derived(Derived {
            text: String::new(),
            terms: vec![Term::Path(params_hi), Term::Path(named)],
        })),
        test: Test::Compare {
            cmp: Cmp::Eq,
            within: None,
        },
    });
    assert_eq!(tally.refs(), vec![i]);
}
