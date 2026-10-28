#![cfg(feature = "serde")]

mod support;

use ergo_sentences::*;
use support::*;

#[test]
fn a_from_line_survives_a_trip_through_json() {
    let line = from(
        "every a1.b named by each of $params.l whose some c1, if any, matches \"x\" and count of d1 is at least 2",
    );
    let json = serde_json::to_string(&line).unwrap();
    let back: From = serde_json::from_str(&json).unwrap();
    assert_eq!(back, line);
}

#[test]
fn a_syntax_error_survives_a_trip_through_json() {
    let errors = parse_from("x whose y is \"a").unwrap_err();
    let json = serde_json::to_string(&errors).unwrap();
    let back: Vec<SyntaxError> = serde_json::from_str(&json).unwrap();
    assert_eq!(back, errors);
}
