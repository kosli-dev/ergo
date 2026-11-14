use super::*;
use crate::path::{Located, Location, Path, Start, Step};
use serde_json::json;
use std::collections::BTreeMap;

fn field(name: &str) -> Side {
    Side::Path(Path {
        start: Start::Subject,
        steps: vec![Step::Key(name.to_string())],
    })
}

fn cause_with(subject: Value, order: Order) -> Cause {
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
    let check = CompareTime {
        left: field("a"),
        right: field("b"),
        order,
    };
    run(&check, &ctx).cause
}

fn before(a: Value, b: Value) -> Cause {
    cause_with(json!({"a": a, "b": b}), Order::Before)
}

#[test]
fn compares_rfc3339_strings_as_instants() {
    assert_eq!(
        before(json!("2024-01-01T00:00:00Z"), json!("2024-01-01T00:00:01Z")),
        Cause::Satisfied
    );
    assert_eq!(
        before(json!("2024-01-01T00:00:01Z"), json!("2024-01-01T00:00:00Z")),
        Cause::Value
    );
    assert_eq!(
        before(
            json!("2024-01-01T00:00:00.000000001Z"),
            json!("2024-01-01T00:00:00.00000001Z")
        ),
        Cause::Satisfied
    );
}

#[test]
fn an_offset_names_the_same_instant_as_utc() {
    let same = json!({"a": "2024-01-01T01:00:00+01:00", "b": "2024-01-01T00:00:00Z"});
    assert_eq!(
        cause_with(same.clone(), Order::OnOrBefore),
        Cause::Satisfied
    );
    assert_eq!(cause_with(same.clone(), Order::OnOrAfter), Cause::Satisfied);
    assert_eq!(cause_with(same.clone(), Order::Before), Cause::Value);
    assert_eq!(cause_with(same, Order::After), Cause::Value);
}

#[test]
fn only_the_first_nine_digits_of_a_fraction_count() {
    assert_eq!(
        instant_nanos("2024-01-01T00:00:00.1234567891Z"),
        instant_nanos("2024-01-01T00:00:00.123456789Z")
    );
}

#[test]
fn compares_numbers_by_value_and_dates_as_days() {
    assert_eq!(before(json!(1.5), json!(2)), Cause::Satisfied);
    assert_eq!(
        cause_with(
            serde_json::from_str(r#"{"a": 2, "b": 2.0}"#).unwrap(),
            Order::OnOrAfter
        ),
        Cause::Satisfied
    );
    assert_eq!(
        before(json!("2024-01-31"), json!("2024-02-01")),
        Cause::Satisfied
    );
    assert_eq!(
        before(json!("2024-01-02"), json!("2024-01-01")),
        Cause::Value
    );
}

#[test]
fn two_times_in_different_formats_fail_as_unusable() {
    assert_eq!(
        before(json!("2024-01-01T00:00:00Z"), json!(1)),
        Cause::Unusable
    );
    assert_eq!(
        before(json!("2024-01-01"), json!("2024-01-02T00:00:00Z")),
        Cause::Unusable
    );
    assert_eq!(before(json!(1), json!("2024-01-02")), Cause::Unusable);
}

#[test]
fn anything_that_is_not_a_time_fails_as_unusable() {
    let later = json!("2024-03-02T00:00:01Z");
    for bad in [
        "2024-01-01t00:00:00z",
        "2024-02-30T00:00:00Z",
        "1900-02-29T00:00:00Z",
        "1677-12-31T23:59:59Z",
        "2262-01-01T00:00:00Z",
        "2024-01-01T00:00:00",
        "2016-12-31T23:59:60Z",
        "2024-01-01T24:00:00Z",
        "2024-01-01 00:00:00Z",
        "2024-01-01T00:00:00+0100",
        "2024-01-01T00:00:00.Z",
        "2024-01-01T00:00:00+24:00",
        "2024-01-01T00:00:00+01:60",
        "2024-01-01T00:00:00Zx",
        "2024-1-01T00:00:00Z",
        "+024-01-01T00:00:00Z",
        "yesterday",
    ] {
        assert_eq!(before(json!(bad), later.clone()), Cause::Unusable, "{bad}");
    }
    for bad in [
        "2023-02-29",
        "2024-13-01",
        "2024-00-10",
        "2024-01-00",
        "2024-01-1",
        "2024-01-01 ",
    ] {
        assert_eq!(
            before(json!(bad), json!("2024-12-01")),
            Cause::Unusable,
            "{bad}"
        );
    }
    assert_eq!(before(json!(true), json!(false)), Cause::Unusable);
}

#[test]
fn the_first_and_last_years_allowed_are_times() {
    assert_eq!(
        before(
            json!("1678-01-01T00:00:00+05:00"),
            json!("2024-01-01T00:00:00Z")
        ),
        Cause::Satisfied
    );
    assert_eq!(
        before(
            json!("2024-01-01T00:00:00Z"),
            json!("2261-12-31T23:59:59-05:00")
        ),
        Cause::Satisfied
    );
    assert_eq!(
        before(json!("2000-02-29T00:00:00Z"), json!("2024-01-01T00:00:00Z")),
        Cause::Satisfied
    );
    assert_eq!(
        before(json!("1678-01-01"), json!("2261-12-31")),
        Cause::Satisfied
    );
}

#[test]
fn a_missing_or_null_side_fails_with_the_worse_outcome() {
    assert_eq!(
        cause_with(json!({"b": "2017-01-02T00:00:00Z"}), Order::Before),
        Cause::Absent
    );
    assert_eq!(
        cause_with(
            json!({"a": null, "b": "2017-01-02T00:00:00Z"}),
            Order::Before
        ),
        Cause::Null
    );
    assert_eq!(cause_with(json!({"a": null}), Order::Before), Cause::Absent);
}

#[test]
fn days_count_from_1970() {
    assert_eq!(date_days("1970-01-01"), Some(0));
    assert_eq!(date_days("1970-01-02"), Some(1));
    assert_eq!(date_days("1969-12-31"), Some(-1));
    assert_eq!(
        instant_nanos("1970-01-01T00:00:01Z"),
        Some(NANOS_PER_SECOND)
    );
    assert_eq!(instant_nanos("1970-01-01T01:00:00+01:00"), Some(0));
}

#[test]
fn a_written_time_on_the_right_has_no_input() {
    let input = json!({"things": [{"a": "2024-01-01"}]});
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
    let check = CompareTime {
        left: field("a"),
        right: Side::Value(json!("2024-06-01")),
        order: Order::Before,
    };
    let v = run(&check, &ctx);
    assert_eq!(v.cause, Cause::Satisfied);
    assert_eq!(v.inputs.len(), 1);
}
