mod support;

use ergo_policy_sentences::*;
use support::*;

fn number_printed(written: &str) -> String {
    printed_phrase(&format!("is {written}"))
        .strip_prefix("is ")
        .unwrap_or_default()
        .to_string()
}

fn string_printed(written: &str) -> String {
    printed_phrase(&format!("is {written}"))
        .strip_prefix("is ")
        .unwrap_or_default()
        .to_string()
}

fn path_printed(written: &str) -> String {
    printed(written)
}

#[test]
fn numbers_print_in_plain_decimal_form() {
    for (written, want) in [
        ("1.0", "1"),
        ("1e2", "100"),
        ("1E+2", "100"),
        ("1.5e-3", "0.0015"),
        ("1e-7", "0.0000001"),
        ("100e-2", "1"),
        ("123e-5", "0.00123"),
        ("12345678901234567890", "12345678901234567890"),
        ("0.1000000000000000000001", "0.1000000000000000000001"),
        ("-0", "0"),
        ("-0.0", "0"),
        ("0e5", "0"),
        ("0.0", "0"),
        ("1.50", "1.5"),
        ("10", "10"),
        ("-1e2", "-100"),
        ("-0.5e1", "-5"),
        ("1.5e300", &format!("15{}", "0".repeat(299))),
        ("0", "0"),
        ("-12.340", "-12.34"),
        ("5e0", "5"),
        ("0.00e3", "0"),
        ("1234.5e1", "12345"),
        ("1234.5e-1", "123.45"),
    ] {
        assert_eq!(number_printed(written), want, "{written}");
    }
}

#[test]
fn numbers_print_in_every_place_a_number_is_read() {
    assert_eq!(
        printed_phrase("is between 1.0 and 2e1"),
        "is between 1 and 20"
    );
    assert_eq!(printed_phrase("is 1 within 0.50"), "is 1 within 0.5");
    assert_eq!(printed_phrase("equals k plus 1.0"), "equals k plus 1");
    assert_eq!(printed_phrase("is one of 1.0, 2e1"), "is one of 1, 20");
}

#[test]
fn an_enormous_exponent_prints_as_written() {
    assert_eq!(number_printed("1e99999999"), "1e99999999");
    assert_eq!(
        number_printed("1e-99999999999999999999999"),
        "1e-99999999999999999999999"
    );
}

#[test]
fn a_string_with_a_backslash_and_no_quote_prints_in_single_quotes() {
    assert_eq!(string_printed("'a\\nb'"), "'a\\nb'");
    assert_eq!(string_printed("\"a\\\\nb\""), "'a\\nb'");
    assert_eq!(string_printed("'^\\d+$'"), "'^\\d+$'");
}

#[test]
fn a_plain_string_prints_in_double_quotes() {
    assert_eq!(string_printed("'abc'"), "\"abc\"");
    assert_eq!(string_printed("\"a b\""), "\"a b\"");
    assert_eq!(string_printed("''"), "\"\"");
}

#[test]
fn a_string_that_cannot_be_single_quoted_prints_in_double_quotes() {
    assert_eq!(string_printed("\"a'b\\\\c\""), "\"a'b\\\\c\"");
    assert_eq!(string_printed("'a\\\\\\\\b'"), "\"a\\\\\\\\b\"");
    assert_eq!(string_printed("\"a\\\\\""), "\"a\\\\\"");
    assert_eq!(string_printed("\"a\\\\\\n\""), "\"a\\\\\\n\"");
}

#[test]
fn a_string_prints_json_escapes_for_quotes_backslashes_and_control_characters() {
    assert_eq!(string_printed("\"a\\\"b\""), "\"a\\\"b\"");
    assert_eq!(string_printed("\"\\n\\r\\t\\b\\f\""), "\"\\n\\r\\t\\b\\f\"");
    assert_eq!(
        string_printed("\"\\u0001\\u001f\\u0000\""),
        "\"\\u0001\\u001f\\u0000\""
    );
    assert_eq!(string_printed("\"\\u000b\""), "\"\\u000b\"");
}

#[test]
fn a_string_prints_other_characters_raw() {
    assert_eq!(string_printed("\"\\/<>&\""), "\"/<>&\"");
    assert_eq!(string_printed("\"\\u00e9\""), "\"é\"");
    assert_eq!(string_printed("\"\\u2028\\u2029\""), "\"\u{2028}\u{2029}\"");
    assert_eq!(string_printed("\"\u{7f}\""), "\"\u{7f}\"");
    assert_eq!(string_printed("\"\\ud800\""), "\"\u{FFFD}\"");
}

#[test]
fn keys_print_bare_when_they_can_be() {
    assert_eq!(path_printed("a-b.c_d.\"e1\""), "a-b.c_d.e1");
    assert_eq!(path_printed("\"x\""), "x");
}

#[test]
fn other_keys_print_as_json_strings() {
    assert_eq!(
        path_printed("x.\"a b\".\"1\".\"$s\".\"\".\"é\""),
        "x.\"a b\".\"1\".\"$s\".\"\".\"é\""
    );
    assert_eq!(
        path_printed("x.\"a\\\"b\".\"c\\\\d\""),
        "x.\"a\\\"b\".\"c\\\\d\""
    );
}

#[test]
fn a_first_key_that_is_a_word_keeps_its_dot() {
    assert_eq!(path_printed(".empty.it"), ".empty.it");
    assert_eq!(path_printed(".it"), ".it");
    assert_eq!(printed_phrase("equals .true"), "equals .true");
    assert_eq!(
        printed_phrase("equals .empty plus .of"),
        "equals .empty plus .of"
    );
}

#[test]
fn a_dot_that_is_not_needed_is_dropped() {
    assert_eq!(path_printed(".x.y"), "x.y");
    assert_eq!(path_printed(".\"a b\""), "\"a b\"");
    assert_eq!(printed_phrase("equals .x"), "equals x");
}

#[test]
fn a_first_key_that_is_not_bare_gets_a_dot_on_the_right_only() {
    assert_eq!(printed_phrase("equals .\"a b\""), "equals .\"a b\"");
    assert_eq!(printed_phrase("equals .\"$schema\""), "equals .\"$schema\"");
    assert_eq!(printed("x whose \"a b\" is 1"), "x whose \"a b\" is 1");
    assert_eq!(printed_phrase("is in .\"a b\""), "is in .\"a b\"");
    assert_eq!(
        printed("x named by each of .\"a b\""),
        "x named by each of .\"a b\""
    );
}

#[test]
fn a_later_key_never_gets_a_dot() {
    assert_eq!(
        printed_phrase("equals x.empty.\"a b\""),
        "equals x.empty.\"a b\""
    );
}

#[test]
fn a_dot_written_before_an_alias_name_is_kept_on_the_right() {
    let read = from("x whose y equals .pr");
    assert_eq!(print_from(&read, &["pr"], &[]), "x whose y equals .pr");
    assert_eq!(print_from(&read, &["other"], &[]), "x whose y equals pr");
    assert_eq!(print_from(&read, &[], &[]), "x whose y equals pr");
}

#[test]
fn a_bare_name_that_is_an_alias_prints_without_a_dot() {
    let read = from("x whose y equals pr");
    assert_eq!(print_from(&read, &["pr"], &[]), "x whose y equals pr");
}

#[test]
fn the_left_of_a_condition_keeps_the_dot_it_was_written_with_when_the_name_is_an_alias() {
    let read = from("x whose .pr is 1 and count of .pr is 2 and days elapsed from .pr to .pr is 1");
    assert_eq!(
        print_from(&read, &["pr"], &[]),
        "x whose .pr is 1 and count of .pr is 2 and days elapsed from .pr to .pr is 1"
    );
}

#[test]
fn a_dotted_path_in_the_path_of_a_from_line_keeps_its_dot_for_an_alias() {
    let read = from(".pr.q");
    assert_eq!(print_path(&read.path, Side::Left, &["pr"]), ".pr.q");
    assert_eq!(print_path(&read.path, Side::Left, &[]), "pr.q");
}

#[test]
fn a_list_path_never_gets_an_alias_dot() {
    let read = from("x whose y is in .pr");
    assert_eq!(print_from(&read, &["pr"], &[]), "x whose y is in pr");
}

#[test]
fn print_term_and_print_path_follow_the_side() {
    let line = from("x whose y equals .\"a b\" plus .it");
    let FromCondition::Condition(c) = &line.whose[0] else {
        panic!()
    };
    let Phrase::Is {
        operand: Operand::Field(terms),
        ..
    } = &c.phrase
    else {
        panic!()
    };
    assert_eq!(print_term(&terms[0], &[]), ".\"a b\"");
    assert_eq!(print_term(&terms[1], &[]), ".it");
    let Term::Path(p) = &terms[0] else { panic!() };
    assert_eq!(print_path(p, Side::Left, &[]), "\"a b\"");
    assert_eq!(print_path(p, Side::Right, &[]), ".\"a b\"");
}

#[test]
fn print_condition_and_print_from_condition_print_one_condition() {
    let line = from("x whose some y.z, if any, is empty and count of w is 3");
    assert_eq!(
        print_from_condition(&line.whose[0], &[], &[]),
        "some y.z, if any, is empty"
    );
    assert_eq!(
        print_from_condition(&line.whose[1], &[], &[]),
        "count of w is 3"
    );
    let FromCondition::Condition(c) = &line.whose[1] else {
        panic!()
    };
    assert_eq!(print_condition(c, &[]), "count of w is 3");
}

#[test]
fn print_from_joins_the_conditions_with_and() {
    assert_eq!(
        printed("every x named by each of $params.l whose p is 1 and q exists"),
        "every x named by each of $params.l whose p is 1 and q exists"
    );
}

#[test]
fn a_bracket_index_that_ends_a_path_prints_in_words() {
    assert_eq!(path_printed("x[3]"), "item 4 of x");
    assert_eq!(path_printed("x[0]"), "item 1 of x");
    assert_eq!(path_printed("x.y[9]"), "item 10 of x.y");
    assert_eq!(path_printed("x[2][3]"), "item 4 of x[2]");
    assert_eq!(path_printed("$params[1]"), "item 2 of $params");
    assert_eq!(
        path_printed("x[9007199254740991]"),
        "item 9007199254740992 of x"
    );
}

#[test]
fn a_bracket_index_followed_by_a_key_stays_in_brackets() {
    assert_eq!(path_printed("x[3].y"), "x[3].y");
    assert_eq!(path_printed("x[3][\"k\"]"), "x[3].k");
    assert_eq!(path_printed("x[3] named by k"), "x[3] named by k");
}

#[test]
fn a_bracket_index_after_a_position_stays_in_brackets() {
    assert_eq!(path_printed("first of x[2]"), "first of x[2]");
    assert_eq!(
        path_printed("item 2 from last of x[2]"),
        "item 2 from last of x[2]"
    );
}

#[test]
fn positions_print_in_words() {
    assert_eq!(path_printed("first of x"), "first of x");
    assert_eq!(path_printed("last of x.y"), "last of x.y");
    assert_eq!(path_printed("item   3  of  x"), "item 3 of x");
    assert_eq!(
        path_printed("item 3 from last of x"),
        "item 3 from last of x"
    );
}

#[test]
fn a_position_in_words_is_not_turned_into_brackets() {
    assert_eq!(path_printed("item 4 of x"), "item 4 of x");
}

#[test]
fn named_by_steps_print_in_words() {
    assert_eq!(path_printed("x[$params.k]"), "x named by $params.k");
    assert_eq!(path_printed("x[$input.k]"), "x named by $input.k");
    assert_eq!(path_printed("x[k]"), "x named by k");
    assert_eq!(path_printed("x named by $params.k"), "x named by $params.k");
    assert_eq!(
        path_printed("x named by $params.\"a b\""),
        "x named by $params.\"a b\""
    );
    assert_eq!(
        path_printed("x named   by   $input.k.m"),
        "x named by $input.k.m"
    );
}

#[test]
fn bracket_keys_print_as_dotted_keys() {
    assert_eq!(path_printed("x[\"a b\"]"), "x.\"a b\"");
    assert_eq!(path_printed("x[\"abc\"]"), "x.abc");
    assert_eq!(path_printed("x[\"\"]"), "x.\"\"");
}

#[test]
fn it_prints_as_it_with_or_without_a_position() {
    assert_eq!(printed("x whose it is 1"), "x whose it is 1");
    assert_eq!(
        printed("x whose first of it exists"),
        "x whose first of it exists"
    );
    assert_eq!(printed("x whose some it is 1"), "x whose some it is 1");
    assert_eq!(
        printed("x whose count of it is 1"),
        "x whose count of it is 1"
    );
}

#[test]
fn is_and_equals_print_by_what_follows() {
    assert_eq!(printed_phrase("is 1"), "is 1");
    assert_eq!(printed_phrase("is equal to 1"), "is 1");
    assert_eq!(printed_phrase("equals k"), "equals k");
    assert_eq!(printed_phrase("is k"), "equals k");
    assert_eq!(printed_phrase("is not 1"), "is not 1");
    assert_eq!(printed_phrase("is not k"), "does not equal k");
    assert_eq!(printed_phrase("does not equal 1"), "is not 1");
    assert_eq!(printed_phrase("equals 1 plus k"), "equals 1 plus k");
    assert_eq!(printed_phrase("is count of k"), "equals count of k");
}

#[test]
fn one_of_and_in_print_by_what_follows() {
    assert_eq!(printed_phrase("is in 1,2"), "is one of 1, 2");
    assert_eq!(printed_phrase("is one of l"), "is in l");
    assert_eq!(printed_phrase("is not in 1,2"), "is not one of 1, 2");
    assert_eq!(printed_phrase("is not one of l"), "is not in l");
    assert_eq!(
        printed_phrase("is one of 1,   2 ,3".replace(" ,3", ",3").as_str()),
        "is one of 1, 2, 3"
    );
}

#[test]
fn a_and_an_print_by_the_type() {
    assert_eq!(printed_phrase("is a object"), "is an object");
    assert_eq!(printed_phrase("is an list"), "is a list");
    assert_eq!(printed_phrase("is a number"), "is a number");
    assert_eq!(printed_phrase("is a boolean"), "is a boolean");
    assert_eq!(printed_phrase("is a string"), "is a string");
}

#[test]
fn every_other_phrase_prints_in_its_one_spelling() {
    for phrase in [
        "exists",
        "does not exist",
        "is empty",
        "is not empty",
        "is a non-empty string",
        "contains 1",
        "does not contain k",
        "contains all of 1, 2",
        "contains none of l",
        "matches \"a\"",
        "does not match l",
        "starts with \"a\"",
        "ends with k",
        "is alphabetically before \"a\"",
        "is alphabetically after k",
        "is at least 1",
        "is at most 1",
        "is more than 1",
        "is less than 1",
        "is between 1 and 2",
        "is before k",
        "is after k",
        "is on or after k",
        "is on or before k",
        "is 1 within 2",
    ] {
        assert_eq!(printed_phrase(phrase), phrase);
    }
}

#[test]
fn terms_print_joined_by_plus() {
    assert_eq!(
        printed_phrase("equals  k  plus  1  plus  sum of l.m plus  days elapsed from a1 to b1"),
        "equals k plus 1 plus sum of l.m plus days elapsed from a1 to b1"
    );
}

#[test]
fn conditions_print_every_left_form() {
    assert_eq!(
        printed(
            "x whose some l, if any, is 1 and every m exists and sum of n is at least 1 and weeks elapsed from p1 to q1 is 1"
        ),
        "x whose some l, if any, is 1 and every m exists and sum of n is at least 1 and weeks elapsed from p1 to q1 is 1"
    );
}

#[test]
fn values_print_every_kind() {
    assert_eq!(
        printed_phrase("is one of true, false, null, \"a\", 'b', 1"),
        "is one of true, false, null, \"a\", \"b\", 1"
    );
}

#[test]
fn params_and_input_print_with_their_dollar() {
    assert_eq!(
        printed("$params.x whose $input.y is 1"),
        "$params.x whose $input.y is 1"
    );
    assert_eq!(printed("$input"), "$input");
}

#[test]
fn a_parent_name_on_the_left_of_a_whose_is_the_items_field_and_prints_with_a_dot() {
    let read = from("b.kids whose b.x equals v and some b.ls is empty");
    assert_eq!(
        print_from(&read, &["b"], &["b"]),
        "b.kids whose .b.x equals v and some .b.ls is empty"
    );
    assert_eq!(
        print_from(&read, &["b"], &[]),
        "b.kids whose b.x equals v and some b.ls is empty"
    );
}

#[test]
fn a_dot_on_the_path_of_some_in_a_from_line_stays_because_it_reads_the_field_and_not_the_part() {
    let read = from("ds whose some .cov.x exists");
    assert_eq!(
        print_from(&read, &["cov"], &[]),
        "ds whose some .cov.x exists"
    );
}

#[test]
fn a_name_that_is_both_a_parent_and_an_alias_prints_with_a_dot_only_on_the_left_of_a_whose() {
    let read = from("b.kids whose b.x equals b.y");
    assert_eq!(
        print_from(&read, &["b"], &["b"]),
        "b.kids whose .b.x equals b.y"
    );
    assert_eq!(
        print_from(&read, &["b"], &[]),
        "b.kids whose b.x equals b.y"
    );
}

#[test]
fn a_bracket_index_too_big_to_be_a_position_prints_as_written() {
    let check = parse_check("xs[9007199254740992] is 1").unwrap();
    assert_eq!(print_check(&check, &[]), "xs[9007199254740992] is 1");
    let check = parse_check("xs[2] is 1").unwrap();
    assert_eq!(print_check(&check, &[]), "item 3 of xs is 1");
}

#[test]
fn a_parent_name_on_the_left_of_a_from_condition_prints_with_a_dot() {
    let line = from("b.kids whose b.x equals v");
    assert_eq!(
        print_from_condition(&line.whose[0], &["b"], &["b"]),
        ".b.x equals v"
    );
    assert_eq!(
        print_from_condition(&line.whose[0], &["b"], &[]),
        "b.x equals v"
    );
}

#[test]
fn a_dot_written_on_the_left_of_a_from_condition_stays_when_the_name_is_an_alias() {
    let read = from("art.items whose art.k is 1 and .art.xs[0] is 5 and count of .art.xs is 1");
    assert_eq!(
        print_from(&read, &["art"], &[]),
        "art.items whose art.k is 1 and item 1 of .art.xs is 5 and count of .art.xs is 1"
    );
    assert_eq!(
        print_from(&read, &[], &[]),
        "art.items whose art.k is 1 and item 1 of art.xs is 5 and count of art.xs is 1"
    );
}
