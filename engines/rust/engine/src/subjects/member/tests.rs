use super::*;
use serde_json::json;

fn walked(input: &Value, keys: &[&str]) -> Walked<'static> {
    let input: &'static Value = Box::leak(Box::new(input.clone()));
    let base = Located {
        value: input,
        location: Location::input_root(),
    };
    let segs: Vec<walk::Seg> = keys
        .iter()
        .map(|key| walk::Seg::Key((*key).to_string()))
        .collect();
    member_walk(&base, &segs, "$input", false)
}

fn locations(w: &Walked) -> Vec<String> {
    w.entries.iter().map(|e| e.at.location.render()).collect()
}

fn keys(w: &Walked) -> Vec<Option<String>> {
    w.entries.iter().map(|e| e.key.clone()).collect()
}

fn said(w: &Walked) -> Vec<(String, Cause)> {
    w.broken
        .iter()
        .filter(|b| !b.msg.is_empty())
        .map(|b| (b.msg.clone(), b.cause))
        .collect()
}

#[test]
fn each_member_of_the_object_at_the_end_is_an_item_in_key_order_with_its_key() {
    let w = walked(
        &json!({"records": [{"id": "r1", "evidence": {
            "sign-off": {"kind": "approval"}, "build-7": {"kind": "scan"}}}]}),
        &["records", "evidence"],
    );
    assert_eq!(
        locations(&w),
        [
            "/records/0/evidence/build-7",
            "/records/0/evidence/sign-off"
        ]
    );
    assert_eq!(
        keys(&w),
        [Some("build-7".to_string()), Some("sign-off".to_string())]
    );
    assert!(w.broken.is_empty());
    assert!(w.lists);
}

#[test]
fn members_sort_by_code_point_whatever_order_the_input_has() {
    let w = walked(&json!({"o": {"b": 1, "B": 2, "a": 3, "é": 4}}), &["o"]);
    assert_eq!(locations(&w), ["/o/B", "/o/a", "/o/b", "/o/é"]);
}

#[test]
fn an_end_that_is_there_but_is_not_an_object_fails_unusable_and_other_ends_still_give_members() {
    let w = walked(
        &json!({"records": [{"evidence": {"a": 1}}, {"evidence": [1]}, {"evidence": "x"}, {"evidence": 2}, {"evidence": true}]}),
        &["records", "evidence"],
    );
    assert_eq!(locations(&w), ["/records/0/evidence/a"]);
    assert_eq!(
        said(&w),
        [
            (
                "item 2 of records: evidence is [1], which isn't an object".to_string(),
                Cause::Unusable
            ),
            (
                "item 3 of records: evidence is \"x\", which isn't an object".to_string(),
                Cause::Unusable
            ),
            (
                "item 4 of records: evidence is 2, which isn't an object".to_string(),
                Cause::Unusable
            ),
            (
                "item 5 of records: evidence is true, which isn't an object".to_string(),
                Cause::Unusable
            ),
        ]
    );
    let broken = &w.broken[0];
    assert_eq!(broken.path, "records[1].evidence");
    assert_eq!(broken.location.as_deref(), Some("/records/1/evidence"));
    assert_eq!(broken.value, json!([1]));
}

#[test]
fn a_list_at_the_end_is_not_walked_into() {
    let w = walked(&json!({"evidence": [{"a": 1}]}), &["evidence"]);
    assert!(w.entries.is_empty());
    assert_eq!(
        said(&w),
        [(
            "evidence is [{\"a\": 1}], which isn't an object".to_string(),
            Cause::Unusable
        )]
    );
    assert!(!w.lists);
}

#[test]
fn a_missing_or_null_end_keeps_absent_or_null() {
    let w = walked(
        &json!({"records": [{}, {"evidence": null}, {"evidence": {"a": 1}}]}),
        &["records", "evidence"],
    );
    assert_eq!(locations(&w), ["/records/2/evidence/a"]);
    assert_eq!(
        said(&w),
        [
            (
                "item 1 of records: evidence is missing".to_string(),
                Cause::Absent
            ),
            (
                "item 2 of records: evidence is null".to_string(),
                Cause::Null
            ),
        ]
    );
}

#[test]
fn an_empty_object_gives_no_member_and_fails_nothing() {
    let w = walked(
        &json!({"records": [{"evidence": {}}]}),
        &["records", "evidence"],
    );
    assert!(w.entries.is_empty());
    assert!(w.broken.is_empty());
}

#[test]
fn a_null_member_is_still_an_item() {
    let w = walked(
        &json!({"records": [{"evidence": {"a": null}}]}),
        &["records", "evidence"],
    );
    assert_eq!(locations(&w), ["/records/0/evidence/a"]);
    assert_eq!(w.entries[0].at.value, &Value::Null);
    assert!(w.broken.is_empty());
}

#[test]
fn no_list_along_the_path_still_gives_the_members_and_says_no_list_was_read() {
    let w = walked(&json!({"o": {"b": 1, "a": 2}}), &["o"]);
    assert_eq!(locations(&w), ["/o/a", "/o/b"]);
    assert!(!w.lists);
    let w = walked(&json!({"b": 1, "a": 2}), &[]);
    assert_eq!(locations(&w), ["/a", "/b"]);
    assert_eq!(keys(&w), [Some("a".to_string()), Some("b".to_string())]);
}

#[test]
fn members_of_mixed_types_name_the_first_member_of_each_type() {
    let w = walked(
        &json!({"records": [{"evidence": {"a": {}, "b": "x", "c": "y"}}]}),
        &["records", "evidence"],
    );
    assert_eq!(w.entries.len(), 3);
    assert_eq!(
        said(&w),
        [(
            "item 1 of records: evidence.a is an object, item 1 of records: evidence.b is text"
                .to_string(),
            Cause::Unusable
        )]
    );
}

#[test]
fn a_list_in_the_middle_is_walked_as_every_walks_it() {
    let w = walked(
        &json!({"records": [{"evidence": {"a": 1}}, {"evidence": {"b": 2}}]}),
        &["records", "evidence"],
    );
    assert_eq!(
        locations(&w),
        ["/records/0/evidence/a", "/records/1/evidence/b"]
    );
}

#[test]
fn a_parent_that_is_a_list_with_no_path_after_it_is_not_an_object_and_is_named() {
    let list = json!([1]);
    match parent_failure(&list, None, "record") {
        Some(Read::Entries { entries, broken }) => {
            assert!(entries.is_empty());
            assert_eq!(broken.len(), 1);
            assert_eq!(broken[0].msg, "record is [1], which isn't an object");
            assert_eq!(broken[0].cause, Cause::NotAnObject);
            assert!(!broken[0].listed);
        }
        _ => panic!("a list parent must say what it is"),
    }
    assert!(parent_failure(&list, Some(&Step::Key("x".into())), "record").is_none());
    assert!(parent_failure(&json!({}), None, "record").is_none());
    assert!(matches!(
        parent_failure(&json!("t"), None, "record"),
        Some(Read::Failed(Cause::NotAnObject))
    ));
}

type EntriesRead = (Vec<(String, Option<String>)>, Vec<(String, Cause)>);

fn entries_of(subject: Value, input: &Value) -> EntriesRead {
    let policy = Policy::read(&json!({
        "ergo_spec": crate::SPEC,
        "subjects": {"e": subject},
        "requirements": {"r": {"subject": "e", "checks": {"c": "status exists"}}}
    }));
    let reading = Reading::of(&policy);
    let env = Env {
        reading: &reading,
        requirement_name: "r",
        requirement: &policy.requirements["r"],
        subject: "e",
        checks: BTreeMap::new(),
        input,
        params: None,
        unreadable: Vec::new(),
    };
    match member_entries(&env, &path::ABSENT, reading.lowered("e").unwrap(), &[]) {
        Read::Entries { entries, broken } => (
            entries
                .iter()
                .map(|e| (e.at.location.render(), e.key.clone()))
                .collect(),
            broken
                .iter()
                .filter(|b| !b.msg.is_empty())
                .map(|b| (b.msg.clone(), b.cause))
                .collect(),
        ),
        Read::Failed(cause) => panic!("the read failed as {cause:?}"),
    }
}

#[test]
fn member_entries_give_each_member_with_its_key_as_the_id() {
    let (entries, broken) = entries_of(
        json!({"from": "every member of records.evidence"}),
        &json!({"records": [{"evidence": {"b": {}, "a": {}}}]}),
    );
    assert_eq!(
        entries,
        [
            ("/records/0/evidence/a".to_string(), Some("a".to_string())),
            ("/records/0/evidence/b".to_string(), Some("b".to_string()))
        ]
    );
    assert!(broken.is_empty());
}

#[test]
fn member_entries_drop_the_key_when_the_subject_has_identified_by() {
    let (entries, _) = entries_of(
        json!({"from": "every member of records.evidence", "identified_by": "id"}),
        &json!({"records": [{"evidence": {"a": {"id": "x"}}}]}),
    );
    assert_eq!(entries, [("/records/0/evidence/a".to_string(), None)]);
}

#[test]
fn member_entries_say_where_a_read_with_no_list_stops_as_every_does() {
    let (entries, broken) = entries_of(json!({"from": "every member of p.q"}), &json!({"p": null}));
    assert!(entries.is_empty());
    assert_eq!(broken, [("p is null".to_string(), Cause::Null)]);
}
