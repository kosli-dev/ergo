mod support;

use ergo_sentences::*;
use support::*;

#[test]
fn a_walk_item_has_a_quantifier_a_path_and_an_alias() {
    assert_eq!(
        for_line("every items.x as i").items,
        vec![ForItem::Walk {
            quantifier: Quantifier::Every,
            path: with_steps(key("items"), vec![dot("x")]),
            whose: vec![],
            if_any: false,
            alias: "i".into()
        }]
    );
}

#[test]
fn a_walk_item_keeps_its_whose_and_if_any() {
    let read = for_line("some items whose k is 1 and j exists, if any, as it_1");
    match &read.items[0] {
        ForItem::Walk {
            quantifier,
            whose,
            if_any,
            alias,
            ..
        } => {
            assert_eq!(*quantifier, Quantifier::Some);
            assert_eq!(whose.len(), 2);
            assert!(*if_any);
            assert_eq!(alias, "it_1");
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_pick_item_has_a_position_a_path_whose_and_sorted_by() {
    assert_eq!(
        for_line("item 2 from last of items.x whose k is 1 sorted by created alphabetically as l")
            .items,
        vec![ForItem::Pick {
            position: Position::Item {
                number: "2".into(),
                from_last: true
            },
            path: with_steps(key("items"), vec![dot("x")]),
            whose: vec![Condition {
                left: Left::Path(key("k")),
                phrase: Phrase::Is {
                    not: false,
                    operand: value(number("1")),
                    within: None
                }
            }],
            sorted_by: Some(SortedBy {
                path: key("created"),
                alphabetically: true
            }),
            alias: "l".into()
        }]
    );
    assert!(matches!(
        &for_line("first of items as f").items[0],
        ForItem::Pick {
            position: Position::First,
            sorted_by: None,
            ..
        }
    ));
    assert!(matches!(
        &for_line("last of items sorted by k as f").items[0],
        ForItem::Pick {
            sorted_by: Some(SortedBy {
                alphabetically: false,
                ..
            }),
            ..
        }
    ));
}

#[test]
fn a_for_line_holds_one_or_two_items() {
    assert_eq!(
        for_line("every items as i, last of other as j").items.len(),
        2
    );
    assert_eq!(
        for_failure("every items as i, some other as j, every third as k"),
        vec!["a for line holds two items at most"]
    );
}

#[test]
fn the_comma_between_items_needs_a_space_after_it() {
    assert!(parse_for("every items as i, some other as j").is_ok());
    assert!(parse_for("every items as i,  some other as j").is_ok());
    assert!(parse_for("every items as i,some other as j").is_err());
    assert!(parse_for("every items as i , some other as j").is_err());
}

#[test]
fn the_if_any_comma_is_not_the_comma_between_items() {
    let read = for_line("every items, if any, as i, some other, if any, as j");
    assert_eq!(read.items.len(), 2);
}

#[test]
fn an_alias_is_a_bare_key_and_may_be_a_word_in_the_tree() {
    assert!(parse_for("every items as empty").is_ok());
    assert!(parse_for("every items as 1x").is_err());
    assert!(parse_for("every items as .x").is_err());
    assert!(parse_for("every items as \"x\"").is_err());
    assert!(parse_for("every items as").is_err());
    assert!(parse_for("every items as i j").is_err());
}

#[test]
fn a_walk_path_may_start_with_a_position() {
    let read = for_line("every first of items as i");
    match &read.items[0] {
        ForItem::Walk { path, .. } => assert_eq!(path.position, Some(Position::First)),
        other => panic!("{other:?}"),
    }
}

#[test]
fn sorted_by_takes_a_field_of_the_item() {
    assert!(parse_for("last of items sorted by \"a b\".c as l").is_ok());
    assert!(parse_for("last of items sorted by .empty as l").is_ok());
    assert!(parse_for("last of items sorted by $params.x as l").is_err());
    assert!(parse_for("last of items sorted by first of x as l").is_err());
    assert!(parse_for("last of items sorted by empty as l").is_err());
    assert!(parse_for("every items sorted by k as l").is_err());
    assert!(parse_for("last of items sorted by k as l, first of other whose j is 1 sorted by m alphabetically as n").is_ok());
}

#[test]
fn the_path_of_a_pick_has_no_position_of_its_own() {
    assert!(parse_for("last of first of items as l").is_err());
}

#[test]
fn a_for_line_fails_with_the_item_messages_first() {
    assert_eq!(
        for_failure("items as i"),
        vec!["an item starts with \"every\", \"some\" or a position, like \"last of\""]
    );
    assert_eq!(
        for_failure("every items"),
        vec!["an item ends with \"as\" and a name, like \"every pull_requests as pr\""]
    );
    assert_eq!(
        for_failure("every items as i,"),
        vec!["an item ends with \"as\" and a name, like \"every pull_requests as pr\""]
    );
}

#[test]
fn a_for_line_otherwise_fails_as_a_check_does() {
    assert_eq!(
        parse_for("every items as \"i").unwrap_err()[0].message,
        "unclosed quote at column 16"
    );
    assert_eq!(
        parse_for("every items whose k is \"a as i").unwrap_err()[0].message,
        "unclosed quote at column 24"
    );
    assert_eq!(
        for_failure("every items whose k is $z j as i"),
        vec!["doesn't parse"]
    );
    assert_eq!(
        for_failure("every items whose empty is 1 as i"),
        vec!["empty is a word of the grammar: write .empty"]
    );
    assert_eq!(
        for_failure("every items whose k is 1 j as i"),
        vec!["doesn't parse"]
    );
}

#[test]
fn a_for_line_prints_its_items_joined_by_a_comma() {
    for line in [
        "every items as i",
        "some items whose k is 1 and j exists, if any, as i",
        "last of items as l",
        "item 3 of items.x whose k is 1 as t",
        "item 2 from last of items sorted by created as t",
        "first of items sorted by created alphabetically as f",
        "every items as i, last of other as j",
    ] {
        assert_eq!(printed_for(line), line);
    }
}

#[test]
fn a_for_line_prints_in_canonical_spacing() {
    assert_eq!(
        printed_for("  every   items  as   i ,".trim_end_matches(" ,")),
        "every items as i"
    );
    assert_eq!(
        printed_for("every items as i,    last   of   other  as j"),
        "every items as i, last of other as j"
    );
}

#[test]
fn a_for_line_keeps_the_dot_of_a_field_called_like_an_alias() {
    let read = for_line("every items as pr, every other whose pr equals .pr as j");
    assert_eq!(
        print_for(&read, &[]),
        "every items as pr, every other whose pr equals .pr as j"
    );
    let read = for_line("last of items sorted by .l as l");
    assert_eq!(print_for(&read, &[]), "last of items sorted by .l as l");
    assert_eq!(
        print_for_item(&read.items[0], &["l"]),
        "last of items sorted by .l as l"
    );
    assert_eq!(
        print_for_item(&read.items[0], &[]),
        "last of items sorted by l as l"
    );
    let plain = for_line("last of items sorted by .m as l");
    assert_eq!(print_for(&plain, &[]), "last of items sorted by m as l");
}

#[test]
fn a_sorted_by_path_prints_its_brackets() {
    assert_eq!(
        printed_for("last of items sorted by x[0] as l"),
        "last of items sorted by x[0] as l"
    );
    assert_eq!(printed_for("last of x[2] as l"), "last of x[2] as l");
}

#[test]
fn print_assertion_prints_one_assertion() {
    let read = check("every items whose k is 1 is empty and y exists");
    assert_eq!(
        print_assertion(&read.assertions[0], &[]),
        "every items whose k is 1 is empty"
    );
    assert_eq!(print_assertion(&read.assertions[1], &[]), "y exists");
}

#[test]
fn print_check_keeps_the_dot_of_an_alias_on_the_right() {
    let read = check("x equals .pr and y equals pr");
    assert_eq!(print_check(&read, &["pr"]), "x equals .pr and y equals pr");
    assert_eq!(print_check(&read, &[]), "x equals pr and y equals pr");
}

#[test]
fn a_long_for_line_does_not_make_the_reader_slow() {
    let whose: Vec<String> = (0..60).map(|n| format!("k{n} is {n}")).collect();
    let line = format!(
        "every items whose {} as i, last of other as j",
        whose.join(" and ")
    );
    assert_eq!(for_line(&line).items.len(), 2);
    assert_eq!(
        for_failure(&format!("{line}, ")),
        vec!["an item ends with \"as\" and a name, like \"every pull_requests as pr\""]
    );
}

#[test]
fn a_for_line_with_an_unknown_name_reads_and_is_written_wrong() {
    let line = for_line("every items whose k is $z as i");
    assert_eq!(for_problems(&line, &[]), vec!["unknown name $z"]);
}
