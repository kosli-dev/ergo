use ergo_policy_cli::outcome::{self, Item};
use serde_json::{Value, json};

fn row(check: &str, id: Value, passed: bool, message: Option<&str>) -> Value {
    let mut row = json!({
        "requirement": "approved",
        "subject": {"type": "pull request", "id": id},
        "check": check,
        "passed": passed,
        "cause": if passed { "satisfied" } else { "value" },
    });
    if let Some(message) = message {
        row["message"] = json!(message);
    }
    row
}

#[test]
fn a_plain_word_id_is_written_bare_and_anything_else_as_json() {
    let cases = [
        (json!("d1"), "d1"),
        (json!(7), "7"),
        (json!("7"), "\"7\""),
        (json!("true"), "\"true\""),
        (json!("null"), "\"null\""),
        (json!("1e3"), "\"1e3\""),
        (json!("web app"), "\"web app\""),
        (json!("\"q"), "\"\\\"q\""),
        (json!(""), "\"\""),
        (json!(true), "true"),
        (json!(null), "null"),
        (serde_json::from_str("1.50").unwrap(), "1.50"),
    ];
    for (id, text) in cases {
        assert_eq!(outcome::id_text(&id).as_deref(), Some(text), "{id}");
        assert_eq!(outcome::read_id(&format!("{text} rest")), Some((id, " rest")));
    }
}

#[test]
fn an_id_that_is_an_object_or_a_list_has_no_text_yet() {
    assert_eq!(outcome::id_text(&json!({"a": 1})), None);
    assert_eq!(outcome::id_text(&json!([1])), None);
}

#[test]
fn a_row_of_a_check_is_a_passes_or_fails_line() {
    assert_eq!(
        outcome::row_line(&row("peer_approved", json!(7), true, None)),
        Ok(Some("pull request 7 passes peer_approved".to_string()))
    );
    assert_eq!(
        outcome::row_line(&row("peer_approved", json!("a b"), false, Some("x is 1"))),
        Ok(Some(
            "pull request \"a b\" fails peer_approved because x is 1".to_string()
        ))
    );
}

#[test]
fn a_passed_row_of_a_check_ergo_adds_is_not_a_line() {
    assert_eq!(
        outcome::row_line(&row("$applies", json!(7), true, None)),
        Ok(None)
    );
    assert_eq!(
        outcome::row_line(&row("$min_subjects", json!(null), true, None)),
        Ok(None)
    );
}

#[test]
fn a_row_the_outcome_form_cannot_show_yet_is_an_error() {
    let mut child = row("c", json!("web"), true, None);
    child["subject"]["in"] = json!({"type": "deployment", "id": "d1"});
    let shown = [
        child,
        row("$applies", json!("d3"), false, Some("env is \"dev\"")),
        row("$min_subjects", json!(null), false, Some("count is 0")),
        row("c", json!({"a": 1}), true, None),
    ];
    for row in shown {
        assert!(outcome::row_line(&row).is_err(), "{row}");
    }
}

#[test]
fn yaml_quotes_only_the_lines_yaml_would_read_otherwise() {
    let items = vec![
        Item::Line("not compliant".to_string()),
        Item::Line("released is met".to_string()),
        Item::Group(
            "approved is not met".to_string(),
            vec![
                "deployment d1 fails a because item 2 of xs: status is \"failed\"".to_string(),
                "deployment d2 fails a because x is 'q' #1".to_string(),
                "deployment d3 fails a because x is \"a\tb\"".to_string(),
                "deployment d4 passes a".to_string(),
            ],
        ),
    ];
    let text = outcome::yaml(&items);
    assert_eq!(
        text,
        "- not compliant\n- released is met\n- approved is not met:\n    - 'deployment d1 fails a because item 2 of xs: status is \"failed\"'\n    - 'deployment d2 fails a because x is ''q'' #1'\n    - \"deployment d3 fails a because x is \\\"a\\tb\\\"\"\n    - deployment d4 passes a\n"
    );
    let read = ergo_policy_cli::yaml::parse(&text).unwrap();
    assert_eq!(read, outcome::to_json(&items));
}

#[test]
fn yaml_quotes_a_heading_that_yaml_would_read_otherwise() {
    let items = vec![Item::Group(
        "a: b is met".to_string(),
        vec!["t 1 passes c".to_string()],
    )];
    let text = outcome::yaml(&items);
    assert_eq!(text, "- 'a: b is met':\n    - t 1 passes c\n");
    assert_eq!(
        ergo_policy_cli::yaml::parse(&text).unwrap(),
        json!([{"a: b is met": ["t 1 passes c"]}])
    );
}
