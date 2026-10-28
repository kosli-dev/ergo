mod support;

use ergo_sentences::*;
use support::*;

fn none() -> Vec<String> {
    Vec::new()
}

fn one(message: &str) -> Vec<String> {
    vec![message.to_string()]
}

#[test]
fn is_not_null_is_written_exists() {
    assert_eq!(
        problems("x is not null"),
        one("\"is not null\" is written \"exists\"")
    );
    assert_eq!(problems("x is not \"a\""), none());
    assert_eq!(problems("x is null"), none());
    assert_eq!(problems("x does not equal y"), none());
}

#[test]
fn within_only_compares_numbers() {
    assert_eq!(
        problems("x is \"a\" within 2"),
        one("\"within\" only compares numbers")
    );
    assert_eq!(
        problems("x is true within 2"),
        one("\"within\" only compares numbers")
    );
    assert_eq!(
        problems("x is null within 2"),
        one("\"within\" only compares numbers")
    );
    assert_eq!(problems("x is 1 within 2"), none());
    assert_eq!(problems("x equals y within 2"), none());
}

#[test]
fn within_needs_a_number_of_zero_or_more() {
    assert_eq!(
        problems("x is 1 within -2"),
        one("\"within\" needs a number of 0 or more")
    );
    assert_eq!(
        problems("x equals y within -0.5"),
        one("\"within\" needs a number of 0 or more")
    );
    assert_eq!(
        problems("x is 1 within -1e-5"),
        one("\"within\" needs a number of 0 or more")
    );
    assert_eq!(problems("x is 1 within 0"), none());
    assert_eq!(problems("x is 1 within -0"), none());
    assert_eq!(problems("x is 1 within -0.0e5"), none());
    assert_eq!(problems("x is 1 within 0.5"), none());
}

#[test]
fn order_phrases_take_a_number() {
    for op in ["is at least", "is at most", "is more than", "is less than"] {
        for bad in ["\"a\"", "true", "false", "null"] {
            assert_eq!(
                problems(&format!("x {op} {bad}")),
                one(&format!("\"{op}\" takes a number")),
                "{op} {bad}"
            );
        }
        assert_eq!(problems(&format!("x {op} 3")), none(), "{op}");
        assert_eq!(problems(&format!("x {op} y")), none(), "{op}");
        assert_eq!(problems(&format!("x {op} y plus 1")), none(), "{op}");
    }
}

#[test]
fn text_phrases_take_text() {
    for op in [
        "starts with",
        "ends with",
        "is alphabetically before",
        "is alphabetically after",
    ] {
        for bad in ["1", "true", "false", "null"] {
            assert_eq!(
                problems(&format!("x {op} {bad}")),
                one(&format!("\"{op}\" takes text")),
                "{op} {bad}"
            );
        }
        assert_eq!(problems(&format!("x {op} \"a\"")), none(), "{op}");
        assert_eq!(problems(&format!("x {op} ''")), none(), "{op}");
        assert_eq!(problems(&format!("x {op} y")), none(), "{op}");
    }
}

#[test]
fn time_phrases_take_a_time_or_a_number() {
    for op in ["is before", "is after", "is on or after", "is on or before"] {
        let message = format!("\"{op}\" takes a time or a number");
        for bad in ["\"yesterday\"", "true", "false", "null", "\"\"", "\"2020\""] {
            assert_eq!(
                problems(&format!("x {op} {bad}")),
                one(&message),
                "{op} {bad}"
            );
        }
        for good in [
            "5",
            "-1.5",
            "\"2020-01-01\"",
            "\"2020-01-01T10:00:00Z\"",
            "'2020-01-01'",
            "y",
            "y plus 1",
        ] {
            assert_eq!(problems(&format!("x {op} {good}")), none(), "{op} {good}");
        }
    }
}

fn takes_a_time(written: &str) -> bool {
    problems(&format!("x is before \"{written}\"")).is_empty()
}

#[test]
fn a_written_date_has_years_from_1678_to_2261() {
    assert!(takes_a_time("1678-01-01"));
    assert!(takes_a_time("2261-12-31"));
    assert!(!takes_a_time("1677-12-31"));
    assert!(!takes_a_time("2262-01-01"));
    assert!(!takes_a_time("1650-01-01"));
    assert!(!takes_a_time("1600-01-01"));
    assert!(!takes_a_time("2299-01-01"));
    assert!(!takes_a_time("0999-01-01"));
}

#[test]
fn a_written_date_is_a_real_date() {
    assert!(takes_a_time("2020-02-29"));
    assert!(!takes_a_time("2021-02-29"));
    assert!(!takes_a_time("1900-02-29"));
    assert!(takes_a_time("2000-02-29"));
    assert!(takes_a_time("2020-04-30"));
    assert!(!takes_a_time("2020-04-31"));
    assert!(takes_a_time("2020-01-31"));
    assert!(!takes_a_time("2020-01-32"));
    assert!(!takes_a_time("2020-00-10"));
    assert!(!takes_a_time("2020-13-10"));
    assert!(!takes_a_time("2020-01-00"));
    assert!(!takes_a_time("2020-1-1"));
    assert!(!takes_a_time("20200101"));
    assert!(!takes_a_time("2020/01/01"));
    assert!(!takes_a_time("2020-01-01 "));
    assert!(!takes_a_time(" 2020-01-01"));
}

#[test]
fn a_written_instant_has_a_time_and_an_offset() {
    assert!(takes_a_time("2020-01-01T00:00:00Z"));
    assert!(takes_a_time("2020-01-01T23:59:59Z"));
    assert!(takes_a_time("2020-01-01T10:00:00+00:00"));
    assert!(takes_a_time("2020-01-01T10:00:00-23:59"));
    assert!(takes_a_time("2020-01-01T10:00:00.5Z"));
    assert!(takes_a_time("2020-01-01T10:00:00.123456789012Z"));
    assert!(takes_a_time("2020-02-29T10:00:00Z"));
    assert!(takes_a_time("1678-01-01T00:00:00Z"));
    assert!(takes_a_time("2261-12-31T23:59:59Z"));
}

#[test]
fn a_written_instant_that_breaks_a_bound_is_not_a_time() {
    assert!(!takes_a_time("2020-01-01T24:00:00Z"));
    assert!(!takes_a_time("2020-01-01T23:60:00Z"));
    assert!(!takes_a_time("2020-01-01T23:59:60Z"));
    assert!(!takes_a_time("2020-01-01T10:00:00.Z"));
    assert!(!takes_a_time("2020-01-01T10:00:00+24:00"));
    assert!(!takes_a_time("2020-01-01T10:00:00-00:60"));
    assert!(!takes_a_time("2020-01-01T10:00:00+0000"));
    assert!(!takes_a_time("2020-01-01T10:00:00"));
    assert!(!takes_a_time("2020-01-01t10:00:00Z"));
    assert!(!takes_a_time("2020-01-01T10:00:00z"));
    assert!(!takes_a_time("2020-01-01 10:00:00Z"));
    assert!(!takes_a_time("2021-02-29T10:00:00Z"));
    assert!(!takes_a_time("1677-12-31T23:59:59Z"));
    assert!(!takes_a_time("2262-01-01T00:00:00Z"));
    assert!(!takes_a_time("2020-01-01T10:00:00Zx"));
}

#[test]
fn a_time_is_read_from_the_decoded_string() {
    assert_eq!(
        problems("x is before \"2020-01-01\\n\""),
        one("\"is before\" takes a time or a number")
    );
    assert_eq!(problems("x is before \"\\u0032020-01-01\""), none());
}

#[test]
fn an_out_of_range_number_is_exempt_from_the_takes_rules() {
    assert_eq!(
        problems("x is at least 1e999"),
        one("number out of range: 1e999")
    );
    assert_eq!(
        problems("x is before 1e999"),
        one("number out of range: 1e999")
    );
    assert_eq!(
        problems("x is at most -1e999"),
        one("number out of range: -1e999")
    );
}

#[test]
fn between_is_min_above_max_compared_on_the_digits() {
    assert_eq!(problems("x is between 2 and 1"), one("min above max"));
    assert_eq!(problems("x is between 1 and 2"), none());
    assert_eq!(problems("x is between 1 and 1"), none());
    assert_eq!(problems("x is between 1.0 and 1"), none());
    assert_eq!(problems("x is between 1e2 and 99"), one("min above max"));
    assert_eq!(problems("x is between 100 and 1e2"), none());
    assert_eq!(problems("x is between -1 and -2"), one("min above max"));
    assert_eq!(problems("x is between -2 and -1"), none());
    assert_eq!(problems("x is between -0 and 0"), none());
    assert_eq!(
        problems("x is between 0.5 and 0.49999999999999999999"),
        one("min above max")
    );
    assert_eq!(
        problems("x is between 12345678901234567891 and 12345678901234567890"),
        one("min above max")
    );
    assert_eq!(
        problems("x is between 12345678901234567890 and 12345678901234567891"),
        none()
    );
    assert_eq!(problems("x is between 1e-5 and 1e-6"), one("min above max"));
    assert_eq!(problems("x is between -1e5 and 1e-6"), none());
}

#[test]
fn a_number_outside_what_a_float_holds_is_out_of_range() {
    for written in [
        "1e309",
        "1e999",
        "-1e999",
        "1e-999",
        "1.7976931348623158e308",
        "2.2250738585072013e-308",
        "1e99999999999999999999",
    ] {
        assert_eq!(
            problems(&format!("x is {written}")),
            one(&format!("number out of range: {written}")),
            "{written}"
        );
    }
    for written in [
        "1.7976931348623157e308",
        "2.2250738585072014e-308",
        "1e308",
        "1e-307",
        "0e999",
        "0.000e5",
        "0",
        "-0",
        "1e0",
    ] {
        assert_eq!(problems(&format!("x is {written}")), none(), "{written}");
    }
}

#[test]
fn an_out_of_range_number_is_found_in_every_place_a_number_is_read() {
    let message = one("number out of range: 1e999");
    assert_eq!(problems("x is one of 1, 1e999"), message);
    assert_eq!(problems("x equals y plus 1e999"), message);
    assert_eq!(problems("x is between 1 and 1e999"), message);
    assert_eq!(problems("x is 1 within 1e999"), message);
    assert_eq!(problems("x contains 1e999"), message);
    assert_eq!(problems("every items whose k is 1e999 exists"), message);
    assert_eq!(problems("count of items whose k is 1e999 is 1"), message);
}

#[test]
fn a_pattern_that_re2_rejects_is_invalid() {
    assert_eq!(problems("x matches \"(\""), one("invalid pattern \"(\""));
    assert_eq!(
        problems("x does not match \"[a\""),
        one("invalid pattern \"[a\"")
    );
    assert_eq!(
        problems("x matches \"a\", \"(\""),
        one("invalid pattern \"(\"")
    );
    assert_eq!(problems("x matches \"^a.*\""), none());
    assert_eq!(problems("x does not match \"\""), none());
}

#[test]
fn a_pattern_that_is_not_text_is_invalid() {
    assert_eq!(problems("x matches 1"), one("invalid pattern 1"));
    assert_eq!(problems("x matches 1.50"), one("invalid pattern 1.5"));
    assert_eq!(problems("x matches true"), one("invalid pattern true"));
    assert_eq!(problems("x matches false"), one("invalid pattern false"));
    assert_eq!(problems("x matches null"), one("invalid pattern null"));
}

#[test]
fn a_pattern_in_a_path_is_not_checked() {
    assert_eq!(problems("x matches $params.p"), none());
    assert_eq!(problems("x matches p"), none());
}

#[test]
fn an_invalid_pattern_is_named_as_written_in_json() {
    assert_eq!(
        problems("x matches \"(\\\\\""),
        one("invalid pattern \"(\\\\\"")
    );
    assert_eq!(
        problems("x matches \"\\\\q\""),
        one("invalid pattern \"\\\\q\"")
    );
}

#[test]
fn contains_after_every_or_some_checks_each_item_of_the_last_list() {
    for op in [
        "contains",
        "does not contain",
        "contains all of",
        "contains none of",
    ] {
        let message = format!(
            "\"{op}\" after every or some would check each item of the last list, not the list: put the walk on a for line"
        );
        assert_eq!(
            problems(&format!("every items {op} 1")),
            one(&message),
            "{op}"
        );
        assert_eq!(
            problems(&format!("some items {op} 1")),
            one(&message),
            "{op}"
        );
        assert_eq!(problems(&format!("items {op} 1")), none(), "{op}");
    }
    assert_eq!(problems("every items matches \"a\""), none());
    assert_eq!(problems("every items is empty"), none());
}

#[test]
fn if_any_cannot_go_with_some() {
    assert_eq!(
        problems("some items, if any, exists"),
        one("if any can't go with some")
    );
    assert_eq!(problems("every items, if any, exists"), none());
    assert_eq!(problems("some items exists"), none());
    assert_eq!(
        for_problems(&for_line("some items, if any, as i"), &[]),
        one("if any can't go with some")
    );
    assert_eq!(
        for_problems(&for_line("every items, if any, as i"), &[]),
        none()
    );
    assert_eq!(
        from_problems(&from("x whose some y, if any, exists"), &[]),
        one("if any can't go with some")
    );
    assert_eq!(
        from_problems(&from("x whose every y, if any, exists"), &[]),
        none()
    );
}

#[test]
fn a_list_position_is_at_most_9007199254740991() {
    let message = one("9007199254740992 can't be a list position");
    assert_eq!(problems("item 9007199254740992 of x exists"), message);
    assert_eq!(problems("x[9007199254740992] exists"), message);
    assert_eq!(problems("x.y[9007199254740992].z exists"), message);
    assert_eq!(problems("x equals y[9007199254740992]"), message);
    assert_eq!(problems("item 9007199254740991 of x exists"), none());
    assert_eq!(problems("x[9007199254740991] exists"), none());
    assert_eq!(problems("x[0] exists"), none());
    assert_eq!(
        for_problems(&for_line("item 9007199254740992 of items as t"), &[]),
        message
    );
    assert_eq!(
        from_problems(&from("x whose y[9007199254740993] exists"), &[]),
        one("9007199254740993 can't be a list position")
    );
}

#[test]
fn a_word_of_the_grammar_is_not_a_first_key_in_a_tree() {
    let tree = Check {
        assertions: vec![Assertion::Plain {
            path: key("empty"),
            phrase: Phrase::Exists { not: false },
        }],
    };
    assert_eq!(
        check_problems(&tree, &[]),
        one("empty is a word of the grammar: write .empty")
    );
    let dotted_tree = Check {
        assertions: vec![Assertion::Plain {
            path: dotted("empty"),
            phrase: Phrase::Exists { not: false },
        }],
    };
    assert_eq!(check_problems(&dotted_tree, &[]), none());
}

#[test]
fn a_word_after_named_by_cannot_be_an_alias() {
    assert_eq!(
        problems("x named by empty exists"),
        one("empty can't be an alias")
    );
    assert_eq!(
        problems("x named by params exists"),
        one("params can't be an alias")
    );
    assert_eq!(
        problems("x named by input exists"),
        one("input can't be an alias")
    );
    assert_eq!(problems("x[of] exists"), one("of can't be an alias"));
    assert_eq!(problems("x named by k exists"), none());
    assert_eq!(problems("x named by $params.empty exists"), none());
}

#[test]
fn it_cannot_name_a_key() {
    assert_eq!(problems("x named by it exists"), one("it can't name a key"));
    assert_eq!(problems("x[it] exists"), one("it can't name a key"));
    assert_eq!(problems("x named by itx exists"), none());
}

#[test]
fn an_alias_of_a_for_item_cannot_be_a_word() {
    for word in ["it", "empty", "params", "input", "every"] {
        assert_eq!(
            for_problems(&for_line(&format!("every items as {word}")), &[]),
            one(&format!("{word} can't be an alias")),
            "{word}"
        );
    }
    assert_eq!(
        for_problems(&for_line("every items as item_1"), &[]),
        none()
    );
}

#[test]
fn an_alias_given_twice_is_reported() {
    assert_eq!(
        for_problems(&for_line("every items as i, some other as i"), &[]),
        one("i is given twice")
    );
    assert_eq!(
        for_problems(&for_line("every items as i, some other as j"), &[]),
        none()
    );
}

#[test]
fn it_can_start_an_assertion_and_follow_every_some_count_and_sum() {
    for line in [
        "it is empty",
        "every it is 1",
        "some it is 1",
        "count of it is 1",
        "sum of it is 1",
        "count of it plus 1 is 1",
        "first of it is 1",
        "every item 2 of it is 1",
        "it is 1 and it is 2",
    ] {
        assert_eq!(problems(line), none(), "{line}");
    }
}

#[test]
fn it_anywhere_else_in_a_check_is_misplaced() {
    let message = one("it can only start an assertion: write it first, like it is not empty");
    for line in [
        "x equals it",
        "x equals it plus 1",
        "x is one of it",
        "every items whose it is 1 is empty",
        "every items whose count of it is 1 is empty",
        "days elapsed from it to y is 1",
        "it plus 1 is 1",
        "x contains it",
    ] {
        match parse_check(line) {
            Ok(read) => assert_eq!(check_problems(&read, &[]), message, "{line}"),
            Err(_) => assert_eq!(check_failure(line), message, "{line}"),
        }
    }
}

#[test]
fn it_in_a_for_line_is_misplaced() {
    let message = one("it can only start an assertion: write it first, like it is not empty");
    assert_eq!(for_failure("every it as i"), message);
    assert_eq!(for_failure("last of items sorted by it as i"), message);
    assert_eq!(
        for_problems(&for_line("every items whose it is 1 as i"), &[]),
        message
    );
}

#[test]
fn it_in_a_from_line_is_allowed_in_a_condition_only() {
    for line in [
        "x whose it is 1",
        "x whose some it is 1",
        "x whose count of it is 1",
        "x whose first of it exists",
    ] {
        assert_eq!(from_problems(&from(line), &[]), none(), "{line}");
    }
    let message = one("it can only start an assertion: write it first, like it is not empty");
    assert_eq!(failure("x whose y equals it"), message);
    assert_eq!(failure("x whose days elapsed from it to y is 1"), message);
}

#[test]
fn it_followed_by_a_step_is_reported_on_a_tree() {
    let tree = Check {
        assertions: vec![Assertion::Plain {
            path: Path {
                position: None,
                start: Start::It,
                steps: vec![dot("name")],
            },
            phrase: Phrase::Exists { not: false },
        }],
    };
    assert_eq!(
        check_problems(&tree, &[]),
        one("it is the whole subject: write name, not it.name")
    );
}

#[test]
fn a_count_cannot_take_a_phrase_that_is_not_a_comparison() {
    assert_eq!(
        check_failure("count of items exists"),
        one("exists can't follow a count of, a sum of or a plus")
    );
    assert_eq!(
        check_failure("sum of items.p is empty"),
        one("is empty can't follow a count of, a sum of or a plus")
    );
    assert_eq!(
        check_failure("1 plus y matches \"a\""),
        one("matches can't follow a count of, a sum of or a plus")
    );
    assert_eq!(
        failure("x whose count of y exists"),
        one("exists can't follow a count of, a sum of or a plus")
    );
    for ok in [
        "is 1",
        "is not 1",
        "is at least 1",
        "is at most 1",
        "is more than 1",
        "is less than 1",
        "is between 1 and 2",
    ] {
        assert_eq!(problems(&format!("count of items {ok}")), none(), "{ok}");
    }
}

#[test]
fn a_number_cannot_start_a_sentence() {
    assert_eq!(
        check_failure("5 is 1"),
        one("a number can't start a sentence")
    );
    assert_eq!(problems("5 plus y is 1"), none());
    assert_eq!(
        check_failure("1e999 is 1"),
        one("number out of range: 1e999")
    );
}

#[test]
fn a_walk_compared_with_itself_names_the_path() {
    assert_eq!(problems("x equals x"), one("x is compared with itself"));
    assert_eq!(
        problems("x.y is not x.y"),
        one("x.y is compared with itself")
    );
    assert_eq!(
        problems("x is at least x"),
        one("x is compared with itself")
    );
    assert_eq!(
        problems("x starts with x"),
        one("x is compared with itself")
    );
    assert_eq!(problems("x is before x"), one("x is compared with itself"));
    assert_eq!(
        problems("x is alphabetically after x"),
        one("x is compared with itself")
    );
    assert_eq!(problems("x equals .x"), one("x is compared with itself"));
    assert_eq!(
        problems("x[1] equals item 2 of x"),
        one("item 2 of x is compared with itself")
    );
    assert_eq!(problems("x equals y"), none());
    assert_eq!(problems("x equals x plus 1"), none());
    assert_eq!(problems("x contains x"), none());
    assert_eq!(problems("x is one of x"), none());
    assert_eq!(problems("x.y equals x"), none());
    assert_eq!(
        problems("$params.x equals $params.x"),
        one("$params.x is compared with itself")
    );
    assert_eq!(problems("$params.x equals $input.x"), none());
}

#[test]
fn an_alias_and_the_field_with_its_name_are_different_paths() {
    assert_eq!(
        problems_with("pr equals pr", &["pr"]),
        one("pr is compared with itself")
    );
    assert_eq!(problems_with("pr equals .pr", &["pr"]), none());
    assert_eq!(problems_with(".pr equals pr", &["pr"]), none());
    assert_eq!(
        problems_with(".pr equals .pr", &["pr"]),
        one(".pr is compared with itself")
    );
    assert_eq!(
        problems_with("pr equals .pr", &[]),
        one("pr is compared with itself")
    );
    assert_eq!(
        problems_with("pr.q equals pr.q", &["pr"]),
        one("pr.q is compared with itself")
    );
}

#[test]
fn after_every_or_some_the_item_is_compared_with_a_field_that_is_the_item() {
    let message = |path: &str| {
        one(&format!(
            "{path} is compared with itself, because after every or some it's read from the item: to read the subject's {path}, put the list on the for line and compare under assert"
        ))
    };
    assert_eq!(problems("every items.x equals x"), message("x"));
    assert_eq!(problems("some items.x.y equals x.y"), message("x.y"));
    assert_eq!(problems("every items.x.y equals y"), message("y"));
    assert_eq!(problems("every items.x is at least x"), message("x"));
    assert_eq!(problems("every x equals x"), none());
    assert_eq!(problems("every x.y equals x"), none());
    assert_eq!(problems("every items.x equals y"), none());
    assert_eq!(problems("every items.x equals x plus 1"), none());
    assert_eq!(
        problems("every items.x contains x"),
        one(
            "\"contains\" after every or some would check each item of the last list, not the list: put the walk on a for line"
        )
    );
    assert_eq!(problems("every items.x equals $params.x"), none());
    assert_eq!(problems_with("every items.pr equals pr", &["pr"]), none());
    assert_eq!(
        problems_with("every items.pr equals .pr", &["pr"]),
        message("pr")
    );
}

#[test]
fn in_a_whose_the_left_is_the_item_and_the_right_is_the_subject() {
    let message = |path: &str| {
        one(&format!(
            "{path} is compared with itself, because in a whose it's read from the item: to read the subject's {path}, compare under assert"
        ))
    };
    assert_eq!(
        problems("every items whose x equals x is empty"),
        message("x")
    );
    assert_eq!(
        problems("every items whose x equals .x is empty"),
        message("x")
    );
    assert_eq!(
        problems("every items whose x.y equals x.y is empty"),
        message("x.y")
    );
    assert_eq!(problems("every items whose x equals y is empty"), none());
    assert_eq!(problems("every items whose x contains x is empty"), none());
    assert_eq!(
        problems_with("every items whose pr equals pr is empty", &["pr"]),
        none()
    );
    assert_eq!(
        problems_with("every items whose pr equals .pr is empty", &["pr"]),
        message("pr")
    );
    assert_eq!(
        problems_with("every items whose .pr equals pr is empty", &["pr"]),
        none()
    );
}

#[test]
fn a_count_with_a_whose_cannot_read_the_subjects_field() {
    assert_eq!(
        problems("count of items whose x equals x is 1"),
        one(
            "x is compared with itself, because in a whose it's read from the item, and a count or a sum can't read the subject's field there yet"
        )
    );
    assert_eq!(problems("count of items whose x equals y is 1"), none());
}

#[test]
fn a_for_item_whose_is_compared_with_the_aliases_before_it() {
    let message = one(
        "x is compared with itself, because in a whose it's read from the item: to read the subject's x, compare under assert",
    );
    assert_eq!(
        for_problems(&for_line("every items whose x equals x as i"), &[]),
        message
    );
    assert_eq!(
        for_problems(
            &for_line("every items as pr, every other whose pr equals pr as j"),
            &[]
        ),
        none()
    );
    assert_eq!(
        for_problems(
            &for_line("every items as pr, every other whose pr equals .pr as j"),
            &[]
        ),
        one(
            "pr is compared with itself, because in a whose it's read from the item: to read the subject's pr, compare under assert"
        )
    );
    assert_eq!(
        for_problems(&for_line("every items whose pr equals pr as j"), &["pr"]),
        none()
    );
}

#[test]
fn sorted_by_reads_a_field_of_each_item() {
    let message = one("\"sorted by\" reads a field of each item");
    assert_eq!(
        for_failure("last of items sorted by $params.x as l"),
        message
    );
    assert_eq!(
        for_failure("last of items sorted by $input.x as l"),
        message
    );
    assert_eq!(
        for_failure("last of items sorted by first of x as l"),
        message
    );
    assert_eq!(
        for_problems(&for_line("last of items sorted by created as l"), &[]),
        none()
    );
}

#[test]
fn sorted_by_does_not_read_an_alias_without_a_dot() {
    assert_eq!(
        for_problems(&for_line("last of items sorted by l as l"), &[]),
        one("\"sorted by\" reads a field of the item, not l: write .l")
    );
    assert_eq!(
        for_problems(
            &for_line("every items as i, last of other sorted by i.x as l"),
            &[]
        ),
        one("\"sorted by\" reads a field of the item, not i: write .i")
    );
    assert_eq!(
        for_problems(&for_line("last of items sorted by .l as l"), &[]),
        none()
    );
    assert_eq!(
        for_problems(&for_line("last of items sorted by m as l"), &[]),
        none()
    );
}

#[test]
fn a_for_item_without_every_some_or_a_position_is_reported() {
    assert_eq!(
        for_failure("items as i"),
        vec!["an item starts with \"every\", \"some\" or a position, like \"last of\""]
    );
    assert_eq!(
        for_failure("every items as i, other as j"),
        vec!["an item starts with \"every\", \"some\" or a position, like \"last of\""]
    );
}

#[test]
fn sorted_by_after_every_or_some_is_reported() {
    assert_eq!(
        for_failure("every items sorted by k as i"),
        vec!["\"sorted by\" goes after a position, like \"last of\", not after every or some"]
    );
}

#[test]
fn if_any_after_a_position_is_reported() {
    assert_eq!(
        for_failure("last of items, if any, as i"),
        vec!["if any can't go with a position"]
    );
}

#[test]
fn a_whose_after_a_plain_path_is_reported() {
    let message = "a whose goes after every, some, count of or sum of";
    assert_eq!(check_failure("items whose k is 1 is empty"), vec![message]);
    assert_eq!(check_failure("y plus 1 whose k is 1 is 3"), vec![message]);
    assert_eq!(
        check_failure("days elapsed from a1 to b1 whose k is 1 is 3"),
        vec![message]
    );
}

#[test]
fn problems_are_sorted_and_listed_once() {
    let found = problems("x is not null and y is not null and z starts with 1");
    let mut sorted = found.clone();
    sorted.sort();
    sorted.dedup();
    assert_eq!(found, sorted);
    assert_eq!(found.len(), 2);
}

#[test]
fn a_problem_in_a_whose_is_found() {
    assert_eq!(
        problems("every items whose k matches \"(\" is empty"),
        one("invalid pattern \"(\"")
    );
    assert_eq!(
        problems("count of items whose k is between 2 and 1 is 1"),
        one("min above max")
    );
}

#[test]
fn from_lines_report_the_same_rules() {
    assert_eq!(
        from_problems(&from("x whose y is between 2 and 1"), &[]),
        one("min above max")
    );
    assert_eq!(
        from_problems(&from("x whose y matches \"(\""), &[]),
        one("invalid pattern \"(\"")
    );
    assert_eq!(
        from_problems(&from("x whose y is not null"), &[]),
        one("\"is not null\" is written \"exists\"")
    );
    assert_eq!(from_problems(&from("x whose y is 1"), &[]), none());
}

#[test]
fn a_parse_failure_lists_the_tree_problems_of_the_lenient_reading_too() {
    assert_eq!(
        check_failure("empty matches \"(\" and y is not null"),
        vec![
            "\"is not null\" is written \"exists\"",
            "empty is a word of the grammar: write .empty",
            "invalid pattern \"(\"",
        ]
    );
    assert_eq!(
        failure("empty whose y is between 2 and 1"),
        vec![
            "empty is a word of the grammar: write .empty",
            "min above max"
        ]
    );
}
