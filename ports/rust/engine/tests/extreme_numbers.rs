use serde_json::{Value, json};
use std::panic::catch_unwind;

const CAUSES: [&str; 7] = [
    "satisfied",
    "value",
    "absent",
    "null",
    "unusable",
    "not_an_object",
    "ambiguous",
];

fn extremes() -> Vec<String> {
    vec![
        "1e400".to_string(),
        "-1e400".to_string(),
        "1e-400".to_string(),
        "1e-70000".to_string(),
        "-1e-70000".to_string(),
        "1e1000000000000".to_string(),
        "-1e1000000000000".to_string(),
        "1e-1000000000000".to_string(),
        "-0".to_string(),
        "0e5".to_string(),
        "9".repeat(400),
        format!("1.{}", "0123456789".repeat(1000)),
        format!("1.{}", "0".repeat(70000)),
    ]
}

const SENTENCES: [&str; 33] = [
    "fa is {p}",
    "fa is not {p}",
    "fa equals fb",
    "fa does not equal fb",
    "fa is at least fb",
    "fa is at most {p}",
    "fa is more than {p}",
    "fa is less than fb",
    "fa is between {p} and {p}",
    "fa is {p} within {p}",
    "fa equals fb within fb",
    "fa equals fb within {p}",
    "fa plus fb is fb",
    "fa plus fb is {p}",
    "fa plus {p} is at least fb",
    "sum of items.x is fa",
    "sum of items.x is at least {p}",
    "sum of items.x plus fa is {p}",
    "sum of items.x whose x is {p} is 0",
    "count of items is {p}",
    "count of items is fa",
    "count of items whose x is at most {p} is 1",
    "days elapsed from fa to fb is {p}",
    "days elapsed from fa to fb is at least fa",
    "fa is after fb",
    "fa is before {p}",
    "fa is on or before {p}",
    "every items.x is at least {p}",
    "some items.x is at most fa",
    "every items.x is between {p} and {p}",
    "fa is one of {p}, 1",
    "fa is in $params.list",
    "fa exists",
];

fn policy(sentence: &str) -> Value {
    json!({
        "ergo_spec": "v0.3-dev",
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {
            "plain": sentence,
            "under_for": {"for": "every items as zz", "assert": [sentence.replace("fa", "zz.x")]},
            "one_of": {"any_of": {"a": [sentence], "b": "fb exists"}}
        }}}
    })
}

fn input(n: &str) -> Value {
    let text = format!(
        r#"{{"things": [{{"id": "t", "fa": {n}, "fb": {n}, "items": [{{"x": {n}}}, {{"x": {n}}}]}}]}}"#
    );
    serde_json::from_str(&text).unwrap()
}

fn causes_of(report: &Value, found: &mut Vec<String>) {
    match report {
        Value::Object(map) => {
            for (key, value) in map {
                if key == "cause"
                    && let Some(cause) = value.as_str()
                {
                    found.push(cause.to_string());
                }
                causes_of(value, found);
            }
        }
        Value::Array(list) => list.iter().for_each(|v| causes_of(v, found)),
        _ => {}
    }
}

#[test]
fn no_numeric_operator_panics_or_gives_a_cause_the_spec_lacks_on_extreme_numbers() {
    let mut trials: Vec<(String, String, String)> = Vec::new();
    for sentence in SENTENCES {
        for extreme in extremes() {
            trials.push((sentence.to_string(), "1".to_string(), extreme.clone()));
            trials.push((sentence.to_string(), extreme, "1.5".to_string()));
        }
    }
    let mut failures = Vec::new();
    for (sentence, written, held) in trials {
        let text = sentence.replace("{p}", &written);
        let policy = policy(&text);
        let input = input(&held);
        let params = json!({"list": [1, 2]});
        let shown: String = text.chars().take(60).collect();
        match catch_unwind(|| ergo_engine::report(&input, &policy, &params)) {
            Err(_) => failures.push(format!("panic: {shown} with {}", held.len())),
            Ok(report) => {
                let mut causes = Vec::new();
                causes_of(&report, &mut causes);
                for cause in causes {
                    if !CAUSES.contains(&cause.as_str()) {
                        failures.push(format!("cause {cause}: {shown}"));
                    }
                }
                if report["requirements"]["r"]["status"].as_str().is_none() {
                    failures.push(format!("no status: {shown}"));
                }
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

fn cause_of(sentence: &str, things: &str) -> String {
    let policy = json!({
        "ergo_spec": "v0.3-dev",
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": sentence}}}
    });
    let input: Value = serde_json::from_str(&format!(r#"{{"things": [{things}]}}"#)).unwrap();
    let report = ergo_engine::report(&input, &policy, &json!({}));
    let results = report["results"].as_array().unwrap();
    let row = results
        .iter()
        .find(|r| r["check"] == "c")
        .unwrap_or_else(|| panic!("{report}"));
    row["cause"].as_str().unwrap().to_string()
}

#[test]
fn exponents_of_31_digits_that_differ_in_the_last_digit_are_compared_exactly() {
    let things = r#"{"id": "t", "fa": 1e1000000000000000000000000000000, "fb": 1e1000000000000000000000000000001}"#;
    assert_eq!(cause_of("fa is at least fb", things), "value");
    assert_eq!(cause_of("fa is fb", things), "value");
    assert_eq!(cause_of("fa is not fb", things), "satisfied");
}

#[test]
fn a_number_whose_exponent_has_more_than_36_digits_fails_every_comparison_as_unusable() {
    let big = format!("1e1{}", "0".repeat(36));
    let bigger = format!("1e1{}1", "0".repeat(35));
    let things = format!(r#"{{"id": "t", "fa": {big}, "fb": {bigger}, "fl": [{big}]}}"#);
    for sentence in [
        "fa is at least fb",
        "fa is less than fb",
        "fa is fb",
        "fa is not fb",
        "fa equals fb",
        "fa does not equal fb",
        "fa is 1",
        "fa is not one of 1, 2",
        "fl contains fb",
        "fl does not contain fb",
        "fl does not contain 1",
    ] {
        assert_eq!(cause_of(sentence, &things), "unusable", "{sentence}");
    }
}

#[test]
fn ids_that_cannot_be_read_count_as_repeated_so_unique_ids_fails() {
    let big = format!("1e1{}", "0".repeat(36));
    let bigger = format!("1e1{}1", "0".repeat(35));
    let things = format!(r#"{{"id": {big}, "fa": 1}}, {{"id": {bigger}, "fa": 1}}"#);
    let policy = json!({
        "ergo_spec": "v0.3-dev",
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": "fa is 1"}}}
    });
    let input: Value = serde_json::from_str(&format!(r#"{{"things": [{things}]}}"#)).unwrap();
    let report = ergo_engine::report(&input, &policy, &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["check"] == "$unique_ids")
        .unwrap_or_else(|| panic!("{report}"));
    assert_eq!(row["passed"], false, "{report}");
}
