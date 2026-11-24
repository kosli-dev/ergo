use ergo_policy_engine::SPEC;
use serde_json::{Value, json};

fn rows(checks: Value, input: Value, params: Value) -> Vec<(String, String, String)> {
    let report = ergo_policy_engine::report(
        &input,
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"c": {"from": "cs", "identified_by": "id", "has": {"pos": "os"}}},
            "requirements": {"r": {"subject": "c", "checks": checks}}
        }),
        &params,
    );
    let mut found: Vec<(String, String, String)> = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| !row["check"].as_str().unwrap().starts_with('$'))
        .map(|row| {
            (
                row["check"].as_str().unwrap().to_string(),
                row["cause"].as_str().unwrap().to_string(),
                row["message"].as_str().unwrap_or("").to_string(),
            )
        })
        .collect();
    found.sort();
    found
}

fn row(check: &str, cause: &str, message: &str) -> (String, String, String) {
    (check.to_string(), cause.to_string(), message.to_string())
}

#[test]
fn a_walk_in_a_for_line_sentence_fails_as_value_when_the_list_on_its_right_is_empty() {
    let checks = json!({
        "every": {"for": "every ms as m", "assert": "every rows.v, if any, is in $params.os.name"},
        "some": {"for": "some ms as m", "assert": "every rows.v, if any, is in pos.name"},
        "beside": {"for": "every rows, if any, as r", "assert": ["r.v exists", "every zs.v, if any, is in pos.name"]},
        "item": {"for": "every ms as m", "assert": "every m.ys.v, if any, is in pos.name"},
        "input": {"for": "every ms as m", "assert": "every m.ys.v, if any, is in $input.os.name"}
    });
    let input =
        json!({"os": [], "cs": [{"id": "c", "rows": [], "zs": [], "ms": [{"ys": []}], "os": []}]});
    assert_eq!(
        rows(checks, input, json!({"os": []})),
        vec![
            row("beside", "value", "pos is []"),
            row("every", "value", "$params.os is []"),
            row("input", "value", "$input.os is []"),
            row("item", "value", "pos is []"),
            row("some", "value", "pos is []"),
        ]
    );
}

#[test]
fn a_for_line_on_an_empty_list_fails_as_value_when_a_list_its_sentence_walks_on_the_right_is_empty()
{
    let checks = json!({
        "in": {"for": "every rows, if any, as r", "assert": "r.v is in pos.name"},
        "params": {"for": "every rows, if any, as r", "assert": "r.v is in $params.os.name"},
        "all": {"for": "every rows, if any, as r", "assert": "r.tags contains all of pos.name"},
        "not_in": {"for": "every rows, if any, as r", "assert": "r.v is not one of pos.name"},
        "two": {"for": "every ms as m, every rows, if any, as r", "assert": "r.v is in pos.name"},
        "walk": {"for": "every rows, if any, as r", "assert": "every r.ys.v, if any, is in pos.name"}
    });
    let input = json!({"cs": [{"id": "c", "rows": [], "ms": [{}], "os": []}]});
    assert_eq!(
        rows(checks, input, json!({"os": []})),
        vec![
            row("all", "value", "pos is []"),
            row("in", "value", "pos is []"),
            row("not_in", "value", "pos is []"),
            row("params", "value", "$params.os is []"),
            row("two", "value", "pos is []"),
            row("walk", "value", "pos is []"),
        ]
    );
    let dot = json!({"dot": {"for": "every rows, if any, as p", "assert": "p.v is in .p.name"}});
    let input = json!({"cs": [{"id": "c", "rows": [], "p": [{"name": []}]}]});
    assert_eq!(
        rows(dot, input, json!({})),
        vec![row("dot", "value", "item 1 of .p: name is []")]
    );
}

#[test]
fn a_for_line_on_an_empty_list_passes_when_the_list_its_sentence_walks_on_the_right_holds_names() {
    let checks = json!({
        "in": {"for": "every rows, if any, as r", "assert": "r.v is in pos.name"},
        "walk": {"for": "every ms as m", "assert": "every m.ys.v, if any, is in pos.name"}
    });
    let input = json!({"cs": [{"id": "c", "rows": [], "ms": [{"ys": []}], "os": [{"name": "a"}]}]});
    assert_eq!(
        rows(checks, input, json!({})),
        vec![row("in", "satisfied", ""), row("walk", "satisfied", "")]
    );
}
