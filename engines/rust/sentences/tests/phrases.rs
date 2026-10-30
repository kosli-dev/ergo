mod support;

use ergo_policy_sentences::*;
use support::*;

fn vals(values: Vec<Value>) -> List {
    List::Values(values)
}

fn params(name: &str) -> Path {
    Path {
        position: None,
        start: Start::Params,
        steps: vec![dot(name)],
    }
}

#[test]
fn one_of_reads_values_and_in_reads_a_path() {
    assert_eq!(
        phrase("is one of 1, 2"),
        Phrase::OneOf {
            not: false,
            list: vals(vec![number("1"), number("2")])
        }
    );
    assert_eq!(
        phrase("is not one of \"a\",\"b\""),
        Phrase::OneOf {
            not: true,
            list: vals(vec![text("a"), text("b")])
        }
    );
    assert_eq!(
        phrase("is in $params.l"),
        Phrase::OneOf {
            not: false,
            list: List::Path(params("l"))
        }
    );
    assert_eq!(
        phrase("is not in l"),
        Phrase::OneOf {
            not: true,
            list: List::Path(key("l"))
        }
    );
}

#[test]
fn one_of_takes_every_kind_of_value() {
    assert_eq!(
        phrase("is one of true, false, null, 'a', \"b\", -1.5e3"),
        Phrase::OneOf {
            not: false,
            list: vals(vec![
                Value::True,
                Value::False,
                Value::Null,
                text("a"),
                text("b"),
                number("-1.5e3")
            ])
        }
    );
}

#[test]
fn a_comma_in_a_list_may_be_followed_by_spaces_but_not_preceded() {
    assert!(parse_from("x whose y is one of 1,  2").is_ok());
    assert!(parse_from("x whose y is one of 1 , 2").is_err());
    assert!(parse_from("x whose y is one of 1,").is_err());
    assert!(parse_from("x whose y is one of ,1").is_err());
}

#[test]
fn exists_empty_and_types_take_no_argument() {
    assert_eq!(phrase("exists"), Phrase::Exists { not: false });
    assert_eq!(phrase("does not exist"), Phrase::Exists { not: true });
    assert_eq!(phrase("is empty"), Phrase::Empty { not: false });
    assert_eq!(phrase("is not empty"), Phrase::Empty { not: true });
    assert_eq!(phrase("is a non-empty string"), Phrase::NonEmptyString);
    assert_eq!(phrase("is a list"), Phrase::Type(Type::List));
    assert_eq!(phrase("is a string"), Phrase::Type(Type::String));
    assert_eq!(phrase("is a number"), Phrase::Type(Type::Number));
    assert_eq!(phrase("is a boolean"), Phrase::Type(Type::Boolean));
    assert_eq!(phrase("is an object"), Phrase::Type(Type::Object));
}

#[test]
fn a_and_an_are_both_read_before_a_type() {
    assert_eq!(phrase("is a object"), Phrase::Type(Type::Object));
    assert_eq!(phrase("is an list"), Phrase::Type(Type::List));
}

#[test]
fn a_phrase_that_takes_nothing_rejects_more_text() {
    assert!(parse_from("x whose y exists z").is_err());
    assert!(parse_from("x whose y is empty z").is_err());
    assert!(parse_from("x whose y is a thing").is_err());
}

#[test]
fn contains_and_starts_with_take_an_operand() {
    assert_eq!(
        phrase("contains \"a\""),
        Phrase::Contains {
            not: false,
            operand: value(text("a"))
        }
    );
    assert_eq!(
        phrase("does not contain k"),
        Phrase::Contains {
            not: true,
            operand: field("k")
        }
    );
    assert_eq!(
        phrase("starts with 'a'"),
        Phrase::StartsWith(value(text("a")))
    );
    assert_eq!(phrase("ends with k"), Phrase::EndsWith(field("k")));
}

#[test]
fn contains_all_and_none_and_matches_take_a_list() {
    assert_eq!(
        phrase("contains all of 1, 2"),
        Phrase::ContainsAll(vals(vec![number("1"), number("2")]))
    );
    assert_eq!(
        phrase("contains none of l"),
        Phrase::ContainsNone(List::Path(key("l")))
    );
    assert_eq!(
        phrase("matches \"a\", \"b\""),
        Phrase::Matches {
            not: false,
            list: vals(vec![text("a"), text("b")])
        }
    );
    assert_eq!(
        phrase("does not match $params.p"),
        Phrase::Matches {
            not: true,
            list: List::Path(params("p"))
        }
    );
}

#[test]
fn alphabetical_and_time_phrases_take_an_operand() {
    assert_eq!(
        phrase("is alphabetically before \"b\""),
        Phrase::Alphabetically {
            after: false,
            operand: value(text("b"))
        }
    );
    assert_eq!(
        phrase("is alphabetically after k"),
        Phrase::Alphabetically {
            after: true,
            operand: field("k")
        }
    );
    for (words, time) in [
        ("is before", TimeOrder::Before),
        ("is after", TimeOrder::After),
        ("is on or after", TimeOrder::OnOrAfter),
        ("is on or before", TimeOrder::OnOrBefore),
    ] {
        assert_eq!(
            phrase(&format!("{words} \"2020-01-01\"")),
            Phrase::Time {
                time,
                operand: value(text("2020-01-01"))
            }
        );
    }
}

#[test]
fn order_phrases_take_an_operand() {
    for (words, order) in [
        ("is at least", Order::AtLeast),
        ("is at most", Order::AtMost),
        ("is more than", Order::MoreThan),
        ("is less than", Order::LessThan),
    ] {
        assert_eq!(
            phrase(&format!("{words} 3")),
            Phrase::Order {
                order,
                operand: value(number("3"))
            }
        );
    }
}

#[test]
fn between_keeps_both_numbers_as_written() {
    assert_eq!(
        phrase("is between -1.50 and 2E3"),
        Phrase::Between {
            min: "-1.50".into(),
            max: "2E3".into()
        }
    );
    assert!(parse_from("x whose y is between 1").is_err());
    assert!(parse_from("x whose y is between 1 and").is_err());
    assert!(parse_from("x whose y is between k and 2").is_err());
    assert!(parse_from("x whose y is between 1 and 2 and 3").is_err());
}

#[test]
fn between_does_not_swallow_the_and_of_the_next_condition() {
    let line = from("x whose y is between 1 and 2 and z is 3");
    assert_eq!(line.whose.len(), 2);
}

#[test]
fn is_reads_a_value_or_a_field_with_any_of_its_spellings() {
    let is = |not, operand, within: Option<&str>| Phrase::Is {
        not,
        operand,
        within: within.map(str::to_string),
    };
    assert_eq!(phrase("is \"a\""), is(false, value(text("a")), None));
    assert_eq!(phrase("is equal to 1"), is(false, value(number("1")), None));
    assert_eq!(phrase("equals k"), is(false, field("k"), None));
    assert_eq!(phrase("is not null"), is(true, value(Value::Null), None));
    assert_eq!(phrase("does not equal k"), is(true, field("k"), None));
    assert_eq!(phrase("is true"), is(false, value(Value::True), None));
    assert_eq!(phrase("is false"), is(false, value(Value::False), None));
}

#[test]
fn within_goes_after_the_operand_of_is_and_keeps_its_digits() {
    assert_eq!(
        phrase("is 1 within 0.50"),
        Phrase::Is {
            not: false,
            operand: value(number("1")),
            within: Some("0.50".into())
        }
    );
    assert_eq!(
        phrase("equals k within 2"),
        Phrase::Is {
            not: false,
            operand: field("k"),
            within: Some("2".into())
        }
    );
}

#[test]
fn within_is_not_read_after_is_not() {
    assert!(parse_from("x whose y is not 1 within 2").is_err());
    assert!(parse_from("x whose y does not equal k within 2").is_err());
}

#[test]
fn within_needs_a_number() {
    assert!(parse_from("x whose y is 1 within k").is_err());
    assert!(parse_from("x whose y is 1 within").is_err());
}

#[test]
fn an_operand_can_add_terms_with_plus() {
    assert_eq!(
        phrase("equals k plus 1 plus count of l"),
        Phrase::Is {
            not: false,
            operand: Operand::Field(vec![
                Term::Path(key("k")),
                Term::Number("1".into()),
                Term::Derived(Derived {
                    kind: DerivedKind::Count,
                    path: key("l"),
                    whose: vec![]
                })
            ]),
            within: None
        }
    );
}

#[test]
fn an_operand_can_start_with_a_number_when_a_plus_follows() {
    assert_eq!(
        phrase("is more than 1 plus k"),
        Phrase::Order {
            order: Order::MoreThan,
            operand: Operand::Field(vec![Term::Number("1".into()), Term::Path(key("k"))])
        }
    );
}

#[test]
fn a_lone_number_is_a_value_not_a_field() {
    assert_eq!(
        phrase("is more than 1"),
        Phrase::Order {
            order: Order::MoreThan,
            operand: value(number("1"))
        }
    );
}

#[test]
fn terms_can_be_a_sum_an_elapsed_time_or_a_position() {
    assert_eq!(
        phrase("equals sum of l.m plus days elapsed from a1.b to c plus first of d"),
        Phrase::Is {
            not: false,
            operand: Operand::Field(vec![
                Term::Derived(Derived {
                    kind: DerivedKind::Sum,
                    path: with_steps(key("l"), vec![dot("m")]),
                    whose: vec![]
                }),
                Term::Elapsed(Elapsed {
                    unit: Unit::Days,
                    from: with_steps(key("a1"), vec![dot("b")]),
                    to: key("c")
                }),
                Term::Path(Path {
                    position: Some(Position::First),
                    start: Start::Field {
                        key: "d".into(),
                        dot: false
                    },
                    steps: vec![]
                })
            ]),
            within: None
        }
    );
}

#[test]
fn every_unit_of_elapsed_time_is_read() {
    for (word, unit) in [
        ("seconds", Unit::Seconds),
        ("minutes", Unit::Minutes),
        ("hours", Unit::Hours),
        ("days", Unit::Days),
        ("weeks", Unit::Weeks),
    ] {
        let read = condition(&format!("{word} elapsed from a1 to b1 is 1"));
        assert_eq!(
            read.left,
            Left::Elapsed(Elapsed {
                unit,
                from: key("a1"),
                to: key("b1")
            })
        );
    }
    assert!(parse_from("x whose years elapsed from a1 to b1 is 1").is_err());
    assert!(parse_from("x whose days elapsed from a1 is 1").is_err());
}

#[test]
fn count_and_sum_on_the_left_take_a_compare_phrase_only() {
    let read = condition("count of l is at least 2");
    assert_eq!(
        read.left,
        Left::Derived(Derived {
            kind: DerivedKind::Count,
            path: key("l"),
            whose: vec![]
        })
    );
    assert!(parse_from("x whose count of l exists").is_err());
    assert!(parse_from("x whose sum of l is one of 1, 2").is_err());
    assert!(parse_from("x whose count of l matches \"a\"").is_err());
    assert!(parse_from("x whose count of l is between 1 and 2").is_ok());
    assert!(parse_from("x whose count of l equals k").is_ok());
    assert!(parse_from("x whose count of l is 1 within 2").is_ok());
}

#[test]
fn a_count_in_a_condition_has_no_whose_of_its_own() {
    assert!(parse_from("x whose count of l whose m is 1 is 2").is_err());
}

#[test]
fn a_condition_may_start_with_some_or_every() {
    assert_eq!(
        from("x whose some l.m, if any, matches \"a\"").whose,
        vec![FromCondition::Quantified {
            quantifier: Quantifier::Some,
            path: with_steps(key("l"), vec![dot("m")]),
            if_any: true,
            phrase: Phrase::Matches {
                not: false,
                list: vals(vec![text("a")])
            }
        }]
    );
    assert_eq!(
        from("x whose every l is 1").whose,
        vec![FromCondition::Quantified {
            quantifier: Quantifier::Every,
            path: key("l"),
            if_any: false,
            phrase: Phrase::Is {
                not: false,
                operand: value(number("1")),
                within: None
            }
        }]
    );
}

#[test]
fn if_any_needs_its_commas_and_spaces() {
    assert!(parse_from("x whose some l if any is 1").is_err());
    assert!(parse_from("x whose some l , if any, is 1").is_err());
    assert!(parse_from("x whose some l,if any, is 1").is_err());
    assert!(parse_from("x whose some l, if any,is 1").is_err());
}

#[test]
fn a_quantified_condition_has_no_whose_of_its_own() {
    assert!(parse_from("x whose some l whose m is 1 is 2").is_err());
}

#[test]
fn conditions_are_joined_by_and_in_order() {
    let line = from("x whose a1 is 1 and b1 exists and some c1 is 2 and count of d1 is 3");
    assert_eq!(line.whose.len(), 4);
    assert!(matches!(line.whose[2], FromCondition::Quantified { .. }));
}

#[test]
fn a_condition_word_after_and_is_not_swallowed_by_the_operand() {
    let line = from("x whose a1 equals b1 and c1 equals d1 plus 1 and e1 exists");
    assert_eq!(line.whose.len(), 3);
}

#[test]
fn a_string_operand_holding_and_does_not_split_the_condition() {
    let line = from("x whose a1 is \"p and q is 1\" and b1 exists");
    assert_eq!(line.whose.len(), 2);
}
