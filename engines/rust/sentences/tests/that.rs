mod support;

use support::*;

#[test]
fn that_picks_items_by_the_value_itself_on_a_from_line() {
    let line = from("every ws that starts with \"b\"");
    assert_eq!(line.whose.len(), 1);
    assert_eq!(
        printed("every ws that starts with \"b\""),
        "every ws that starts with \"b\""
    );
}

#[test]
fn every_condition_after_an_and_needs_its_own_word() {
    assert_eq!(
        printed("ws that starts with \"b\" and that ends with \"y\""),
        "ws that starts with \"b\" and that ends with \"y\""
    );
    assert_eq!(
        printed("ws whose it starts with \"b\" and that ends with \"y\""),
        "ws whose it starts with \"b\" and that ends with \"y\""
    );
    assert_eq!(
        printed("ws whose p is 1 and whose q is 2"),
        "ws whose p is 1 and whose q is 2"
    );
}

#[test]
fn a_condition_after_and_without_a_word_is_written_wrong() {
    assert_eq!(failure("ws whose p is 1 and q is 2"), vec!["doesn't parse"]);
    assert_eq!(
        failure("ws that starts with \"b\" and ends with \"y\""),
        vec!["doesn't parse"]
    );
    assert_eq!(
        failure("ws that starts with \"b\" that ends with \"y\""),
        vec!["doesn't parse"]
    );
    assert_eq!(failure("ws that"), vec!["doesn't parse"]);
}

#[test]
fn that_works_in_checks_and_for_lines() {
    assert_eq!(
        printed_check("every ws that starts with \"b\" ends with \"y\""),
        "every ws that starts with \"b\" ends with \"y\""
    );
    assert_eq!(
        printed_check("count of ws that starts with \"b\" and that ends with \"y\" is 1"),
        "count of ws that starts with \"b\" and that ends with \"y\" is 1"
    );
    assert_eq!(
        printed_for("every ws that starts with \"b\" as w"),
        "every ws that starts with \"b\" as w"
    );
    assert_eq!(
        check_failure("every ws that is not empty"),
        vec!["doesn't parse"]
    );
    assert_eq!(
        check_failure("every items whose p is 1 and q is 2 is not empty"),
        vec!["doesn't parse"]
    );
}

#[test]
fn a_field_called_that_is_written_with_a_dot() {
    assert_eq!(
        printed("every items whose .that is \"x\""),
        "every items whose .that is \"x\""
    );
    assert_eq!(printed_check(".that is \"x\""), ".that is \"x\"");
}
