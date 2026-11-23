use super::*;
use crate::SPEC;
use crate::ops::clause::{self, Clause};
use crate::path::{Located, Location, Start, Step};
use serde_json::json;
use std::collections::BTreeMap;

fn lowered(sentence: &str) -> Check {
    let tree = s::parse_check(sentence).unwrap();
    crate::lower::lower_assertion(&tree.assertions[0], &Scope::new()).unwrap()
}

#[test]
fn a_count_of_or_a_sum_of_reads_its_lists_by_item_and_a_plain_check_doesnt() {
    for sentence in [
        "count of rs whose v is \"a\" is 1",
        "count of rs.v that is \"a\" is 1",
        "count of xs.m named by $input.k is 1",
        "sum of rs.n is 1",
        "every rs.v is \"a\"",
        "some rs whose v is \"a\" exists",
    ] {
        assert!(lowered(sentence).reads_by_item(), "{sentence}");
    }
    for sentence in [
        "k is $input.m named by $params.k",
        "k is m named by $input.k",
        "tags contains $input.m named by $params.k",
        "ts is after $input.ts",
        "x plus y is 3",
    ] {
        assert!(!lowered(sentence).reads_by_item(), "{sentence}");
    }
}

#[test]
fn a_tally_lists_the_refs_inside_ref_steps_but_not_a_side_that_is_a_ref() {
    let names: Vec<String> = lowered("x plus y named by $params.k is $params.limit")
        .refs()
        .iter()
        .map(crate::name::name)
        .collect();
    assert_eq!(names, vec!["$params.k"]);
}

#[test]
fn a_tally_reads_every_path_of_its_terms() {
    let check = lowered("days elapsed from x to y plus w is 1");
    assert_eq!(check.paths().len(), 3);
}

fn verdict_of(sentence: &str, subject: Value) -> Verdict {
    verdict_on_input(sentence, json!({"things": [subject]}))
}

fn verdict_on_input(sentence: &str, input: Value) -> Verdict {
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    crate::ops::run(&lowered(sentence), &ctx)
}

fn cause(sentence: &str, subject: Value) -> Cause {
    verdict_of(sentence, subject).cause
}

fn entries(sentence: &str, subject: Value) -> Vec<Value> {
    entries_on_input(sentence, json!({"things": [subject]}))
}

fn entries_on_input(sentence: &str, input: Value) -> Vec<Value> {
    verdict_on_input(sentence, input)
        .inputs
        .iter()
        .map(Input::to_json)
        .collect()
}

fn number(text: &str) -> Number {
    text.parse().unwrap()
}

fn sum_text(texts: &[&str]) -> String {
    let numbers: Vec<Number> = texts.iter().map(|t| number(t)).collect();
    add(&numbers).unwrap().to_string()
}

fn days(from: Value, to: Value, wanted: &str) -> Cause {
    cause(
        &format!("days elapsed from x to y is {wanted}"),
        json!({"x": from, "y": to}),
    )
}

#[test]
fn thirty_six_hours_is_one_and_a_half_days() {
    assert_eq!(
        days(
            json!("2026-10-01T00:00:00Z"),
            json!("2026-10-02T12:00:00Z"),
            "1.5"
        ),
        Cause::Satisfied
    );
}

#[test]
fn one_second_is_rounded_down_to_eleven_millionths_of_a_day() {
    assert_eq!(
        days(
            json!("2026-10-01T00:00:00Z"),
            json!("2026-10-01T00:00:01Z"),
            "0.000011"
        ),
        Cause::Satisfied
    );
    assert_eq!(
        days(
            json!("2026-10-01T00:00:00Z"),
            json!("2026-10-01T00:00:01Z"),
            "0.000012"
        ),
        Cause::Value
    );
}

#[test]
fn two_equal_times_are_zero_apart() {
    assert_eq!(
        days(json!("2026-10-01"), json!("2026-10-01"), "0"),
        Cause::Satisfied
    );
}

#[test]
fn units_are_one_sixty_thirty_six_hundred_and_so_on_seconds() {
    let subject = json!({"x": 0, "y": 1209600});
    for (sentence, wanted) in [
        ("seconds", "1209600"),
        ("minutes", "20160"),
        ("hours", "336"),
        ("days", "14"),
        ("weeks", "2"),
    ] {
        assert_eq!(
            cause(
                &format!("{sentence} elapsed from x to y is {wanted}"),
                subject.clone()
            ),
            Cause::Satisfied,
            "{sentence}"
        );
    }
}

#[test]
fn offsets_move_the_instant_they_name() {
    assert_eq!(
        days(
            json!("2026-10-01T00:00:00+02:00"),
            json!("2026-10-01T00:00:00Z"),
            "0.083333"
        ),
        Cause::Satisfied
    );
    assert_eq!(
        days(
            json!("2026-10-01T05:30:00-04:00"),
            json!("2026-10-01T09:30:00.5Z"),
            "0.000005"
        ),
        Cause::Satisfied
    );
}

#[test]
fn a_fraction_past_nine_digits_is_cut_off() {
    assert_eq!(
        cause(
            "seconds elapsed from x to y is 1",
            json!({"x": "2026-10-01T00:00:00.1234567899Z", "y": "2026-10-01T00:00:01.1234567890Z"})
        ),
        Cause::Satisfied
    );
}

#[test]
fn two_dates_are_whole_days_apart() {
    assert_eq!(
        days(json!("2026-10-01"), json!("2026-10-08"), "7"),
        Cause::Satisfied
    );
    assert_eq!(
        days(json!("2026-02-28"), json!("2026-03-01"), "1"),
        Cause::Satisfied
    );
}

#[test]
fn two_numbers_are_seconds_rounded_to_the_nearest_microsecond() {
    assert_eq!(days(json!(100), json!(129700), "1.5"), Cause::Satisfied);
    assert_eq!(
        cause(
            "seconds elapsed from x to y is 0.000001",
            json!({"x": 0, "y": 0.0000014})
        ),
        Cause::Satisfied
    );
    assert_eq!(
        cause(
            "seconds elapsed from x to y is 0.000002",
            json!({"x": 0, "y": 0.0000015})
        ),
        Cause::Satisfied
    );
    assert_eq!(
        cause(
            "seconds elapsed from x to y is 0",
            json!({"x": 0.0000004, "y": 0})
        ),
        Cause::Satisfied
    );
}

#[test]
fn numbers_from_minus_nine_billion_to_nine_billion_are_times() {
    assert_eq!(
        cause(
            "seconds elapsed from x to y is 18000000000",
            json!({"x": -9000000000i64, "y": 9000000000i64})
        ),
        Cause::Satisfied
    );
}

#[test]
fn a_number_past_either_edge_is_unusable() {
    assert_eq!(
        days(json!(9000000001i64), json!(9000000001i64), "0"),
        Cause::Unusable
    );
    assert_eq!(days(json!(-9000000001i64), json!(0), "0"), Cause::Unusable);
    assert_eq!(
        days(json!(0), json!(1700000000000i64), "0"),
        Cause::Unusable
    );
}

#[test]
fn the_end_before_the_start_fails_as_value_and_shows_no_number() {
    let sentence = "days elapsed from x to y is at most 5";
    let subject = json!({"x": "2026-01-02T00:00:00Z", "y": "2026-01-01T00:00:00Z"});
    assert_eq!(cause(sentence, subject.clone()), Cause::Value);
    assert_eq!(entries(sentence, subject)[0]["value"], Value::Null);
    assert_eq!(cause(sentence, json!({"x": 5, "y": 4})), Cause::Value);
    assert_eq!(
        cause(sentence, json!({"x": "2026-01-02", "y": "2026-01-01"})),
        Cause::Value
    );
}

#[test]
fn times_in_different_formats_are_unusable() {
    let pairs = [
        (json!("2026-10-01"), json!("2026-10-01T00:00:00Z")),
        (json!("2026-10-01T00:00:00Z"), json!("2026-10-01")),
        (json!(0), json!("2026-10-01")),
        (json!("2026-10-01T00:00:00Z"), json!(5)),
    ];
    for (x, y) in pairs {
        assert_eq!(days(x, y, "0"), Cause::Unusable);
    }
}

#[test]
fn things_that_are_not_times_are_unusable() {
    let pairs = [
        (json!("yesterday"), json!("today")),
        (json!(true), json!(true)),
        (json!([1]), json!([1])),
        (json!({}), json!({})),
        (json!("2026-02-30"), json!("2026-03-01")),
        (json!("2026-10-01t00:00:00z"), json!("2026-10-01t00:00:00z")),
    ];
    for (x, y) in pairs {
        assert_eq!(days(x, y, "0"), Cause::Unusable);
    }
}

#[test]
fn a_missing_or_null_path_fails_as_absent_or_null_and_the_worst_wins() {
    let sentence = "days elapsed from x to y is at least 0";
    assert_eq!(cause(sentence, json!({"y": 1})), Cause::Absent);
    assert_eq!(cause(sentence, json!({"x": 1})), Cause::Absent);
    assert_eq!(cause(sentence, json!({"x": null, "y": 1})), Cause::Null);
    assert_eq!(cause(sentence, json!({"x": 1, "y": null})), Cause::Null);
    assert_eq!(cause(sentence, json!({"x": null})), Cause::Absent);
    assert_eq!(cause(sentence, json!({"x": "x", "y": null})), Cause::Null);
    assert_eq!(cause(sentence, json!({"x": "x"})), Cause::Absent);
}

#[test]
fn a_subject_that_is_not_an_object_fails_as_not_an_object() {
    assert_eq!(
        cause("days elapsed from x to y is at least 0", json!("s")),
        Cause::NotAnObject
    );
}

#[test]
fn an_elapsed_side_shows_its_number_then_each_path_in_order() {
    assert_eq!(
        entries(
            "days elapsed from x to y is 1.5",
            json!({"x": 100, "y": 129700})
        ),
        [
            json!({"name": "days elapsed from x to y", "value": 1.5, "locations": ["/things/0/x", "/things/0/y"]}),
            json!({"name": "x", "value": 100, "locations": ["/things/0/x"]}),
            json!({"name": "y", "value": 129700, "locations": ["/things/0/y"]}),
        ]
    );
}

#[test]
fn a_failed_elapsed_side_shows_null_and_where_each_read_stopped() {
    assert_eq!(
        entries("days elapsed from x to y is 1", json!({"x": 100})),
        [
            json!({"name": "days elapsed from x to y", "value": null, "locations": ["/things/0/x", "/things/0"]}),
            json!({"name": "x", "value": 100, "locations": ["/things/0/x"]}),
            json!({"name": "y", "value": null, "locations": ["/things/0"]}),
        ]
    );
}

#[test]
fn decimals_are_added_as_decimals() {
    assert_eq!(sum_text(&["0.1", "0.2"]), "0.3");
    assert_eq!(sum_text(&["0.1", "0.7"]), "0.8");
    assert_eq!(sum_text(&["1", "2"]), "3");
    assert_eq!(sum_text(&["-0.5", "0.25"]), "-0.25");
    assert_eq!(sum_text(&["-1.5", "1.5"]), "0");
    assert_eq!(sum_text(&["1e2", "0.5"]), "100.5");
    assert_eq!(sum_text(&["0.00000000000001", "1"]), "1.00000000000001");
}

#[test]
fn a_sum_needing_more_than_fifteen_digits_at_a_common_scale_is_unusable() {
    let unusable = |texts: &[&str]| {
        let numbers: Vec<Number> = texts.iter().map(|t| number(t)).collect();
        add(&numbers).is_none()
    };
    assert!(unusable(&["0.1234567890123456", "1"]));
    assert!(unusable(&["0.1000000000000000001", "0.2"]));
    assert!(unusable(&["1e15", "0.5"]));
    assert!(unusable(&["1e20", "1e20"]));
    assert!(unusable(&["1e-15", "1"]));
    assert!(unusable(&["1e-16", "0"]));
    assert!(unusable(&["1e-16"]));
    assert!(unusable(&["999999999999999", "1"]));
    assert!(unusable(&["1e300", "1e300"]));
    assert!(unusable(&["1e15"]));
    assert_eq!(sum_text(&["999999999999999", "0"]), "999999999999999");
    assert_eq!(sum_text(&["-999999999999999", "1"]), "-999999999999998");
    assert_eq!(sum_text(&["1e13", "1.5"]), "10000000000001.5");
    assert_eq!(sum_text(&["1.50", "1e2"]), "101.5");
}

#[test]
fn a_sum_has_no_exponent_and_no_trailing_zeros() {
    assert_eq!(sum_text(&["1.5", "1.5"]), "3");
    assert_eq!(sum_text(&["0.5", "0.5", "-1"]), "0");
    assert_eq!(sum_text(&["-0.5", "-0.25"]), "-0.75");
    assert_eq!(sum_text(&["1e-3", "1e-3"]), "0.002");
    assert_eq!(sum_text(&["0", "-0.0"]), "0");
}

#[test]
fn a_sum_with_digits_further_apart_than_fifteen_is_unusable() {
    let numbers = [number("1e200000"), number("1")];
    assert!(add(&numbers).is_none());
    assert_eq!(
        cause(
            "x plus 1 is 2",
            json!({"x": serde_json::from_str::<Value>("1e200000").unwrap()})
        ),
        Cause::Unusable
    );
}

#[test]
fn a_plus_in_a_sentence_adds_decimals() {
    assert_eq!(
        cause("x plus y is 0.3", json!({"x": 0.1, "y": 0.2})),
        Cause::Satisfied
    );
    assert_eq!(cause("0.1 plus 0.2 is 0.3", json!({})), Cause::Satisfied);
    assert_eq!(cause("x plus 2 is 5", json!({"x": 4})), Cause::Value);
    assert_eq!(
        cause("1 plus x plus y is 6", json!({"x": 2, "y": 3})),
        Cause::Satisfied
    );
}

#[test]
fn a_plus_fails_as_its_worst_operand() {
    let sentence = "x plus y is 3";
    assert_eq!(cause(sentence, json!({"x": 1})), Cause::Absent);
    assert_eq!(cause(sentence, json!({"x": null, "y": 2})), Cause::Null);
    assert_eq!(cause(sentence, json!({"x": "1", "y": 2})), Cause::Unusable);
    assert_eq!(
        cause(sentence, json!({"x": true, "y": null})),
        Cause::Unusable
    );
    assert_eq!(
        cause(sentence, json!({"x": null, "y": {}})),
        Cause::Unusable
    );
    assert_eq!(cause(sentence, json!({"x": "1"})), Cause::Unusable);
    assert_eq!(cause(sentence, json!({"x": [1], "y": {}})), Cause::Unusable);
    assert_eq!(cause(sentence, json!("s")), Cause::NotAnObject);
}

#[test]
fn a_plus_shows_its_number_then_each_operand_and_a_number_shows_nothing() {
    assert_eq!(
        entries("x plus 2 is 5", json!({"x": 3})),
        [
            json!({"name": "x plus 2", "value": 5, "locations": ["/things/0/x"]}),
            json!({"name": "x", "value": 3, "locations": ["/things/0/x"]}),
        ]
    );
}

#[test]
fn a_failed_plus_shows_null() {
    assert_eq!(
        entries("x plus 2 is 5", json!({"x": "3"})),
        [
            json!({"name": "x plus 2", "value": null, "locations": ["/things/0/x"]}),
            json!({"name": "x", "value": "3", "locations": ["/things/0/x"]}),
        ]
    );
}

#[test]
fn a_plus_with_an_elapsed_term_lists_the_elapsed_entry_then_its_paths() {
    assert_eq!(
        entries(
            "1 plus days elapsed from x to y is 2",
            json!({"x": 0, "y": 86400})
        ),
        [
            json!({"name": "1 plus days elapsed from x to y", "value": 2, "locations": ["/things/0/x", "/things/0/y"]}),
            json!({"name": "days elapsed from x to y", "value": 1, "locations": ["/things/0/x", "/things/0/y"]}),
            json!({"name": "x", "value": 0, "locations": ["/things/0/x"]}),
            json!({"name": "y", "value": 86400, "locations": ["/things/0/y"]}),
        ]
    );
}

#[test]
fn a_path_read_twice_is_shown_once_and_its_location_listed_once() {
    assert_eq!(
        entries("x plus x is 4", json!({"x": 2})),
        [
            json!({"name": "x plus x", "value": 4, "locations": ["/things/0/x"]}),
            json!({"name": "x", "value": 2, "locations": ["/things/0/x"]}),
        ]
    );
}

#[test]
fn the_right_side_comes_after_the_left_and_a_repeat_is_dropped() {
    assert_eq!(
        entries(
            "n is days elapsed from x to y",
            json!({"n": 1, "x": 0, "y": 86400})
        ),
        [
            json!({"name": "n", "value": 1, "locations": ["/things/0/n"]}),
            json!({"name": "days elapsed from x to y", "value": 1, "locations": ["/things/0/x", "/things/0/y"]}),
            json!({"name": "x", "value": 0, "locations": ["/things/0/x"]}),
            json!({"name": "y", "value": 86400, "locations": ["/things/0/y"]}),
        ]
    );
    assert_eq!(
        entries("x plus 1 is at least x", json!({"x": 2})),
        [
            json!({"name": "x plus 1", "value": 3, "locations": ["/things/0/x"]}),
            json!({"name": "x", "value": 2, "locations": ["/things/0/x"]}),
        ]
    );
}

#[test]
fn both_sides_failing_gives_the_worst_cause_and_both_sides_entries() {
    let verdict = verdict_of("x plus 1 is y plus 1", json!({"x": null}));
    assert_eq!(verdict.cause, Cause::Absent);
    let names: Vec<&str> = verdict.inputs.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, ["x plus 1", "x", "y plus 1", "y"]);
    assert_eq!(
        cause("x plus 1 is y plus 1", json!({"x": null, "y": null})),
        Cause::Null
    );
    assert_eq!(
        cause("x plus 1 is y plus 1", json!({"x": 1})),
        Cause::Absent
    );
}

#[test]
fn a_derived_side_can_be_on_the_left_the_right_or_both() {
    let subject = json!({"x": 1, "y": 2, "c": 3});
    assert_eq!(cause("x plus y is c", subject.clone()), Cause::Satisfied);
    assert_eq!(cause("c is x plus y", subject.clone()), Cause::Satisfied);
    assert_eq!(
        cause("x plus y is 1 plus 2", subject.clone()),
        Cause::Satisfied
    );
    assert_eq!(cause("x plus y is not c", subject), Cause::Value);
}

#[test]
fn a_derived_side_takes_is_is_not_within_the_orders_and_between() {
    let subject = json!({"x": 1, "y": 2});
    for (sentence, wanted) in [
        ("x plus y is 3", Cause::Satisfied),
        ("x plus y is 4", Cause::Value),
        ("x plus y is not 4", Cause::Satisfied),
        ("x plus y is not 3", Cause::Value),
        ("x plus y is 3.5 within 0.5", Cause::Satisfied),
        ("x plus y is 3.6 within 0.5", Cause::Value),
        ("x plus y is at least 3", Cause::Satisfied),
        ("x plus y is at least 4", Cause::Value),
        ("x plus y is at most 3", Cause::Satisfied),
        ("x plus y is at most 2", Cause::Value),
        ("x plus y is more than 2", Cause::Satisfied),
        ("x plus y is more than 3", Cause::Value),
        ("x plus y is less than 4", Cause::Satisfied),
        ("x plus y is less than 3", Cause::Value),
        ("x plus y is between 3 and 4", Cause::Satisfied),
        ("x plus y is between 2 and 3", Cause::Satisfied),
        ("x plus y is between 4 and 5", Cause::Value),
        ("x plus y is between 1 and 2", Cause::Value),
    ] {
        assert_eq!(cause(sentence, subject.clone()), wanted, "{sentence}");
    }
}

#[test]
fn between_fails_with_the_cause_of_a_side_that_fails() {
    assert_eq!(
        cause("x plus 2 is between 4 and 6", json!({})),
        Cause::Absent
    );
    assert_eq!(
        cause("x plus 2 is between 4 and 6", json!({"x": null})),
        Cause::Null
    );
    assert_eq!(
        cause("x plus 2 is between 4 and 6", json!({"x": "x"})),
        Cause::Unusable
    );
    assert_eq!(
        cause(
            "days elapsed from x to y is between 1 and 2",
            json!({"x": 86400, "y": 0})
        ),
        Cause::Value
    );
}

#[test]
fn a_plain_side_that_is_not_a_number_is_unusable() {
    assert_eq!(
        cause("x plus 1 is y", json!({"x": 1, "y": "2"})),
        Cause::Unusable
    );
    assert_eq!(
        cause("y is x plus 1", json!({"x": 1, "y": "2"})),
        Cause::Unusable
    );
    assert_eq!(cause("x plus 1 is \"2\"", json!({"x": 1})), Cause::Unusable);
    assert_eq!(cause("x plus 1 is true", json!({"x": 1})), Cause::Unusable);
    assert_eq!(
        cause("x plus 1 is at least \"2\"", json!({"x": 1})),
        Cause::Unusable
    );
    assert_eq!(
        cause("x plus 1 is 2 within 1", json!({"x": 1})),
        Cause::Satisfied
    );
}

#[test]
fn a_null_value_on_the_right_fails_as_null_and_a_missing_path_as_absent() {
    assert_eq!(cause("x plus 1 is null", json!({"x": 1})), Cause::Null);
    assert_eq!(cause("x plus 1 is y", json!({"x": 1})), Cause::Absent);
    assert_eq!(
        cause("x plus 1 is y", json!({"x": 1, "y": null})),
        Cause::Null
    );
}

#[test]
fn elapsed_days_compare_with_a_field_or_a_sum_on_the_right() {
    let subject = json!({"n": 1, "x": 0, "y": 86400});
    assert_eq!(
        cause("n is days elapsed from x to y", subject.clone()),
        Cause::Satisfied
    );
    assert_eq!(
        cause(
            "n is more than 1 plus days elapsed from x to y",
            subject.clone()
        ),
        Cause::Value
    );
    assert_eq!(
        cause("n plus 1 is 1 plus days elapsed from x to y", subject),
        Cause::Satisfied
    );
}

fn run_on(sentence: &str, subject: Value, input_rest: Value, params: Value) -> Verdict {
    let mut input = json!({"things": [subject]});
    if let (Some(rest), Some(map)) = (input_rest.as_object(), input.as_object_mut()) {
        map.extend(rest.clone());
    }
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    crate::ops::run(&lowered(sentence), &ctx)
}

fn json_entries(verdict: &Verdict) -> Vec<Value> {
    verdict.inputs.iter().map(Input::to_json).collect()
}

#[test]
fn a_count_is_the_number_of_values_the_path_ends_at_and_null_is_counted() {
    let subject = json!({"xs": [1, null, "a"]});
    assert_eq!(cause("count of xs is 3", subject.clone()), Cause::Satisfied);
    assert_eq!(cause("count of xs is 2", subject), Cause::Value);
    assert_eq!(
        cause("count of xs.n is 2", json!({"xs": [{"n": 1}, {"n": null}]})),
        Cause::Satisfied
    );
}

#[test]
fn a_count_over_an_empty_list_is_zero_and_shows_the_empty_list() {
    let sentence = "count of xs is 0";
    assert_eq!(cause(sentence, json!({"xs": []})), Cause::Satisfied);
    assert_eq!(
        entries(sentence, json!({"xs": []})),
        [
            json!({"name": "count of xs", "value": 0, "locations": []}),
            json!({"name": "xs[]", "value": [], "locations": []}),
        ]
    );
}

#[test]
fn a_count_shows_its_number_then_the_list_with_one_location_per_item() {
    assert_eq!(
        entries("count of xs is 2", json!({"xs": ["a", "b"]})),
        [
            json!({"name": "count of xs", "value": 2, "locations": ["/things/0/xs/0", "/things/0/xs/1"]}),
            json!({"name": "xs[]", "value": ["a", "b"], "locations": ["/things/0/xs/0", "/things/0/xs/1"]}),
        ]
    );
}

#[test]
fn a_count_over_a_list_that_is_missing_null_or_not_a_list_fails_and_shows_null() {
    let sentence = "count of xs is 0";
    for (subject, wanted) in [
        (json!({}), Cause::Absent),
        (json!({"xs": null}), Cause::Null),
        (json!({"xs": "abc"}), Cause::Unusable),
        (json!({"xs": {"a": 1}}), Cause::Unusable),
    ] {
        assert_eq!(cause(sentence, subject.clone()), wanted, "{subject}");
        assert_eq!(
            entries(sentence, subject)[0],
            json!({"name": "count of xs", "value": null, "locations": []})
        );
    }
}

#[test]
fn a_count_fails_as_absent_when_a_value_it_counts_is_missing() {
    assert_eq!(
        cause("count of xs.n is 2", json!({"xs": [{"n": 1}, {}]})),
        Cause::Absent
    );
    assert_eq!(
        cause("count of xs.n is 2", json!({"xs": [{"n": 1}, 5]})),
        Cause::NotAnObject
    );
}

#[test]
fn a_count_walks_every_list_along_the_path() {
    let subject = json!({"ps": [{"cs": [1, 2]}, {"cs": [3]}]});
    assert_eq!(
        cause("count of ps.cs is 3", subject.clone()),
        Cause::Satisfied
    );
    assert_eq!(
        entries("count of ps.cs is 3", subject)[1],
        json!({"name": "ps[].cs[]", "value": [1, 2, 3], "locations": ["/things/0/ps/0/cs/0", "/things/0/ps/0/cs/1", "/things/0/ps/1/cs/0"]})
    );
    assert_eq!(
        cause("count of ps.cs is 1", json!({"ps": [{"cs": [1]}, {}]})),
        Cause::Absent
    );
}

#[test]
fn a_count_on_a_subject_that_is_not_an_object_fails_as_not_an_object_with_nothing_read() {
    let verdict = verdict_of("count of xs.n is 1", json!(5));
    assert_eq!(verdict.cause, Cause::NotAnObject);
    assert_eq!(
        json_entries(&verdict),
        [
            json!({"name": "count of xs.n", "value": null, "locations": []}),
            json!({"name": "xs.n", "value": [], "locations": []}),
        ]
    );
}

#[test]
fn a_sum_adds_the_values_as_decimals() {
    let subject = json!({"xs": [{"n": 0.1}, {"n": 0.2}]});
    assert_eq!(
        cause("sum of xs.n is 0.3", subject.clone()),
        Cause::Satisfied
    );
    assert_eq!(
        entries("sum of xs.n is 0.3", subject)[0],
        json!({"name": "sum of xs.n", "value": 0.3, "locations": ["/things/0/xs/0/n", "/things/0/xs/1/n"]})
    );
}

#[test]
fn a_sum_over_no_items_is_zero() {
    assert_eq!(
        cause("sum of xs.n is 0", json!({"xs": []})),
        Cause::Satisfied
    );
    assert_eq!(
        cause("sum of xs.n that is 1 is 0", json!({"xs": [{"n": 5}]})),
        Cause::Satisfied
    );
}

#[test]
fn a_count_or_sum_through_a_value_that_isnt_an_object_names_that_value() {
    for sentence in ["count of xs.m.v is 3", "sum of xs.m.v is 3"] {
        let policy = json!({
            "ergo_spec": SPEC,
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "thing", "checks": {"c": sentence}}}
        });
        let input = json!({"things": [{"id": 1, "xs": [{"m": "s"}]}]});
        let report = crate::report(&input, &policy, &json!({}));
        let found = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap();
        assert_eq!(found["cause"], "unusable", "{sentence}");
        assert_eq!(
            found["message"], "item 1 of xs: m is \"s\", which isn't an object",
            "{sentence}"
        );
    }
}

#[test]
fn a_sum_fails_as_absent_null_or_unusable_and_the_worst_wins() {
    let sentence = "sum of xs.n is 0";
    assert_eq!(
        cause(sentence, json!({"xs": [{"n": 1}, {}]})),
        Cause::Absent
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"n": 1}, {"n": null}]})),
        Cause::Null
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"n": 1}, {"n": "2"}]})),
        Cause::Unusable
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"n": true}]})),
        Cause::Unusable
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"n": null}, {}, {"n": "x"}]})),
        Cause::Unusable
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"n": null}, {}]})),
        Cause::Absent
    );
    assert_eq!(cause(sentence, json!({"xs": null})), Cause::Null);
    assert_eq!(cause(sentence, json!({})), Cause::Absent);
}

#[test]
fn a_whose_leaves_out_an_item_it_fails_with_value_and_a_missing_field_for_exists() {
    let subject = json!({"xs": [{"k": 1}, {"k": 2}, {"k": 1}, {}]});
    assert_eq!(
        cause("count of xs whose k exists is 3", subject.clone()),
        Cause::Satisfied
    );
    assert_eq!(
        cause(
            "count of xs whose k is 1 is 2",
            json!({"xs": [{"k": 1}, {"k": 2}, {"k": 1}]})
        ),
        Cause::Satisfied
    );
    assert_eq!(
        cause(
            "sum of xs.n that is a number is 5",
            json!({"xs": [{"n": 5}, {"n": "x"}]})
        ),
        Cause::Satisfied
    );
    assert_eq!(
        cause("count of xs whose k exists is 3", subject),
        Cause::Satisfied
    );
}

#[test]
fn an_item_a_whose_cannot_decide_fails_the_side_with_its_cause() {
    let sentence = "count of xs whose k is 1 is 1";
    assert_eq!(
        cause(sentence, json!({"xs": [{"k": 1}, {}]})),
        Cause::Absent
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"k": 1}, {"k": null}]})),
        Cause::Null
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"k": 1}, {"k": "a"}]})),
        Cause::Unusable
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"k": 2}, {}]})),
        Cause::Absent
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"k": 1}, 5]})),
        Cause::NotAnObject
    );
}

#[test]
fn a_whose_that_reads_a_missing_ref_fails_the_side_even_on_an_empty_list() {
    let sentence = "count of xs whose k is one of $params.limit is 0";
    let run = |subject: Value, params: Value| run_on(sentence, subject, json!({}), params).cause;
    assert_eq!(run(json!({"xs": []}), json!({})), Cause::Absent);
    assert_eq!(run(json!({"xs": []}), json!({"limit": null})), Cause::Null);
    assert_eq!(
        run(json!({"xs": []}), json!({"limit": [1]})),
        Cause::Satisfied
    );
    assert_eq!(run(json!({"xs": [{"k": 1}]}), json!({})), Cause::Absent);
}

#[test]
fn a_param_a_whose_compares_with_is_read_up_front_so_an_empty_list_fails_without_it() {
    let sentence = "count of xs whose k is $params.limit is 0";
    let run = |subject: Value, params: Value| run_on(sentence, subject, json!({}), params).cause;
    assert_eq!(run(json!({"xs": []}), json!({})), Cause::Absent);
    assert_eq!(run(json!({"xs": []}), json!({"limit": null})), Cause::Null);
    assert_eq!(
        run(json!({"xs": []}), json!({"limit": 1})),
        Cause::Satisfied
    );
}

#[test]
fn a_ref_step_in_the_path_or_the_whose_that_cannot_be_used_is_unusable() {
    let in_path = "count of m named by $params.k is 1";
    let subject = json!({"m": {"a": [1]}});
    assert_eq!(
        run_on(in_path, subject.clone(), json!({}), json!({"k": "a"})).cause,
        Cause::Satisfied
    );
    assert_eq!(
        run_on(in_path, subject.clone(), json!({}), json!({"k": 1.5})).cause,
        Cause::Unusable
    );
    assert_eq!(
        run_on(in_path, subject.clone(), json!({}), json!({})).cause,
        Cause::Absent
    );
    assert_eq!(
        run_on(in_path, subject, json!({}), json!({"k": null})).cause,
        Cause::Null
    );
    let in_whose = "count of xs whose m named by $params.k is 1 is 0";
    assert_eq!(
        run_on(in_whose, json!({"xs": []}), json!({}), json!({"k": [1]})).cause,
        Cause::Unusable
    );
}

#[test]
fn a_count_on_the_right_of_a_phrase_is_read_after_the_left_and_shows_its_list() {
    assert_eq!(
        entries("n is count of xs", json!({"n": 2, "xs": ["a", "b"]})),
        [
            json!({"name": "n", "value": 2, "locations": ["/things/0/n"]}),
            json!({"name": "count of xs", "value": 2, "locations": ["/things/0/xs/0", "/things/0/xs/1"]}),
            json!({"name": "xs[]", "value": ["a", "b"], "locations": ["/things/0/xs/0", "/things/0/xs/1"]}),
        ]
    );
    assert_eq!(
        cause("n is count of xs", json!({"n": 3, "xs": ["a", "b"]})),
        Cause::Value
    );
    assert_eq!(cause("n is count of xs", json!({"n": 2})), Cause::Absent);
}

#[test]
fn a_count_plus_a_number_or_a_path_is_added_and_shows_each_part() {
    assert_eq!(
        entries("x plus count of xs is 5", json!({"x": 3, "xs": [1, 2]})),
        [
            json!({"name": "x plus count of xs", "value": 5, "locations": ["/things/0/x", "/things/0/xs/0", "/things/0/xs/1"]}),
            json!({"name": "x", "value": 3, "locations": ["/things/0/x"]}),
            json!({"name": "count of xs", "value": 2, "locations": ["/things/0/xs/0", "/things/0/xs/1"]}),
            json!({"name": "xs[]", "value": [1, 2], "locations": ["/things/0/xs/0", "/things/0/xs/1"]}),
        ]
    );
    assert_eq!(
        cause("count of xs plus 1 is 3", json!({"xs": [1, 2]})),
        Cause::Satisfied
    );
    assert_eq!(
        cause(
            "count of xs plus sum of ys is 6",
            json!({"xs": [1, 2], "ys": [1, 3]})
        ),
        Cause::Satisfied
    );
    assert_eq!(cause("1 plus count of xs is 2", json!({})), Cause::Absent);
}

#[test]
fn two_counts_of_the_same_list_show_the_list_once() {
    assert_eq!(
        entries("count of xs is at most count of xs", json!({"xs": [1]})),
        [
            json!({"name": "count of xs", "value": 1, "locations": ["/things/0/xs/0"]}),
            json!({"name": "xs[]", "value": [1], "locations": ["/things/0/xs/0"]}),
        ]
    );
    assert_eq!(
        entries(
            "count of xs whose k is 1 is at most count of xs",
            json!({"xs": [{"k": 1}]})
        )
        .iter()
        .map(|e| e["name"].as_str().unwrap().to_string())
        .collect::<Vec<_>>(),
        ["count of xs whose k is 1", "xs[]", "count of xs"]
    );
}

#[test]
fn the_paths_a_whose_reads_outside_the_item_come_after_the_list_sorted_by_name() {
    let verdict = run_on(
        "count of xs whose k is $input.b and whose k is $input.a is 1",
        json!({"xs": [{"k": 1}]}),
        json!({"a": 1, "b": 1}),
        json!({}),
    );
    let names: Vec<&str> = verdict.inputs.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(
        names,
        [
            "count of xs whose k equals $input.b and whose k equals $input.a",
            "xs[]",
            "$input.a",
            "$input.b"
        ]
    );
}

#[test]
fn a_count_in_the_whose_of_an_every_reads_the_focus_and_decides_which_items_are_checked() {
    let sentence = "every xs.t whose count of ys is at least 1 exists";
    let subject = json!({"xs": [{"t": {"ys": [1]}}, {"t": {"ys": []}, "ys": [1]}]});
    assert_eq!(cause(sentence, subject), Cause::Satisfied);
    assert_eq!(
        cause(sentence, json!({"xs": [{"t": {"ys": []}, "ys": [1]}]})),
        Cause::Value
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"t": {"ys": null}, "ys": [1]}]})),
        Cause::Null
    );
    assert_eq!(
        cause(sentence, json!({"xs": [{"t": {}, "ys": [1]}]})),
        Cause::Absent
    );
}

#[test]
fn an_item_a_counted_whose_cannot_decide_is_listed_at_the_counted_list() {
    let check = lowered("every xs.t whose count of ys is at least 1 is \"x\"");
    let Check::Walk(walk) = check else {
        panic!("not a walk");
    };
    let path = walk.whose[0].left_path().unwrap();
    assert_eq!(path.steps, [Step::Key("ys".to_string())]);
}

#[test]
fn a_count_on_the_item_reads_its_own_field_even_when_it_is_named_like_a_parent() {
    let scope = Scope::new().with_parent("b", BTreeMap::new()).in_item();
    let tree = s::parse_check("count of b.kids is at least 1").unwrap();
    let Check::Tally(check) = lower_assertion(&tree.assertions[0], &scope)
        .unwrap()
        .unwrap()
    else {
        panic!("not a tally");
    };
    let path = check.paths()[0];
    assert_eq!(path.start, Start::Own);
    assert_eq!(
        path.steps,
        [Step::Key("b".into()), Step::Key("kids".into())]
    );
}

#[test]
fn a_whose_can_compare_a_field_of_the_focus_with_a_count_of_its_own_list() {
    let sentence = "every xs.o whose n is count of ys exists";
    let subject = json!({"xs": [{"o": {"n": 2, "ys": [1, 1]}}, {"o": {"n": 1, "ys": [1, 1]}}]});
    assert_eq!(cause(sentence, subject), Cause::Satisfied);
    assert_eq!(
        cause(
            sentence,
            json!({"xs": [{"o": {"n": 1, "ys": [1, 1]}, "n": 2}]})
        ),
        Cause::Value
    );
}

fn subject_with(n: &str) -> Value {
    serde_json::from_str(&format!(
        r#"{{"fa": {n}, "fb": {n}, "items": [{{"x": {n}}}]}}"#
    ))
    .unwrap()
}

#[test]
fn a_number_below_the_range_of_a_float_is_unusable_in_a_sum_and_does_not_panic() {
    for n in ["1e-70000", "1e-1000000000000"] {
        assert_eq!(
            cause("sum of items.x is 0", subject_with(n)),
            Cause::Unusable,
            "{n}"
        );
        assert_eq!(
            cause("fa plus fb is 0", subject_with(n)),
            Cause::Unusable,
            "{n}"
        );
    }
}

#[test]
fn a_number_above_the_range_of_a_float_is_unusable_in_a_sum_and_does_not_allocate_it() {
    for n in ["1e1000000000000", "-1e1000000000000"] {
        assert_eq!(
            cause("sum of items.x is 0", subject_with(n)),
            Cause::Unusable,
            "{n}"
        );
        assert_eq!(
            cause("fa plus fb is 1", subject_with(n)),
            Cause::Unusable,
            "{n}"
        );
    }
}

#[test]
fn a_sum_of_a_number_with_a_long_fraction_is_unusable() {
    let long = format!("0.{}1", "0".repeat(9000));
    assert_eq!(
        cause("fa plus fb is fb", subject_with(&long)),
        Cause::Unusable
    );
    assert_eq!(
        cause("sum of items.x is fa", subject_with(&long)),
        Cause::Unusable
    );
}

#[test]
fn a_ref_inside_a_count_path_or_whose_is_among_the_refs_of_the_check() {
    let names: Vec<String> =
        lowered("count of m named by $params.a whose k is one of $params.b is 1")
            .refs()
            .iter()
            .map(crate::name::name)
            .collect();
    assert_eq!(names, vec!["$params.a", "$params.b"]);
}

#[test]
fn a_count_path_is_among_the_paths_of_the_check() {
    let check = lowered("count of xs plus y is 1");
    assert_eq!(check.paths().len(), 2);
}

#[test]
fn a_sentence_that_is_not_derived_is_not_lowered_here() {
    let tree = s::parse_check("x is y").unwrap();
    assert!(lower_assertion(&tree.assertions[0], &Scope::new()).is_none());
    let tree = s::parse_check("every xs is 1").unwrap();
    assert!(lower_assertion(&tree.assertions[0], &Scope::new()).is_none());
}

#[test]
fn a_number_out_of_range_is_written_wrong() {
    let tree = s::parse_check("x plus 1e999 is 2").unwrap();
    assert!(
        lower_assertion(&tree.assertions[0], &Scope::new())
            .unwrap()
            .is_err()
    );
}

fn row_names(checks: Value) -> Vec<String> {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"t": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "t", "checks": {"c": checks}}}
    });
    let input = json!({"things": [{"id": 1, "x": 1, "y": 3}]});
    let report = crate::report(&input, &policy, &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap();
    row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["name"].as_str().unwrap().to_string())
        .collect()
}

#[test]
fn a_row_of_one_sentence_lists_its_entries_in_reading_order_not_by_name() {
    assert_eq!(
        row_names(json!("y is more than x plus 1")),
        ["y", "x plus 1", "x"]
    );
}

#[test]
fn a_row_of_several_sentences_lists_its_entries_sorted_by_name() {
    assert_eq!(
        row_names(json!({"assert": ["y is more than x plus 1", "y is 3"]})),
        ["x", "x plus 1", "y"]
    );
}

fn failed_items_of(sentence: &str, items: Value, params: Value) -> Vec<Value> {
    let input = json!({"things": [{"items": items}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    crate::ops::run_full(&lowered(sentence), &ctx)
        .failed_items
        .unwrap()
}

fn named(failed: &[Value]) -> Vec<(&str, &Value, &Value)> {
    failed
        .iter()
        .map(|f| (f["path"].as_str().unwrap(), &f["value"], &f["locations"][0]))
        .collect()
}

#[test]
fn a_whose_names_the_right_side_when_only_the_right_side_was_not_read() {
    let failed = failed_items_of(
        "every items whose lo is at least hi exists",
        json!([{"lo": 1, "s": "ok"}, {"hi": 1, "s": "ok"}, {"s": "ok"}, {"lo": 1, "hi": null, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&failed),
        [
            ("items[0].hi", &json!(null), &json!("/things/0/items/0")),
            ("items[1].lo", &json!(null), &json!("/things/0/items/1")),
            ("items[2].lo", &json!(null), &json!("/things/0/items/2")),
            ("items[3].hi", &json!(null), &json!("/things/0/items/3/hi")),
        ]
    );
}

#[test]
fn a_whose_names_the_left_side_when_both_were_read() {
    let failed = failed_items_of(
        "every items whose lo is at least hi exists",
        json!([{"lo": "x", "hi": 1, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&failed),
        [("items[0].lo", &json!("x"), &json!("/things/0/items/0/lo"))]
    );
}

#[test]
fn a_whose_with_a_count_names_the_count_list_when_it_is_the_side_not_read() {
    let on_left = failed_items_of(
        "every items whose count of kids is at least min exists",
        json!([{"kids": [1], "s": "ok"}, {"min": 1, "s": "ok"}, {"s": "ok"}, {"kids": 5, "min": 1, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&on_left),
        [
            ("items[0].min", &json!(null), &json!("/things/0/items/0")),
            ("items[1].kids", &json!(null), &json!("/things/0/items/1")),
            ("items[2].kids", &json!(null), &json!("/things/0/items/2")),
            ("items[3].kids", &json!(5), &json!("/things/0/items/3/kids")),
        ]
    );
    let on_right = failed_items_of(
        "every items whose min is at most count of kids exists",
        json!([{"kids": [1], "s": "ok"}, {"min": 1, "s": "ok"}, {"s": "ok"}, {"kids": 5, "min": 1, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&on_right),
        [
            ("items[0].min", &json!(null), &json!("/things/0/items/0")),
            ("items[1].kids", &json!(null), &json!("/things/0/items/1")),
            ("items[2].min", &json!(null), &json!("/things/0/items/2")),
            ("items[3].kids", &json!(5), &json!("/things/0/items/3/kids")),
        ]
    );
}

#[test]
fn a_whose_with_a_plus_side_names_its_first_path_that_was_not_read() {
    let failed = failed_items_of(
        "every items whose lo is at least hi plus 1 exists",
        json!([{"lo": 1, "s": "ok"}, {"lo": 1, "hi": null, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&failed),
        [
            ("items[0].hi", &json!(null), &json!("/things/0/items/0")),
            ("items[1].hi", &json!(null), &json!("/things/0/items/1/hi")),
        ]
    );
    let counted = failed_items_of(
        "every items whose min is at most count of kids plus 1 exists",
        json!([{"min": 1, "s": "ok"}, {"min": 1, "kids": 5, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&counted),
        [
            ("items[0].kids", &json!(null), &json!("/things/0/items/0")),
            ("items[1].kids", &json!(5), &json!("/things/0/items/1/kids")),
        ]
    );
    let first_of_two = failed_items_of(
        "every items whose lo is at least x plus y exists",
        json!([{"lo": 1, "y": 1, "s": "ok"}, {"lo": 1, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&first_of_two),
        [
            ("items[0].x", &json!(null), &json!("/things/0/items/0")),
            ("items[1].x", &json!(null), &json!("/things/0/items/1")),
        ]
    );
}

#[test]
fn a_whose_with_an_elapsed_side_names_its_first_path_that_was_not_read() {
    let failed = failed_items_of(
        "every items whose days elapsed from start to stop is at least lo exists",
        json!([{"start": "2026-01-01T00:00:00Z", "lo": 1, "s": "ok"}, {"lo": 1, "s": "ok"}]),
        json!({}),
    );
    assert_eq!(
        named(&failed),
        [
            ("items[0].stop", &json!(null), &json!("/things/0/items/0")),
            ("items[1].start", &json!(null), &json!("/things/0/items/1")),
        ]
    );
}

#[test]
fn a_whose_root_that_cant_be_read_leaves_no_failed_item_when_the_item_reads_fine() {
    for sentence in [
        "every items whose lo is at least $params.min exists",
        "every items whose $params.min is at most lo exists",
        "every items whose lo is at least $input.min exists",
    ] {
        let failed = failed_items_of(sentence, json!([{"lo": 1, "s": "ok"}]), json!({}));
        assert!(failed.is_empty(), "{sentence}");
    }
}

type Read = (String, Value, Vec<String>);

fn ran_with(
    scope: &Scope,
    sentence: &str,
    input: Value,
    aliases: &[(&str, Located)],
) -> (Vec<Value>, Vec<Read>) {
    let tree = s::parse_check(sentence).unwrap();
    let check = crate::lower::lower_assertion(&tree.assertions[0], scope).unwrap();
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: aliases
            .iter()
            .map(|(name, at)| (name.to_string(), at.clone()))
            .collect(),
    };
    let ran = crate::ops::run_full(&check, &ctx);
    let inputs = ran
        .verdict
        .inputs
        .into_iter()
        .map(|input| (input.name, input.value, input.locations))
        .collect();
    (ran.failed_items.unwrap(), inputs)
}

#[test]
fn a_whose_that_only_a_part_of_the_subject_stops_lists_no_item_and_reads_the_part_at_the_subjects_location()
 {
    let scope = Scope::new().with_part(
        "w",
        crate::lower::PartDef {
            steps: vec![Step::Key("meta".into()), Step::Key("w".into())],
            id: None,
        },
    );
    let input = json!({"things": [{"id": "t", "meta": {}, "items": [{"lo": 1, "s": "ok"}]}]});
    let (failed, inputs) = ran_with(
        &scope,
        "every items whose lo is at least w exists",
        input,
        &[],
    );
    assert!(failed.is_empty());
    assert!(inputs.contains(&(
        "w".to_string(),
        json!(null),
        vec!["/things/0/meta".to_string()]
    )));
}

#[test]
fn a_whose_that_only_a_parents_field_stops_lists_no_item_and_reads_the_field_at_the_parents_location()
 {
    let scope = Scope::new().with_parent("art", BTreeMap::new());
    let input =
        json!({"arts": [{"id": "a"}], "things": [{"id": "t", "items": [{"lo": 1, "s": "ok"}]}]});
    let parent = Located {
        value: &input["arts"][0],
        location: Location::input_root().key("arts").index(0),
    };
    let (failed, inputs) = ran_with(
        &scope,
        "every items whose lo is at least art.q exists",
        input.clone(),
        &[("art", parent)],
    );
    assert!(failed.is_empty());
    assert!(inputs.contains(&(
        "art.q".to_string(),
        json!(null),
        vec!["/arts/0".to_string()]
    )));
}

fn verdict_in(
    scope: &Scope,
    sentence: &str,
    input: &Value,
    aliases: &[(&str, Located)],
) -> Verdict {
    let tree = s::parse_check(sentence).unwrap();
    let check = crate::lower::lower_assertion(&tree.assertions[0], scope).unwrap();
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input,
        params: None,
        aliases: aliases
            .iter()
            .map(|(name, at)| (name.to_string(), at.clone()))
            .collect(),
    };
    crate::ops::run(&check, &ctx)
}

fn part_x() -> Scope {
    Scope::new().with_part(
        "x",
        crate::lower::PartDef {
            steps: vec![Step::Key("p".into())],
            id: None,
        },
    )
}

fn rows_with_own_x() -> Value {
    let item = |n: u64, v: u64| json!({"n": n, "v": v, "x": {"z": [1, 1, 1]}});
    json!({"things": [{"id": "t", "p": {"z": [1]}, "xs": [item(1, 1), item(1, 1), item(3, 5)]}]})
}

#[test]
fn a_count_on_the_right_of_a_whose_reads_the_part_and_not_the_items_field_of_the_same_name() {
    let input = rows_with_own_x();
    for (sentence, cause) in [
        ("every xs whose n is count of x.z exists", Cause::Satisfied),
        (
            "every xs whose n is at most sum of x.z exists",
            Cause::Satisfied,
        ),
        ("count of xs whose n is count of x.z is 2", Cause::Satisfied),
    ] {
        assert_eq!(
            verdict_in(&part_x(), sentence, &input, &[]).cause,
            cause,
            "{sentence}"
        );
    }
}

#[test]
fn a_count_on_the_left_of_a_whose_and_one_after_a_dot_read_the_items_field_when_a_part_has_the_name()
 {
    let input = rows_with_own_x();
    for (sentence, cause) in [
        ("count of xs whose count of x.z is 3 is 3", Cause::Satisfied),
        (
            "count of xs whose n is count of .x.z is 1",
            Cause::Satisfied,
        ),
    ] {
        assert_eq!(
            verdict_in(&part_x(), sentence, &input, &[]).cause,
            cause,
            "{sentence}"
        );
    }
}

#[test]
fn a_part_on_the_right_of_a_whose_that_is_missing_or_null_or_not_a_list_fails_closed() {
    for (part, in_every, in_count) in [
        (None, Cause::Absent, Cause::Absent),
        (Some(json!(null)), Cause::Null, Cause::Null),
        (Some(json!({"z": "abc"})), Cause::Unusable, Cause::Unusable),
        (
            Some(json!({"z": {"k": 1}})),
            Cause::Unusable,
            Cause::Unusable,
        ),
    ] {
        let mut input = rows_with_own_x();
        let thing = input["things"][0].as_object_mut().unwrap();
        match part {
            Some(value) => thing.insert("p".into(), value),
            None => thing.remove("p"),
        };
        for (sentence, cause) in [
            ("every xs whose n is count of x.z exists", in_every),
            ("count of xs whose n is count of x.z is 2", in_count),
        ] {
            assert_eq!(
                verdict_in(&part_x(), sentence, &input, &[]).cause,
                cause,
                "{sentence}"
            );
        }
    }
}

#[test]
fn a_count_on_the_right_of_a_whose_reads_a_for_alias_and_not_the_items_field_of_the_same_name() {
    let input = json!({"things": [{"id": "t", "groups": [[1, 1]], "rows": [
        {"n": 2, "v": 1, "g": [5, 5, 5, 5, 5]},
        {"n": 5, "v": 9, "g": [5, 5, 5, 5, 5]},
    ]}]});
    let group = Located {
        value: &input["things"][0]["groups"][0],
        location: Location::input_root()
            .key("things")
            .index(0)
            .key("groups")
            .index(0),
    };
    let scope = Scope::new().with_for_alias("g");
    for (sentence, cause) in [
        ("every rows whose n is count of g exists", Cause::Satisfied),
        ("count of rows whose n is count of g is 1", Cause::Satisfied),
        ("count of rows whose count of g is 5 is 2", Cause::Satisfied),
        (
            "count of rows whose n is count of .g is 1",
            Cause::Satisfied,
        ),
    ] {
        assert_eq!(
            verdict_in(&scope, sentence, &input, &[("g", group.clone())]).cause,
            cause,
            "{sentence}"
        );
    }
}

fn first_entry_part(scope: &Scope, sentence: &str) -> Value {
    let input = json!({"things": [{"id": "t", "items": [{"w": 1}, {"w": 2}], "pa": {"w": 2, "items": [{"w": 2}]}}]});
    verdict_in(scope, sentence, &input, &[]).inputs[0]
        .to_json()
        .get("part")
        .cloned()
        .unwrap_or(Value::Null)
}

#[test]
fn a_count_carries_a_part_tag_only_when_its_list_is_read_from_the_part() {
    let scope = Scope::new().with_part(
        "pa",
        crate::lower::PartDef {
            steps: vec![Step::Key("pa".into())],
            id: None,
        },
    );
    assert_eq!(
        first_entry_part(&scope, "count of items whose w is pa.w is 1"),
        Value::Null
    );
    assert_eq!(
        first_entry_part(&scope, "count of pa.items whose w is pa.w is 1"),
        json!({"name": "pa", "id": null})
    );
}

fn named_row(subject: &str, has: Value, check: &str, input: Value) -> Value {
    let mut found = json!({"from": "every xs"});
    if !has.is_null() {
        found["has"] = has;
    }
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {subject: found},
        "requirements": {"r": {"subject": subject, "checks": {"c": check}}}
    });
    let report = crate::report(&input, &policy, &json!({}));
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

#[test]
fn a_count_of_a_field_named_like_the_subject_says_an_unusable_field_once() {
    let row = named_row(
        "kid",
        Value::Null,
        "count of .kid is 1",
        json!({"xs": [{"kid": 1}]}),
    );
    assert_eq!(row["cause"], "unusable");
    assert_eq!(row["message"], ".kid is 1, which isn't a list or an object");
    assert_eq!(row["inputs"][1]["name"], ".kid");
}

#[test]
fn a_whose_names_the_field_it_reads_with_a_dot_when_the_subject_has_that_name() {
    let row = named_row(
        "thing",
        json!({"p": "thing"}),
        "count of ys whose thing is p is 1",
        json!({"xs": [{"thing": {"x": 1}, "ys": [{"thing": 1}]}]}),
    );
    assert_eq!(
        row["message"],
        "item 1 of ys: .thing is 1, which isn't an object"
    );
}

#[test]
fn a_count_on_a_subject_that_is_not_an_object_lists_the_part_its_whose_reads() {
    let row = named_row(
        "thing",
        json!({"p": "thing"}),
        "count of ys whose thing is p is 1",
        json!({"xs": [3]}),
    );
    assert_eq!(row["cause"], "not_an_object");
    let names: Vec<&str> = row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .map(|input| input["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["count of ys whose thing equals p", "ys", "p"]);
}

fn counted_records(sentence: &str, items: Value, params: Value) -> Vec<Value> {
    let Check::Tally(tally) = lowered(sentence) else {
        panic!("{sentence} is not a count or a sum");
    };
    let Side::Derived(derived) = &tally.left else {
        panic!("{sentence} has no count or sum on the left");
    };
    let Term::Counted(counted) = &derived.terms[0] else {
        panic!("{sentence} starts with no count or sum");
    };
    let input = json!({"things": [{"items": items}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    counted_said(counted, &ctx).1
}

#[test]
fn an_item_a_whose_cant_use_is_recorded_with_the_field_it_read() {
    let records = counted_records(
        "count of items whose v is at least 3 is at least 1",
        json!([{"v": "a"}]),
        json!({}),
    );
    assert_eq!(
        records,
        [json!({
            "path": "items[0].v",
            "item": "item 1 of items",
            "cause": "unusable",
            "value": "a",
            "locations": ["/things/0/items/0/v"],
            "ergo/text": "item 1 of items: v is \"a\", which isn't a number",
            "ergo/item": {"value": {"v": "a"}, "locations": ["/things/0/items/0"]},
        })]
    );
}

#[test]
fn an_item_a_whose_with_an_unreadable_root_cant_use_is_recorded_with_the_field_it_read() {
    let records = counted_records(
        "count of items whose v is at least $params.min is at least 1",
        json!([{"v": "a"}]),
        json!({}),
    );
    assert_eq!(
        records,
        [json!({
            "path": "items[0].v",
            "item": "item 1 of items",
            "cause": "unusable",
            "value": "a",
            "locations": ["/things/0/items/0/v"],
            "ergo/text": "item 1 of items: v is \"a\", which isn't a number",
            "ergo/item": {"value": {"v": "a"}, "locations": ["/things/0/items/0"]},
        })]
    );
}

#[test]
fn an_item_a_whose_with_a_root_on_the_left_cant_use_is_recorded_with_the_field_it_read() {
    for params in [json!({}), json!({"min": 2})] {
        let records = counted_records(
            "count of items whose $params.min is at least v is at least 1",
            json!([{"v": "a"}]),
            params.clone(),
        );
        assert_eq!(
            records,
            [json!({
                "path": "items[0].v",
                "item": "item 1 of items",
                "cause": "unusable",
                "value": "a",
                "locations": ["/things/0/items/0/v"],
                "ergo/text": "item 1 of items: v is \"a\", which isn't a number",
                "ergo/item": {"value": {"v": "a"}, "locations": ["/things/0/items/0"]},
            })],
            "{params}"
        );
    }
}

#[test]
fn an_item_that_isnt_an_object_beside_a_root_on_the_left_of_is_in_is_recorded_with_its_list() {
    for params in [json!({}), json!({"k": "x"})] {
        let records = counted_records(
            "count of items whose $params.k is in tags is 1",
            json!(["a"]),
            params.clone(),
        );
        assert_eq!(
            records,
            [json!({
                "path": "items[0].tags",
                "item": "item 1 of items",
                "cause": "not_an_object",
                "value": null,
                "locations": ["/things/0/items/0"],
                "ergo/text": "item 1 of items is \"a\", which isn't an object",
                "ergo/item": {"value": "a", "locations": ["/things/0/items/0"]},
            })],
            "{params}"
        );
    }
}

#[test]
fn an_item_whose_lost_end_a_whose_reads_is_recorded_at_that_end() {
    let records = counted_records(
        "count of items.v whose it is at least 3 is at least 1",
        json!([{"w": 1}]),
        json!({}),
    );
    assert_eq!(
        records,
        [json!({
            "path": "items[0].v",
            "item": "item 1 of items",
            "cause": "absent",
            "value": null,
            "locations": ["/things/0/items/0"],
            "ergo/text": "item 1 of items: v is missing",
            "ergo/item": {"value": {"w": 1}, "locations": ["/things/0/items/0"]},
        })]
    );
}

#[test]
fn an_item_whose_end_a_sum_cant_add_is_recorded_at_that_end() {
    let records = counted_records(
        "sum of items.v is at least 1",
        json!([{"v": "a"}]),
        json!({}),
    );
    assert_eq!(
        records,
        [json!({
            "path": "items[0].v",
            "item": "item 1 of items",
            "cause": "unusable",
            "value": "a",
            "locations": ["/things/0/items/0/v"],
            "ergo/text": "item 1 of items: v is \"a\", which isn't a number",
            "ergo/item": {"value": {"v": "a"}, "locations": ["/things/0/items/0"]},
        })]
    );
}

fn cause_and_row(sentence: &str, items: Value, params: Value) -> (Cause, String) {
    cause_and_row_in(sentence, json!({"things": [{"items": items}]}), params)
}

fn cause_and_row_in(sentence: &str, input: Value, params: Value) -> (Cause, String) {
    let check = lowered(sentence);
    let Check::Tally(tally) = &check else {
        panic!("{sentence} is not a count or a sum");
    };
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    let verdict = crate::ops::run(&check, &ctx);
    let said = super::row_said(
        tally,
        &ctx,
        verdict.cause,
        super::super::message::said(&check, &ctx, &verdict),
    );
    (verdict.cause, super::super::message::said_text(&said))
}

#[test]
fn a_count_or_sum_says_params_that_cant_take_a_key_and_a_missing_input_key() {
    for sentence in [
        "sum of items.n that is at least $params.q named by $input.k is 1",
        "count of items.n that is at least $params.q named by $input.k is 1",
    ] {
        assert_eq!(
            cause_and_row(sentence, json!([{"n": 1}, {"n": 2}]), json!({"q": "s"})),
            (
                Cause::Unusable,
                "$params.q is \"s\", which isn't an object; $input.k is missing".to_string()
            )
        );
    }
}

#[test]
fn a_missing_input_key_keeps_the_items_a_count_or_sum_cant_read() {
    for sentence in [
        "sum of items.n that is at least $params.q named by $input.k is 1",
        "count of items.n that is at least $params.q named by $input.k is 1",
    ] {
        assert_eq!(
            cause_and_row(
                sentence,
                json!([{"n": "x"}, {"n": null}]),
                json!({"q": {"a": 1}})
            ),
            (
                Cause::Unusable,
                "$input.k is missing; item 1 of items: n is \"x\", which isn't a number; item 2 of items: n is null"
                    .to_string()
            )
        );
    }
}

#[test]
fn a_count_says_a_that_key_from_params_that_is_missing_or_null_once_beside_each_item() {
    let sentence = "count of items.v that is m named by $params.k is 0";
    for (items, params, cause, said) in [
        (
            json!([{"v": null}]),
            json!({"k": null}),
            Cause::NotAnObject,
            "$params.k is null; item 1 of items: v is null, which isn't an object",
        ),
        (
            json!([{"v": "s"}, {"v": {}}]),
            json!({}),
            Cause::NotAnObject,
            "$params.k is missing; item 1 of items: v is \"s\", which isn't an object; item 2 of items: v: m is missing",
        ),
    ] {
        assert_eq!(
            cause_and_row(sentence, items, params),
            (cause, said.to_string())
        );
    }
}

fn said_and_count(sentence: &str, input: Value, params: Value) -> (Cause, String, Value) {
    let (cause, said) = cause_and_row_in(sentence, input.clone(), params.clone());
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    let verdict = crate::ops::run(&lowered(sentence), &ctx);
    (cause, said, verdict.inputs[0].to_json()["value"].clone())
}

fn with_m(m: Option<Value>) -> Value {
    let mut input = json!({"things": [{"xs": [], "ys": [1]}]});
    if let Some(m) = m {
        input["m"] = m;
    }
    input
}

#[test]
fn a_count_on_an_empty_list_says_only_the_root_a_key_from_the_item_is_read_in_whatever_the_phrase()
{
    for sentence in [
        "count of xs whose v is $input.m named by key is 1",
        "count of xs whose v is not $input.m named by key is 0",
        "count of xs that is $input.m named by key is 1",
        "count of xs that is $input.m named by key is 0",
        "count of xs whose v is $input.m named by key and whose w equals 1 is 0",
        "count of xs whose tags contains $input.m named by key is 1",
        "count of xs whose v matches $input.m named by key is 1",
        "count of xs whose v is $input.m named by key within 1 is 1",
        "count of xs whose $input.m named by key is v is 0",
    ] {
        for (m, cause, said) in [
            (None, Cause::Absent, "$input.m is missing"),
            (Some(json!(null)), Cause::Null, "$input.m is null"),
            (
                Some(json!(3)),
                Cause::Unusable,
                "$input.m is 3, which isn't an object",
            ),
        ] {
            assert_eq!(
                said_and_count(sentence, with_m(m.clone()), json!({})),
                (cause, said.to_string(), Value::Null),
                "{sentence} with {m:?}"
            );
        }
    }
}

#[test]
fn a_count_on_an_empty_list_says_only_a_root_further_back_than_the_key() {
    for (sentence, m, cause, said) in [
        "count of xs whose v is $input.m.a named by key is 0",
        "count of xs whose v is not $input.m.a named by key is 0",
    ]
    .into_iter()
    .flat_map(|sentence| {
        [
            (
                json!(3),
                Cause::Unusable,
                "$input.m is 3, which isn't an object",
            ),
            (json!(null), Cause::Null, "$input.m is null"),
            (
                json!({"a": 3}),
                Cause::Unusable,
                "$input.m.a is 3, which isn't an object",
            ),
        ]
        .map(|(m, cause, said)| (sentence, m, cause, said))
    }) {
        assert_eq!(
            said_and_count(sentence, with_m(Some(m.clone())), json!({})),
            (cause, said.to_string(), Value::Null),
            "{sentence} with {m}"
        );
    }
}

#[test]
fn a_count_on_an_empty_list_says_only_a_params_root_a_key_from_the_item_is_read_in() {
    let sentence = "count of xs whose v is not $params.m named by key is 0";
    for (params, cause, said) in [
        (json!({}), Cause::Absent, "$params.m is missing"),
        (json!({"m": null}), Cause::Null, "$params.m is null"),
    ] {
        assert_eq!(
            said_and_count(sentence, with_m(None), params),
            (cause, said.to_string(), Value::Null)
        );
    }
}

#[test]
fn a_count_on_an_empty_list_is_0_when_the_root_a_key_from_the_item_is_read_in_is_an_object() {
    for sentence in [
        "count of xs whose v is not $input.m named by key is 0",
        "count of xs that is $input.m named by key is 0",
    ] {
        let (cause, _, count) = said_and_count(sentence, with_m(Some(json!({}))), json!({}));
        assert_eq!((cause, count), (Cause::Satisfied, json!(0)));
    }
}

#[test]
fn a_plus_leaves_out_only_the_number_of_the_count_whose_root_fails() {
    let sentence = "count of ys plus count of xs whose v is $input.m named by key is 1";
    for m in [None, Some(json!(null)), Some(json!(3))] {
        let values: Vec<(String, Value)> = entries_on_input(sentence, with_m(m))
            .iter()
            .map(|entry| {
                (
                    entry["name"].as_str().unwrap().to_string(),
                    entry["value"].clone(),
                )
            })
            .filter(|(name, _)| name.starts_with("count of"))
            .collect();
        assert_eq!(
            values,
            vec![
                (
                    "count of ys plus count of xs whose v equals $input.m named by key".to_string(),
                    Value::Null
                ),
                ("count of ys".to_string(), json!(1)),
                (
                    "count of xs whose v equals $input.m named by key".to_string(),
                    Value::Null
                ),
            ]
        );
    }
}

#[test]
fn a_count_whose_row_fails_for_params_it_walks_doesnt_say_its_number() {
    let check = lowered("count of $params.a is 1");
    let Check::Tally(tally) = &check else {
        panic!("not a count");
    };
    let input = json!({"things": [{}]});
    let params = json!([]);
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    let verdict = Verdict {
        cause: Cause::Unusable,
        inputs: crate::ops::run(&check, &ctx).inputs,
    };
    let said = super::super::message::said(&check, &ctx, &verdict);
    let row = super::row_said(tally, &ctx, Cause::Unusable, said);
    assert!(
        !super::super::message::said_text(&row).contains("is 0"),
        "the count's number isn't said"
    );
}

#[test]
fn a_count_says_a_that_key_it_cant_read_once_and_each_item_its_own_value() {
    let clauses = tally_clauses(
        "count of items.v that is m named by $params.k is 0",
        json!([{"v": "s"}, {"v": {}}, {"v": {"m": null}}, {"v": {"m": {}}}]),
        json!({}),
    );
    assert_eq!(
        kinds_and_texts(&clauses),
        [
            (clause::Kind::Root, "$params.k is missing".to_string()),
            (
                clause::Kind::Item,
                "item 1 of items: v is \"s\", which isn't an object".to_string()
            ),
            (
                clause::Kind::Item,
                "item 2 of items: v: m is missing".to_string()
            ),
            (
                clause::Kind::Item,
                "item 3 of items: v: m is null".to_string()
            ),
        ]
    );
}

#[test]
fn a_count_fails_with_the_worst_cause_of_its_that_key_and_its_items() {
    let sentence = "count of items.v that is m named by $params.k is 0";
    for (items, params, cause) in [
        (
            json!([{"v": "s"}, {"v": {}}]),
            json!({}),
            Cause::NotAnObject,
        ),
        (json!([{"v": null}]), json!({"k": null}), Cause::NotAnObject),
        (json!([{"v": {}}]), json!({"k": null}), Cause::Absent),
    ] {
        assert_eq!(cause_and_row(sentence, items, params).0, cause);
    }
}

#[test]
fn a_count_says_each_items_own_reads_beside_a_whose_key_that_isnt_text() {
    let clauses = tally_clauses(
        "count of items whose zz is m named by $params.k is 0",
        json!([{"v": 1}, {"v": 2}]),
        json!({"k": 3}),
    );
    assert_eq!(
        kinds_and_texts(&clauses),
        [
            (
                clause::Kind::Root,
                "$params.k is 3, which isn't text".to_string()
            ),
            (
                clause::Kind::Item,
                "item 1 of items: zz is missing, and m is missing".to_string()
            ),
            (
                clause::Kind::Item,
                "item 2 of items: zz is missing, and m is missing".to_string()
            ),
        ]
    );
}

#[test]
fn a_count_of_params_that_arent_an_object_says_them_as_its_list_and_no_item() {
    let clauses = tally_clauses_on("count of $params whose v is 1 is 1", json!({}), json!([3]));
    assert_eq!(
        kinds_and_texts(&clauses),
        [(
            clause::Kind::List,
            "$params is [3], which isn't an object".to_string()
        )]
    );
}

#[test]
fn a_sum_of_a_key_of_params_that_arent_an_object_says_them_as_its_list() {
    let clauses = tally_clauses_on("sum of $params.v is 1", json!({}), json!([3]));
    assert_eq!(
        kinds_and_texts(&clauses),
        [(
            clause::Kind::List,
            "$params is [3], which isn't an object".to_string()
        )]
    );
}

#[test]
fn a_count_of_a_key_of_params_that_are_a_number_says_they_arent_a_list_or_an_object() {
    let clauses = tally_clauses_on("count of $params.a is 1", json!({}), json!(3));
    assert_eq!(
        kinds_and_texts(&clauses),
        [(
            clause::Kind::List,
            "$params is 3, which isn't a list or an object".to_string()
        )]
    );
}

#[test]
fn a_sum_says_the_root_before_an_input_key_and_the_key() {
    let clauses = tally_clauses(
        "sum of items.n that is at least $params.q named by $input.k is 1",
        json!([{"n": 1}, {"n": 2}]),
        json!({"q": "s"}),
    );
    assert_eq!(
        kinds_and_texts(&clause::shown(&clauses)),
        [
            (
                clause::Kind::Root,
                "$params.q is \"s\", which isn't an object".to_string()
            ),
            (clause::Kind::Root, "$input.k is missing".to_string()),
        ]
    );
}

fn tally_clauses(sentence: &str, items: Value, params: Value) -> Vec<Clause> {
    tally_clauses_on(sentence, json!({"items": items}), params)
}

fn tally_clauses_on(sentence: &str, subject: Value, params: Value) -> Vec<Clause> {
    tally_clauses_in(sentence, json!({"things": [subject]}), params)
}

fn tally_clauses_in(sentence: &str, input: Value, params: Value) -> Vec<Clause> {
    let Check::Tally(tally) = lowered(sentence) else {
        panic!("{sentence} is not a count or a sum");
    };
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    tally.counted_clauses(&ctx)
}

fn kinds_causes_and_texts(clauses: &[Clause]) -> Vec<(clause::Kind, Cause, String)> {
    clauses
        .iter()
        .map(|said| {
            (
                said.kind,
                said.cause,
                clause::text(std::slice::from_ref(said)),
            )
        })
        .collect()
}

fn mixed_list_root(name: &str) -> (clause::Kind, Cause, String) {
    (
        clause::Kind::Root,
        Cause::Unusable,
        format!("{name} is [1, \"a\", null, and 1 more], which isn't a list of one kind of value"),
    )
}

fn item_said(cause: Cause, text: &str) -> (clause::Kind, Cause, String) {
    (clause::Kind::Item, cause, text.to_string())
}

#[test]
fn a_count_says_each_items_own_value_beside_a_root_list_that_isnt_one_kind_of_value() {
    let clauses = tally_clauses_in(
        "count of es whose v is not in $input.x is 0",
        json!({
            "things": [{"es": [{"v": 3}, {"v": "abc"}, {"v": [1, "a", null]}, {"v": null}, {"v": []}]}],
            "x": [1, "a", null, {"b": 2}],
        }),
        json!({}),
    );
    assert_eq!(
        kinds_causes_and_texts(&clauses),
        [
            mixed_list_root("$input.x"),
            item_said(
                Cause::Unusable,
                "item 1 of es: v is 3, which isn't a number or an object or text"
            ),
            item_said(
                Cause::Unusable,
                "item 2 of es: v is \"abc\", which isn't a number or an object or text"
            ),
            item_said(
                Cause::Unusable,
                "item 3 of es: v is [1, \"a\", null], which isn't a number or an object or text"
            ),
            item_said(Cause::Null, "item 4 of es: v is null"),
            item_said(
                Cause::Unusable,
                "item 5 of es: v is [], which isn't a number or an object or text"
            ),
        ]
    );
}

#[test]
fn a_count_says_each_items_own_list_beside_a_root_list_of_some_of_that_isnt_one_kind_of_value() {
    let clauses = tally_clauses_in(
        "count of es whose v contains some of $input.x is 0",
        json!({
            "things": [{"es": [{"v": ["a", "b"]}, {"v": null}]}],
            "x": [1, "a", null, {"b": 2}],
        }),
        json!({}),
    );
    assert_eq!(
        kinds_causes_and_texts(&clauses),
        [
            mixed_list_root("$input.x"),
            item_said(
                Cause::Unusable,
                "item 1 of es: v is [\"a\", \"b\"], which isn't a list of numbers or objects or text"
            ),
            item_said(Cause::Null, "item 2 of es: v is null"),
        ]
    );
}

#[test]
fn a_count_after_plus_says_each_items_own_value_beside_a_root_list_that_isnt_one_kind_of_value() {
    let clauses = tally_clauses_on(
        "count of fs plus count of es whose v is in $params.x is 0",
        json!({"fs": null, "es": [{}, {"v": []}, {"v": "abc"}, {"v": []}]}),
        json!({"x": [1, "a", null, {"b": 2}]}),
    );
    assert_eq!(
        kinds_causes_and_texts(&clauses),
        [
            (clause::Kind::List, Cause::Null, "fs is null".to_string()),
            mixed_list_root("$params.x"),
            item_said(Cause::Absent, "item 1 of es: v is missing"),
            item_said(
                Cause::Unusable,
                "item 2 of es: v is [], which isn't a number or an object or text"
            ),
            item_said(
                Cause::Unusable,
                "item 3 of es: v is \"abc\", which isn't a number or an object or text"
            ),
            item_said(
                Cause::Unusable,
                "item 4 of es: v is [], which isn't a number or an object or text"
            ),
        ]
    );
}

#[test]
fn test_root_list_of_only_nulls_names_no_kind_so_the_item_says_nothing() {
    let clauses = tally_clauses_in(
        "count of es whose v is in $input.x is 0",
        json!({"things": [{"es": [{"v": 3}, {"v": null}]}], "x": [null, null]}),
        json!({}),
    );
    assert_eq!(
        kinds_causes_and_texts(&clauses),
        [item_said(Cause::Null, "item 2 of es: v is null")]
    );
}

#[test]
fn a_count_names_no_kind_for_an_items_own_list_beside_an_empty_root_list() {
    let clauses = tally_clauses_in(
        "count of es whose v contains some of $input.x is 0",
        json!({"things": [{"es": [{"v": [1, "a"]}]}], "x": []}),
        json!({}),
    );
    assert_eq!(
        kinds_causes_and_texts(&clauses),
        [(
            clause::Kind::Root,
            Cause::Unusable,
            "$input.x is [], which isn't a list with at least one value".to_string()
        )]
    );
}

fn kinds_and_names(clauses: &[Clause]) -> Vec<(clause::Kind, &str)> {
    clauses
        .iter()
        .map(|clause| (clause.kind, clause.name.as_str()))
        .collect()
}

#[test]
fn a_count_says_its_roots_then_its_items_then_and_n_more() {
    let clauses = tally_clauses(
        "count of items whose v is at least $params.min is 1",
        json!([{}, {}, {}, {}, {}]),
        json!({"min": "s"}),
    );
    let names: Vec<String> = (1..=5).map(|n| format!("item {n} of items")).collect();
    let mut wanted = vec![(clause::Kind::Root, "$params.min")];
    wanted.extend(names.iter().map(|name| (clause::Kind::Item, name.as_str())));
    assert_eq!(kinds_and_names(&clauses), wanted);
    let shown = clause::shown(&clauses);
    assert_eq!(
        shown.last().map(|clause| clause.kind),
        Some(clause::Kind::More(2))
    );
    assert_eq!(
        clause::text(&shown),
        "$params.min is \"s\", which isn't a number; item 1 of items: v is missing; item 2 of items: v is missing; item 3 of items: v is missing; and 2 more"
    );
}

#[test]
fn a_count_in_a_whose_that_cant_be_read_says_its_items_once_with_one_and_n_more() {
    let clauses = tally_clauses(
        "count of items whose n is count of $params.pos.name is 2",
        json!([{"n": 1}, {"n": 2}]),
        json!({"pos": [{"name": "a"}, {}, {}, {}, {}, {}]}),
    );
    assert_eq!(
        clause::text(&clause::shown(&clauses)),
        "item 2 of $params.pos: name is missing; item 3 of $params.pos: name is missing; item 4 of $params.pos: name is missing; and 2 more"
    );
}

fn kinds_and_texts(clauses: &[Clause]) -> Vec<(clause::Kind, String)> {
    clauses
        .iter()
        .map(|said| (said.kind, clause::text(std::slice::from_ref(said))))
        .collect()
}

#[test]
fn a_sum_says_an_item_it_cant_add_as_an_item() {
    let clauses = tally_clauses(
        "sum of items.v is 1",
        json!([{"v": 1}, {"v": "a"}, {"v": null}]),
        json!({}),
    );
    assert_eq!(
        kinds_and_texts(&clauses),
        [
            (
                clause::Kind::Item,
                "item 2 of items: v is \"a\", which isn't a number".to_string()
            ),
            (clause::Kind::Item, "item 3 of items: v is null".to_string()),
        ]
    );
}

#[test]
fn a_root_whose_value_holds_a_semicolon_is_one_clause() {
    let clauses = tally_clauses(
        "count of items whose v is at least $params.min is 1",
        json!([{"v": 1}]),
        json!({"min": "a; item 1 of items: b"}),
    );
    assert_eq!(
        kinds_and_texts(&clauses),
        [(
            clause::Kind::Root,
            "$params.min is \"a; item 1 of items: b\", which isn't a number".to_string()
        )]
    );
}

#[test]
fn a_count_or_a_sum_whose_list_is_missing_null_or_not_a_list_says_it_as_a_list() {
    for sentence in ["count of items is 1", "sum of items.v is 1"] {
        for (subject, cause, said) in [
            (json!({}), Cause::Absent, "items is missing"),
            (json!({"items": null}), Cause::Null, "items is null"),
            (
                json!({"items": "s"}),
                Cause::Unusable,
                "items is \"s\", which isn't a list or an object",
            ),
        ] {
            let clauses = tally_clauses_on(sentence, subject, json!({}));
            assert_eq!(
                kinds_and_texts(&clauses),
                [(clause::Kind::List, said.to_string())],
                "{sentence}"
            );
            assert_eq!(clauses[0].cause, cause, "{sentence}");
        }
    }
}

#[test]
fn an_inner_list_a_count_cant_read_is_said_with_its_item_in_list_order() {
    let clauses = tally_clauses(
        "count of items.ys whose n is 1 is 9",
        json!([{"ys": [{"n": 1}, {}]}, {}]),
        json!({}),
    );
    assert_eq!(
        clause::text(&clause::shown(&clauses)),
        "item 1 of items: item 2 of ys: n is missing; item 2 of items: ys is missing"
    );
}

fn row_message(sentence: &str, items: Value, params: Value) -> String {
    let check = lowered(sentence);
    let Check::Tally(tally) = &check else {
        panic!("{sentence} is not a count or a sum");
    };
    let input = json!({"things": [{"items": items}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    let verdict = crate::ops::run(&check, &ctx);
    super::super::message::said_text(&with_all_items(
        tally,
        &ctx,
        verdict.cause,
        super::super::message::said(&check, &ctx, &verdict),
    ))
}

#[test]
fn a_count_after_a_side_says_three_items_and_then_and_n_more() {
    assert_eq!(
        row_message(
            "count of items whose v is 1 is $params.n",
            json!([{}, {}, {}, {}]),
            json!({}),
        ),
        "$params.n is missing, and item 1 of items: v is missing; item 2 of items: v is missing; item 3 of items: v is missing; and 1 more"
    );
}

#[test]
fn two_sums_in_a_row_each_say_their_own_items_joined_with_and() {
    assert_eq!(
        row_message(
            "sum of items.n plus sum of items.m is 100",
            json!([{"n": "y", "m": "z"}]),
            json!({}),
        ),
        "item 1 of items: n is \"y\", which isn't a number, and item 1 of items: m is \"z\", which isn't a number"
    );
}

#[test]
fn a_root_compared_ignoring_case_stands_in_as_text_so_each_item_is_read_on_its_own() {
    let check = lowered("v is $input.r ignoring case");
    let Some(Check::Compare(alone)) = without_roots(&check) else {
        panic!("no stand-in for {check:?}");
    };
    assert_eq!(alone.right, compare::Side::Value(json!("")));
    assert!(alone.ignoring.is_some());
    assert!(without_roots(&lowered("v is $input.r")).is_none());
}

fn lowered_in(scope: &Scope, sentence: &str) -> Check {
    let tree = s::parse_check(sentence).unwrap();
    crate::lower::lower_assertion(&tree.assertions[0], scope).unwrap()
}

fn derived_left(check: &Check) -> &Derived {
    let Check::Tally(tally) = check else {
        panic!("not a count or a sum");
    };
    let Side::Derived(derived) = &tally.left else {
        panic!("no count or sum on the left");
    };
    derived
}

#[test]
fn a_count_reads_a_hidden_alias_when_a_ref_step_of_its_list_names_it() {
    let scope = Scope::new().with_for_alias("g");
    let check = lowered_in(&scope, "count of xs named by g.k is 1");
    assert!(reads_derived(derived_left(&check), &["g"]));
    assert!(!reads_derived(derived_left(&check), &["h"]));
}

#[test]
fn a_whose_that_reads_no_hidden_alias_does_not_make_its_count_read_one() {
    let scope = Scope::new().with_for_alias("g");
    let check = lowered_in(&scope, "count of rs whose v is \"a\" is 1");
    assert!(!reads_derived(derived_left(&check), &["g"]));
}

#[test]
fn a_whose_that_reads_a_hidden_alias_makes_its_count_read_it() {
    let scope = Scope::new().with_for_alias("g");
    let check = lowered_in(&scope, "count of rs whose n is count of g is 1");
    assert!(reads_derived(derived_left(&check), &["g"]));
    assert!(!reads_derived(derived_left(&check), &["h"]));
}

#[test]
fn an_elapsed_term_reads_a_hidden_alias_named_on_either_end() {
    let scope = Scope::new().with_for_alias("g");
    let from = lowered_in(&scope, "days elapsed from g.a to y plus 1 is 2");
    let to = lowered_in(&scope, "days elapsed from x to g.b plus 1 is 2");
    let neither = lowered_in(&scope, "days elapsed from x to y plus 1 is 2");
    assert!(reads_derived(derived_left(&from), &["g"]));
    assert!(reads_derived(derived_left(&to), &["g"]));
    assert!(!reads_derived(derived_left(&neither), &["g"]));
}

fn report_row(sentence: &str, input: Value) -> Value {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": sentence}}}
    });
    let report = crate::report(&input, &policy, &json!({}));
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

fn row_says(sentence: &str, input: Value) -> (String, String) {
    let row = report_row(sentence, input);
    (
        row["cause"].as_str().unwrap().to_string(),
        row["message"].as_str().unwrap().to_string(),
    )
}

const IN_ROOT_LIST: &str = "count of xs whose v is in $input.rs.k is 2";

fn times(text: &str, part: &str) -> usize {
    text.matches(part).count()
}

#[test]
fn a_walked_root_that_is_not_an_object_is_said_once_and_before_the_count() {
    let message = row_says(
        IN_ROOT_LIST,
        json!({"rs": [1], "things": [{"id": 1, "xs": []}]}),
    )
    .1;
    assert!(message.starts_with("item 1 of $input.rs is 1, which isn't an object"));
    assert_eq!(times(&message, "item 1 of $input.rs"), 1);
}

#[test]
fn a_walked_root_item_that_lacks_the_field_is_said_once_and_before_the_item_that_lacks_its_own() {
    let (cause, message) = row_says(
        IN_ROOT_LIST,
        json!({"rs": [{"k": 1}, {}], "things": [{"id": 1, "xs": [{"v": 1}, {}]}]}),
    );
    assert_eq!(cause, "absent");
    assert!(message.starts_with("item 2 of $input.rs: k is missing"));
    assert_eq!(times(&message, "item 2 of $input.rs"), 1);
}

#[test]
fn a_walked_root_that_is_unusable_and_an_item_that_is_null_fail_as_unusable() {
    let (cause, message) = row_says(
        IN_ROOT_LIST,
        json!({"rs": [1], "things": [{"id": 1, "xs": [{"v": null}]}]}),
    );
    assert_eq!(cause, "unusable");
    assert!(message.starts_with("item 1 of $input.rs is 1, which isn't an object"));
    assert_eq!(times(&message, "item 1 of $input.rs"), 1);
}

#[test]
fn a_walked_root_in_a_second_whose_is_said_with_the_one_in_the_first_and_not_its_items() {
    assert_eq!(
        row_says(
            "count of xs whose v is in $input.rs.k and whose w is in $input.q.k is 2",
            json!({"rs": [1], "q": "x", "things": [{"id": 1}]})
        )
        .1,
        "$input.q is \"x\", which isn't an object; xs is missing"
    );
}

#[test]
fn a_sum_says_the_items_that_are_not_numbers_and_not_the_walked_root_that_reads_fine() {
    assert_eq!(
        row_says(
            "sum of xs.n that is in $input.rs.k is 3",
            json!({"rs": [{"k": "s"}], "things": [{"id": 1, "xs": [{"n": "s"}]}]})
        )
        .1,
        "item 1 of xs: n is \"s\", which isn't a number"
    );
}

fn all_items(sentence: &str, items: Value, params: Value, cause: Cause, said: Said) -> String {
    let check = lowered(sentence);
    let Check::Tally(tally) = &check else {
        panic!("{sentence} is not a count or a sum");
    };
    let input = json!({"things": [{"items": items}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: Some(&params),
        aliases: BTreeMap::new(),
    };
    super::super::message::said_text(&with_all_items(tally, &ctx, cause, said))
}

#[test]
fn a_row_that_is_not_failing_gets_no_items_added_to_what_it_says() {
    assert_eq!(
        all_items(
            "count of items whose v is 1 is $params.n",
            json!([{}]),
            json!({}),
            Cause::Satisfied,
            Vec::new(),
        ),
        ""
    );
    assert_eq!(
        all_items(
            "count of items whose v is 1 is $params.n",
            json!([{}]),
            json!({}),
            Cause::Absent,
            Vec::new(),
        ),
        "item 1 of items: v is missing"
    );
}

#[test]
fn params_that_are_a_list_are_said_first_when_the_count_reads_them_whole() {
    let said = all_items(
        "count of $params is 1",
        json!([]),
        json!([1, 2]),
        Cause::Unusable,
        Vec::new(),
    );
    assert!(said.starts_with("$params is [1, 2], which isn't an object"));
}

#[test]
fn params_that_are_a_list_are_not_said_first_when_the_count_reads_a_key_of_them() {
    assert_eq!(
        all_items(
            "count of $params.xs is 1",
            json!([]),
            json!([1, 2]),
            Cause::Unusable,
            Vec::new(),
        ),
        "$params is [1, 2], which isn't an object"
    );
}

const ROOT_NOT_AN_OBJECT: &str = "item 1 of $input.rs is 1, which isn't an object";

fn with_roots_said(said: Said) -> String {
    let check = lowered(IN_ROOT_LIST);
    let Check::Tally(tally) = &check else {
        panic!("not a count");
    };
    let input = json!({"rs": [1], "things": [{"xs": []}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    super::super::message::said_text(&with_walked_roots(tally, &ctx, said))
}

#[test]
fn a_walked_root_the_row_already_says_is_said_once_and_first() {
    assert_eq!(
        with_roots_said(vec![
            vec![Piece::Said("other".to_string())],
            vec![Piece::Said(ROOT_NOT_AN_OBJECT.to_string())],
        ]),
        format!("{ROOT_NOT_AN_OBJECT}; other")
    );
}

#[test]
fn a_root_clause_of_the_row_that_is_not_a_walked_root_stays() {
    let missing = Clause::root("$input.q", Cause::Absent, "$input.q is missing".to_string());
    let walked = Clause::root("$input.rs", Cause::Unusable, ROOT_NOT_AN_OBJECT.to_string());
    assert_eq!(
        with_roots_said(vec![vec![Piece::Counted(vec![missing, walked])]]),
        format!("{ROOT_NOT_AN_OBJECT}; $input.q is missing")
    );
}

#[test]
fn a_walked_root_is_not_added_again_when_the_roots_already_have_it() {
    let check = lowered(IN_ROOT_LIST);
    let Check::Tally(tally) = &check else {
        panic!("not a count");
    };
    let input = json!({"rs": [1], "things": [{"xs": []}]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let outer = outer_ctx(&ctx);
    let whose: Vec<&Check> = tally.counted_whose().collect();
    let roots = super::super::message::walked_root_clauses(&whose, &outer);
    assert_eq!(roots.len(), 1);
    assert_eq!(and_walked_roots(roots.clone(), &whose, &outer).len(), 1);
    assert_eq!(and_walked_roots(Vec::new(), &whose, &outer).len(), 1);
}

fn item_clause(name: &str) -> Clause {
    Clause::item(name, Cause::Absent, String::new(), Vec::new())
}

#[test]
fn an_item_is_its_own_when_it_is_the_item_or_one_of_its_parts() {
    assert!(own_item(&item_clause("item 1 of xs"), "item 1 of xs"));
    assert!(own_item(&item_clause("item 1 of xs: ys"), "item 1 of xs"));
}

#[test]
fn an_item_is_not_its_own_when_another_item_starts_with_the_same_text() {
    assert!(!own_item(&item_clause("item 10 of xs"), "item 1 of xs"));
    assert!(!own_item(&item_clause("item 1 of xs2: ys"), "item 1 of xs"));
}

#[test]
fn a_list_with_the_name_of_an_item_is_not_that_item() {
    let list = Clause::list("item 1 of xs", Cause::Absent, String::new());
    assert!(!own_item(&list, "item 1 of xs"));
}

fn counted_text(sentence: &str, items: Value) -> String {
    clause::text(&clause::shown(&tally_clauses(sentence, items, json!({}))))
}

#[test]
fn an_item_that_stops_before_its_end_says_what_it_met() {
    assert_eq!(
        counted_text("sum of items.n is 3", json!([{}])),
        "item 1 of items: n is missing"
    );
    assert_eq!(
        counted_text("count of items.m.n is 3", json!([{"m": 1}])),
        "item 1 of items: m is 1, which isn't an object"
    );
}

fn faults_of(sentence: &str, input: Value) -> Vec<(Cause, String)> {
    let Check::Tally(tally) = lowered(sentence) else {
        panic!("{sentence} is not a count or a sum");
    };
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let path = tally.counted_paths()[0].clone();
    counted_faults(&tally, &path, &ctx)
}

#[test]
fn a_counted_list_that_cannot_be_read_is_a_fault_of_its_path() {
    assert_eq!(
        faults_of("count of xs whose v is 1 is 2", json!({"things": [{}]})),
        [(Cause::Absent, "xs is missing".to_string())]
    );
    assert_eq!(
        faults_of(
            "count of xs whose v is 1 is 2",
            json!({"things": [{"xs": null}]})
        ),
        [(Cause::Null, "xs is null".to_string())]
    );
    assert!(
        faults_of(
            "count of xs whose v is 1 is 2",
            json!({"things": [{"xs": [{"v": 1}]}]})
        )
        .is_empty()
    );
}

#[test]
fn the_refs_a_whose_walks_are_the_refs_the_count_walks() {
    let walking = |sentence: &str| -> Vec<String> {
        lowered(sentence)
            .walking_refs()
            .iter()
            .map(crate::name::name)
            .collect()
    };
    assert_eq!(
        walking("count of xs whose v is in $input.rs.k is 2"),
        ["$input.rs.k"]
    );
    assert!(walking("count of xs whose v is 1 is 2").is_empty());
}

fn list_state(sentence: &str, subject: Value) -> crate::path::Outcome {
    let Check::Tally(tally) = lowered(sentence) else {
        panic!("{sentence} is not a count or a sum");
    };
    let input = json!({"things": [subject]});
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        subject: Located {
            value: &input["things"][0],
            location: Location::input_root().key("things").index(0),
        },
        input: &input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let outer = outer_ctx(&ctx);
    let path = tally.counted_paths()[0].clone();
    let walked = walk::walk(
        &path,
        &outer,
        Options {
            if_any: false,
            empty_adds_nothing: true,
        },
    );
    walked_list(&walked, &path, &outer).state
}

#[test]
fn a_walked_list_is_absent_when_the_object_it_walks_has_no_such_field() {
    assert_eq!(
        list_state("count of xs.ys is 1", json!({"xs": {"a": {}}})),
        crate::path::Outcome::Absent
    );
}

#[test]
fn a_walked_list_is_found_when_only_an_item_of_it_lacks_the_field() {
    assert_eq!(
        list_state("count of xs.ys is 1", json!({"xs": [{"ys": [1]}, {}]})),
        crate::path::Outcome::Found
    );
}

fn list_read(sentence: &str, subject: Value, list: &str) -> crate::path::Outcome {
    verdict_of(sentence, subject)
        .inputs
        .into_iter()
        .find(|input| input.name == list)
        .unwrap_or_else(|| panic!("{sentence} has no input {list}"))
        .state
}

#[test]
fn a_count_of_or_a_sum_of_a_value_that_is_not_a_list_or_an_object_reads_it_as_unusable() {
    for value in [json!(3), json!("s"), json!(true)] {
        for sentence in ["count of ms is 1", "sum of ms is 1"] {
            assert_eq!(
                list_read(sentence, json!({"ms": value}), "ms"),
                crate::path::Outcome::Unusable,
                "{sentence} on {value}"
            );
        }
    }
    assert_eq!(
        list_read("count of y[0].v is 1", json!({"y": [{"v": 1}]}), "y[0].v"),
        crate::path::Outcome::Unusable
    );
    assert_eq!(
        list_read(
            "count of x named by zz is 1",
            json!({"x": {"k": 5}, "zz": "k"}),
            "x named by zz"
        ),
        crate::path::Outcome::Unusable
    );
}

#[test]
fn a_count_of_or_a_sum_of_member_of_a_value_that_is_not_an_object_reads_it_as_unusable() {
    for value in [json!(3), json!("s"), json!(true), json!([1])] {
        for sentence in [
            "count of member of costs is 1",
            "sum of member of costs is at most 3",
        ] {
            assert_eq!(
                list_read(sentence, json!({"costs": value}), "costs"),
                crate::path::Outcome::Unusable,
                "{sentence} on {value}"
            );
        }
    }
}

#[test]
fn half_a_microsecond_rounds_up_and_less_rounds_down_whatever_its_length() {
    for (from, to, wanted) in [
        (0.0, 0.0000005, "0.000001"),
        (0.0, 0.0000004, "0"),
        (0.0, 0.00000004, "0"),
        (0.0, 0.00000005, "0"),
    ] {
        assert_eq!(
            cause(
                &format!("seconds elapsed from x to y is {wanted}"),
                json!({"x": from, "y": to})
            ),
            Cause::Satisfied,
            "{from} {to}"
        );
    }
}

#[test]
fn a_count_or_a_sum_fails_an_item_whose_path_meets_null_before_its_end_as_null_naming_that_step() {
    for sentence in [
        "count of items.m.n is 3",
        "sum of items.m.n is 3",
        "count of items.m.n.o is 3",
    ] {
        assert_eq!(
            cause(sentence, json!({"items": [{"m": null}]})),
            Cause::Null,
            "{sentence}"
        );
        assert_eq!(
            kinds_causes_and_texts(&tally_clauses(sentence, json!([{"m": null}]), json!({}))),
            [item_said(Cause::Null, "item 1 of items: m is null")],
            "{sentence}"
        );
    }
}

#[test]
fn a_sum_of_one_number_with_fifteen_decimals_is_that_number() {
    assert_eq!(sum_text(&["1e-15"]), "0.000000000000001");
    assert_eq!(sum_text(&["1e-15", "1e-15"]), "0.000000000000002");
}

#[test]
fn text_that_is_not_digits_has_no_parts() {
    for text in ["", ".", "-", "e5", "1x", "1.5y", "x"] {
        assert!(Parts::of(text).is_none(), "{text}");
    }
    assert!(Parts::of("1.5").is_some());
}

#[test]
fn a_count_or_a_sum_still_says_a_missing_step_as_missing_beside_one_that_is_null() {
    for sentence in ["count of items.m.n is 3", "sum of items.m.n is 3"] {
        assert_eq!(
            cause(sentence, json!({"items": [{}, {"m": null}]})),
            Cause::Absent,
            "{sentence}"
        );
        assert_eq!(
            kinds_causes_and_texts(&tally_clauses(
                sentence,
                json!([{}, {"m": null}]),
                json!({})
            )),
            [
                item_said(Cause::Absent, "item 1 of items: m.n is missing"),
                item_said(Cause::Null, "item 2 of items: m is null"),
            ],
            "{sentence}"
        );
    }
}

#[test]
fn an_empty_list_on_the_right_of_a_whose_or_a_that_fails_the_count_as_value() {
    for sentence in [
        "count of xs whose v is in $input.cs.name is 0",
        "count of xs whose v is not one of $input.cs.name is 0",
        "count of xs whose v matches $input.cs.name is 0",
        "count of xs.v that is in $input.cs.name is 0",
        "sum of xs.n that is in $input.cs.name is 0",
    ] {
        for xs in [json!([]), json!([{"v": "a", "n": 1}])] {
            let input = json!({"cs": [], "things": [{"xs": xs}]});
            assert_eq!(
                verdict_on_input(sentence, input).cause,
                Cause::Value,
                "{sentence} on {xs}"
            );
        }
    }
}

#[test]
fn an_empty_list_on_the_right_of_a_whose_still_lets_each_item_say_its_own_problem() {
    for sentence in [
        "count of xs whose v is in $input.cs.name is 0",
        "count of xs whose v is not one of $input.cs.name is 0",
        "count of xs.v that is in $input.cs.name is 0",
    ] {
        let input = json!({"cs": [], "things": [{"xs": [{}]}]});
        assert_eq!(
            verdict_on_input(sentence, input.clone()).cause,
            Cause::Absent,
            "{sentence}"
        );
        assert_eq!(
            kinds_causes_and_texts(&tally_clauses_in(sentence, input, json!({}))),
            [
                (
                    clause::Kind::Root,
                    Cause::Value,
                    "$input.cs is []".to_string()
                ),
                item_said(Cause::Absent, "item 1 of xs: v is missing"),
            ],
            "{sentence}"
        );
    }
}

#[test]
fn an_empty_list_on_the_right_of_a_whose_is_said_once_whatever_the_items() {
    for xs in [json!([]), json!([{"v": "a"}, {"v": "b"}])] {
        assert_eq!(
            kinds_causes_and_texts(&tally_clauses_in(
                "count of xs whose v is in $input.cs.name is 0",
                json!({"cs": [], "things": [{"xs": xs}]}),
                json!({})
            )),
            [(
                clause::Kind::Root,
                Cause::Value,
                "$input.cs is []".to_string()
            )],
            "{xs}"
        );
    }
}

#[test]
fn a_plus_beside_an_empty_list_on_the_right_of_a_whose_says_only_the_list() {
    for k in [json!(0), json!(5)] {
        assert_eq!(
            row_says(
                "k plus count of xs whose v is in $input.cs.name is 0",
                json!({"cs": [], "things": [{"id": 1, "k": k, "xs": [{"v": "a"}]}]})
            ),
            ("value".to_string(), "$input.cs is []".to_string()),
            "{k}"
        );
    }
}

fn read_of(state: crate::path::Outcome, locations: &[&str]) -> Input {
    Input {
        name: "m".to_string(),
        value: json!([]),
        locations: locations.iter().map(|l| l.to_string()).collect(),
        part: None,
        state,
        null_at: None,
        worked: false,
    }
}

#[test]
fn two_reads_of_the_same_value_merge_into_one_input_with_the_worst_outcome() {
    use crate::path::Outcome;
    let usable = read_of(Outcome::Found, &[]);
    let unusable = read_of(Outcome::Unusable, &[]);
    let absent = read_of(Outcome::Absent, &[]);
    let elsewhere = read_of(Outcome::Absent, &["/m"]);
    for (entries, wanted) in [
        (
            vec![usable.clone(), unusable.clone()],
            vec![unusable.clone()],
        ),
        (
            vec![unusable.clone(), usable.clone()],
            vec![unusable.clone()],
        ),
        (
            vec![absent, unusable.clone(), usable.clone()],
            vec![unusable.clone()],
        ),
        (vec![usable.clone(), usable.clone()], vec![usable]),
        (
            vec![unusable.clone(), elsewhere.clone()],
            vec![unusable, elsewhere],
        ),
    ] {
        assert_eq!(merged(entries.clone()), wanted, "{entries:?}");
    }
}

#[test]
fn a_walked_list_after_is_in_ignoring_case_in_a_count_whose_is_said_before_a_list_that_is_missing()
{
    assert_eq!(
        cause_and_row_in(
            "count of xs whose v is in $input.cs.name ignoring case is 0",
            json!({"things": [{}], "cs": [{"name": 3}]}),
            json!({}),
        ),
        (
            Cause::Unusable,
            "item 1 of $input.cs: name is 3, which isn't text; xs is missing".to_string()
        )
    );
    assert_eq!(
        cause_and_row_in(
            "count of xs whose v is in $input.cs.name ignoring case is 0",
            json!({"things": [{}], "cs": [{"name": "a"}]}),
            json!({}),
        ),
        (Cause::Absent, "xs is missing".to_string())
    );
}
