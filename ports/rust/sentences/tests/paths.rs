mod support;

use ergo_sentences::*;
use support::*;

#[test]
fn a_bare_key_with_steps_is_a_field_path() {
    assert_eq!(
        path("git_commit_info.sha1"),
        with_steps(key("git_commit_info"), vec![dot("sha1")])
    );
    assert_eq!(
        path("coverage-verification.a-b"),
        with_steps(key("coverage-verification"), vec![dot("a-b")])
    );
    assert_eq!(path("_x1"), key("_x1"));
}

#[test]
fn params_and_input_start_their_own_paths() {
    assert_eq!(
        path("$params.x.y"),
        Path {
            position: None,
            start: Start::Params,
            steps: vec![dot("x"), dot("y")]
        }
    );
    assert_eq!(
        path("$input"),
        Path {
            position: None,
            start: Start::Input,
            steps: vec![]
        }
    );
}

#[test]
fn a_dot_in_front_of_the_first_key_is_kept() {
    assert_eq!(path(".empty"), dotted("empty"));
    assert_eq!(path(".it"), dotted("it"));
    assert_eq!(path(".x"), dotted("x"));
    assert_eq!(path(".\"a b\""), dotted("a b"));
}

#[test]
fn a_quoted_first_key_is_a_field_on_the_left() {
    assert_eq!(path("\"a b\".c"), with_steps(key("a b"), vec![dot("c")]));
    assert_eq!(path("\"\""), key(""));
}

#[test]
fn a_quoted_first_key_on_the_right_needs_a_dot() {
    assert_eq!(
        phrase("equals .\"a b\""),
        Phrase::Is {
            not: false,
            operand: Operand::Field(vec![Term::Path(dotted("a b"))]),
            within: None
        }
    );
    assert_eq!(
        phrase("is \"a b\""),
        Phrase::Is {
            not: false,
            operand: value(text("a b")),
            within: None
        }
    );
}

#[test]
fn a_dollar_key_is_written_in_quotes() {
    assert_eq!(path("\"$schema\""), key("$schema"));
    assert_eq!(path("ab.\"b$c\""), with_steps(key("ab"), vec![dot("b$c")]));
}

#[test]
fn quoted_keys_are_decoded_like_json() {
    assert_eq!(
        path("ab.\"x\\\"y\""),
        with_steps(key("ab"), vec![dot("x\"y")])
    );
    assert_eq!(
        path("ab.\"\\u00e9\\n\\/\""),
        with_steps(key("ab"), vec![dot("é\n/")])
    );
    assert_eq!(
        path("ab.\"\\ud83d\\ude00\""),
        with_steps(key("ab"), vec![dot("\u{1F600}")])
    );
}

#[test]
fn a_lone_surrogate_escape_becomes_the_replacement_character() {
    assert_eq!(
        path("ab.\"\\ud800\""),
        with_steps(key("ab"), vec![dot("\u{FFFD}")])
    );
    assert_eq!(
        path("ab.\"\\udc00\""),
        with_steps(key("ab"), vec![dot("\u{FFFD}")])
    );
    assert_eq!(
        path("ab.\"\\ud800x\""),
        with_steps(key("ab"), vec![dot("\u{FFFD}x")])
    );
    assert_eq!(
        path("ab.\"\\ud800\\u0041\""),
        with_steps(key("ab"), vec![dot("\u{FFFD}A")])
    );
}

#[test]
fn a_double_quoted_value_is_decoded_like_json() {
    assert_eq!(
        phrase("is \"a\\tb\\\\c\\u0041\""),
        Phrase::Is {
            not: false,
            operand: value(text("a\tb\\cA")),
            within: None
        }
    );
}

#[test]
fn a_single_quoted_value_keeps_its_backslashes_except_before_a_quote_or_a_backslash() {
    for (written, want) in [
        ("'a\\nb'", "a\\nb"),
        ("'a\\'b'", "a'b"),
        ("'a\\\\b'", "a\\b"),
        ("'\\\\\\''", "\\'"),
        ("''", ""),
        ("'a\"b'", "a\"b"),
    ] {
        assert_eq!(
            phrase(&format!("is {written}")),
            Phrase::Is {
                not: false,
                operand: value(text(want)),
                within: None
            },
            "{written}"
        );
    }
}

#[test]
fn steps_are_keys_named_by_brackets_and_indexes() {
    assert_eq!(
        path("ab.b named by $params.k[3][\"x y\"][k][$input.z].c"),
        with_steps(
            key("ab"),
            vec![
                dot("b"),
                Step::NamedBy(Reference::Params("k".into())),
                Step::Index("3".into()),
                Step::BracketKey("x y".into()),
                Step::Brackets(Reference::Name("k".into())),
                Step::Brackets(Reference::Input("z".into())),
                dot("c"),
            ]
        )
    );
}

#[test]
fn a_reference_is_a_params_or_input_key_or_a_bare_name() {
    assert_eq!(
        path("ab named by $input.\"x y\""),
        with_steps(
            key("ab"),
            vec![Step::NamedBy(Reference::Input("x y".into()))]
        )
    );
    assert_eq!(
        path("ab named by k"),
        with_steps(key("ab"), vec![Step::NamedBy(Reference::Name("k".into()))])
    );
}

#[test]
fn a_reference_takes_one_key_and_the_rest_is_a_step() {
    assert_eq!(
        path("ab named by $params.k.m"),
        with_steps(
            key("ab"),
            vec![Step::NamedBy(Reference::Params("k".into())), dot("m")]
        )
    );
}

#[test]
fn a_bracket_index_keeps_its_digits() {
    assert_eq!(
        path("ab[0]"),
        with_steps(key("ab"), vec![Step::Index("0".into())])
    );
    assert_eq!(
        path("ab[9007199254740993]"),
        with_steps(key("ab"), vec![Step::Index("9007199254740993".into())])
    );
}

#[test]
fn a_bracket_index_has_no_leading_zero_sign_or_space() {
    for bad in [
        "ab[00]", "ab[01]", "ab[-1]", "ab[1.5]", "ab[ 1]", "ab[1 ]", "ab[]",
    ] {
        assert!(parse_path(bad).is_err(), "{bad}");
    }
}

#[test]
fn positions_are_read_in_words() {
    let at = |position| Path {
        position: Some(position),
        start: Start::Field {
            key: "xs".into(),
            dot: false,
        },
        steps: vec![],
    };
    assert_eq!(path("first of xs"), at(Position::First));
    assert_eq!(path("last of xs"), at(Position::Last));
    assert_eq!(
        path("item 3 of xs"),
        at(Position::Item {
            number: "3".into(),
            from_last: false
        })
    );
    assert_eq!(
        path("item 2 from last of xs"),
        at(Position::Item {
            number: "2".into(),
            from_last: true
        })
    );
}

#[test]
fn a_position_keeps_its_digits_and_takes_the_rest_of_the_path() {
    assert_eq!(
        path("item 9007199254740993 of ab.b[1]"),
        Path {
            position: Some(Position::Item {
                number: "9007199254740993".into(),
                from_last: false
            }),
            start: Start::Field {
                key: "ab".into(),
                dot: false
            },
            steps: vec![dot("b"), Step::Index("1".into())]
        }
    );
}

#[test]
fn a_position_is_a_positive_number_without_leading_zeros() {
    for bad in [
        "item 0 of xs",
        "item 01 of xs",
        "item of xs",
        "item -1 of xs",
        "item 1.5 of xs",
        "item 2 from of xs",
    ] {
        assert!(parse_path(bad).is_err(), "{bad}");
    }
}

#[test]
fn a_position_needs_a_path_after_of() {
    assert!(parse_path("first of").is_err());
    assert!(parse_path("first of first of xs").is_err());
    assert!(parse_path("first  of  xs").is_ok());
}

#[test]
fn a_position_can_come_before_params_and_input() {
    assert_eq!(path("last of $params.l").position, Some(Position::Last));
    assert_eq!(path("first of $input").start, Start::Input);
}

#[test]
fn grammar_words_are_not_bare_first_keys() {
    for word in [
        "a",
        "after",
        "alphabetically",
        "an",
        "and",
        "as",
        "at",
        "before",
        "between",
        "count",
        "days",
        "each",
        "empty",
        "equal",
        "every",
        "false",
        "first",
        "hours",
        "in",
        "it",
        "item",
        "last",
        "less",
        "minutes",
        "more",
        "named",
        "not",
        "null",
        "of",
        "on",
        "one",
        "or",
        "plus",
        "seconds",
        "some",
        "sorted",
        "sum",
        "to",
        "true",
        "weeks",
        "whose",
        "within",
    ] {
        assert!(parse_path(word).is_err(), "{word}");
        assert_eq!(path(&format!(".{word}")), dotted(word), "{word}");
        assert_eq!(
            path(&format!("x.{word}")),
            with_steps(key("x"), vec![dot(word)]),
            "{word}"
        );
    }
}

#[test]
fn words_that_are_not_in_the_list_are_keys() {
    for word in [
        "from", "by", "elapsed", "exists", "contains", "if", "any", "Every", "items", "isa", "ita",
    ] {
        assert_eq!(path(word), key(word), "{word}");
    }
}

#[test]
fn it_is_only_read_where_the_grammar_puts_it() {
    assert!(parse_from("it").is_err());
    assert!(parse_from("x whose it is 1").is_ok());
    assert!(parse_from("x whose some it is 1").is_ok());
    assert!(parse_from("x whose count of it is 1").is_ok());
    assert!(parse_from("x whose first of it is 1").is_ok());
    assert!(parse_from("x whose a1 is it").is_err());
    assert!(parse_from("x whose a1 equals it").is_err());
    assert!(parse_from("x whose a1 is one of it").is_err());
    assert!(parse_from("x whose days elapsed from it to b1 is 1").is_err());
    assert!(parse_from("x named by each of it").is_err());
}

#[test]
fn it_in_a_condition_is_the_item_itself() {
    assert_eq!(condition("it is \"a\"").left, Left::Path(it()));
    assert_eq!(
        condition("item 2 of it exists").left,
        Left::Path(Path {
            position: Some(Position::Item {
                number: "2".into(),
                from_last: false
            }),
            start: Start::It,
            steps: vec![]
        })
    );
}

#[test]
fn it_is_not_a_prefix_of_a_longer_word() {
    assert_eq!(condition("items is 1").left, Left::Path(key("items")));
    assert_eq!(condition("it-x is 1").left, Left::Path(key("it-x")));
    assert_eq!(condition("its is 1").left, Left::Path(key("its")));
}

#[test]
fn a_dotted_it_is_a_field() {
    assert_eq!(condition(".it is 1").left, Left::Path(dotted("it")));
}

#[test]
fn a_step_cannot_follow_it() {
    assert!(parse_from("x whose it.name is 1").is_err());
    assert!(parse_from("x whose it[0] is 1").is_err());
    assert!(parse_from("x whose it named by k is 1").is_err());
}

#[test]
fn params_cannot_be_a_step() {
    assert!(parse_path("ab.$params").is_err());
    assert!(parse_path("ab.$params.x").is_err());
    assert!(parse_path("ab[$params]").is_err());
}

#[test]
fn a_path_cannot_hold_spaces_other_than_named_by() {
    for bad in [
        "ab b",
        "ab. b",
        "ab .b",
        "ab.b ",
        "ab..b",
        "ab.",
        ".",
        "ab named",
        "ab named by",
        "ab named  by",
    ] {
        let trimmed_ok = bad.trim_matches(' ') != bad;
        assert_eq!(parse_path(bad).is_ok(), trimmed_ok, "{bad:?}");
    }
}

#[test]
fn spaces_at_both_ends_are_dropped_but_tabs_are_not() {
    assert_eq!(path("   ab.b  "), with_steps(key("ab"), vec![dot("b")]));
    assert!(parse_path("\tab").is_err());
    assert!(parse_path("ab\t").is_err());
    assert!(parse_from("x\twhose y is 1").is_err());
    assert!(parse_from("x whose\ty is 1").is_err());
}

#[test]
fn several_spaces_between_words_are_one_gap() {
    assert_eq!(
        printed("every   x  named  by  each  of  y   whose  z   is   1"),
        "every x named by each of y whose z is 1"
    );
}

#[test]
fn a_dollar_name_other_than_params_and_input_is_not_a_path() {
    assert!(parse_path("$other").is_err());
    assert!(parse_path("$params2").is_err());
    assert!(parse_path("$paramsx.y").is_err());
}

#[test]
fn a_key_cannot_start_with_a_digit() {
    assert!(parse_path("1a").is_err());
    assert!(parse_path("ab.1").is_err());
    assert_eq!(path("ab.\"1\""), with_steps(key("ab"), vec![dot("1")]));
}

#[test]
fn a_from_line_is_a_path_with_every_named_by_each_of_and_whose() {
    let line = from("every a1.b named by each of $params.names whose c1 is 1");
    assert!(line.every);
    assert_eq!(line.path, with_steps(key("a1"), vec![dot("b")]));
    assert_eq!(
        line.named_by_each_of,
        Some(Path {
            position: None,
            start: Start::Params,
            steps: vec![dot("names")]
        })
    );
    assert_eq!(line.whose.len(), 1);
}

#[test]
fn a_from_line_without_extras_has_none_of_them() {
    let line = from("items");
    assert!(!line.every);
    assert_eq!(line.path, key("items"));
    assert_eq!(line.named_by_each_of, None);
    assert!(line.whose.is_empty());
}

#[test]
fn each_of_does_not_become_a_named_by_step() {
    let line = from("a1 named by each of b1");
    assert_eq!(line.path, key("a1"));
    assert_eq!(line.named_by_each_of, Some(key("b1")));
}

#[test]
fn a_named_by_step_before_each_of_stays_a_step() {
    let line = from("a1 named by $params.g named by each of $params.names");
    assert_eq!(
        line.path,
        with_steps(
            key("a1"),
            vec![Step::NamedBy(Reference::Params("g".into()))]
        )
    );
    assert!(line.named_by_each_of.is_some());
}

#[test]
fn a_path_named_by_a_word_that_starts_each_of_still_reads() {
    let line = from("a1 named by each");
    assert_eq!(
        line.path,
        with_steps(
            key("a1"),
            vec![Step::NamedBy(Reference::Name("each".into()))]
        )
    );
}

#[test]
fn every_is_a_prefix_not_a_key() {
    assert!(from("every x").every);
    assert!(!from("everything").every);
    assert_eq!(from("everything").path, key("everything"));
    assert!(parse_from("every").is_err());
    assert!(parse_from("every every").is_err());
    assert!(parse_from("everyx").is_ok());
}

#[test]
fn the_right_side_of_each_of_is_a_right_path() {
    assert!(parse_from("x named by each of \"a b\"").is_err());
    assert!(parse_from("x named by each of .\"a b\"").is_ok());
    assert!(parse_from("x named by each of empty").is_err());
    assert!(parse_from("x named by each of .empty").is_ok());
}
