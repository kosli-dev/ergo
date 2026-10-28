mod support;

use ergo_sentences::*;
use support::*;

fn errors_of(line: &str) -> Vec<SyntaxError> {
    parse_from(line).unwrap_err()
}

fn one(message: &str, column: Option<usize>) -> Vec<SyntaxError> {
    vec![SyntaxError {
        column,
        message: message.to_string(),
    }]
}

#[test]
fn an_unclosed_double_quote_names_its_column() {
    assert_eq!(
        errors_of("x whose y is \"abc"),
        one("unclosed quote at column 14", Some(14))
    );
}

#[test]
fn an_unclosed_single_quote_names_its_column() {
    assert_eq!(
        errors_of("x whose y is 'abc"),
        one("unclosed quote at column 14", Some(14))
    );
}

#[test]
fn the_column_of_an_unclosed_quote_comes_after_closed_strings() {
    assert_eq!(
        errors_of("x whose y is \"a\" and z is \"b"),
        one("unclosed quote at column 27", Some(27))
    );
}

#[test]
fn a_quote_closed_by_an_escape_is_still_unclosed() {
    assert_eq!(
        errors_of("x whose y is \"a\\\""),
        one("unclosed quote at column 14", Some(14))
    );
    assert_eq!(
        errors_of("x whose y is 'a\\'"),
        one("unclosed quote at column 14", Some(14))
    );
}

#[test]
fn an_apostrophe_in_a_word_opens_a_string() {
    assert_eq!(
        errors_of("x whose y is it's"),
        one("unclosed quote at column 16", Some(16))
    );
}

#[test]
fn columns_count_characters_not_bytes() {
    assert_eq!(
        errors_of("x whose \"é\" is \"a"),
        one("unclosed quote at column 16", Some(16))
    );
}

#[test]
fn columns_count_a_four_byte_character_as_one() {
    assert_eq!(
        errors_of("x whose \"\u{1F600}\" is \"a"),
        one("unclosed quote at column 16", Some(16))
    );
}

#[test]
fn columns_count_from_the_trimmed_line() {
    assert_eq!(
        errors_of("   x whose y is \"a"),
        one("unclosed quote at column 14", Some(14))
    );
}

#[test]
fn an_unclosed_quote_is_reported_before_everything_else() {
    assert_eq!(
        errors_of("empty whose y is \"a \"\\q\" $z"),
        one("unclosed quote at column 24", Some(24))
    );
}

#[test]
fn an_invalid_string_names_its_column() {
    assert_eq!(
        errors_of("x whose y is \"\\q\""),
        one("invalid string at column 14", Some(14))
    );
    assert_eq!(
        errors_of("x whose y is '\u{1}'"),
        one("invalid string at column 14", Some(14))
    );
}

#[test]
fn every_invalid_string_gets_its_own_message() {
    assert_eq!(
        errors_of("x whose y is \"\\q\" and z is \"\\u12\""),
        vec![
            SyntaxError {
                column: Some(14),
                message: "invalid string at column 14".into()
            },
            SyntaxError {
                column: Some(28),
                message: "invalid string at column 28".into()
            },
        ]
    );
}

#[test]
fn a_tab_inside_a_string_is_invalid() {
    assert_eq!(
        errors_of("x whose y is \"a\tb\""),
        one("invalid string at column 14", Some(14))
    );
}

#[test]
fn a_bad_escape_in_a_key_is_an_invalid_string() {
    assert_eq!(
        errors_of("x.\"\\q\""),
        one("invalid string at column 3", Some(3))
    );
}

#[test]
fn a_grammar_word_as_a_first_key_says_to_write_a_dot() {
    assert_eq!(
        failure("empty whose y is 1"),
        vec!["empty is a word of the grammar: write .empty"]
    );
    assert_eq!(
        failure("x whose y equals empty"),
        vec!["empty is a word of the grammar: write .empty"]
    );
    assert_eq!(
        failure("x whose y is one of first"),
        vec!["first is a word of the grammar: write .first"]
    );
}

#[test]
fn several_grammar_words_are_listed_sorted_and_once() {
    assert_eq!(
        failure("x whose some of is 1 and count of every is 2 and of is 3"),
        vec![
            "every is a word of the grammar: write .every",
            "of is a word of the grammar: write .of",
        ]
    );
}

#[test]
fn a_word_that_is_a_phrase_start_is_still_a_word() {
    assert_eq!(
        failure("not"),
        vec!["not is a word of the grammar: write .not"]
    );
    assert_eq!(failure("a"), vec!["a is a word of the grammar: write .a"]);
    assert_eq!(
        failure("x named by each of in"),
        vec!["in is a word of the grammar: write .in"]
    );
}

#[test]
fn it_followed_by_a_key_says_what_to_write() {
    assert_eq!(
        failure("x whose it.name is 1"),
        vec!["it is the whole subject: write name, not it.name"]
    );
    assert_eq!(
        failure("x whose it.\"a b\" is 1"),
        vec!["it is the whole subject: write \"a b\", not it.\"a b\""]
    );
}

#[test]
fn it_followed_by_anything_else_says_nothing_can_follow() {
    assert_eq!(
        failure("x whose it[0] is 1"),
        vec!["it is the whole subject: nothing can follow it"]
    );
    assert_eq!(
        failure("x whose it named by k is 1"),
        vec!["it is the whole subject: nothing can follow it"]
    );
}

#[test]
fn it_as_the_path_of_a_from_line_can_only_start_an_assertion() {
    let message = "it can only start an assertion: write it first, like it is not empty";
    assert_eq!(failure("it"), vec![message]);
    assert_eq!(failure("every it"), vec![message]);
    assert_eq!(failure("it whose y is 1"), vec![message]);
    assert_eq!(failure("x named by each of it"), vec![message]);
    assert_eq!(failure("x whose y equals it"), vec![message]);
    assert_eq!(failure("x whose y is one of it"), vec![message]);
    assert_eq!(
        failure("x whose days elapsed from it to z is 1"),
        vec![message]
    );
}

#[test]
fn it_problems_are_listed_with_word_problems_in_order() {
    assert_eq!(
        failure("empty whose it.name is 1 and y equals it"),
        vec![
            "empty is a word of the grammar: write .empty",
            "it can only start an assertion: write it first, like it is not empty",
            "it is the whole subject: write name, not it.name",
        ]
    );
}

#[test]
fn naming_a_key_with_a_word_is_reported() {
    assert_eq!(
        failure("empty named by empty"),
        vec![
            "empty can't be an alias",
            "empty is a word of the grammar: write .empty",
        ]
    );
}

#[test]
fn a_dollar_name_that_is_not_params_or_input_is_unknown() {
    assert_eq!(failure("x whose y equals $z"), vec!["unknown name $z"]);
    assert_eq!(failure("$z"), vec!["unknown name $z"]);
    assert_eq!(failure("x[$z]"), vec!["unknown name $z"]);
}

#[test]
fn unknown_names_are_sorted_and_listed_once() {
    assert_eq!(
        failure("x whose y equals $b and z equals $a and w equals $b"),
        vec!["unknown name $a", "unknown name $b"]
    );
}

#[test]
fn a_dollar_name_inside_a_string_is_not_a_name() {
    assert!(parse_from("x whose y is \"$z\"").is_ok());
    assert_eq!(
        failure("x whose y is \"$z\" and w is $v"),
        vec!["unknown name $v"]
    );
}

#[test]
fn a_dollar_name_glued_to_a_word_is_not_looked_at() {
    assert_eq!(failure("x$z"), vec!["doesn't parse"]);
}

#[test]
fn a_name_that_starts_with_params_is_unknown() {
    assert_eq!(failure("$paramsx"), vec!["unknown name $paramsx"]);
    assert_eq!(
        failure("x whose y equals $inputs.z"),
        vec!["unknown name $inputs"]
    );
}

#[test]
fn two_quantifiers_are_reported() {
    assert_eq!(
        failure("some l every m"),
        vec!["two quantifiers in one sentence: put them on a for line"]
    );
}

#[test]
fn a_missing_number_after_within_is_reported() {
    assert_eq!(
        failure("x whose y is 1 within"),
        vec!["\"within\" needs a number after it"]
    );
}

#[test]
fn a_quantified_path_with_no_phrase_names_the_column_after_it() {
    assert_eq!(
        errors_of("some l.m"),
        one(
            "nothing after the path at column 9: expected a phrase, like \"is\" or \"exists\"",
            Some(9)
        )
    );
}

#[test]
fn columns_after_every_count_from_the_text_that_follows_it() {
    assert_eq!(
        errors_of("every x whose y is \"a"),
        one("unclosed quote at column 14", Some(14))
    );
    assert_eq!(
        errors_of("every   x whose \"\\q\" is 1"),
        one("invalid string at column 9", Some(9))
    );
}

#[test]
fn a_whose_inside_a_condition_says_a_condition_cannot_have_one() {
    let message = "a condition after whose can't have a whose of its own";
    assert_eq!(failure("x whose some l whose m is 1 is 2"), vec![message]);
    assert_eq!(
        failure("x whose count of l whose m is 1 is 2"),
        vec![message]
    );
    assert_eq!(
        failure("x whose y is 1 and every l whose m is 1 is 2"),
        vec![message]
    );
    assert_eq!(failure("x whose sum of l whose m is 1 is 2"), vec![message]);
}

#[test]
fn a_line_that_reads_in_no_way_does_not_parse() {
    for line in [
        "",
        "x whose",
        "x whose ",
        "x whose y",
        "x whose y is",
        "x y",
        "x is 1",
        "whose y is 1",
        "x whose y is 1 and",
    ] {
        assert_eq!(failure(line), vec!["doesn't parse"], "{line:?}");
    }
}

#[test]
fn a_condition_after_a_count_with_a_phrase_it_cannot_take_is_reported() {
    assert_eq!(
        failure("x whose count of l exists"),
        vec!["exists can't follow a count of, a sum of or a plus"]
    );
    assert_eq!(
        failure("x whose count of l is empty"),
        vec!["is empty can't follow a count of, a sum of or a plus"]
    );
    assert_eq!(
        failure("x whose days elapsed from a1 to b1 is one of 1, 2"),
        vec!["is one of can't follow a count of, a sum of or a plus"]
    );
}

#[test]
fn errors_say_nothing_about_a_line_that_parses() {
    assert!(parse_from("x whose y is \"a\"").is_ok());
    assert!(parse_from("x whose y is 'a'").is_ok());
}

#[test]
fn a_path_that_does_not_parse_has_the_same_messages() {
    assert_eq!(
        parse_path("ab.b c").unwrap_err(),
        one("doesn't parse", None)
    );
    assert_eq!(
        parse_path("ab.\"c").unwrap_err(),
        one("unclosed quote at column 4", Some(4))
    );
    assert_eq!(parse_path("$z").unwrap_err(), one("unknown name $z", None));
    assert_eq!(
        parse_path("empty").unwrap_err(),
        one("empty is a word of the grammar: write .empty", None)
    );
    assert_eq!(
        parse_path("it").unwrap_err(),
        one(
            "it can only start an assertion: write it first, like it is not empty",
            None
        )
    );
    assert_eq!(
        parse_path("x whose y is 1").unwrap_err(),
        one("doesn't parse", None)
    );
}

#[test]
fn the_error_of_a_path_keeps_every_in_the_text() {
    assert_eq!(
        parse_path("every \"a").unwrap_err(),
        one("unclosed quote at column 7", Some(7))
    );
}

#[test]
fn a_line_that_is_only_a_path_names_what_is_wrong_with_the_path_first() {
    assert_eq!(
        check_failure("and"),
        ["and is a word of the grammar: write .and"]
    );
    assert_eq!(
        check_failure("every"),
        ["every is a word of the grammar: write .every"]
    );
    assert_eq!(
        check_failure("whose"),
        ["whose is a word of the grammar: write .whose"]
    );
    assert_eq!(
        check_failure("it"),
        ["it can only start an assertion: write it first, like it is not empty"]
    );
    assert_eq!(
        check_failure("it.x"),
        ["it is the whole subject: write x, not it.x"]
    );
    assert_eq!(
        check_failure("x named by between"),
        ["between can't be an alias"]
    );
    assert_eq!(check_failure("x named by and"), ["and can't be an alias"]);
}

#[test]
fn a_line_that_is_only_a_path_written_well_says_nothing_follows_it() {
    for (line, column) in [
        ("x", 2),
        ("x.y", 4),
        ("first of x", 11),
        ("x.and", 6),
        (".every", 7),
        ("$params.x", 10),
        ("x named by y", 13),
        ("every xs", 9),
    ] {
        assert_eq!(
            check_failure(line),
            [format!(
                "nothing after the path at column {column}: expected a phrase, like \"is\" or \"exists\""
            )],
            "{line}"
        );
    }
}

#[test]
fn a_lone_path_after_every_or_some_says_nothing_follows_it_whatever_it_holds() {
    for (line, column) in [("every it", 9), ("every last", 11), ("some   it", 10)] {
        assert_eq!(
            check_failure(line),
            [format!(
                "nothing after the path at column {column}: expected a phrase, like \"is\" or \"exists\""
            )],
            "{line}"
        );
    }
}

#[test]
fn a_for_item_given_as_a_from_line_says_an_item_starts_with_every_or_some() {
    for line in [
        "every pull_requests.commits as commit",
        "every xs as x",
        "x as y",
    ] {
        assert_eq!(
            failure(line),
            [r#"an item starts with "every", "some" or a position, like "last of""#],
            "{line}"
        );
    }
}

#[test]
fn a_syntax_error_displays_as_its_message_and_is_an_error() {
    let errors = errors_of("x whose y is \"abc");
    assert_eq!(errors[0].to_string(), "unclosed quote at column 14");
    let boxed: Box<dyn std::error::Error> = Box::new(errors[0].clone());
    assert_eq!(boxed.to_string(), "unclosed quote at column 14");
}
