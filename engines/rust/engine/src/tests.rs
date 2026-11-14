use super::*;
use serde_json::json;

#[test]
fn problems_of_names_that_need_quoting_are_listed_in_the_order_the_report_writes_them() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"s": {"from": "xs", "has": {"x\ty": "ys", "x y": "ys", "x\"y": "ys", "x": "ys"}}},
        "requirements": {"r": {"subject": "s", "checks": {"c": "x exists"}}}
    });
    let report = report(&json!({"xs": [{"x": 1}]}), &policy, &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "$well_formed")
        .unwrap();
    let names: Vec<&str> = row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|input| input["name"].as_str())
        .filter(|name| name.starts_with("subjects."))
        .collect();
    assert_eq!(
        names,
        [
            "subjects.s.has.\"x y\"",
            "subjects.s.has.\"x\\\"y\"",
            "subjects.s.has.\"x\\ty\""
        ]
    );
}

#[test]
fn the_fields_of_a_requirement_come_before_the_fields_of_its_subject() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"s": {"from": "xs", "zq": 1}},
        "requirements": {"r": {"subject": "s", "zz": 1, "checks": {"c": "x exists"}}}
    });
    let report = report(&json!({"xs": [{"x": 1}]}), &policy, &json!({}));
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "$well_formed")
        .unwrap();
    let names: Vec<&str> = row["inputs"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|input| input["name"].as_str())
        .collect();
    assert_eq!(names, ["count(checks)", "require", "zz", "subjects.s.zq"]);
}

#[test]
fn report_and_violations_work_from_json_alone() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things"}},
        "requirements": {"s": {"subject": "thing", "require": "most", "checks": {"c": "x exists"}}}
    });
    let report = report(&json!({}), &policy, &Value::Null);
    assert_eq!(report["compliant"], json!(false));
    let violations = violations(&report);
    assert_eq!(violations.as_array().unwrap().len(), 1);
    assert_eq!(violations[0]["check"], json!("$well_formed"));
}

#[test]
fn the_same_policy_gives_the_same_report_whatever_order_it_was_written_in() {
    let a: Value = serde_json::from_str(&r#"{"requirements": {"b": {"subject": "t", "checks": {"y": "x exists", "x": "x exists"}}, "a": {"subject": "t", "checks": {"c": "x exists"}}}, "subjects": {"t": {"from": "t"}, "u": null}, "ergo_spec": "{{spec}}"}"#.replace("{{spec}}", SPEC)).unwrap();
    let b: Value = serde_json::from_str(&r#"{"ergo_spec": "{{spec}}", "subjects": {"u": null, "t": {"from": "t"}}, "requirements": {"a": {"checks": {"c": "x exists"}, "subject": "t"}, "b": {"checks": {"x": "x exists", "y": "x exists"}, "subject": "t"}}}"#.replace("{{spec}}", SPEC)).unwrap();
    let input = json!({"t": []});
    assert_eq!(
        report(&input, &a, &Value::Null).to_string(),
        report(&input, &b, &Value::Null).to_string()
    );
}

#[test]
fn extra_problems_reach_the_report() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"thing": {"from": "things"}},
        "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
    });
    let mut problems = Problems::new();
    policy::add_problem(&mut problems, "checks.c".to_string(), "doesn't parse");
    let extra = BTreeMap::from([("s".to_string(), problems)]);
    let report = report_with(&json!({}), &policy, &Value::Null, &extra);
    assert_eq!(
        report["results"][0]["inputs"][2]["value"],
        json!(["doesn't parse"])
    );
}
fn plain_everywhere(value: &Value, at: &str) {
    match value {
        Value::Number(number) => {
            let text = number.to_string();
            assert!(
                !text.contains(['e', 'E']) && !(text.contains('.') && text.ends_with('0')),
                "{at}: {text}"
            );
            assert!(text != "-0", "{at}: {text}");
        }
        Value::Array(items) => items
            .iter()
            .enumerate()
            .for_each(|(i, item)| plain_everywhere(item, &format!("{at}/{i}"))),
        Value::Object(map) => map
            .iter()
            .for_each(|(k, item)| plain_everywhere(item, &format!("{at}/{k}"))),
        _ => {}
    }
}

#[test]
fn no_number_in_the_report_or_the_violations_keeps_a_written_form() {
    let input: Value = serde_json::from_str(
        r#"{"items": [{"id": 1.0, "x": 1.50, "y": -0.0, "z": 1e2, "w": 2.5e-3, "l": [1.0, 2.50], "n": -0}, {"id": 1, "x": 100.0}]}"#,
    )
    .unwrap();
    let params: Value = serde_json::from_str(r#"{"k": [1.50, 2.0], "m": 1e1}"#).unwrap();
    let policy: Value = serde_json::from_str(
        &r#"{"ergo_spec": "{{spec}}",
            "subjects": {"d": {"from": "items", "identified_by": "id"}},
            "requirements": {"r": {"subject": "d", "min_subjects": 2.0,
                "checks": {"a": "x is 1.50", "b": "y is 0.0", "c": "z is at least 1e2",
                           "e": "x is between 1.0 and 2.50", "g": "count of l is 2.0",
                           "h": "x is in $params.k", "i": "w is $params.m"}}}}"#
            .replace("{{spec}}", SPEC),
    )
    .unwrap();
    let report = report(&input, &policy, &params);
    plain_everywhere(&report, "report");
    plain_everywhere(&violations(&report), "violations");
    assert!(!report["results"].as_array().unwrap().is_empty());
}
