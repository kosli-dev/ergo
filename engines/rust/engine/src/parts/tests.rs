use super::*;
use crate::path::Outcome;
use serde_json::json;

fn read(name: &str, value: Value, state: Outcome) -> Input {
    Input {
        name: name.to_string(),
        value,
        locations: Vec::new(),
        part: None,
        state,
        null_at: None,
        worked: false,
    }
}

fn lowered(sentence: &str) -> crate::ops::Check {
    let tree = ergo_policy_sentences::parse_check(sentence).unwrap();
    crate::lower::lower_assertion(&tree.assertions[0], &crate::lower::Scope::new()).unwrap()
}

fn outcome_of(
    sentences: &[&str],
    input: &Value,
    params: Option<&Value>,
    name: &str,
) -> Option<&'static str> {
    outcome_in(sentences, input, input, params, name)
}

fn outcome_in(
    sentences: &[&str],
    subject: &Value,
    input: &Value,
    params: Option<&Value>,
    name: &str,
) -> Option<&'static str> {
    let checks: Vec<crate::ops::Check> = sentences.iter().map(|s| lowered(s)).collect();
    let all: Vec<&crate::ops::Check> = checks.iter().collect();
    let ctx = crate::path::Ctx {
        subject: crate::path::Located {
            value: subject,
            location: crate::path::Location::input_root(),
        },
        input,
        params,
        aliases: std::collections::BTreeMap::new(),
        label: None,
        item_by_item: checks.iter().any(crate::ops::Check::reads_by_item),
    };
    let read = checks
        .iter()
        .flat_map(|check| crate::ops::run(check, &ctx).inputs)
        .find(|read| read.name == name)
        .unwrap();
    outcome(&read, crate::checks::input_unfit(&all, &read, &ctx))
}

#[test]
fn a_missing_input_is_absent_and_a_null_one_is_null_beside_a_value_the_row_cant_use() {
    let check = ["x is at least 3", "w is at least 3"];
    assert_eq!(
        outcome_of(&check, &json!({"w": "a"}), None, "x"),
        Some("absent")
    );
    assert_eq!(
        outcome_of(&check, &json!({"x": null, "w": "a"}), None, "x"),
        Some("null")
    );
    assert_eq!(
        outcome_of(&check, &json!({"w": "a"}), None, "w"),
        Some("unusable")
    );
    for state in [Outcome::Absent, Outcome::Null] {
        let missing = read("x", Value::Null, state);
        assert_eq!(outcome(&missing, true), outcome(&missing, false));
    }
}

#[test]
fn a_found_value_is_unusable_only_when_the_check_cant_use_it() {
    let check = ["x is at least 3"];
    assert_eq!(
        outcome_of(&check, &json!({"x": "1"}), None, "x"),
        Some("unusable")
    );
    assert_eq!(
        outcome_of(&check, &json!({"x": 1}), None, "x"),
        Some("usable")
    );
}

#[test]
fn a_side_the_compare_cant_use_is_unusable_without_a_message() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({"v": "a"}), None, "v"),
        Some("unusable")
    );
}

#[test]
fn a_side_the_compare_can_use_is_usable_when_the_check_fails() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({"v": 1}), None, "v"),
        Some("usable")
    );
}

#[test]
fn a_missing_side_is_absent_where_the_compare_needs_a_number() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({}), None, "v"),
        Some("absent")
    );
}

#[test]
fn a_null_side_is_null_where_the_compare_needs_a_number() {
    assert_eq!(
        outcome_of(&["v is at least 3"], &json!({"v": null}), None, "v"),
        Some("null")
    );
}

#[test]
fn a_key_of_the_wrong_kind_stays_usable() {
    assert_eq!(
        outcome_of(
            &["m named by k is 1"],
            &json!({"k": 3, "m": {"a": 1}}),
            None,
            "k"
        ),
        Some("usable")
    );
}

#[test]
fn a_walked_root_stays_usable_when_another_clause_of_the_message_says_which_isnt() {
    assert_eq!(
        outcome_of(
            &["every $input.xs is at least 5", "$params.q is at least 1"],
            &json!({"xs": [3]}),
            Some(&json!({"q": "s"})),
            "$input.xs[]"
        ),
        Some("usable")
    );
}

#[test]
fn a_walked_root_with_an_item_the_walk_cant_read_is_unusable() {
    assert_eq!(
        outcome_of(
            &["x is in $input.os.name"],
            &json!({"x": "bob", "os": [{"name": "bob"}, 3]}),
            None,
            "$input.os[].name"
        ),
        Some("unusable")
    );
}

#[test]
fn a_side_stays_usable_when_the_check_fails_on_the_other_side_before_using_it() {
    assert_eq!(
        outcome_of(&["l contains w"], &json!({"l": "a"}), None, "l"),
        Some("usable")
    );
}

#[test]
fn a_walked_list_that_starts_at_the_input_is_unusable_when_an_item_isnt_an_object() {
    assert_eq!(
        outcome_in(
            &["id is in $input.id"],
            &json!({"id": "a"}),
            &json!([{"id": "a"}, 1]),
            None,
            "$input[].id"
        ),
        Some("unusable")
    );
}

#[test]
fn a_walked_field_of_the_subject_stays_usable_when_an_item_isnt_an_object() {
    assert_eq!(
        outcome_of(
            &["x is in os.name"],
            &json!({"x": "bob", "os": [{"name": "bob"}, 3]}),
            None,
            "os[].name"
        ),
        Some("usable")
    );
}

#[test]
fn a_value_whose_name_ends_a_clause_about_another_value_stays_usable() {
    let subject = json!({"id": "a"});
    let input = json!([{"id": "a"}]);
    let sentences = ["id is in $input[0].id"];
    assert_eq!(
        outcome_in(&sentences, &subject, &input, None, "id"),
        Some("usable")
    );
    assert_eq!(
        outcome_in(&sentences, &subject, &input, None, "$input[0].id"),
        Some("unusable")
    );
}

#[test]
fn a_worked_out_number_has_no_outcome() {
    let mut count = read("count of xs", json!(2), Outcome::Found);
    count.worked = true;
    assert_eq!(outcome(&count, true), None);
}

#[test]
fn a_string_check_with_two_assertions_numbers_them() {
    assert_eq!(
        assertion_locations("r", "c", &json!("x is 1 and y is 2"), None, 2),
        vec![
            "$policy:/requirements/r/checks/c#1",
            "$policy:/requirements/r/checks/c#2"
        ]
    );
}

#[test]
fn a_listed_assert_points_at_each_line_and_escapes_the_keys() {
    assert_eq!(
        assertion_locations(
            "r/s",
            "c~",
            &json!({"assert": ["x is 1 and y is 2", "z is 3"]}),
            None,
            3
        ),
        vec![
            "$policy:/requirements/r~1s/checks/c~0/assert/0#1",
            "$policy:/requirements/r~1s/checks/c~0/assert/0#2",
            "$policy:/requirements/r~1s/checks/c~0/assert/1"
        ]
    );
}

#[test]
fn an_option_written_as_one_string_points_at_the_option() {
    assert_eq!(
        assertion_locations("r", "c", &json!({"any_of": {"o": "a is 1"}}), Some("o"), 1),
        vec!["$policy:/requirements/r/checks/c/any_of/o"]
    );
}

fn record(item: &str, path: &str, cause: &str, text: &str) -> Value {
    json!({
        "path": path,
        "item": item,
        "cause": cause,
        "value": 1,
        "locations": [],
        "ergo/text": text,
    })
}

#[test]
fn an_item_entry_says_its_clauses_without_its_name() {
    use crate::ops::clause::Kind;
    let item = said_clause("item 1 of xs", Cause::Value, "item 1 of xs: w is 2");
    assert_eq!(
        (item.kind, item.said[0].text.as_str()),
        (Kind::Item, "w is 2")
    );
    let root = said_clause("item 2 of xs", Cause::Value, "$params.min is \"s\"");
    assert_eq!(root.kind, Kind::Root);
    let list = said_clause("xs", Cause::Absent, "xs: is missing");
    assert_eq!(
        (list.kind, list.said[0].text.as_str()),
        (Kind::List, "is missing")
    );
    let records = [
        record(
            "item 1 of xs",
            "xs[0].v",
            "value",
            "item 1 of xs: v is \"p; q\"",
        ),
        record("item 1 of xs", "xs[0].w", "value", "item 1 of xs: w is 2"),
        record(
            "item 2 of xs",
            "xs[1].v",
            "unusable",
            "$params.min is \"s\"",
        ),
        record("xs", "xs", "absent", "xs: is missing"),
    ];
    let walked = walk_entries(&records, &record_clauses(&records));
    assert_eq!(
        walked.roots,
        [Clause::root(
            "item 2 of xs",
            Cause::Unusable,
            "$params.min is \"s\"".to_string()
        )]
    );
    let said: Vec<(&str, &str)> = walked
        .entries
        .iter()
        .map(|entry| match entry {
            Failure::Item { part, .. } | Failure::List(part) => {
                (part.name.as_str(), part.message.as_str())
            }
            _ => panic!("an entry that is neither an item nor a list"),
        })
        .collect();
    assert_eq!(
        said,
        [
            ("item 1 of xs", "v is \"p; q\"; w is 2"),
            ("xs", "is missing"),
        ]
    );
}

#[test]
fn walk_entries_read_each_records_clause_kind_and_not_its_text() {
    use crate::ops::clause::Kind;
    let records = [
        record(
            "item 1 of xs",
            "xs[0].v",
            "unusable",
            "item 1 of xs: v is 1",
        ),
        record("item 2 of xs", "xs[1].v", "value", "$params.min is 1"),
        record("xs", "xs", "absent", "xs: is missing"),
    ];
    let clauses = [
        Clause::root(
            "$params.min",
            Cause::Unusable,
            "$params.min is \"s\"".to_string(),
        ),
        Clause::item(
            "item 2 of xs",
            Cause::Value,
            String::new(),
            vec![Clause::said(Cause::Value, "v is 2".to_string())],
        ),
        Clause {
            said: vec![Clause::said(Cause::Absent, "is missing".to_string())],
            ..Clause::list("xs", Cause::Absent, "xs: is missing".to_string())
        },
    ];
    let walked = walk_entries(&records, &clauses);
    let roots: Vec<(Kind, &str)> = walked
        .roots
        .iter()
        .map(|root| (root.kind, root.text.as_str()))
        .collect();
    assert_eq!(roots, [(Kind::Root, "$params.min is \"s\"")]);
    let said: Vec<(bool, &str, &str)> = walked
        .entries
        .iter()
        .map(|entry| match entry {
            Failure::Item { part, .. } => (true, part.name.as_str(), part.message.as_str()),
            Failure::List(part) => (false, part.name.as_str(), part.message.as_str()),
            _ => panic!("an entry that is neither an item nor a list"),
        })
        .collect();
    assert_eq!(
        said,
        [
            (true, "item 2 of xs", "v is 2"),
            (false, "xs", "is missing")
        ]
    );
}

#[test]
fn a_member_name_is_an_item_and_reads_back_as_the_path_of_its_key() {
    assert!(is_item("member k of xs"));
    assert!(is_item("member \"a of b\" of xs"));
    assert!(!is_item("membership is 1"));
    assert_eq!(position_name("member k of xs"), "xs.k");
    assert_eq!(position_name("member \"a; b\" of r.e"), "r.e.\"a; b\"");
    assert_eq!(position_name("member \"a of b\" of xs"), "xs.\"a of b\"");
    assert_eq!(list_base("member k of xs"), "xs");
    assert_eq!(list_base("member \"a of b\" of xs"), "xs");
}

#[test]
fn a_member_record_becomes_an_item_entry_named_by_its_key() {
    use crate::ops::clause::Kind;
    let member = said_clause("member a of xs", Cause::Value, "member a of xs is 2");
    assert_eq!(member.kind, Kind::Item);
    let records = [record(
        "member a of xs",
        "member a of xs",
        "value",
        "member a of xs is 2",
    )];
    let walked = walk_entries(&records, &record_clauses(&records));
    let Failure::Item { part, .. } = &walked.entries[0] else {
        panic!("not an item entry");
    };
    assert_eq!(part.name, "member a of xs");
    assert_eq!(part.inputs[0]["name"], json!("xs.a"));
}

#[test]
fn a_member_entry_of_an_object_in_a_list_nests_under_its_item_named_by_its_key() {
    let input = json!({"s": {"rs": [{"statuses": {"a": "DONE", "b": 1}}]}});
    let entry = Failure::Item {
        part: Part {
            name: "member b of rs[0].statuses".to_string(),
            cause: Cause::Unusable,
            inputs: Vec::new(),
            failures: Vec::new(),
            message: "item 1 of rs: member b of statuses is 1, which isn't text".to_string(),
        },
        value: json!(1),
        locations: vec!["/s/rs/0/statuses/b".to_string()],
    };
    let nested = nest(vec![entry], &input);
    assert_eq!(nested[0].part().name, "item 1 of rs");
    let inner = &nested[0].part().failures[0];
    assert_eq!(inner.part().name, "member b of statuses");
    assert_eq!(
        inner.part().message,
        "member b of statuses is 1, which isn't text"
    );
}

#[test]
fn a_null_value_that_was_found_has_no_outcome_whether_or_not_the_check_can_use_it() {
    let found = read("x", Value::Null, Outcome::Found);
    assert_eq!(outcome(&found, false), None);
    assert_eq!(outcome(&found, true), None);
}

#[test]
fn an_item_or_list_entry_belongs_to_the_list_before_its_position_and_its_field() {
    assert_eq!(list_base("item 2 of xs"), "xs");
    assert_eq!(list_base("item 1 of xs[0].v"), "xs");
    assert_eq!(list_base("xs[3].v"), "xs");
    assert_eq!(list_base("xs"), "xs");
    assert_eq!(list_base("item x"), "item x");
}

#[test]
fn a_row_input_is_in_a_list_only_when_it_reads_inside_that_list() {
    let lists = vec!["xs".to_string()];
    assert!(item_input("xs[].v", &lists));
    assert!(!item_input("ys[].v", &lists));
    assert!(!item_input("xs", &lists));
}

#[test]
fn an_item_text_that_names_another_item_is_kept_whole() {
    use crate::ops::clause::Kind;
    let clause = said_clause("item 1 of xs", Cause::Value, "item 2 of ys: w is 1");
    assert_eq!(
        (clause.kind, clause.text.as_str(), clause.said.is_empty()),
        (Kind::Item, "item 2 of ys: w is 1", true)
    );
}

#[test]
fn an_item_outcome_follows_its_cause_and_falls_back_on_its_value() {
    assert_eq!(item_outcome("absent", &json!(1)), "absent");
    assert_eq!(item_outcome("null", &json!(1)), "null");
    assert_eq!(item_outcome("unusable", &json!(1)), "unusable");
    assert_eq!(item_outcome("not_an_object", &json!(1)), "not_an_object");
    assert_eq!(item_outcome("value", &json!(1)), "usable");
    assert_eq!(item_outcome("value", &Value::Null), "null");
}

fn failed_item(name: &str, place: &str, message: &str) -> Failure {
    Failure::Item {
        part: Part {
            name: name.to_string(),
            cause: Cause::Value,
            inputs: Vec::new(),
            failures: Vec::new(),
            message: message.to_string(),
        },
        value: json!(1),
        locations: vec![place.to_string()],
    }
}

fn failed_list(name: &str, cause: Cause, place: &str, message: &str) -> Failure {
    Failure::List(Part {
        name: name.to_string(),
        cause,
        inputs: vec![json!({"name": name, "locations": [place]})],
        failures: Vec::new(),
        message: message.to_string(),
    })
}

fn names_and_places(entries: &[Failure]) -> Vec<(String, Vec<String>)> {
    entries
        .iter()
        .map(|entry| {
            let places = match entry {
                Failure::Item { locations, .. } => locations.clone(),
                other => other
                    .part()
                    .inputs
                    .iter()
                    .flat_map(|i| i["locations"].as_array().cloned().unwrap_or_default())
                    .filter_map(|l| l.as_str().map(str::to_string))
                    .collect(),
            };
            (entry.part().name.clone(), places)
        })
        .collect()
}

fn pair(name: &str, place: &str) -> (String, Vec<String>) {
    (name.to_string(), vec![place.to_string()])
}

#[test]
fn an_item_nested_two_levels_deep_sits_under_each_outer_item_with_dotted_names() {
    let input = json!({"xs": [{"p": {"ys": [{"w": [1, 2, 3, 4]}, {"w": [1]}]}}]});
    let out = nest(
        vec![failed_item(
            "item 4 of xs[0].p.ys[0].w",
            "/xs/0/p/ys/0/w/3",
            "item 1 of xs: item 1 of p.ys: item 4 of w: x is 4",
        )],
        &input,
    );
    assert_eq!(names_and_places(&out), [pair("item 1 of xs", "/xs/0")]);
    assert_eq!(out[0].part().message, "");
    assert_eq!(out[0].part().cause, Cause::Value);
    let middle = &out[0].part().failures;
    assert_eq!(
        names_and_places(middle),
        [pair("item 1 of p.ys", "/xs/0/p/ys/0")]
    );
    let leaf = &middle[0].part().failures;
    assert_eq!(
        names_and_places(leaf),
        [pair("item 4 of w", "/xs/0/p/ys/0/w/3")]
    );
    assert_eq!(leaf[0].part().message, "x is 4");
}

#[test]
fn a_list_that_stopped_short_is_said_under_the_item_it_was_in() {
    let out = nest(
        vec![failed_list(
            "xs[0].ys[1].w",
            Cause::Absent,
            "/xs/0/ys/1",
            "item 1 of xs: item 2 of ys: w is missing",
        )],
        &json!({"xs": [{"ys": [{}, {}]}]}),
    );
    assert_eq!(names_and_places(&out), [pair("item 1 of xs", "/xs/0")]);
    let inner = &out[0].part().failures;
    assert_eq!(
        names_and_places(inner),
        [pair("item 2 of ys", "/xs/0/ys/1")]
    );
    let leaf = &inner[0].part().failures;
    assert_eq!(leaf.len(), 1);
    assert!(matches!(leaf[0], Failure::List(_)));
    assert_eq!(leaf[0].part().name, "w");
    assert_eq!(leaf[0].part().message, "w is missing");
}

#[test]
fn a_list_message_that_starts_with_a_colon_is_kept_as_it_is() {
    let out = nest(
        vec![failed_list("xs[0].ys", Cause::Value, "/xs/0/ys", ": foo")],
        &json!({"xs": [{"ys": []}]}),
    );
    assert_eq!(out[0].part().failures[0].part().message, ": foo");
}

#[test]
fn an_item_in_lists_four_deep_is_left_as_it_is() {
    let out = nest(
        vec![failed_item(
            "item 1 of a[0].b[0].c[0].d[0].e",
            "/a/0/b/0/c/0/d/0/e/0",
            "item 1 of a: m",
        )],
        &json!({}),
    );
    assert_eq!(
        names_and_places(&out),
        [pair(
            "item 1 of a[0].b[0].c[0].d[0].e",
            "/a/0/b/0/c/0/d/0/e/0"
        )]
    );
    assert_eq!(out[0].part().message, "item 1 of a: m");
}

#[test]
fn items_of_the_same_outer_item_are_grouped_in_the_order_they_first_appear() {
    let out = nest(
        vec![
            failed_item(
                "item 1 of xs[0].ys",
                "/xs/0/ys/0",
                "item 1 of xs: item 1 of ys: v is 1",
            ),
            failed_item(
                "item 2 of xs[1].ys",
                "/xs/1/ys/1",
                "item 2 of xs: item 2 of ys: v is 2",
            ),
            failed_item(
                "item 2 of xs[0].ys",
                "/xs/0/ys/1",
                "item 1 of xs: item 2 of ys: v is 3",
            ),
        ],
        &json!({"xs": [{"ys": [1, 2]}, {"ys": [1, 2]}]}),
    );
    assert_eq!(
        names_and_places(&out),
        [pair("item 1 of xs", "/xs/0"), pair("item 2 of xs", "/xs/1")]
    );
    assert_eq!(
        names_and_places(&out[0].part().failures),
        [
            pair("item 1 of ys", "/xs/0/ys/0"),
            pair("item 2 of ys", "/xs/0/ys/1")
        ]
    );
    assert_eq!(
        names_and_places(&out[1].part().failures),
        [pair("item 2 of ys", "/xs/1/ys/1")]
    );
}

#[test]
fn two_entries_for_the_same_item_beside_nested_ones_merge_and_keep_each_input_once() {
    let mut first = failed_item("item 1 of ws", "/ws/0", "item 1 of ws: q");
    let mut second = failed_item("item 1 of ws", "/ws/0", "item 1 of ws: r");
    for entry in [&mut first, &mut second] {
        if let Failure::Item { part, .. } = entry {
            part.inputs = vec![json!({"name": "ws[0]"})];
        }
    }
    let out = nest(
        vec![
            failed_item(
                "item 1 of xs[0].ys",
                "/xs/0/ys/0",
                "item 1 of xs: item 1 of ys: v is 1",
            ),
            first,
            second,
        ],
        &json!({"xs": [{"ys": [1]}], "ws": [1]}),
    );
    assert_eq!(names_and_places(&out).len(), 2);
    assert_eq!(out[1].part().name, "item 1 of ws");
    assert_eq!(out[1].part().inputs, [json!({"name": "ws[0]"})]);
}

#[test]
fn a_list_entry_keeps_its_own_name_in_its_message_when_the_text_says_it() {
    let out = nest(
        vec![failed_list(
            "xs[0].ys[1].w",
            Cause::Absent,
            "/xs/0/ys/1",
            "item 1 of xs: item 2 of ys: w: is missing",
        )],
        &json!({"xs": [{"ys": [{}, {}]}]}),
    );
    let leaf = &out[0].part().failures[0].part().failures;
    assert_eq!(leaf[0].part().message, "w: is missing");
}
