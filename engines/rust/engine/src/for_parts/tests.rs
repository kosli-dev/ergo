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
