use ergo_cli::yaml::parse;
use serde_json::{Value, json};

fn value(text: &str) -> Value {
    parse(&format!("v: {text}\n")).unwrap()["v"].clone()
}

fn digits(text: &str) -> String {
    value(text).to_string()
}

fn digits_in_json(text: &str) -> String {
    serde_json::from_str::<Value>(text).unwrap().to_string()
}

fn same(text: &str, expected: Value) {
    let got = value(text);
    match (got.as_f64(), expected.as_f64()) {
        (Some(a), Some(b)) => assert_eq!(a, b, "{text}"),
        _ => assert_eq!(got, expected, "{text}"),
    }
}

#[test]
fn yes_and_no_words_are_booleans() {
    for t in [
        "yes", "Yes", "YES", "on", "On", "ON", "y", "Y", "true", "True", "TRUE",
    ] {
        same(t, json!(true));
    }
    for t in [
        "no", "No", "NO", "off", "Off", "OFF", "n", "N", "false", "False", "FALSE",
    ] {
        same(t, json!(false));
    }
}

#[test]
fn other_cases_of_the_words_are_strings() {
    same("tRUE", json!("tRUE"));
    same("yEs", json!("yEs"));
}

#[test]
fn null_forms() {
    for t in ["~", "null", "Null", "NULL", ""] {
        same(t, Value::Null);
    }
}

#[test]
fn boolean_keys_become_the_words() {
    let v = parse("n: 1\ny: 2\n").unwrap();
    assert_eq!(v, json!({"false": 1, "true": 2}));
}

#[test]
fn number_keys_become_their_text() {
    assert_eq!(parse("1: a\n").unwrap(), json!({"1": "a"}));
    assert_eq!(parse("0x10: a\n").unwrap(), json!({"16": "a"}));
    assert_eq!(parse("1.5: a\n").unwrap(), json!({"1.5": "a"}));
}

#[test]
fn a_null_key_or_a_list_key_is_an_error() {
    assert!(parse("~: a\n").is_err());
    assert!(parse("? [1, 2]\n: a\n").is_err());
}

#[test]
fn radix_and_octal_integers() {
    same("010", json!(8));
    same("0o10", json!(8));
    same("0x10", json!(16));
    same("0x1F", json!(31));
    same("0b11", json!(3));
    same("007", json!(7));
    same("08", json!(8));
    same("-010", json!(-8));
    same("-0x10", json!(-16));
}

#[test]
fn underscores_signs_and_short_forms() {
    same("1_000", json!(1000));
    same("+1", json!(1));
    same(".5", json!(0.5));
    same("5.", json!(5));
    same("-0", json!(0));
    same("0.0", json!(0));
    same("-0.0", json!(0));
    same("0", json!(0));
}

#[test]
fn exponents() {
    same("1e3", json!(1000));
    same("1.5e-3", json!(0.0015));
    same("1E3", json!(1000));
}

#[test]
fn json_cannot_hold_forms_are_written_plain() {
    assert_eq!(digits("010"), "8");
    assert_eq!(digits("0x1F"), "31");
    assert_eq!(digits("1_000"), "1000");
    assert_eq!(digits("+1"), "1");
    assert_eq!(digits(".5"), "0.5");
    assert_eq!(digits("5."), "5");
    assert_eq!(digits("08"), "8");
    assert_eq!(digits("-.5"), "-0.5");
}

#[test]
fn digits_as_written_are_kept() {
    assert_eq!(digits("1.10"), "1.10");
    assert_eq!(digits("1e400"), digits_in_json("1e400"));
    assert_eq!(digits("-1e400"), digits_in_json("-1e400"));
    assert!(digits("1e400").starts_with("1e"));
    assert!(digits("1e400").ends_with("400"));
    assert!(value("1e400").is_number());
    assert_eq!(
        digits("123456789012345678901234567890"),
        "123456789012345678901234567890"
    );
    assert_eq!(digits("12345678901234567890"), "12345678901234567890");
    assert_eq!(
        digits("0.1000000000000000055511151231257827"),
        "0.1000000000000000055511151231257827"
    );
}

#[test]
fn a_radix_number_past_64_bits_is_a_string() {
    same("0x1ffffffffffffffff", json!("0x1ffffffffffffffff"));
}

#[test]
fn strings_stay_strings() {
    same("v0.2", json!("v0.2"));
    same("0.2.1", json!("0.2.1"));
    same("1:20", json!("1:20"));
    same("2026-10-29", json!("2026-10-29"));
    same("2026-10-29T10:00:00Z", json!("2026-10-29T10:00:00Z"));
    same("1_", json!(1));
    same("0x", json!("0x"));
}

#[test]
fn quoted_scalars_are_always_strings() {
    same("'yes'", json!("yes"));
    same("\"1e400\"", json!("1e400"));
    same("'~'", json!("~"));
    same("\"010\"", json!("010"));
}

#[test]
fn explicit_tags() {
    assert_eq!(
        parse("a: !!str 1\nb: !!int \"3\"\nc: !!float 1\n").unwrap()["a"],
        json!("1")
    );
    assert_eq!(parse("b: !!int \"3\"\n").unwrap()["b"], json!(3));
    assert!(parse("a: !custom 1\n").is_err());
}

#[test]
fn a_timestamp_tag_keeps_the_text() {
    assert_eq!(
        parse("v: !!timestamp 2026-10-29\n").unwrap()["v"],
        json!("2026-10-29")
    );
}

#[test]
fn a_binary_tag_is_decoded_from_base64() {
    assert_eq!(parse("v: !!binary aGk=\n").unwrap()["v"], json!("hi"));
    assert_eq!(
        parse("v: !!binary |\n  aG\n  k=\n").unwrap()["v"],
        json!("hi")
    );
    assert_eq!(parse("v: !!binary /w==\n").unwrap()["v"], json!("\u{fffd}"));
    assert!(parse("v: !!binary '!!!'\n").is_err());
}

#[test]
fn a_binary_tag_takes_only_padded_standard_base64_as_opa_does() {
    for text in ["aGk", "a-_k", "'aG k='", "aG=k", "a==="] {
        assert!(parse(&format!("v: !!binary {text}\n")).is_err(), "{text}");
    }
}

#[test]
fn anchors_aliases_and_merge_keys() {
    let v = parse("base: &b\n  k: 1\ncopy: *b\nmerged:\n  <<: *b\n  j: 2\n").unwrap();
    assert_eq!(
        v,
        json!({"base": {"k": 1}, "copy": {"k": 1}, "merged": {"j": 2, "k": 1}})
    );
}

#[test]
fn merge_keys_follow_document_order() {
    let v = parse("b: &b\n  k: 1\n  j: 1\nm:\n  k: 2\n  <<: *b\no:\n  <<: *b\n  k: 3\n").unwrap();
    assert_eq!(v["m"], json!({"k": 1, "j": 1}));
    assert_eq!(v["o"], json!({"k": 3, "j": 1}));
}

#[test]
fn earlier_maps_in_a_merge_list_win() {
    let v = parse("a: &a {k: 1}\nb: &b {k: 2, j: 3}\nm:\n  <<: [*a, *b]\n").unwrap();
    assert_eq!(v["m"], json!({"k": 1, "j": 3}));
}

#[test]
fn the_first_map_of_a_merge_list_wins_over_a_later_explicit_key_only_before_it() {
    let v = parse("a: &a {k: 1}\nb: &b {k: 2, z: 3}\nm:\n  <<: [*a, *b]\n").unwrap();
    assert_eq!(v["m"], json!({"k": 1, "z": 3}));
}

#[test]
fn a_merge_of_a_non_map_is_an_error() {
    assert!(parse("m:\n  <<: 1\n").is_err());
}

#[test]
fn an_alias_to_an_unknown_anchor_is_an_error() {
    assert!(parse("a: *nope\n").is_err());
}

#[test]
fn the_last_duplicate_key_wins_even_nested() {
    assert_eq!(parse("a: 1\na: 2\n").unwrap(), json!({"a": 2}));
    assert_eq!(
        parse("x:\n  a: 1\n  a: 2\n").unwrap(),
        json!({"x": {"a": 2}})
    );
}

#[test]
fn infinity_and_nan_are_errors() {
    for t in [
        ".inf", "-.inf", "+.inf", ".Inf", ".INF", ".nan", ".NaN", ".NAN",
    ] {
        assert!(parse(&format!("v: {t}\n")).is_err(), "{t}");
    }
}

#[test]
fn only_the_first_document_is_read() {
    assert_eq!(parse("a: 1\n---\nb: 2\n").unwrap(), json!({"a": 1}));
}

#[test]
fn an_empty_file_is_null_and_a_top_level_list_or_scalar_is_kept() {
    assert_eq!(parse("").unwrap(), Value::Null);
    assert_eq!(parse("# nothing\n").unwrap(), Value::Null);
    assert_eq!(parse("- 1\n- 2\n").unwrap(), json!([1, 2]));
    assert_eq!(parse("hello\n").unwrap(), json!("hello"));
}

#[test]
fn nested_lists_and_flow_collections() {
    assert_eq!(
        parse("a: [1, {b: yes}]\n").unwrap(),
        json!({"a": [1, {"b": true}]})
    );
}
