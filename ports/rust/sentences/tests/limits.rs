mod support;

use ergo_sentences::*;
use support::*;

fn long_line(conditions: usize) -> String {
    let mut line = String::from("things");
    for n in 0..conditions {
        line.push_str(if n == 0 { " whose " } else { " and " });
        line.push_str(&format!("field_{n} is one of {n}, 2, 3"));
    }
    line
}

#[test]
fn a_line_of_three_hundred_characters_with_ten_ands_parses() {
    let line = long_line(11);
    assert!(line.chars().count() >= 300, "{}", line.chars().count());
    assert_eq!(from(&line).whose.len(), 11);
}

#[test]
fn the_same_line_ending_in_an_error_is_rejected_quickly() {
    let mut line = long_line(11);
    line.push_str(" and last is");
    assert_eq!(failure(&line), vec!["doesn't parse"]);
    let mut line = long_line(11);
    line.push_str(" and empty is 1");
    assert_eq!(
        failure(&line),
        vec!["empty is a word of the grammar: write .empty"]
    );
}

#[test]
fn a_hundred_conditions_parse() {
    assert_eq!(from(&long_line(100)).whose.len(), 100);
}

#[test]
fn a_hundred_conditions_ending_in_an_error_are_rejected_quickly() {
    let mut line = long_line(100);
    let column = line.chars().count() + " and x is ".len() + 1;
    line.push_str(" and x is \"a");
    assert_eq!(
        failure(&line),
        vec![format!("unclosed quote at column {column}")]
    );
}

#[test]
fn a_long_chain_of_plus_parses() {
    let terms: Vec<String> = (0..200).map(|n| format!("t{n}")).collect();
    let line = format!("x whose y equals {}", terms.join(" plus "));
    assert_eq!(from(&line).whose.len(), 1);
    let line = format!("{line} plus");
    assert_eq!(failure(&line), vec!["doesn't parse"]);
}

#[test]
fn a_long_list_of_values_parses() {
    let values: Vec<String> = (0..500).map(|n| n.to_string()).collect();
    let line = format!("x whose y is one of {}", values.join(", "));
    assert_eq!(from(&line).whose.len(), 1);
}

#[test]
fn a_long_path_parses() {
    let steps: Vec<String> = (0..300).map(|n| format!("k{n}")).collect();
    let line = format!("x.{}", steps.join("."));
    assert_eq!(parse_path(&line).unwrap().steps.len(), 300);
    assert_eq!(parse_path(&format!("{line} x")).unwrap_err().len(), 1);
}

#[test]
fn many_and_words_that_could_be_values_do_not_make_it_slow() {
    let mut line = String::from("x whose y equals z");
    for _ in 0..40 {
        line.push_str(" and y equals z plus 1 plus 2 plus 3");
    }
    assert_eq!(from(&line).whose.len(), 41);
    line.push_str(" and");
    assert_eq!(failure(&line), vec!["doesn't parse"]);
}

#[test]
fn a_tab_instead_of_a_space_does_not_parse() {
    assert_eq!(failure("x\twhose y is 1"), vec!["doesn't parse"]);
    assert_eq!(failure("x whose y is\t1"), vec!["doesn't parse"]);
    assert_eq!(failure("x whose\ty is 1"), vec!["doesn't parse"]);
}

#[test]
fn a_non_breaking_space_is_not_a_space() {
    assert!(parse_from("x\u{a0}whose y is 1").is_err());
    assert!(parse_from("\u{a0}x").is_err());
}

#[test]
fn params_as_a_step_does_not_parse() {
    assert!(parse_from("x.$params").is_err());
    assert!(parse_from("x whose y equals z.$input").is_err());
}

#[test]
fn item_zero_does_not_parse() {
    assert!(parse_from("item 0 of x").is_err());
    assert!(parse_from("x whose item 0 of y is 1").is_err());
}

#[test]
fn it_as_the_path_of_a_from_line_does_not_parse() {
    assert!(parse_from("it").is_err());
    assert!(parse_from("every it").is_err());
    assert!(parse_from("first of it").is_err());
}

#[test]
fn a_word_is_case_sensitive() {
    assert!(parse_from("x WHOSE y is 1").is_err());
    assert!(parse_from("x whose y IS 1").is_err());
    assert!(parse_from("X whose y is 1").is_ok());
    assert!(parse_from("x whose Empty is 1").is_ok());
}

#[test]
fn parenthesis_and_other_symbols_do_not_parse() {
    for line in [
        "(x)",
        "x whose (y is 1)",
        "x whose y == 1",
        "x whose y is 1;",
        "x whose y is 1 or z is 2",
        "x, y",
    ] {
        assert!(parse_from(line).is_err(), "{line:?}");
    }
}

#[test]
fn a_very_long_exponent_does_not_stop_the_reader() {
    let line = format!("x whose y is 1e{}", "9".repeat(60));
    assert!(parse_from(&line).is_ok());
}

fn within_seconds<T>(seconds: u64, read: impl FnOnce() -> T) -> T {
    let started = std::time::Instant::now();
    let read = read();
    let took = started.elapsed();
    assert!(
        took < std::time::Duration::from_secs(seconds),
        "took {took:?}"
    );
    read
}

#[test]
fn a_path_line_of_a_hundred_kilobytes_parses_in_time_that_grows_with_its_length() {
    let line = format!("x{} is 1", ".a".repeat(50_000));
    assert!(line.len() > 100_000);
    let check = within_seconds(5, || parse_check(&line)).unwrap();
    match &check.assertions[0] {
        Assertion::Plain { path, .. } => assert_eq!(path.steps.len(), 50_000),
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_list_of_ten_thousand_values_parses_in_time_that_grows_with_its_length() {
    let values = vec!["1"; 10_000].join(", ");
    let line = format!("x is one of {values}");
    let check = within_seconds(5, || parse_check(&line)).unwrap();
    match &check.assertions[0] {
        Assertion::Plain {
            phrase:
                Phrase::OneOf {
                    list: List::Values(values),
                    ..
                },
            ..
        } => assert_eq!(values.len(), 10_000),
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_chain_of_a_hundred_kilobytes_of_plus_terms_parses_in_time_that_grows_with_its_length() {
    let line = format!("x is y{}", " plus y".repeat(14_000));
    let check = within_seconds(5, || parse_check(&line)).unwrap();
    match &check.assertions[0] {
        Assertion::Plain {
            phrase:
                Phrase::Is {
                    operand: Operand::Field(terms),
                    ..
                },
            ..
        } => assert_eq!(terms.len(), 14_001),
        other => panic!("{other:?}"),
    }
}
