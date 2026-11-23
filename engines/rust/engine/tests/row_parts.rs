use ergo_policy_engine::SPEC;
use serde_json::{Value, json};

fn row(check: Value, thing: Value, params: Value) -> Value {
    let report = ergo_policy_engine::report(
        &json!({"things": [thing]}),
        &json!({
            "ergo_spec": SPEC,
            "subjects": {"t": {"from": "things", "identified_by": "id"}},
            "requirements": {"r": {"subject": "t", "checks": {"c": check}}}
        }),
        &params,
    );
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone()
}

fn kinds(row: &Value) -> Vec<(String, String, String)> {
    row["failures"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| {
            (
                entry["kind"].as_str().unwrap().to_string(),
                entry["name"].as_str().unwrap().to_string(),
                entry["message"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

fn entry(kind: &str, name: &str, message: &str) -> (String, String, String) {
    (kind.to_string(), name.to_string(), message.to_string())
}

#[test]
fn a_for_line_key_that_cant_be_read_sits_on_the_row_with_no_assertion_entry() {
    let check = json!({"for": "every o named by $params.k as x", "assert": ["x is 1", "x is 2"]});
    let got = row(check, json!({"id": "t", "o": {"a": [1]}}), json!({}));
    assert_eq!(got["message"], "$params.k is missing");
    assert_eq!(got["cause"], "absent");
    assert!(kinds(&got).is_empty());
    let key = got["inputs"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(key["name"], "$params.k");
    assert_eq!(key["outcome"], "absent");
}

#[test]
fn a_for_line_key_that_cant_be_read_is_said_before_a_list_that_fails_whatever_the_key() {
    let check = json!({"for": "every o named by $params.k as x", "assert": ["x is 1", "z is 3"]});
    for (o, said, cause) in [
        (Value::Null, "o is null", "absent"),
        (
            json!("s"),
            "o is \"s\", which isn't a list or an object",
            "unusable",
        ),
        (json!([]), "o is []", "absent"),
    ] {
        let got = row(check.clone(), json!({"id": "t", "z": 2, "o": o}), json!({}));
        assert_eq!(
            got["message"],
            format!("z is 2; $params.k is missing; {said}")
        );
        assert_eq!(got["cause"], cause);
        assert_eq!(
            kinds(&got),
            vec![
                entry("assertion", "z is 3", "z is 2"),
                entry("list", "o", said)
            ]
        );
    }
}

#[test]
fn a_whose_key_that_is_missing_is_said_once_and_each_item_says_the_value_before_it() {
    let check =
        json!({"for": "every xs whose v is m named by $params.k as x", "assert": "x.v is 1"});
    let got = row(check, json!({"id": "t", "xs": [{"v": 1}]}), json!({}));
    assert_eq!(
        got["message"],
        "$params.k is missing; item 1 of xs: m is missing"
    );
    assert_eq!(
        kinds(&got),
        vec![entry("item", "item 1 of xs", "m is missing")]
    );
    assert!(
        got["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .any(|input| input["name"] == "$params.k" && input["outcome"] == "absent")
    );
}

#[test]
fn a_clause_an_earlier_sentence_gave_is_said_once_in_the_row_and_kept_in_each_entry() {
    let got = row(
        json!({"assert": ["expires_at exists", "expires_at is after as_of"]}),
        json!({"id": "t"}),
        json!({}),
    );
    assert_eq!(got["message"], "expires_at is missing; as_of is missing");
    assert_eq!(
        kinds(&got),
        vec![
            entry("assertion", "expires_at exists", "expires_at is missing"),
            entry(
                "assertion",
                "expires_at is after as_of",
                "expires_at is missing, and as_of is missing"
            )
        ]
    );
}

#[test]
fn a_one_line_walk_says_the_value_before_a_missing_key_as_a_list_entry() {
    let got = row(
        json!("every o named by $params.k is 1"),
        json!({"id": "t"}),
        json!({}),
    );
    assert_eq!(got["message"], "$params.k is missing; o is missing");
    let assertion = &got["failures"][0];
    assert_eq!(assertion["message"], "$params.k is missing");
    assert_eq!(assertion["failures"][0]["kind"], "list");
    assert_eq!(assertion["failures"][0]["message"], "o is missing");
}

#[test]
fn a_walk_in_an_any_of_option_lists_the_params_it_reads_on_its_assertion() {
    let check = json!({"any_of": {
        "declared": "some ids.v is in $params.allowed",
        "other": "id is \"x\""
    }});
    let params = json!({"allowed": ["a", "b"]});
    let got = row(check, json!({"id": "t", "ids": [{"v": "c"}]}), params);
    let assertion = &got["failures"][0]["failures"][0];
    assert_eq!(assertion["kind"], "assertion");
    assert_eq!(
        assertion["inputs"],
        json!([
            {"locations": ["$params:/allowed"], "name": "$params.allowed", "outcome": "usable", "value": ["a", "b"]}
        ])
    );
    assert_eq!(assertion["failures"][0]["name"], "item 1 of ids");
    assert_eq!(assertion["failures"][0]["inputs"][0]["name"], "ids[0].v");
}

fn tree(entries: &Value) -> Vec<String> {
    let mut out = Vec::new();
    for entry in entries.as_array().into_iter().flatten() {
        out.push(format!(
            "{} {}: {}",
            entry["kind"].as_str().unwrap(),
            entry["name"].as_str().unwrap(),
            entry["message"].as_str().unwrap()
        ));
        out.extend(
            tree(&entry["failures"])
                .into_iter()
                .map(|e| format!("  {e}")),
        );
    }
    out
}

fn rows_of(policy: Value, input: Value) -> Vec<Value> {
    let mut policy = policy;
    policy["ergo_spec"] = json!(SPEC);
    ergo_policy_engine::report(&input, &policy, &Value::Null)["results"]
        .as_array()
        .unwrap()
        .clone()
}

fn tree_of(rows: &[Value], check: &str) -> Vec<String> {
    tree(&rows.iter().find(|row| row["check"] == check).unwrap()["failures"])
}

#[test]
fn a_for_lines_whose_root_with_more_than_three_problems_is_said_once_capped_and_no_item_says_it() {
    let pos = rows_of(
        json!({
            "subjects": {"c": {"from": "every cs", "has": {"pos": "os"}}},
            "requirements": {"r": {"subject": "c", "checks": {
                "whose": {"for": "every rows whose v is in pos.name as r", "assert": "r.v is \"bob\""}
            }}}
        }),
        json!({"cs": [{"id": "c1", "os": [{"name": "bob", "k": 1}, {"v": 0}, {"v": 1}, {"v": 2}, {"v": 3}, {"v": 4}], "rows": [{"v": "bob"}, {}, {}]}]}),
    );
    assert_eq!(
        tree_of(&pos, "whose"),
        [
            "list rows: item 2 of pos: name is missing; item 3 of pos: name is missing; item 4 of pos: name is missing; and 2 more",
            "item item 2 of rows: v is missing",
            "item item 3 of rows: v is missing"
        ]
    );
    let counted = rows_of(
        json!({
            "subjects": {"t": {"from": "every teams", "has": {"pl": "c"}}},
            "requirements": {"r": {"subject": "t", "checks": {
                "own": {"for": "every rows whose n is count of pl.k, if any, as r", "assert": "r.n is at least 0"},
                "second": {"for": "every ms as m, every m.ws whose n is count of pl.k, if any, as w", "assert": "w.n is at least 0"}
            }}}
        }),
        json!({"teams": [[
            {"c": [1, 2], "rows": [{"n": 2}, {"n": 3}], "ms": [{"ws": [{"n": 2}, {"n": 3}]}]},
            {"c": [1, 2], "rows": [{"n": 2}, {"n": 3}], "ms": [{"ws": [{"n": 2}, {"n": 3}]}]}
        ]]}),
    );
    let capped = "item 1 of t: item 1 of c is 1, which isn't an object; item 1 of t: item 2 of c is 2, which isn't an object; item 2 of t: item 1 of c is 1, which isn't an object; and 1 more";
    assert_eq!(tree_of(&counted, "own"), [format!("list t.rows: {capped}")]);
    assert_eq!(
        tree_of(&counted, "second")[0],
        format!("list t.ms: {capped}")
    );
}

fn spec_groups() -> Vec<(String, Value)> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../spec/cases");
    let mut topics: Vec<_> = std::fs::read_dir(&root)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    topics.sort();
    let mut out = Vec::new();
    for topic in topics {
        let file = topic.join("cases.json");
        let Ok(text) = std::fs::read_to_string(&file) else {
            continue;
        };
        let name = topic.file_name().unwrap().to_string_lossy().to_string();
        let groups: Value = serde_json::from_str(&text.replace("{{spec}}", SPEC)).unwrap();
        for group in groups.as_array().unwrap() {
            out.push((name.clone(), group.clone()));
        }
    }
    out
}

fn fails(rows: &Value, row: &Value) -> bool {
    rows.as_array().into_iter().flatten().any(|other| {
        other["requirement"] == row["requirement"]
            && other["check"] == row["check"]
            && other["subject"] == row["subject"]
            && other["passed"] == false
    })
}

fn assertion_of(rows: &Value, row: &Value, sentence: &str) -> Option<Value> {
    let same = rows.as_array()?.iter().find(|other| {
        other["requirement"] == row["requirement"]
            && other["check"] == row["check"]
            && other["subject"] == row["subject"]
    })?;
    let mut entry = same["failures"]
        .as_array()?
        .iter()
        .find(|entry| entry["kind"] == "assertion" && entry["name"] == sentence)?
        .clone();
    entry.as_object_mut()?.remove("locations");
    Some(entry)
}

#[test]
fn a_sentence_has_the_same_assertion_entry_as_alone_in_its_check() {
    let mut differ: Vec<String> = Vec::new();
    for (topic, group) in spec_groups() {
        let params = group.get("params").cloned().unwrap_or(json!({}));
        let policy = &group["policy"];
        let Some(requirements) = policy["requirements"].as_object() else {
            continue;
        };
        for (requirement, body) in requirements {
            let Some(checks) = body["checks"].as_object() else {
                continue;
            };
            for (check, written) in checks {
                let Some(sentences) = written["assert"].as_array() else {
                    continue;
                };
                if written.get("for").is_none() || sentences.len() < 2 {
                    continue;
                }
                for case in group["cases"].as_array().unwrap() {
                    let full = ergo_policy_engine::report(&case["input"], policy, &params);
                    let rows = &full["results"];
                    for (at, sentence) in sentences.iter().enumerate() {
                        let Some(text) = sentence.as_str() else {
                            continue;
                        };
                        if sentences.iter().filter(|s| *s == sentence).count() > 1 {
                            continue;
                        }
                        let mut alone = policy.clone();
                        alone["requirements"][requirement]["checks"][check]["assert"] = json!(text);
                        let by_itself = ergo_policy_engine::report(&case["input"], &alone, &params);
                        for row in rows.as_array().into_iter().flatten().filter(|row| {
                            row["requirement"] == requirement.as_str()
                                && row["check"] == check.as_str()
                        }) {
                            if !fails(&by_itself["results"], row) {
                                continue;
                            }
                            let beside = assertion_of(rows, row, text);
                            let own = assertion_of(&by_itself["results"], row, text);
                            if beside != own {
                                differ.push(format!(
                                    "{topic} / {} / {} / {check} / sentence {}",
                                    group["description"].as_str().unwrap_or_default(),
                                    case["description"].as_str().unwrap_or_default(),
                                    at + 1
                                ));
                            }
                        }
                    }
                }
            }
        }
    }
    assert_eq!(differ, NO_ENTRY_YET_FOR_AN_ITEM_WHOSE_SECOND_LIST_FAILS);
}

const NO_ENTRY_YET_FOR_AN_ITEM_WHOSE_SECOND_LIST_FAILS: [&str; 4] = [
    "for / a for line whose second list fails for an item, with sentences that don't read the second alias / runs the sentences that don't read y for each item and says them before the list / c / sentence 2",
    "for / a for line whose second list has a named by key from $params that isn't text / says the key once on the row, after the sentence that doesn't read x / c / sentence 2",
    "messages / a for line over two lists, with a walk under the first item before a sentence on the second / the parts follow the items, not the sentences / c / sentence 1",
    "messages / a for line over two lists, with a sentence on the second item before a walk under the first / the parts follow the items, not the sentences / c / sentence 2",
];
