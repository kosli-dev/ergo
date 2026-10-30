mod support;

use ergo_policy_sentences::*;
use support::*;

fn is(value: Value) -> Phrase {
    Phrase::Is {
        not: false,
        operand: Operand::Value(value),
        within: None,
    }
}

fn count(path: Path) -> Derived {
    Derived {
        kind: DerivedKind::Count,
        path,
        whose: vec![],
    }
}

#[test]
fn a_plain_assertion_is_a_path_and_a_phrase() {
    assert_eq!(
        assertion("x.y is 1"),
        Assertion::Plain {
            path: with_steps(key("x"), vec![dot("y")]),
            phrase: is(number("1"))
        }
    );
}

#[test]
fn a_check_is_assertions_joined_by_and() {
    let read = check("x is 1 and y exists and z is empty");
    assert_eq!(read.assertions.len(), 3);
    assert!(matches!(read.assertions[1], Assertion::Plain { .. }));
}

#[test]
fn a_quantified_assertion_keeps_its_whose_and_if_any() {
    assert_eq!(
        assertion("every items.x whose k is 1, if any, is empty"),
        Assertion::Quantified {
            quantifier: Quantifier::Every,
            path: with_steps(key("items"), vec![dot("x")]),
            whose: vec![Condition {
                left: Left::Path(key("k")),
                phrase: is(number("1"))
            }],
            if_any: true,
            phrase: Phrase::Empty { not: false }
        }
    );
    assert!(matches!(
        assertion("some items exists"),
        Assertion::Quantified {
            quantifier: Quantifier::Some,
            if_any: false,
            ..
        }
    ));
}

#[test]
fn every_is_a_quantifier_not_a_key() {
    assert!(parse_check("every is 1").is_err());
    assert!(parse_check("everything is 1").is_ok());
    assert!(parse_check("some").is_err());
}

#[test]
fn a_whose_takes_every_condition_before_the_phrase() {
    let whole = check(
        "every items.price whose kind is \"a\" and qty is 1 is at least 2 and owner is \"x\"",
    );
    assert_eq!(whole.assertions.len(), 2);
    match &whole.assertions[0] {
        Assertion::Quantified { whose, phrase, .. } => {
            assert_eq!(whose.len(), 2);
            assert_eq!(
                *phrase,
                Phrase::Order {
                    order: Order::AtLeast,
                    operand: value(number("2"))
                }
            );
        }
        other => panic!("{other:?}"),
    }
    assert_eq!(
        whole.assertions[1],
        Assertion::Plain {
            path: key("owner"),
            phrase: is(text("x"))
        }
    );
}

#[test]
fn a_whose_with_one_condition_leaves_the_next_and_to_the_check() {
    let whole = check("every items whose kind is \"a\" is empty and owner is \"x\"");
    assert_eq!(whole.assertions.len(), 2);
}

#[test]
fn the_and_of_between_is_not_the_and_of_the_check() {
    let whole = check("x is between 1 and 2 and y is between 3 and 4");
    assert_eq!(whole.assertions.len(), 2);
    assert_eq!(
        check("every items whose k is between 1 and 2 and j is 3 is empty")
            .assertions
            .len(),
        1
    );
}

#[test]
fn an_and_inside_a_string_does_not_split_the_check() {
    assert_eq!(
        check("x is \"a and y is 1\" and z exists").assertions.len(),
        2
    );
}

#[test]
fn if_any_goes_after_a_quantified_path_or_whose_only() {
    assert!(parse_check("every x, if any, is 1").is_ok());
    assert!(parse_check("every x whose y is 1, if any, is 1").is_ok());
    assert!(parse_check("some x, if any, is 1").is_ok());
    assert!(parse_check("x, if any, is 1").is_err());
    assert!(parse_check("every x if any is 1").is_err());
    assert!(parse_check("every x , if any, is 1").is_err());
    assert!(parse_check("every x, if any is 1").is_err());
    assert!(parse_check("count of x, if any, is 1").is_err());
}

#[test]
fn a_count_with_a_whose_is_a_derived_assertion() {
    assert_eq!(
        assertion("count of items whose k is 1 is at least 2"),
        Assertion::Derived {
            terms: vec![Term::Derived(Derived {
                kind: DerivedKind::Count,
                path: key("items"),
                whose: vec![Condition {
                    left: Left::Path(key("k")),
                    phrase: is(number("1"))
                }]
            })],
            phrase: Phrase::Order {
                order: Order::AtLeast,
                operand: value(number("2"))
            }
        }
    );
}

#[test]
fn only_the_last_term_can_carry_a_whose() {
    let read = assertion("1 plus count of items whose k is 1 is 3");
    let Assertion::Derived { terms, .. } = read else {
        panic!()
    };
    assert_eq!(terms.len(), 2);
    assert_eq!(terms[0], Term::Number("1".into()));
    assert!(matches!(&terms[1], Term::Derived(d) if d.whose.len() == 1));
    assert!(parse_check("1 plus y whose k is 1 is 3").is_err());
    assert!(parse_check("y plus 1 whose k is 1 is 3").is_err());
    assert!(parse_check("days elapsed from a1 to b1 whose k is 1 is 3").is_err());
    assert!(parse_check("count of a1 whose k is 1 plus count of b1 whose j is 2 is 3").is_err());
}

#[test]
fn a_chain_of_terms_needs_two_terms_unless_it_is_a_count_or_a_time() {
    assert!(parse_check("y plus 1 is 3").is_ok());
    assert!(parse_check("1 plus y is 3").is_ok());
    assert!(parse_check("count of y is 3").is_ok());
    assert!(parse_check("days elapsed from a1 to b1 is 3").is_ok());
    assert!(parse_check("5 is 3").is_err());
    assert_eq!(
        assertion("count of x plus count of y is 4"),
        Assertion::Derived {
            terms: vec![
                Term::Derived(count(key("x"))),
                Term::Derived(count(key("y")))
            ],
            phrase: is(number("4"))
        }
    );
}

#[test]
fn a_derived_assertion_takes_a_compare_phrase_only() {
    assert!(parse_check("count of y exists").is_err());
    assert!(parse_check("y plus 1 contains 3").is_err());
    assert!(parse_check("y plus 1 is between 1 and 2").is_ok());
    assert!(parse_check("y plus 1 is 1 within 2").is_ok());
}

#[test]
fn it_starts_an_assertion_and_follows_a_quantifier() {
    assert_eq!(
        assertion("it is empty"),
        Assertion::Plain {
            path: it(),
            phrase: Phrase::Empty { not: false }
        }
    );
    assert!(matches!(
        assertion("every it is 1"),
        Assertion::Quantified { path, .. } if path == it()
    ));
    assert!(parse_check("x is 1 and it exists").is_ok());
}

#[test]
fn a_tab_between_words_does_not_parse_but_one_at_either_end_is_dropped() {
    assert!(parse_check("x\tis 1").is_err());
    assert_eq!(printed_check("x is 1\t"), "x is 1");
    assert_eq!(printed_check("\tx is 1\n"), "x is 1");
}

#[test]
fn every_white_space_character_at_either_end_of_a_line_is_dropped() {
    for ch in [
        '\t', '\n', '\u{b}', '\u{c}', '\r', ' ', '\u{85}', '\u{a0}', '\u{1680}', '\u{2000}',
        '\u{200a}', '\u{2028}', '\u{2029}', '\u{202f}', '\u{205f}', '\u{3000}',
    ] {
        let line = format!("{ch}x is 1{ch}");
        assert_eq!(printed_check(&line), "x is 1", "{ch:?}");
        assert_eq!(
            printed_for(&format!("{ch}every xs as x{ch}")),
            "every xs as x",
            "{ch:?}"
        );
        assert_eq!(
            printed(&format!("{ch}every xs whose y is 1{ch}")),
            "every xs whose y is 1",
            "{ch:?}"
        );
    }
}

#[test]
fn a_byte_order_mark_or_a_zero_width_space_is_not_white_space() {
    for ch in ['\u{feff}', '\u{200b}', '\u{1c}'] {
        assert!(parse_check(&format!("{ch}x is 1")).is_err(), "{ch:?}");
        assert!(parse_check(&format!("x is 1{ch}")).is_err(), "{ch:?}");
    }
}

#[test]
fn a_long_check_does_not_make_the_reader_slow() {
    let parts: Vec<String> = (0..100)
        .map(|n| format!("every items_{n} whose k is 1 and j is between 1 and 2 is at least {n}"))
        .collect();
    let line = parts.join(" and ");
    assert_eq!(check(&line).assertions.len(), 100);
    assert_eq!(check_failure(&format!("{line} and")), vec!["doesn't parse"]);
    let line = parts.join(" and ");
    assert_eq!(
        check_failure(&format!("{line} and empty is 1")),
        vec!["empty is a word of the grammar: write .empty"]
    );
}

#[test]
fn the_check_errors_have_the_same_order_as_a_from_line() {
    assert_eq!(
        parse_check("x is \"abc").unwrap_err()[0].message,
        "unclosed quote at column 6"
    );
    assert_eq!(
        parse_check("x is \"\\q\"").unwrap_err()[0].message,
        "invalid string at column 6"
    );
    assert_eq!(
        check_failure("some l every m is 1"),
        vec!["two quantifiers in one sentence: put them on a for line"]
    );
    assert_eq!(
        check_failure("x is 1 within"),
        vec!["\"within\" needs a number after it"]
    );
    assert_eq!(
        parse_check("some l.m").unwrap_err(),
        vec![SyntaxError {
            column: Some(9),
            message:
                "nothing after the path at column 9: expected a phrase, like \"is\" or \"exists\""
                    .into()
        }]
    );
    assert_eq!(check_failure("x is"), vec!["doesn't parse"]);
    assert_eq!(check_failure(""), vec!["doesn't parse"]);
}

#[test]
fn checks_print_every_form() {
    for line in [
        "x is 1",
        "every items.x whose k is 1 and j exists, if any, is empty",
        "some items whose count of k is 2 matches \"a\"",
        "count of items whose k is 1 is at least 2",
        "1 plus count of items whose k equals 1 plus 2 is 3",
        "days elapsed from a1 to b1 is more than 2",
        "it is empty and every it is 1",
        "x is 1 and y is 2",
    ] {
        assert_eq!(printed_check(line), line);
    }
}

#[test]
fn a_check_is_printed_in_canonical_spacing() {
    assert_eq!(
        printed_check("  every   items  whose  k  is  1,  if any,  is   empty  "),
        "every items whose k is 1, if any, is empty"
    );
}
