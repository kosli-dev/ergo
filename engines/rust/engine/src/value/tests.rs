use super::*;

fn v(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

fn eq(a: &Value, b: &Value) -> bool {
    equal(a, b).unwrap()
}

fn num(text: &str) -> serde_json::Number {
    match v(text) {
        Value::Number(n) => n,
        _ => panic!("not a number"),
    }
}

#[test]
fn one_written_four_ways_is_equal() {
    for other in ["1.0", "1e0", "10e-1", "0.1e1", "1.000"] {
        assert!(eq(&v("1"), &v(other)), "{other}");
    }
}

#[test]
fn numbers_past_a_float_are_compared_exactly() {
    assert!(!eq(&v("9007199254740993"), &v("9007199254740992")));
    assert_eq!(
        compare_numbers(&num("9007199254740993"), &num("9007199254740992")),
        Some(Ordering::Greater)
    );
}

#[test]
fn huge_exponents_are_compared_without_a_float() {
    assert!(eq(&v("1e400"), &v("10e399")));
    assert!(!eq(&v("1e400"), &v("1e401")));
    assert!(eq(&v("1e-400"), &v("10e-401")));
    assert_eq!(
        compare_numbers(&num("1e400"), &num("1e399")),
        Some(Ordering::Greater)
    );
    assert_eq!(
        compare_numbers(&num("1e-400"), &num("0")),
        Some(Ordering::Greater)
    );
}

#[test]
fn an_exponent_of_36_digits_orders_exactly() {
    let low = format!("1e1{}", "0".repeat(35));
    let high = format!("1e1{}1", "0".repeat(34));
    assert_eq!(
        compare_numbers(&num(&high), &num(&low)),
        Some(Ordering::Greater)
    );
    assert_eq!(
        compare_numbers(&num(&low), &num(&high)),
        Some(Ordering::Less)
    );
    assert_eq!(
        compare_numbers(
            &num(&format!("1e-1{}1", "0".repeat(34))),
            &num(&format!("1e-1{}", "0".repeat(35)))
        ),
        Some(Ordering::Less)
    );
}

#[test]
fn exponents_of_31_digits_that_differ_in_the_last_digit_are_not_equal() {
    let low = "1e1000000000000000000000000000000";
    let high = "1e1000000000000000000000000000001";
    assert_eq!(
        compare_numbers(&num(high), &num(low)),
        Some(Ordering::Greater)
    );
    assert_eq!(equal(&v(low), &v(high)), Some(false));
}

#[test]
fn a_number_whose_exponent_has_more_than_36_digits_cannot_be_read() {
    let big = format!("1e1{}", "0".repeat(36));
    assert_eq!(compare_numbers(&num(&big), &num("1e400")), None);
    assert_eq!(compare_numbers(&num(&big), &num(&big)), None);
    assert_eq!(equal(&v(&big), &v(&big)), None);
    assert_eq!(
        equal(&v(&format!("[{big}]")), &v(&format!("[{big}]"))),
        None
    );
    assert!(!is_readable(&num(&format!("1e-1{}", "0".repeat(36)))));
}

#[test]
fn values_that_differ_elsewhere_are_unequal_even_with_a_number_that_cannot_be_read() {
    let big = format!("1e1{}", "0".repeat(36));
    assert_eq!(
        equal(&v(&format!("[{big}, 1]")), &v(&format!("[{big}, 2]"))),
        Some(false)
    );
    assert_eq!(
        equal(&v(&format!("[{big}]")), &v(&format!("[{big}, 1]"))),
        Some(false)
    );
    assert_eq!(equal(&v(&big), &v("\"a\"")), Some(false));
}

#[test]
fn zero_is_zero_however_it_is_written() {
    for zero in ["0", "0.0", "-0", "0e5", "-0.000e-3"] {
        assert!(eq(&v("0"), &v(zero)), "{zero}");
    }
}

#[test]
fn numbers_order_by_sign_then_size() {
    let order = |a, b| compare_numbers(&num(a), &num(b));
    assert_eq!(order("-1", "1"), Some(Ordering::Less));
    assert_eq!(order("-2", "-1"), Some(Ordering::Less));
    assert_eq!(order("-1", "-2"), Some(Ordering::Greater));
    assert_eq!(order("-1", "0"), Some(Ordering::Less));
    assert_eq!(order("0", "-1"), Some(Ordering::Greater));
    assert_eq!(order("0", "1"), Some(Ordering::Less));
    assert_eq!(order("1", "0"), Some(Ordering::Greater));
    assert_eq!(order("0.5", "0.25"), Some(Ordering::Greater));
    assert_eq!(order("12", "123"), Some(Ordering::Less));
    assert_eq!(order("99", "100"), Some(Ordering::Less));
    assert_eq!(order("0.001", "0.01"), Some(Ordering::Less));
}

#[test]
fn between_includes_both_ends() {
    let inside = |lo, n, hi| between(&num(lo), &num(n), &num(hi));
    assert_eq!(inside("1", "1", "3"), Some(true));
    assert_eq!(inside("1", "3", "3"), Some(true));
    assert_eq!(inside("1", "0.9", "3"), Some(false));
    assert_eq!(inside("1", "3.1", "3"), Some(false));
}

#[test]
fn a_string_never_equals_a_number() {
    assert!(!eq(&v("\"1\""), &v("1")));
}

#[test]
fn types_never_equal_each_other() {
    assert!(!eq(&v("null"), &v("false")));
    assert!(!eq(&v("0"), &v("false")));
    assert!(!eq(&v("[]"), &v("{}")));
    assert!(!eq(&v("null"), &v("0")));
}

#[test]
fn lists_compare_in_order_and_by_length() {
    assert!(eq(&v("[1, 2]"), &v("[1.0, 2e0]")));
    assert!(!eq(&v("[1, 2]"), &v("[2, 1]")));
    assert!(!eq(&v("[1]"), &v("[1, 1]")));
}

#[test]
fn objects_compare_by_keys_whatever_their_order() {
    assert!(eq(&v("{\"a\": 1, \"b\": 2}"), &v("{\"b\": 2.0, \"a\": 1}")));
    assert!(!eq(&v("{\"a\": 1}"), &v("{\"a\": 1, \"b\": 2}")));
    assert!(!eq(&v("{\"a\": 1, \"b\": 2}"), &v("{\"a\": 1, \"c\": 2}")));
    assert!(!eq(&v("{\"a\": null}"), &v("{\"b\": null}")));
}

#[test]
fn strings_compare_by_code_points() {
    assert!(eq(&v("\"\\u00e9\""), &v("\"é\"")));
    assert!(!eq(&v("\"e\\u0301\""), &v("\"é\"")));
}

#[test]
fn type_names_are_the_spec_words() {
    assert_eq!(type_name(&v("null")), "null");
    assert_eq!(type_name(&v("true")), "boolean");
    assert_eq!(type_name(&v("1")), "number");
    assert_eq!(type_name(&v("\"s\"")), "string");
    assert_eq!(type_name(&v("[]")), "list");
    assert_eq!(type_name(&v("{}")), "object");
}

#[test]
fn json_text_writes_numbers_as_plain_decimals() {
    for (written, plain) in [
        ("1.50", "1.5"),
        ("-0.0", "0"),
        ("-0", "0"),
        ("100.0", "100"),
        ("1e2", "100"),
        ("2.5e-3", "0.0025"),
        ("-1.25e1", "-12.5"),
        ("0.000", "0"),
        ("12345678901234567890", "12345678901234567890"),
        (
            "0.1000000000000000055511151231257827",
            "0.1000000000000000055511151231257827",
        ),
        (
            "123456789012345678901234567890.5",
            "123456789012345678901234567890.5",
        ),
        ("1e-300", &format!("0.{}1", "0".repeat(299))),
    ] {
        assert_eq!(json_text(&v(written)), plain, "{written}");
    }
}

#[test]
fn a_number_past_a_float_keeps_the_text_serde_json_gives_it() {
    assert_eq!(json_text(&v("1e-400")), "1e-400");
    assert_eq!(json_text(&v("-1e400")), "-1e+400");
}

#[test]
fn a_literal_past_a_float_is_shown_as_out_of_range() {
    assert_eq!(literal_text(&v("1e400")), "<number out of range>");
    assert_eq!(literal_text(&v("[1, 1e-400]")), "<number out of range>");
    assert_eq!(literal_text(&v("1.50")), "1.5");
    assert_eq!(literal_text(&v("0e400")), "0");
}

#[test]
fn json_text_writes_the_numbers_inside_lists_and_objects_plain() {
    assert_eq!(json_text(&v("[1.0, \"a\"]")), "[1,\"a\"]");
    assert_eq!(json_text(&v("{\"k\": 2.50}")), "{\"k\":2.5}");
}

#[test]
fn json_text_sorts_as_bytes() {
    let mut texts = [
        json_text(&v("3")),
        json_text(&v("10")),
        json_text(&v("\"b\"")),
    ];
    texts.sort();
    assert_eq!(texts, ["\"b\"", "10", "3"]);
}

#[test]
fn positions_are_whole_numbers_up_to_the_largest_a_float_holds() {
    let pos = |t: &str| Decimal::parse(t).unwrap().as_position();
    assert_eq!(pos("0"), Some(0));
    assert_eq!(pos("-0"), Some(0));
    assert_eq!(pos("3"), Some(3));
    assert_eq!(pos("3.0"), Some(3));
    assert_eq!(pos("1e2"), Some(100));
    assert_eq!(pos("9007199254740991"), Some(9_007_199_254_740_991));
    assert_eq!(pos("9007199254740992"), None);
    assert_eq!(pos("1.5"), None);
    assert_eq!(pos("-1"), None);
    assert_eq!(pos("1e400"), None);
    assert_eq!(pos("1e-1"), None);
}

#[test]
fn whole_numbers_of_zero_or_more_are_what_min_subjects_takes() {
    let whole = |t: &str| Decimal::parse(t).unwrap().is_non_negative_whole();
    for good in ["0", "-0", "1", "2.0", "1e2", "10e-1", "1e400"] {
        assert!(whole(good), "{good}");
    }
    for bad in ["-1", "1.5", "1e-1", "-1e400", "0.5"] {
        assert!(!whole(bad), "{bad}");
    }
}

#[test]
fn text_that_is_not_a_number_does_not_parse() {
    for bad in ["", "-", ".", "1e", "1ea", "a", "1.2.3", "1e+"] {
        assert!(Decimal::parse(bad).is_none(), "{bad}");
    }
}
