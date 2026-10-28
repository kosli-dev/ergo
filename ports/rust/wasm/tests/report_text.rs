use ergo_wasm::report_text;
use serde_json::Value;

const POLICY: &str = r#"{
  "ergo_spec": "v0.3-dev",
  "subjects": {"item": {"from": "items", "identified_by": "id"}},
  "requirements": {"r": {"subject": "item", "checks": {"exact": "n is 9007199254740993"}}}
}"#;

#[test]
fn a_report_comes_back_as_json_text_from_the_engine() {
    let text = report_text(r#"{"items": [{"id": "a", "n": 1}]}"#, POLICY, "{}").unwrap();
    let report: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(report["engine"]["name"], "ergo-engine");
    assert_eq!(report["compliant"], false);
}

#[test]
fn a_number_a_javascript_number_cannot_hold_is_kept_as_written() {
    let text = report_text(
        r#"{"items": [{"id": "a", "n": 9007199254740993}]}"#,
        POLICY,
        "{}",
    )
    .unwrap();
    assert!(text.contains("9007199254740993"), "{text}");
    let report: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(report["compliant"], true);
}

#[test]
fn input_that_is_not_json_is_named_in_the_message() {
    let message = report_text("{", POLICY, "{}").unwrap_err();
    assert!(
        message.starts_with("the input isn't valid JSON: "),
        "{message}"
    );
}

#[test]
fn a_policy_that_is_not_json_is_named_in_the_message() {
    let message = report_text("{}", "nope", "{}").unwrap_err();
    assert!(
        message.starts_with("the policy isn't valid JSON: "),
        "{message}"
    );
}

#[test]
fn params_that_are_not_json_are_named_in_the_message() {
    let message = report_text("{}", POLICY, "").unwrap_err();
    assert!(
        message.starts_with("the params aren't valid JSON: "),
        "{message}"
    );
}
