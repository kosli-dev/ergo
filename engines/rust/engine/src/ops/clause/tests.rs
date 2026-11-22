use super::*;

fn read(kind: Kind, name: &str, cause: Cause, text: &str) -> Clause {
    Clause {
        kind,
        name: name.to_string(),
        cause,
        text: text.to_string(),
        said: Vec::new(),
        group: 0,
        said_first: false,
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

fn null(name: &str) -> Clause {
    root(name, Cause::Null, &format!("{name} is null"))
}

fn unread(name: &str, cause: Cause, text: &str) -> Clause {
    read(Kind::Item, name, cause, text)
}

fn items_of(list: &str, from: usize, to: usize, said: impl Fn() -> Vec<Clause>) -> Vec<Clause> {
    (from..=to)
        .map(|n| item(&format!("item {n} of {list}"), Cause::Absent, said()))
        .collect()
}

fn with(mut clauses: Vec<Clause>, more: Vec<Clause>) -> Vec<Clause> {
    clauses.extend(more);
    clauses
}

#[test]
fn shown_and_text_give_what_joined_gives() {
    let rows: Vec<(Vec<Clause>, Vec<&str>)> = vec![
        (
            vec![
                root(
                    "$params.min",
                    Cause::Unusable,
                    "$params.min is \"s\", which isn't a number",
                ),
                item("item 2 of xs", Cause::Absent, vec![missing("v")]),
            ],
            vec![
                "$params.min is \"s\", which isn't a number",
                "item 2 of xs: v is missing",
            ],
        ),
        (
            items_of("cs", 1, 2, || items_of("rs", 1, 2, || vec![missing("ok")])),
            vec![
                "item 1 of cs: item 1 of rs: ok is missing",
                "item 1 of cs: item 2 of rs: ok is missing",
                "item 2 of cs: item 1 of rs: ok is missing",
                "item 2 of cs: item 2 of rs: ok is missing",
            ],
        ),
        (
            items_of("xs", 1, 5, || vec![missing("x.v"), missing("x.w")]),
            vec![
                "item 1 of xs: x.v is missing, and x.w is missing",
                "item 2 of xs: x.v is missing, and x.w is missing",
                "item 3 of xs: x.v is missing, and x.w is missing",
                "item 4 of xs: x.v is missing, and x.w is missing",
                "item 5 of xs: x.v is missing, and x.w is missing",
            ],
        ),
        (
            vec![
                missing("$params.q"),
                missing("pr.z"),
                item("item 2 of xs", Cause::Absent, vec![missing("aa")]),
                item("item 2 of xs", Cause::Absent, vec![missing("b")]),
            ],
            vec![
                "$params.q is missing",
                "pr.z is missing",
                "item 2 of xs: aa is missing",
                "item 2 of xs: b is missing",
            ],
        ),
        (
            vec![
                root("pr.l", Cause::Unusable, "pr.l is \"s\", which isn't a list"),
                null("$params.l"),
                item("item 1 of xs", Cause::Absent, vec![missing("w")]),
            ],
            vec![
                "pr.l is \"s\", which isn't a list",
                "$params.l is null",
                "item 1 of xs: w is missing",
            ],
        ),
        (
            vec![
                unread(
                    "item 2 of $params.envs",
                    Cause::Unusable,
                    "item 2 of $params.envs is null, which isn't an object",
                ),
                item(
                    "item 3 of $params.envs",
                    Cause::Absent,
                    vec![missing("name")],
                ),
                unread(
                    "item 4 of $params.envs",
                    Cause::Unusable,
                    "item 4 of $params.envs is 3, which isn't an object",
                ),
                item(
                    "item 5 of $params.envs",
                    Cause::Absent,
                    vec![missing("name")],
                ),
                item(
                    "item 6 of $params.envs",
                    Cause::Absent,
                    vec![missing("name")],
                ),
            ],
            vec![
                "item 2 of $params.envs is null, which isn't an object",
                "item 3 of $params.envs: name is missing",
                "item 4 of $params.envs is 3, which isn't an object",
                "item 5 of $params.envs: name is missing",
                "item 6 of $params.envs: name is missing",
            ],
        ),
        (
            with(
                vec![item(
                    "item 1 of xs",
                    Cause::Absent,
                    vec![
                        item("item 2 of ys", Cause::Absent, vec![missing("n")]),
                        item("item 3 of ys", Cause::Null, vec![null("n")]),
                    ],
                )],
                items_of("xs", 2, 4, || vec![missing("ys")]),
            ),
            vec![
                "item 1 of xs: item 2 of ys: n is missing",
                "item 1 of xs: item 3 of ys: n is null",
                "item 2 of xs: ys is missing",
                "item 3 of xs: ys is missing",
                "item 4 of xs: ys is missing",
            ],
        ),
        (
            vec![item(
                "item 1 of ws",
                Cause::Unusable,
                vec![
                    unread(
                        "item 2 of items",
                        Cause::Unusable,
                        "item 2 of items is null, which isn't an object",
                    ),
                    missing("cov.x"),
                ],
            )],
            vec![
                "item 1 of ws: item 2 of items is null, which isn't an object",
                "item 1 of ws: cov.x is missing",
            ],
        ),
        (
            vec![
                root(
                    "$params",
                    Cause::NotAnObject,
                    "$params is 3, which isn't an object",
                ),
                read(Kind::List, "es", Cause::Absent, "es is missing"),
            ],
            vec!["$params is 3, which isn't an object", "es is missing"],
        ),
        (
            vec![
                root(
                    "za",
                    Cause::Unusable,
                    "za is 3, which isn't a list or an object",
                ),
                root(
                    "zb",
                    Cause::Unusable,
                    "zb is \"s\", which isn't a list or an object",
                ),
            ],
            vec![
                "za is 3, which isn't a list or an object",
                "zb is \"s\", which isn't a list or an object",
            ],
        ),
        (
            with(
                vec![missing("$params.k"), missing("$params.k")],
                items_of("es", 1, 5, || vec![missing("m")]),
            ),
            vec![
                "$params.k is missing",
                "$params.k is missing",
                "item 1 of es: m is missing",
                "item 2 of es: m is missing",
                "item 3 of es: m is missing",
                "item 4 of es: m is missing",
                "item 5 of es: m is missing",
            ],
        ),
        (
            vec![root("x", Cause::Value, "x is \"a; y is 1, which isn't b\"")],
            vec!["x is \"a; y is 1, which isn't b\""],
        ),
        (
            vec![missing("zz"), null("x")],
            vec!["zz is missing", "x is null"],
        ),
        (
            vec![
                item(
                    "item 1 of lst",
                    Cause::Value,
                    vec![root("l.x", Cause::Value, "l.x is 5")],
                ),
                unread(
                    "item 2 of lst",
                    Cause::Unusable,
                    "item 2 of lst is null, which isn't an object",
                ),
                unread(
                    "item 3 of lst",
                    Cause::Unusable,
                    "item 3 of lst is 5, which isn't an object",
                ),
                item(
                    "item 4 of lst",
                    Cause::Value,
                    vec![root("l.x", Cause::Value, "l.x is 6")],
                ),
            ],
            vec![
                "item 1 of lst: l.x is 5",
                "item 2 of lst is null, which isn't an object",
                "item 3 of lst is 5, which isn't an object",
                "item 4 of lst: l.x is 6",
            ],
        ),
        (
            vec![
                null("$params.k"),
                item("item 2 of es", Cause::Absent, vec![missing("m")]),
                item("item 3 of es", Cause::Absent, vec![missing("zz")]),
                item("item 4 of es", Cause::Null, vec![null("m")]),
                item("item 5 of es", Cause::Absent, vec![missing("m")]),
            ],
            vec![
                "$params.k is null",
                "item 2 of es: m is missing",
                "item 3 of es: zz is missing",
                "item 4 of es: m is null",
                "item 5 of es: m is missing",
            ],
        ),
        (
            vec![item(
                "item 1 of xs",
                Cause::Value,
                (1..=4)
                    .map(|n| {
                        unread(
                            &format!("item {n} of x.ns"),
                            Cause::Value,
                            &format!("item {n} of x.ns is {}", n + 1),
                        )
                    })
                    .collect(),
            )],
            vec![
                "item 1 of xs: item 1 of x.ns is 2",
                "item 1 of xs: item 2 of x.ns is 3",
                "item 1 of xs: item 3 of x.ns is 4",
                "item 1 of xs: item 4 of x.ns is 5",
            ],
        ),
    ];
    for (clauses, strings) in rows {
        let strings: Vec<String> = strings.into_iter().map(str::to_string).collect();
        assert_eq!(
            text(&shown(&clauses)),
            crate::ops::message::joined(strings.clone()),
            "{strings:?}"
        );
    }
}

#[test]
fn and_n_more_comes_after_the_roots_and_the_lists_in_a_count() {
    let mut clauses: Vec<Clause> = (1..=5)
        .map(|n| {
            item(
                &format!("item {n} of xs"),
                Cause::Absent,
                vec![missing("v")],
            )
        })
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
fn a_list_isnt_counted_and_comes_after_the_items_of_an_earlier_group() {
    let es = |n: usize| {
        item(
            &format!("item {n} of es"),
            Cause::Value,
            vec![root("zz", Cause::Value, &format!("zz is {}", n + 1))],
        )
    };
    let list = |name: &str| read(Kind::List, name, Cause::Null, &format!("{name} is null"));
    assert_eq!(
        text(&shown(&with(
            (1..=4).map(es).collect(),
            vec![list("ks").in_group(1)]
        ))),
        "item 1 of es: zz is 2; item 2 of es: zz is 3; item 3 of es: zz is 4; ks is null; and 1 more"
    );
    assert_eq!(
        text(&shown(&with(vec![list("ks")], (1..=3).map(es).collect()))),
        "ks is null; item 1 of es: zz is 2; item 2 of es: zz is 3; item 3 of es: zz is 4"
    );
}

#[test]
fn a_problem_two_clauses_say_alike_is_said_once() {
    let empty = || read(Kind::List, "x.ys", Cause::Value, "x.ys is []");
    let told = Clause {
        said: vec![root("es is null", Cause::Null, "es is null")],
        ..read(Kind::List, "es", Cause::Null, "es is null")
    };
    let clauses = vec![
        told,
        read(Kind::List, "es", Cause::Null, "es is null").in_group(1),
        item(
            "item 1 of xs",
            Cause::Value,
            vec![
                Clause {
                    said: vec![root("x.ys is []", Cause::Value, "x.ys is []")],
                    ..empty()
                },
                empty(),
            ],
        ),
        item(
            "item 2 of xs",
            Cause::Null,
            vec![
                root("x", Cause::Null, "x is null"),
                root("x is null", Cause::Null, "x is null"),
            ],
        ),
    ];
    assert_eq!(
        text(&shown(&clauses)),
        "es is null; item 1 of xs: x.ys is []; item 2 of xs: x is null"
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
        root(
            "w.z",
            Cause::Unusable,
            "w.z is \"p; q\", which isn't a number",
        ),
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

#[test]
fn roots_of_a_later_sentence_come_after_the_roots_of_an_earlier_one() {
    let clauses = vec![
        missing("$params.b").in_group(1),
        root(
            "$params.a",
            Cause::Unusable,
            "$params.a is \"s\", which isn't a number",
        )
        .in_group(2),
    ];
    assert_eq!(
        text(&shown(&clauses)),
        "$params.b is missing; $params.a is \"s\", which isn't a number"
    );
}

#[test]
fn a_sentences_items_come_before_what_a_later_sentence_says() {
    let es = item(
        "item 1 of es",
        Cause::Value,
        vec![root("zz", Cause::Value, "zz is 2")],
    );
    let z = || root("z is 2", Cause::Value, "z is 2");
    assert_eq!(
        text(&shown(&[es.clone(), z().in_group(1)])),
        "item 1 of es: zz is 2; z is 2"
    );
    assert_eq!(
        text(&shown(&[es.in_group(1), z()])),
        "z is 2; item 1 of es: zz is 2"
    );
}

#[test]
fn a_root_two_sentences_say_is_said_once_in_the_first() {
    let clauses = vec![
        missing("zz").in_group(1),
        null("$params.a").in_group(2),
        missing("zz").in_group(2),
        root(
            "$params.c",
            Cause::Unusable,
            "$params.c is 3, which isn't text",
        )
        .in_group(2),
    ];
    assert_eq!(
        text(&shown(&clauses)),
        "zz is missing; $params.c is 3, which isn't text; $params.a is null"
    );
}

#[test]
fn an_items_own_part_beside_the_items_under_it_isnt_counted() {
    let clauses: Vec<Clause> = (1..=5)
        .map(|n| {
            let review = if n == 1 { 2 } else { 1 };
            item(
                &format!("item {n} of cs"),
                Cause::Value,
                vec![
                    item(
                        &format!("item {review} of c.reviews"),
                        Cause::Value,
                        vec![root("ok", Cause::Value, "ok is false")],
                    ),
                    root("c.a", Cause::Value, "c.a is 2"),
                ],
            )
        })
        .collect();
    assert_eq!(
        text(&shown(&clauses)),
        "item 1 of cs: item 2 of c.reviews: ok is false; item 1 of cs: c.a is 2; item 2 of cs: item 1 of c.reviews: ok is false; item 2 of cs: c.a is 2; item 3 of cs: item 1 of c.reviews: ok is false; item 3 of cs: c.a is 2; and 2 more"
    );
}

#[test]
fn clauses_come_back_whole_from_a_record() {
    let clauses = vec![
        root(
            "w.z",
            Cause::Unusable,
            "w.z is \"p; q\", which isn't a number",
        )
        .in_group(2),
        read(Kind::List, "ys", Cause::Absent, "ys is missing"),
        item(
            "item 1 of ws",
            Cause::Null,
            vec![
                unread(
                    "item 2 of items",
                    Cause::NotAnObject,
                    "item 2 of items is null, which isn't an object",
                ),
                null("cov.x"),
            ],
        ),
        Clause {
            kind: Kind::More(2),
            ..read(Kind::Root, "", Cause::Value, "")
        },
    ];
    let record = serde_json::json!({ "ergo/clauses": to_value(&clauses) });
    assert_eq!(of_value(&record["ergo/clauses"]), Some(clauses));
}

#[test]
fn clauses_that_cant_be_read_back_give_nothing() {
    let whole = to_value(&[missing("v").in_group(1)]);
    let mut wrong_cause = whole.clone();
    wrong_cause[0]["cause"] = serde_json::json!("lost");
    let mut no_group = whole.clone();
    no_group[0]
        .as_object_mut()
        .map(|clause| clause.remove("group"));
    let mut said_not_a_list = whole.clone();
    said_not_a_list[0]["said"] = serde_json::json!("v is missing");
    for value in [
        serde_json::Value::Null,
        serde_json::json!({}),
        serde_json::json!(["v is missing"]),
        wrong_cause,
        no_group,
        said_not_a_list,
    ] {
        assert_eq!(of_value(&value), None, "{value}");
    }
    assert!(of_value(&whole).is_some());
}
