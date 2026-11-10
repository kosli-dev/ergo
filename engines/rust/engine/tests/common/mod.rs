use serde_json::json;

pub fn fill_spec(text: &str) -> String {
    let report = ergo_policy_engine::report(&json!({}), &json!({}), &json!({}));
    let spec = report["ergo"].as_str().expect("a report names its spec");
    text.replace("{{spec}}", spec)
}

#[test]
fn the_placeholder_is_filled_with_the_spec_of_the_engine() {
    let filled = fill_spec(r#"{"a": "{{spec}}", "b": "expected {{spec}}.", "c": "v0.5"}"#);
    assert!(!filled.contains("{{spec}}"));
    assert!(filled.contains("\"c\": \"v0.5\""));
    let policy = fill_spec(r#"{"ergo_spec": "{{spec}}", "requirements": {}}"#);
    let policy: serde_json::Value = serde_json::from_str(&policy).unwrap();
    let report = ergo_policy_engine::report(&json!({}), &policy, &json!({}));
    assert_eq!(report["ergo"], policy["ergo_spec"]);
}

#[test]
fn a_policy_that_writes_another_version_is_still_rejected() {
    let report = ergo_policy_engine::report(
        &json!({}),
        &json!({"ergo_spec": "v0.5", "requirements": {}}),
        &json!({}),
    );
    assert_eq!(report["compliant"], json!(false));
}
