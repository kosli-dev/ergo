use super::*;
use serde_json::json;

fn path(text: &str) -> s::Path {
    s::parse_path(text).unwrap()
}

fn key(text: &str) -> Step {
    Step::Key(text.to_string())
}

fn it(position: Option<s::Position>) -> s::Path {
    s::Path {
        position,
        start: s::Start::That,
        steps: Vec::new(),
    }
}

fn lowered(scope: &Scope, text: &str) -> path::Path {
    scope.path(&path(text)).unwrap()
}

fn part(steps: &[&str], id: Option<&[&str]>) -> PartDef {
    PartDef {
        steps: steps.iter().map(|k| key(k)).collect(),
        id: id.map(|ids| ids.iter().map(|k| key(k)).collect()),
    }
}

fn scope() -> Scope {
    Scope::new()
        .with_part("cov", part(&["d", "b"], Some(&["id"])))
        .with_parent(
            "artifact",
            BTreeMap::from([("att".to_string(), part(&["a", "t"], None))]),
        )
        .with_for_alias("pr")
}

#[test]
fn a_bare_first_key_is_a_field_of_the_subject() {
    let p = lowered(&Scope::new(), "a1.b");
    assert_eq!(p.start, Start::Subject);
    assert_eq!(p.steps, [key("a1"), key("b")]);
}

#[test]
fn it_is_the_subject_and_params_and_input_start_there() {
    let p = Scope::new().path(&it(None)).unwrap();
    assert_eq!((p.start, p.steps), (Start::Subject, vec![]));
    let p = lowered(&Scope::new(), "$params.k.j");
    assert_eq!(
        (p.start, p.steps),
        (Start::Params, vec![key("k"), key("j")])
    );
    let p = lowered(&Scope::new(), "$input.k");
    assert_eq!((p.start, p.steps), (Start::Input, vec![key("k")]));
}

#[test]
fn a_dot_always_reads_a_field_even_when_an_alias_has_the_name() {
    let p = lowered(&scope(), ".cov.x");
    assert_eq!(p.start, Start::Own);
    assert_eq!(p.steps, [key("cov"), key("x")]);
    let p = lowered(&scope(), ".artifact.x");
    assert_eq!(p.start, Start::Own);
    assert_eq!(p.steps, [key("artifact"), key("x")]);
    let p = lowered(&scope(), ".pr.x");
    assert_eq!(p.start, Start::Own);
    let p = lowered(&scope(), ".free.x");
    assert_eq!(p.start, Start::Subject);
    let p = lowered(&Scope::new(), ".empty");
    assert_eq!(p.steps, [key("empty")]);
}

#[test]
fn a_part_alias_starts_at_the_part_with_its_id() {
    let p = lowered(&scope(), "cov.x");
    let Start::Part(found) = p.start else {
        panic!("not a part");
    };
    assert_eq!(found.name, "cov");
    assert_eq!(found.base, Start::Subject);
    assert_eq!(found.steps, [key("d"), key("b")]);
    assert_eq!(found.id, Some(vec![key("id")]));
    assert_eq!(p.steps, [key("x")]);
}

#[test]
fn a_parent_name_starts_at_the_parent_and_a_part_of_it_at_the_part() {
    let p = lowered(&scope(), "artifact.owner");
    assert_eq!(p.start, Start::Alias("artifact".into()));
    assert_eq!(p.steps, [key("owner")]);
    let p = lowered(&scope(), "artifact.att.n");
    let Start::Part(found) = p.start else {
        panic!("not a part");
    };
    assert_eq!(found.name, "artifact.att");
    assert_eq!(found.base, Start::Alias("artifact".into()));
    assert_eq!(p.steps, [key("n")]);
    let p = lowered(&scope(), "artifact");
    assert_eq!(
        (p.start, p.steps),
        (Start::Alias("artifact".into()), vec![])
    );
}

#[test]
fn a_for_alias_starts_at_the_alias() {
    let p = lowered(&scope(), "pr.author");
    assert_eq!(p.start, Start::Alias("pr".into()));
}

#[test]
fn the_left_of_a_condition_reads_parts_but_never_parents_or_for_aliases() {
    let left = |text: &str| scope().left_path(&path(text)).unwrap();
    assert!(matches!(left("cov.x").start, Start::Part(_)));
    let p = left("artifact.owner");
    assert_eq!(p.start, Start::Own);
    assert_eq!(p.steps, [key("artifact"), key("owner")]);
    assert_eq!(left("pr.author").start, Start::Own);
    assert_eq!(left("free.author").start, Start::Subject);
    assert!(matches!(left(".cov.x").start, Start::Own));
}

#[test]
fn steps_read_keys_brackets_indexes_and_refs() {
    let p = lowered(&Scope::new(), "a1.\"b c\"[\"k\"][2].d");
    assert_eq!(
        p.steps,
        [key("a1"), key("b c"), key("k"), Step::Index(2), key("d")]
    );
    let p = lowered(&Scope::new(), "m named by $params.k.v");
    assert_eq!(
        p.steps,
        [
            key("m"),
            Step::Ref(Box::new(path::Path {
                start: Start::Params,
                steps: vec![key("k")]
            })),
            key("v")
        ]
    );
    let p = lowered(&Scope::new(), "m[$input.k]");
    assert!(matches!(&p.steps[1], Step::Ref(r) if r.start == Start::Input));
}

#[test]
fn a_bare_name_after_named_by_is_a_field_step_unless_an_alias_has_the_name() {
    let p = lowered(&Scope::new(), "m named by sev");
    assert!(matches!(&p.steps[1], Step::Field(f) if f.steps == [key("sev")]));
    let p = lowered(&scope(), "m named by pr");
    assert!(matches!(&p.steps[1], Step::Ref(r) if r.start == Start::Alias("pr".into())));
}

#[test]
fn named_by_a_part_alias_is_written_wrong() {
    assert_eq!(
        scope().path(&path("m named by cov")).unwrap_err(),
        ["named by cov reads a part, which isn't supported yet"]
    );
}

#[test]
fn positions_become_a_last_step_counting_from_zero() {
    assert_eq!(
        lowered(&Scope::new(), "first of xs").steps,
        [key("xs"), Step::Index(0)]
    );
    assert_eq!(
        lowered(&Scope::new(), "item 3 of xs.ys").steps,
        [key("xs"), key("ys"), Step::Index(2)]
    );
    let p = Scope::new().path(&it(Some(s::Position::First))).unwrap();
    assert_eq!(p.steps, [Step::Index(0)]);
}

#[test]
fn a_last_position_and_one_counted_from_the_end_are_not_read_yet() {
    for text in ["last of xs", "item 2 from last of xs"] {
        let problems = Scope::new().path(&path(text)).unwrap_err();
        assert_eq!(
            problems,
            [
                "last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""
            ]
        );
    }
}

#[test]
fn a_position_past_the_largest_a_float_holds_is_written_wrong() {
    let mut written = path("xs");
    written
        .steps
        .push(s::Step::Index("9007199254740992".to_string()));
    assert_eq!(
        Scope::new().path(&written).unwrap_err(),
        ["9007199254740992 can't be a list position"]
    );
    let picked = s::Position::Item {
        number: "9007199254740992".to_string(),
        from_last: false,
    };
    assert_eq!(
        Scope::new().path(&it(Some(picked))).unwrap_err(),
        ["9007199254740992 can't be a list position"]
    );
    assert_eq!(
        lowered(&Scope::new(), "xs[9007199254740991]").steps,
        [key("xs"), Step::Index(9_007_199_254_740_991)]
    );
    let zero = s::Position::Item {
        number: "0".to_string(),
        from_last: false,
    };
    assert!(Scope::new().path(&it(Some(zero))).is_err());
}

#[test]
fn the_aliases_a_scope_knows_are_listed_sorted_and_once() {
    assert_eq!(scope().aliases(), ["artifact", "cov", "pr"]);
    assert_eq!(scope().parts().keys().collect::<Vec<_>>(), ["cov"]);
}

#[test]
fn a_part_path_keeps_its_first_key_and_rejects_params_input_and_that() {
    let steps = part_steps(&path("d.b[1]")).unwrap();
    assert_eq!(steps, [key("d"), key("b"), Step::Index(1)]);
    assert_eq!(
        part_steps(&path("$params.x")).unwrap_err(),
        ["a part reads inside its subject, so it can't start at $params or $input"]
    );
    assert_eq!(
        part_steps(&path("$input.x")).unwrap_err(),
        ["a part reads inside its subject, so it can't start at $params or $input"]
    );
    assert_eq!(
        part_steps(&it(None)).unwrap_err(),
        ["that can only start a condition: write that first, like that is not empty"]
    );
    assert_eq!(
        part_steps(&path("a1 named by foo")).unwrap_err(),
        ["unknown alias foo"]
    );
}

#[test]
fn values_keep_their_type_and_numbers_as_they_were_written() {
    let scope = Scope::new();
    assert_eq!(
        scope.value(&s::Value::String("a".into())).unwrap(),
        json!("a")
    );
    assert_eq!(scope.value(&s::Value::True).unwrap(), json!(true));
    assert_eq!(scope.value(&s::Value::False).unwrap(), json!(false));
    assert_eq!(scope.value(&s::Value::Null).unwrap(), Value::Null);
    let number = scope.value(&s::Value::Number("1.50".into())).unwrap();
    assert_eq!(number.to_string(), "1.50");
    let number = scope.value(&s::Value::Number("1e2".into())).unwrap();
    assert_eq!(crate::value::equal(&number, &json!(100)), Some(true));
}

#[test]
fn a_number_a_float_cannot_hold_is_written_wrong() {
    let scope = Scope::new();
    for text in ["1e400", "-1e400", "1e-400"] {
        assert_eq!(
            scope.value(&s::Value::Number(text.into())).unwrap_err(),
            [format!("number out of range: {text}")],
            "{text}"
        );
    }
    for text in [
        "0",
        "0.0",
        "-0",
        "2.22507385850721e-308",
        "1.79769313486231e308",
        "0e500",
        "1.50000000000000000000",
    ] {
        assert!(
            scope.value(&s::Value::Number(text.into())).is_ok(),
            "{text}"
        );
    }
}

#[test]
fn a_number_with_more_than_15_significant_digits_is_written_wrong() {
    let scope = Scope::new();
    for text in [
        "1234567890.1209567890",
        "12345678901234567890",
        "2.2250738585072014e-308",
        "1.7976931348623157e308",
    ] {
        assert_eq!(
            scope.value(&s::Value::Number(text.into())).unwrap_err(),
            [format!(
                "number with more than 15 significant digits: {text}"
            )],
            "{text}"
        );
    }
}

fn condition(text: &str) -> s::Condition {
    let line = s::parse_from(&format!("xs whose {text}")).unwrap();
    match line.whose.into_iter().next().unwrap() {
        s::FromCondition::Condition(condition) => condition,
        other => panic!("{other:?}"),
    }
}

#[test]
fn exists_and_does_not_exist_lower_to_present_and_missing() {
    let Check::Present(found) = lower_condition(&condition("x exists"), &Scope::new()).unwrap()
    else {
        panic!("not present");
    };
    assert!(!found.missing);
    assert_eq!(found.path.steps, [key("x")]);
    let Check::Present(found) =
        lower_condition(&condition("x does not exist"), &Scope::new()).unwrap()
    else {
        panic!("not present");
    };
    assert!(found.missing);
}

#[test]
fn the_left_side_of_a_condition_is_read_without_parents() {
    let Check::Present(found) = lower_condition(&condition("artifact.x exists"), &scope()).unwrap()
    else {
        panic!("not present");
    };
    assert_eq!(found.path.start, Start::Own);
    assert_eq!(found.path.steps, [key("artifact"), key("x")]);
}

#[test]
fn a_problem_in_the_path_of_a_condition_comes_back() {
    assert_eq!(
        lower_condition(&condition("xs[9007199254740992] exists"), &Scope::new()).unwrap_err(),
        ["9007199254740992 can't be a list position"]
    );
}

#[test]
fn a_count_or_a_plus_on_the_right_of_a_from_condition_is_read_into_a_tally() {
    for text in [
        "x is at least count of ys",
        "x equals y plus 1",
        "x is less than sum of ys.n",
    ] {
        assert!(
            matches!(
                lower_condition(&condition(text), &Scope::new()),
                Ok(Check::Tally(_))
            ),
            "{text}"
        );
    }
}

#[test]
fn a_count_on_the_left_of_a_from_condition_never_reads_a_parent() {
    let Ok(Check::Tally(found)) =
        lower_condition(&condition("count of artifact.xs is at least 1"), &scope())
    else {
        panic!("not a tally");
    };
    let paths = found.paths();
    assert_eq!(paths[0].start, Start::Own);
    assert_eq!(paths[0].steps, [key("artifact"), key("xs")]);
}

#[test]
fn a_count_on_the_left_is_read_into_a_tally() {
    assert!(matches!(
        lower_condition(&condition("count of xs is at least 1"), &Scope::new()),
        Ok(Check::Tally(_))
    ));
    assert!(matches!(
        lower_condition(&condition("sum of xs.n is between 1 and 2"), &Scope::new()),
        Ok(Check::Tally(_))
    ));
}

#[test]
fn a_walk_counts_each_name_and_position_but_not_input_or_params() {
    let steps = |text: &str| walk_steps(&Scope::new().on_subject().path(&path(text)).unwrap());
    assert_eq!(steps("k1.k2.k3"), 3);
    assert_eq!(steps("first of k1.k2"), 3);
    assert_eq!(steps("$input.k1.k2"), 2);
    assert_eq!(steps("$params.k1"), 1);
}

#[test]
fn a_walk_of_ten_steps_reads_and_one_of_eleven_is_written_wrong() {
    let ten = path::Path {
        start: Start::Subject,
        steps: (1..=10).map(|n| Step::Key(format!("k{n}"))).collect(),
    };
    assert_eq!(walk_too_long(&ten), None);
    let mut eleven = ten.clone();
    eleven.steps.push(Step::Key("k11".into()));
    assert_eq!(
        walk_too_long(&eleven).as_deref(),
        Some("every and some over more than ten steps aren't supported yet")
    );
}

#[test]
fn an_alias_is_a_step_and_a_part_counts_its_own_path_in_place_of_its_alias() {
    let alias = path::Path {
        start: Start::Alias("z".into()),
        steps: (1..=10).map(|n| Step::Key(format!("k{n}"))).collect(),
    };
    assert_eq!(walk_steps(&alias), 11);
    let part = path::Path {
        start: Start::Part(Box::new(PartStart {
            name: "x".into(),
            base: Start::Subject,
            steps: (1..=10).map(|n| Step::Key(format!("k{n}"))).collect(),
            id: None,
        })),
        steps: vec![Step::Key("z".into())],
    };
    assert_eq!(walk_steps(&part), 11);
}
