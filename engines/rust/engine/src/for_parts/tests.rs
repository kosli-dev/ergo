use super::*;

#[test]
fn a_clause_ends_at_a_semicolon_outside_quotes_so_a_quoted_key_or_value_stays_whole() {
    assert_eq!(
        clauses("member \"a; b\" of statuses is 1; member b of statuses is 1"),
        [
            "member \"a; b\" of statuses is 1",
            "member b of statuses is 1"
        ]
    );
    assert_eq!(
        clauses("item 1 of records: member \"a; b: c\" of r.evidence: e.status is 1"),
        ["item 1 of records: member \"a; b: c\" of r.evidence: e.status is 1"]
    );
    assert_eq!(
        clauses("item 1 of xs is \"a; b\", which isn't a number; item 2 of xs is 1"),
        [
            "item 1 of xs is \"a; b\", which isn't a number",
            "item 2 of xs is 1"
        ]
    );
}

#[test]
fn a_member_whose_key_holds_a_semicolon_makes_its_whole_clause_and_leaves_no_root() {
    let failed = [json!({
        "item": "member \"a; b\" of statuses",
        "ergo/text": "member \"a; b\" of statuses is 1",
    })];
    let made = item_made(&failed, &[]);
    assert_eq!(made, ["member \"a; b\" of statuses is 1"]);
    assert!(row_roots("member \"a; b\" of statuses is 1", &made).is_empty());
}

fn entries(for_line: &str, assertions: Value, subject: Value, params: Value) -> Vec<String> {
    let policy = json!({
        "ergo_spec": crate::SPEC,
        "subjects": {"thing": {"from": "things", "identified_by": "id"}},
        "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": for_line, "assert": assertions}}}}
    });
    let mut subject = subject;
    subject["id"] = json!(1);
    let report = crate::report(&json!({"things": [subject]}), &policy, &params);
    let row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "c")
        .unwrap()
        .clone();
    let mut out = Vec::new();
    tree(&row["failures"], 0, &mut out);
    out
}

fn tree(failures: &Value, depth: usize, out: &mut Vec<String>) {
    for entry in failures.as_array().into_iter().flatten() {
        let inputs: Vec<String> = entry["inputs"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|input| format!("{} {}", input["name"], input["outcome"]))
            .collect();
        out.push(format!(
            "{}{} {} [{}] {:?} ({})",
            "  ".repeat(depth),
            entry["kind"].as_str().unwrap_or_default(),
            entry["name"].as_str().unwrap_or_default(),
            entry["cause"].as_str().unwrap_or_default(),
            entry["message"].as_str().unwrap_or_default(),
            inputs.join(", ")
        ));
        tree(&entry["failures"], depth + 1, out);
    }
}

#[test]
fn an_items_own_read_keeps_its_own_cause_beside_a_root() {
    let said = entries(
        "every ws as w",
        json!("every w.xs.v is at least $params.min"),
        json!({"ws": [{"xs": [{}, {}]}]}),
        json!({"min": "s"}),
    );
    assert_eq!(said[1], "  item item 1 of ws [absent] \"\" ()");
    assert_eq!(
        said[2],
        "    item item 1 of w.xs [absent] \"v is missing\" (\"w.xs[0].v\" \"absent\")"
    );
}

#[test]
fn an_item_entry_is_its_clause() {
    assert_eq!(
        entries(
            "every xs as x",
            json!("every x.ys.n is 1"),
            json!({"xs": [{"ys": [{"n": 1}, {}]}, {}]}),
            json!({}),
        ),
        [
            "assertion every x.ys.n is 1 [absent] \"\" ()",
            "  item item 1 of xs [absent] \"\" ()",
            "    item item 2 of x.ys [absent] \"n is missing\" (\"x.ys[1].n\" \"absent\")",
            "  item item 2 of xs [absent] \"\" ()",
            "    list x.ys [absent] \"x.ys is missing\" (\"x.ys\" \"absent\")",
        ]
    );
}

#[test]
fn a_value_that_holds_a_semicolon_stays_whole_in_its_entry() {
    let said = entries(
        "every xs as x",
        json!("x.v is 1"),
        json!({"xs": [{"v": "p; q"}, {"v": "r; s"}, {"v": 3}, {"v": 4}, {"v": 5}]}),
        json!({}),
    );
    assert_eq!(said.len(), 6, "{said:#?}");
    assert_eq!(said[0], "assertion x.v is 1 [unusable] \"\" ()");
    assert_eq!(
        said[1],
        "  item item 1 of xs [unusable] \"x.v is \\\"p; q\\\", which isn't a number\" (\"x.v\" \"unusable\")"
    );
    assert_eq!(
        said[2],
        "  item item 2 of xs [unusable] \"x.v is \\\"r; s\\\", which isn't a number\" (\"x.v\" \"unusable\")"
    );
}

fn two_roots(subject: Value) -> Vec<String> {
    entries(
        "every xs as x",
        json!(["x.v is at least $params.min", "x.w is at least $params.min"]),
        subject,
        json!({"min": "s"}),
    )
}

const MIN_S: &str = "(\"$params.min\" \"unusable\")";

#[test]
fn every_assertion_entry_holds_the_root_it_reads() {
    assert_eq!(
        two_roots(json!({"xs": [{"v": 1}, {}]})),
        [
            format!(
                "assertion x.v is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            "  item item 2 of xs [absent] \"x.v is missing\" (\"x.v\" \"absent\")".to_string(),
            format!(
                "assertion x.w is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            "  item item 1 of xs [absent] \"x.w is missing\" (\"x.w\" \"absent\")".to_string(),
            "  item item 2 of xs [absent] \"x.w is missing\" (\"x.w\" \"absent\")".to_string(),
        ]
    );
}

#[test]
fn an_item_whose_only_problem_is_a_root_has_no_entry() {
    assert_eq!(
        two_roots(json!({"xs": [{"v": 1, "w": 2}]})),
        [
            format!(
                "assertion x.v is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            format!(
                "assertion x.w is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
        ]
    );
}

#[test]
fn an_assertion_entry_says_only_its_roots() {
    assert_eq!(
        entries(
            "every xs as x",
            json!("x.v is at least $params.min"),
            json!({"xs": [{"v": "a"}, {}]}),
            json!({"min": "s"}),
        ),
        [
            format!(
                "assertion x.v is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            "  item item 1 of xs [unusable] \"x.v is \\\"a\\\", which isn't a number\" (\"x.v\" \"unusable\")".to_string(),
            "  item item 2 of xs [absent] \"x.v is missing\" (\"x.v\" \"absent\")".to_string(),
        ]
    );
}

#[test]
fn an_assertion_doesnt_say_its_items_again_beside_a_missing_root() {
    assert_eq!(
        entries(
            "every ws as w",
            json!("w.z is at least $params.min"),
            json!({"ws": [{}]}),
            json!({}),
        ),
        [
            "assertion w.z is at least $params.min [absent] \"$params.min is missing\" (\"$params.min\" \"absent\")",
            "  item item 1 of ws [absent] \"w.z is missing\" (\"w.z\" \"absent\")",
        ]
    );
}

#[test]
fn an_assertion_over_an_empty_list_lists_the_root_it_cant_read() {
    for (params, outcome) in [
        (json!({"min": "s"}), "unusable"),
        (json!({"min": null}), "null"),
        (json!({}), "absent"),
    ] {
        let said = entries(
            "every ws as w",
            json!("w.z is at least $params.min"),
            json!({"ws": []}),
            params,
        );
        assert!(
            said[0].ends_with(&format!("(\"$params.min\" \"{outcome}\")")),
            "{said:#?}"
        );
    }
}

#[test]
fn a_walk_through_the_alias_holds_the_root_beside_items_that_keep_their_own_cause() {
    assert_eq!(
        entries(
            "every ws as w",
            json!("every w.xs.v is at least $params.min"),
            json!({"ws": [{"xs": [{}]}]}),
            json!({"min": "s"}),
        ),
        [
            format!(
                "assertion every w.xs.v is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            "  item item 1 of ws [absent] \"\" ()".to_string(),
            "    item item 1 of w.xs [absent] \"v is missing\" (\"w.xs[0].v\" \"absent\")"
                .to_string(),
        ]
    );
}
