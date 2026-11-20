use super::*;

fn read(kind: Kind, name: &str, cause: Cause, text: &str) -> Clause {
    Clause {
        kind,
        name: name.to_string(),
        cause,
        text: text.to_string(),
        said: Vec::new(),
    }
}

fn root(name: &str, cause: Cause, text: &str) -> Clause {
    read(Kind::Root, name, cause, text)
}

fn item(name: &str, cause: Cause, said: Vec<Clause>) -> Clause {
    Clause {
        said,
        ..read(Kind::Item, name, cause, "")
    }
}

fn missing(name: &str) -> Clause {
    root(name, Cause::Absent, &format!("{name} is missing"))
}

#[test]
fn and_n_more_comes_after_the_roots_and_the_lists_in_a_count() {
    let mut clauses: Vec<Clause> = (1..=5)
        .map(|n| item(&format!("item {n} of xs"), Cause::Absent, vec![missing("v")]))
        .collect();
    clauses.push(root(
        "$params.min",
        Cause::Unusable,
        "$params.min is \"s\", which isn't a number",
    ));
    assert_eq!(
        text(&shown(&clauses)),
        "$params.min is \"s\", which isn't a number; item 1 of xs: v is missing; item 2 of xs: v is missing; item 3 of xs: v is missing; and 2 more"
    );
}

#[test]
fn the_cap_counts_leaf_items_not_outer_items() {
    let rs = || {
        vec![
            item("item 1 of rs", Cause::Absent, vec![missing("ok")]),
            item("item 2 of rs", Cause::Absent, vec![missing("ok")]),
        ]
    };
    let clauses = vec![
        item("item 1 of cs", Cause::Absent, rs()),
        item("item 2 of cs", Cause::Absent, rs()),
    ];
    assert_eq!(
        text(&shown(&clauses)),
        "item 1 of cs: item 1 of rs: ok is missing; item 1 of cs: item 2 of rs: ok is missing; item 2 of cs: item 1 of rs: ok is missing; and 1 more"
    );
}

#[test]
fn roots_come_worst_cause_first_then_by_name_and_before_the_list() {
    let clauses = vec![
        read(Kind::List, "xs", Cause::Value, "xs is []"),
        root("za", Cause::Null, "za is null"),
        root("zc", Cause::Unusable, "zc is \"s\", which isn't a number"),
        root("zb", Cause::Unusable, "zb is \"s\", which isn't a number"),
    ];
    assert_eq!(
        text(&shown(&clauses)),
        "zb is \"s\", which isn't a number; zc is \"s\", which isn't a number; za is null; xs is []"
    );
}

#[test]
fn a_root_whose_value_holds_a_semicolon_stays_one_clause() {
    let clauses = vec![
        root("w.z", Cause::Unusable, "w.z is \"p; q\", which isn't a number"),
        item("item 1 of ws", Cause::Absent, vec![missing("w.v")]),
    ];
    let shown = shown(&clauses);
    assert_eq!(shown, clauses);
    assert_eq!(
        text(&shown),
        "w.z is \"p; q\", which isn't a number; item 1 of ws: w.v is missing"
    );
}

#[test]
fn two_clauses_of_one_item_join_with_and() {
    let clauses: Vec<Clause> = (1..=5)
        .map(|n| {
            item(
                &format!("item {n} of xs"),
                Cause::Absent,
                vec![missing("x.v"), missing("x.w")],
            )
        })
        .collect();
    assert_eq!(
        text(&shown(&clauses)),
        "item 1 of xs: x.v is missing, and x.w is missing; item 2 of xs: x.v is missing, and x.w is missing; item 3 of xs: x.v is missing, and x.w is missing; and 2 more"
    );
}
