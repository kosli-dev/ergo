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

fn permutations(items: &[String]) -> Vec<Vec<String>> {
    if items.len() <= 1 {
        return vec![items.to_vec()];
    }
    let mut all = Vec::new();
    for i in 0..items.len() {
        let mut rest = items.to_vec();
        let first = rest.remove(i);
        for mut tail in permutations(&rest) {
            tail.insert(0, first.clone());
            all.push(tail);
        }
    }
    all
}

fn unique_ids_row(ids: &[String]) -> Value {
    let things: Vec<String> = ids
        .iter()
        .map(|id| format!(r#"{{"id": {id}, "fa": 1}}"#))
        .collect();
    let policy = json!({
        "ergo_spec": "v0.3-dev",
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": "fa is 1"}}}
    });
    let input: Value =
        serde_json::from_str(&format!(r#"{{"things": [{}]}}"#, things.join(", "))).unwrap();
    let report = ergo_engine::report(&input, &policy, &json!({}));
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["check"] == "$unique_ids")
        .unwrap_or_else(|| panic!("{report}"))
        .clone()
}

fn repeated_ids_named(row: &Value) -> Vec<String> {
    row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|i| {
            i["name"]
                .as_str()
                .is_some_and(|n| n.starts_with("repeated"))
        })
        .unwrap_or_else(|| panic!("{row}"))["value"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.to_string())
        .collect()
}

#[test]
fn ids_that_cannot_be_read_are_named_as_repeated_in_the_same_order_whatever_the_input_order() {
    let big = format!("1e1{}", "0".repeat(36));
    let bigger = format!("1e1{}1", "0".repeat(35));
    let ids: Vec<String> = ["2", "10", &big, "3", &bigger, "3", &big]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let mut seen = std::collections::BTreeSet::new();
    for order in permutations(&ids) {
        let row = unique_ids_row(&order);
        assert_eq!(row["passed"], false, "{row}");
        seen.insert(repeated_ids_named(&row));
    }
    assert_eq!(seen.len(), 1, "{seen:?}");
    let named = seen.into_iter().next().unwrap();
    assert_eq!(named.len(), 3, "{named:?}");
    assert!(named.contains(&"3".to_string()), "{named:?}");
    assert!(
        !named.contains(&"2".to_string()) && !named.contains(&"10".to_string()),
        "{named:?}"
    );
}

#[test]
fn one_id_that_cannot_be_read_fails_unique_ids_and_names_only_itself() {
    let big = format!("1e1{}", "0".repeat(36));
    let ids: Vec<String> = ["5", "20", &big, "100", "7", "\"x\"", "-3"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    for order in permutations(&ids).into_iter().step_by(97) {
        let row = unique_ids_row(&order);
        assert_eq!(row["passed"], false, "{row}");
        let named = repeated_ids_named(&row);
        assert_eq!(named.len(), 1, "{named:?}");
        assert!(named[0].contains("e"), "{named:?}");
    }
}

#[test]
fn within_fails_as_unusable_when_it_cannot_work_the_gap_out_exactly() {
    let tiny = r#"{"id": "t", "fa": 1e-1000000000000000000000000000000, "fb": 0}"#;
    assert_eq!(cause_of("fa equals fb within 0", tiny), "unusable");
    assert_eq!(cause_of("fa is 0 within 0", tiny), "unusable");
    let spread = r#"{"id": "t", "fa": 1e-5000, "fb": 0}"#;
    assert_eq!(cause_of("fa equals fb within 0", spread), "unusable");
    let big = format!("1e1{}", "0".repeat(36));
    let unreadable = format!(r#"{{"id": "t", "fa": {big}, "fb": {big}}}"#);
    assert_eq!(cause_of("fa equals fb within 1", &unreadable), "unusable");
    let near = r#"{"id": "t", "fa": 1e-300, "fb": 0}"#;
    assert_eq!(cause_of("fa equals fb within 0", near), "value");
    assert_eq!(cause_of("fa equals fb within 1e-300", near), "satisfied");
}

#[test]
fn within_absorbs_the_float_noise_of_numbers_past_fifteen_digits() {
    for (fa, fb) in [
        ("0.30000000000000004", "0.3"),
        ("12.340000000000002", "12.34"),
        ("1761700000.123456", "1761700000.12"),
    ] {
        let item = format!(r#"{{"id": "t", "fa": {fa}, "fb": {fb}}}"#);
        assert_eq!(
            cause_of("fa equals fb within 0.01", &item),
            "satisfied",
            "{fa}"
        );
    }
    let big = r#"{"id": "t", "fa": 1e9, "fb": 1e9}"#;
    assert_eq!(cause_of("fa equals fb within 0.000001", big), "satisfied");
}

#[test]
fn within_does_not_overflow_on_exponents_at_both_ends_of_what_it_reads() {
    let ends = r#"{"id": "t", "fa": 1e9000000000000000000, "fb": 1e-9000000000000000000}"#;
    assert_eq!(cause_of("fa equals fb within 1", ends), "unusable");
}

fn one_item_policy() -> Value {
    json!({
        "ergo_spec": "v0.3-dev",
        "subjects": {"item": {"from": "items"}},
        "requirements": {"r": {"subject": "item", "checks": {"c": "size is at least 5"}}}
    })
}

#[test]
fn one_subject_whose_id_cannot_be_read_passes_unique_ids() {
    let big = format!("1e1{}", "0".repeat(36));
    let input: Value =
        serde_json::from_str(&format!(r#"{{"items": [{{"size": {big}}}]}}"#)).unwrap();
    let report = ergo_engine::report(&input, &one_item_policy(), &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["check"] == "$unique_ids")
        .unwrap_or_else(|| panic!("{report}"));
    assert_eq!(row["passed"], true, "{row}");
    assert_eq!(row["cause"], "satisfied", "{row}");
}

#[test]
fn two_subjects_with_the_same_id_that_cannot_be_read_still_fail_unique_ids() {
    let big = format!("1e1{}", "0".repeat(36));
    let row = unique_ids_row(&[big.clone(), big]);
    assert_eq!(row["passed"], false, "{row}");
}

#[test]
fn a_number_that_cannot_be_read_keeps_its_digits_in_the_report_text() {
    let big = format!("1e1{}", "0".repeat(36));
    let input: Value =
        serde_json::from_str(&format!(r#"{{"items": [{{"size": {big}}}]}}"#)).unwrap();
    let text = ergo_engine::report(&input, &one_item_policy(), &json!({})).to_string();
    assert!(!text.contains(r#""size":null"#), "{text}");
    assert!(
        text.contains(&format!(r#""size":1e+1{}"#, "0".repeat(36))),
        "{text}"
    );
}

#[test]
fn within_reads_a_zero_and_trailing_zeros_as_the_number_written() {
    let zeros = "0".repeat(5000);
    let zero = r#"{"id": "t", "fa": 0e-5000, "fb": 0}"#;
    assert_eq!(cause_of("fa equals fb within 1", zero), "satisfied");
    let one = format!(r#"{{"id": "t", "fa": 1.{zeros}, "fb": 1}}"#);
    assert_eq!(cause_of("fa equals fb within 1", &one), "satisfied");
    let same = r#"{"id": "t", "fa": 1, "fb": 1}"#;
    assert_eq!(
        cause_of(&format!("fa equals fb within 0.{zeros}"), same),
        "satisfied"
    );
}

#[test]
fn a_zero_whose_exponent_has_more_than_36_digits_is_zero() {
    let big = format!("1{}", "0".repeat(36));
    for zero in [
        format!("0e{big}"),
        format!("-0.0e-{big}"),
        format!("0E+{big}"),
    ] {
        let things = format!(r#"{{"id": "t", "fa": {zero}, "fb": 0}}"#);
        assert_eq!(cause_of("fa is 0", &things), "satisfied", "{zero}");
        assert_eq!(
            cause_of("fa is at least fb", &things),
            "satisfied",
            "{zero}"
        );
        assert_eq!(
            cause_of("fa is less than 1", &things),
            "satisfied",
            "{zero}"
        );
    }
}

#[test]
fn a_match_on_a_readable_item_decides_a_list_check_that_holds_a_number_it_cannot_read() {
    let big = format!("1e1{}", "0".repeat(36));
    let things = format!(
        r#"{{"id": "t", "fl": [{big}, 1], "fa": 1, "fz": 3, "ones": [1], "both": [1, 3]}}"#
    );
    for (sentence, cause) in [
        ("fl contains 1", "satisfied"),
        ("fl contains fa", "satisfied"),
        ("fl does not contain 1", "value"),
        ("fa is in fl", "satisfied"),
        ("fa is one of fl", "satisfied"),
        ("fa is not in fl", "value"),
        ("fa is not one of fl", "value"),
        ("fl contains all of ones", "satisfied"),
        ("fl contains none of ones", "value"),
        ("fl contains none of both", "value"),
        ("fl contains fz", "unusable"),
        ("fl does not contain fz", "unusable"),
        ("fz is in fl", "unusable"),
        ("fz is one of fl", "unusable"),
        ("fz is not in fl", "unusable"),
        ("fz is not one of fl", "unusable"),
        ("fl contains all of both", "unusable"),
    ] {
        assert_eq!(cause_of(sentence, &things), cause, "{sentence}");
    }
}
