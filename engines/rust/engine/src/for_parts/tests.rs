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
    let record = json!({
        "ergo/clauses": clause::to_value(&[Clause::said(
            Cause::Value,
            "member \"a; b\" of statuses is 1".to_string(),
        )]),
    });
    assert_eq!(
        clause::lines(&own_said(&record, &[])),
        ["member \"a; b\" of statuses is 1"]
    );
    assert!(own_said(&record, &made).is_empty());
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

#[test]
fn an_assertion_says_a_root_that_walks_a_list_once_with_its_items_capped() {
    let said = entries(
        "every rows as r",
        json!("r.v is in $params.pos.name"),
        json!({"rows": [{"v": "bob"}, {}]}),
        json!({"pos": [{"name": "bob"}, {"v": 0}, {"v": 1}, {"v": 2}, {"v": 3}]}),
    );
    assert!(
        said[0].starts_with("assertion r.v is in $params.pos.name [absent] \"item 2 of $params.pos: name is missing; item 3 of $params.pos: name is missing; item 4 of $params.pos: name is missing; and 1 more\" "),
        "{said:#?}"
    );
}

#[test]
fn no_list_entry_holds_the_items_message() {
    assert_eq!(
        entries(
            "every xs as x",
            json!([
                "x.v is at least $params.min",
                "z is 1",
                "x.w is at least $params.min"
            ]),
            json!({"xs": [{"v": 1}, {}], "z": 2}),
            json!({"min": "s"}),
        ),
        [
            format!(
                "assertion x.v is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            "  item item 2 of xs [absent] \"x.v is missing\" (\"x.v\" \"absent\")".to_string(),
            "assertion z is 1 [value] \"z is 2\" (\"z\" \"usable\")".to_string(),
            format!(
                "assertion x.w is at least $params.min [unusable] \"$params.min is \\\"s\\\", which isn't a number\" {MIN_S}"
            ),
            "  item item 1 of xs [absent] \"x.w is missing\" (\"x.w\" \"absent\")".to_string(),
            "  item item 2 of xs [absent] \"x.w is missing\" (\"x.w\" \"absent\")".to_string(),
        ]
    );
}

#[test]
fn a_root_of_the_lines_own_whose_sits_on_the_lists_entry_capped_and_on_no_assertion() {
    assert_eq!(
        entries(
            "every rows whose v is in $params.pos.name as r",
            json!("r.v is \"bob\""),
            json!({"rows": [{"v": "bob"}, {}, {}]}),
            json!({"pos": [{"name": "bob"}, {"v": 0}, {"v": 1}, {"v": 2}, {"v": 3}, {"v": 4}]}),
        ),
        [
            "list rows [absent] \"item 2 of $params.pos: name is missing; item 3 of $params.pos: name is missing; item 4 of $params.pos: name is missing; and 2 more\" (\"rows[]\" \"usable\")",
            "item item 2 of rows [absent] \"v is missing\" (\"rows[1].v\" \"absent\")",
            "item item 3 of rows [absent] \"v is missing\" (\"rows[2].v\" \"absent\")",
        ]
    );
}

#[test]
fn a_key_of_a_second_list_that_cant_be_read_is_no_entry_of_the_first_list() {
    let said = entries(
        "every ws as w, every w.o named by $params.k as x",
        json!(["x is 1", "z is 1"]),
        json!({"ws": [{"o": {"a": 1}}], "z": 2}),
        json!({}),
    );
    assert!(
        !said.iter().any(|entry| entry.starts_with("list ws ")),
        "{said:#?}"
    );
}

#[test]
fn what_a_sentence_says_of_an_item_whose_second_list_fails_stays_in_an_entry_until_the_item_has_its_own()
 {
    let said = entries(
        "every xs as x, every x.ys as y",
        json!(["x.w is 1", "y.n is 1"]),
        json!({"xs": [{"ys": [{"n": 1}], "w": 1}, {"w": 2}]}),
        json!({}),
    );
    assert!(
        said.iter().any(|entry| entry.contains("x.w is 2")),
        "{said:#?}"
    );
}

#[test]
fn what_a_sentence_says_of_an_item_whose_second_list_fails_stays_in_an_entry_beside_a_root_it_cant_read()
 {
    let said = entries(
        "every ws as w, every ys whose n is in $params.z as x",
        json!("w.v is at least $params.min"),
        json!({"ws": [{"v": 1}, {"v": "a"}, {}], "ys": [{"n": 1}]}),
        json!({"min": null}),
    );
    assert!(
        said.iter()
            .any(|entry| entry.contains("which isn't a number")),
        "{said:#?}"
    );
    assert!(
        said.iter().any(|entry| entry.contains("w.v is missing")),
        "{said:#?}"
    );
}

#[test]
fn what_a_walk_says_of_an_item_whose_sorted_second_list_fails_stays_in_an_entry_beside_a_root_it_cant_read()
 {
    let said = entries(
        "every ws as w, first of ys whose n is in $params.z sorted by n as x",
        json!("every w.ys.v is at least $params.min"),
        json!({"ws": [{"ys": [{"v": 1}]}, {"ys": null}], "ys": [{"n": 1}]}),
        json!({"min": null}),
    );
    assert!(
        said.iter().any(|entry| entry.contains("w.ys is null")),
        "{said:#?}"
    );
}

#[test]
fn an_item_that_isnt_an_object_stays_in_the_list_entry_beside_a_sort_key_that_isnt_text() {
    let said = entries(
        "first of xs sorted by m named by $params.km as x",
        json!(["x.v is 1", "z is 1"]),
        json!({"z": 2, "xs": [{"v": 2, "m": 2}, [1], {"v": 2, "m": [1]}]}),
        json!({"km": 3}),
    );
    assert!(
        said.iter()
            .any(|entry| entry.contains("item 2 of xs is [1], which isn't an object")),
        "{said:#?}"
    );
}

#[test]
fn an_items_problem_that_only_the_row_says_beside_a_null_root_stays_in_an_entry() {
    let said = entries(
        "every ws as w, every ys whose n is in $params.z as x",
        json!("w.v is at least $params.min"),
        json!({"ws": [{"v": 1}, {"v": "a"}, {}], "ys": [{"n": 1}]}),
        json!({"min": null, "z": [1]}),
    );
    assert!(
        said.iter()
            .any(|entry| entry.contains("which isn't a number")),
        "{said:#?}"
    );
}
