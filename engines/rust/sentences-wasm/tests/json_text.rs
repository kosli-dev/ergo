use ergo_policy_sentences_wasm::*;
use serde_json::Value;

fn json(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

fn tree_of(text: &str) -> String {
    json(text)["tree"].to_string()
}

#[test]
fn a_check_sentence_gives_a_tree() {
    let answer = json(&parse_check_text("approvals is at least 2"));
    assert!(answer["tree"].is_object());
    assert!(answer.get("errors").is_none());
}

#[test]
fn a_for_line_gives_a_tree() {
    assert!(json(&parse_for_text("every xs as x"))["tree"].is_object());
}

#[test]
fn a_from_line_gives_a_tree() {
    assert!(json(&parse_from_text("every items whose x is 1"))["tree"].is_object());
}

#[test]
fn a_path_gives_a_tree() {
    assert!(json(&parse_path_text("x.y[1]")).get("tree").is_some());
}

#[test]
fn a_syntax_error_gives_its_message_and_column() {
    let answer = json(&parse_check_text("x is \"a"));
    assert!(answer.get("tree").is_none());
    assert_eq!(answer["errors"][0]["message"], "unclosed quote at column 6");
    assert_eq!(answer["errors"][0]["column"], 6);
}

#[test]
fn an_error_without_a_column_gives_null() {
    let answer = json(&parse_for_text("every xs"));
    let error = &answer["errors"][0];
    assert!(error["message"].is_string());
    assert!(error["column"].is_null());
}

#[test]
fn a_problem_comes_back_for_a_tree_that_reads_but_is_written_wrong() {
    let tree = tree_of(&parse_check_text("x is not null"));
    let answer = json(&check_problems_text(&tree, "[]").unwrap());
    assert_eq!(
        answer["problems"],
        serde_json::json!([r#""is not null" is written "exists""#])
    );
}

#[test]
fn a_tree_with_nothing_wrong_has_no_problems() {
    let tree = tree_of(&parse_check_text("x is 1"));
    let answer = json(&check_problems_text(&tree, "[]").unwrap());
    assert_eq!(answer["problems"], serde_json::json!([]));
}

#[test]
fn a_for_and_a_from_line_list_their_problems() {
    let for_tree = tree_of(&parse_for_text("every xs as x"));
    assert!(json(&for_problems_text(&for_tree, "[]").unwrap())["problems"].is_array());
    let from_tree = tree_of(&parse_from_text("every items whose x is 1"));
    assert!(json(&from_problems_text(&from_tree).unwrap())["problems"].is_array());
}

#[test]
fn a_check_prints_back_as_the_sentence_that_was_read() {
    let tree = tree_of(&parse_check_text("approvals is at least 2"));
    assert_eq!(
        print_check_text(&tree, "[]").unwrap(),
        "approvals is at least 2"
    );
}

#[test]
fn a_for_line_and_a_from_line_print_back() {
    let for_tree = tree_of(&parse_for_text("every xs as x"));
    assert_eq!(print_for_text(&for_tree, "[]").unwrap(), "every xs as x");
    let from_tree = tree_of(&parse_from_text("every items whose x is 1"));
    assert_eq!(
        print_from_text(&from_tree, "[]", "[]").unwrap(),
        "every items whose x is 1"
    );
}

#[test]
fn a_tree_that_is_not_json_is_refused_by_name() {
    for result in [
        check_problems_text("{", "[]"),
        for_problems_text("{", "[]"),
        from_problems_text("{"),
        print_check_text("{", "[]"),
        print_for_text("{", "[]"),
        print_from_text("{", "[]", "[]"),
    ] {
        assert!(
            result
                .unwrap_err()
                .starts_with("the tree isn't valid JSON: ")
        );
    }
}

#[test]
fn a_json_value_that_is_not_a_tree_is_refused() {
    assert!(check_problems_text("42", "[]").is_err());
}

#[test]
fn names_that_are_not_a_json_list_of_strings_are_refused() {
    let tree = tree_of(&parse_check_text("x is 1"));
    for names in ["{", "{}", "[1]"] {
        assert!(
            print_check_text(&tree, names)
                .unwrap_err()
                .starts_with("the names aren't valid JSON: ")
        );
    }
    let from_tree = tree_of(&parse_from_text("every items whose x is 1"));
    assert!(
        print_from_text(&from_tree, "[]", "{")
            .unwrap_err()
            .starts_with("the parents aren't valid JSON: ")
    );
}
