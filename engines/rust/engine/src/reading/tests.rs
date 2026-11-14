use super::*;
use crate::SPEC;
use serde_json::json;

fn reading(subjects: Value) -> (Policy, Reading) {
    let policy = Policy::read(&json!({
        "ergo_spec": SPEC,
        "subjects": subjects,
        "requirements": {}
    }));
    let reading = Reading::of(&policy);
    (policy, reading)
}

fn problem_names(reading: &Reading, subject: &str) -> Vec<String> {
    reading.infos[subject].problems.keys().cloned().collect()
}

fn texts(reading: &Reading, subject: &str, at: &str) -> Vec<String> {
    reading.infos[subject].problems[at]
        .iter()
        .cloned()
        .collect()
}

#[test]
fn a_plain_from_is_a_root_read_from_the_input() {
    let (_, r) = reading(json!({"d": {"from": "data.deployments"}}));
    let lowered = r.lowered("d").unwrap();
    assert_eq!(lowered.from_text, "data.deployments");
    assert!(matches!(lowered.source, Source::Root { every: false, .. }));
}

#[test]
fn a_whose_dot_on_a_field_named_like_the_subject_stays_in_the_from_text() {
    let policy = json!({
        "ergo_spec": SPEC,
        "subjects": {"kid": {"from": "every kids whose .kid is 1"}},
        "requirements": {"r": {"subject": "kid", "checks": {"c": ".x is 1"}}}
    });
    let input = json!({"kids": [{"kid": 1, "x": 1}, {"kid": 2, "x": 1}, {"x": 1}]});
    let report = crate::report(&input, &policy, &json!({}));
    let applies: Vec<(String, String)> = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["check"] == "$applies" && row["cause"] != "satisfied")
        .map(|row| {
            (
                row["cause"].as_str().unwrap().to_string(),
                row["message"].as_str().unwrap().to_string(),
            )
        })
        .collect();
    assert_eq!(
        applies,
        [
            ("value".to_string(), ".kid is 2".to_string()),
            ("absent".to_string(), ".kid is missing".to_string())
        ]
    );
    let checked = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["check"] == "c")
        .map(|row| row["passed"].clone())
        .collect::<Vec<_>>();
    assert_eq!(checked, [json!(true)]);
}

#[test]
fn a_subject_with_no_from_reads_the_input_field_of_its_own_name() {
    let (_, r) = reading(json!({"artifact": null, "pull request": {}}));
    assert_eq!(r.lowered("artifact").unwrap().from_text, "artifact");
    assert_eq!(
        r.lowered("pull request").unwrap().from_text,
        "\"pull request\""
    );
}

#[test]
fn a_from_that_is_the_input_alone_reads_the_whole_input() {
    let (_, r) = reading(json!({"art": {"from": "$input"}}));
    assert_eq!(r.lowered("art").unwrap().from_text, "$input");
}

#[test]
fn a_from_that_is_only_a_named_by_step_is_written_as_it_was() {
    let (_, r) = reading(json!({"s": {"from": "every $input named by $params.k"}}));
    assert_eq!(
        r.lowered("s").unwrap().from_text,
        "every $input named by $params.k"
    );
    let (_, r) = reading(json!({"s": {"from": "$input named by $params.k"}}));
    assert_eq!(
        r.lowered("s").unwrap().from_text,
        "$input named by $params.k"
    );
}

#[test]
fn a_line_that_does_not_parse_is_listed_under_from() {
    let (_, r) = reading(json!({"d": {"from": "deployments whose environment is \"prod"}}));
    assert_eq!(
        texts(&r, "d", "subjects.d.from"),
        ["unclosed quote at column 34"]
    );
    assert!(r.lowered("d").is_none());
    assert_eq!(r.infos["d"].entry["from"], json!("<invalid from>"));
}

#[test]
fn a_path_in_identified_by_that_does_not_parse_is_listed_under_identified_by() {
    let (_, r) = reading(json!({"d": {"from": "ds", "identified_by": "environment is"}}));
    assert_eq!(
        texts(&r, "d", "subjects.d.identified_by"),
        ["identified_by is a path, like \"id\" or \"build.number\""]
    );
}

#[test]
fn a_path_alone_names_the_subject_it_starts_at_as_a_child() {
    let (_, r) = reading(json!({"art": {"from": "arts"}, "p": {"from": "art.pulls"}}));
    assert_eq!(r.infos["p"].relation, Relation::Child("art".into()));
    assert_eq!(r.lowered("p").unwrap().from_text, "art.pulls");
}

#[test]
fn a_path_through_a_part_of_a_dollar_subject_quotes_the_subject_name() {
    let (_, r) = reading(json!({
        "$x": {"from": "things", "has": {"pa": "meta"}},
        "kid": {"from": "\"$x\".pa.items"}
    }));
    assert_eq!(r.lowered("kid").unwrap().from_text, "\"$x\".pa.items");
}

#[test]
fn a_subject_name_with_named_by_each_of_is_a_child_that_keeps_its_keys_inside_its_parent() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"},
        "k": {"from": "art named by each of $params.k"},
        "j": {"from": "first of art named by each of $params.k"},
    }));
    assert_eq!(r.infos["k"].relation, Relation::Child("art".into()));
    assert_eq!(r.infos["j"].relation, Relation::Child("art".into()));
    assert!(matches!(
        r.lowered("k").unwrap().source,
        Source::Child {
            each_of: Some(_),
            ..
        }
    ));
}

#[test]
fn a_dotted_first_key_named_like_another_subject_keeps_its_dot_in_every_printed_from() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"},
        "k": {"from": ".art named by each of $params.k"},
        "p": {"from": ".art.p"},
        "q": {"from": ".other.p"},
    }));
    assert_eq!(r.lowered("k").unwrap().from_text, ".art");
    assert_eq!(r.lowered("p").unwrap().from_text, ".art.p");
    assert_eq!(r.lowered("q").unwrap().from_text, "other.p");
    assert_eq!(
        r.infos["k"].entry["from"],
        json!(".art named by each of $params.k")
    );
    assert_eq!(r.infos["p"].entry["from"], json!(".art.p"));
    assert_eq!(r.infos["q"].entry["from"], json!("other.p"));
}

#[test]
fn a_kept_dot_goes_after_the_position_of_a_printed_from() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"},
        "p": {"from": ".art.p[0]"},
        "q": {"from": "first of .art.p"},
    }));
    assert_eq!(r.infos["p"].entry["from"], json!("item 1 of .art.p"));
    assert_eq!(r.infos["q"].entry["from"], json!("first of .art.p"));
}

#[test]
fn a_subject_name_and_nothing_more_narrows_that_subject() {
    let (_, r) = reading(
        json!({"art": {"from": "arts", "identified_by": "id"}, "b": {"from": "art whose x exists"}}),
    );
    assert_eq!(r.infos["b"].relation, Relation::Narrows("art".into()));
    assert_eq!(r.lowered("b").unwrap().filters.len(), 1);
    assert_eq!(r.infos["b"].entry["identified_by"], json!("id"));
}

#[test]
fn a_position_after_a_subjects_name_is_a_child_that_reads_the_position_and_does_not_narrow() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"},
        "a": {"from": "art[1]"},
        "b": {"from": "first of art"},
        "c": {"from": "item 2 of art"},
    }));
    for name in ["a", "b", "c"] {
        assert_eq!(r.infos[name].relation, Relation::Child("art".into()));
    }
}

#[test]
fn a_subject_called_like_its_own_from_reads_the_input_field() {
    let (_, r) = reading(json!({"lockfile": {"from": "lockfile whose status exists"}}));
    assert_eq!(r.infos["lockfile"].relation, Relation::Root);
    assert_eq!(r.lowered("lockfile").unwrap().from_text, "lockfile");
}

#[test]
fn a_dot_reads_the_field_and_not_the_subject() {
    let (_, r) = reading(json!({"art": {"from": "arts"}, "b": {"from": ".a.x"}}));
    assert_eq!(r.infos["b"].relation, Relation::Root);
}

#[test]
fn a_subject_that_narrows_a_blank_name_reports_no_id_of_its_own_nor_its_parents() {
    let (_, r) = reading(json!({
        " ": {"from": "things", "identified_by": "id"},
        "b": {"from": "\" \" whose id is \"a\""}
    }));
    assert_eq!(r.infos["b"].entry["identified_by"], Value::Null);
    assert_eq!(r.infos[" "].entry["identified_by"], json!("id"));
}

#[test]
fn a_subject_in_a_loop_lists_the_whole_loop_but_only_reads_itself() {
    let policy = Policy::read(&json!({
        "ergo_spec": SPEC,
        "subjects": {"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}},
        "requirements": {}
    }));
    let r = Reading::of(&policy);
    assert_eq!(r.listed("x"), ["x", "y"]);
    assert_eq!(r.used("x"), ["x"]);
}

#[test]
fn subjects_that_narrow_each_other_lead_to_a_loop() {
    let (_, r) =
        reading(json!({"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}}));
    assert_eq!(texts(&r, "x", "subjects.x.from"), ["leads to a loop"]);
    assert_eq!(texts(&r, "y", "subjects.y.from"), ["leads to a loop"]);
    assert!(r.lowered("x").is_none());
}

#[test]
fn a_subject_that_reaches_a_loop_leads_to_a_loop_too() {
    let (_, r) = reading(json!({"pa": {"from": "pb"}, "pb": {"from": "pa"}, "pc": {"from": "pa"}}));
    assert_eq!(texts(&r, "pc", "subjects.pc.from"), ["leads to a loop"]);
}

#[test]
fn a_chain_of_four_subjects_is_written_wrong() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"}, "b": {"from": "art.bs"}, "c": {"from": "b.cs"}, "d": {"from": "c.ds"}
    }));
    assert_eq!(
        texts(&r, "d", "subjects.d.from"),
        ["a chain of more than three subjects isn't supported yet"]
    );
    assert!(problem_names(&r, "c").is_empty());
}

#[test]
fn a_blank_subject_name_cannot_start_a_chain() {
    let (_, r) = reading(json!({" ": {"from": "things"}, "b": {"from": "\" \" whose id exists"}}));
    assert_eq!(
        texts(&r, "b", "subjects.b.from"),
        ["\" \" isn't a subject name"]
    );
}

#[test]
fn every_reads_a_list_in_each_parent_but_never_stands_for_the_subject_itself() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"},
        "p": {"from": "every art.prs"},
        "q": {"from": "every art"},
        "w": {"from": "every art whose x is 1"}
    }));
    assert!(!r.infos["p"].problems.contains_key("subjects.p.from"));
    assert!(matches!(
        r.lowered("p").unwrap().source,
        Source::Child { every: true, .. }
    ));
    for name in ["q", "w"] {
        assert_eq!(
            texts(&r, name, &format!("subjects.{name}.from")),
            ["art is a subject: write art whose \u{2026} to narrow it, without every"]
        );
    }
}

#[test]
fn every_cannot_go_with_named_by_each_of() {
    let (_, r) = reading(json!({"s": {"from": "every art.b named by each of $params.l"}}));
    assert_eq!(
        texts(&r, "s", "subjects.s.from"),
        [
            "every can't go with named by each of: start the from line at a subject to read its names one subject at a time"
        ]
    );
}

#[test]
fn named_by_each_of_a_field_or_a_subject_is_written_wrong() {
    for line in [
        "t named by each of t.keys",
        "t named by each of keys",
        "t named by each of .keys",
        "things named by each of t.keys",
        "t named by each of k.keys",
        "t named by each of t",
    ] {
        let (_, r) = reading(json!({"t": {"from": "things"}, "k": {"from": line}}));
        assert_eq!(
            texts(&r, "k", "subjects.k.from"),
            [EACH_START_PROBLEM],
            "{line}"
        );
    }
}

#[test]
fn named_by_each_of_params_or_input_is_read() {
    for line in [
        "t named by each of $params.keys",
        "t named by each of $input.keys",
        "things named by each of $params.keys",
    ] {
        let (_, r) = reading(json!({"t": {"from": "things"}, "k": {"from": line}}));
        assert!(
            !r.infos["k"].problems.contains_key("subjects.k.from"),
            "{line}"
        );
    }
}

#[test]
fn every_takes_ten_steps_and_an_eleventh_is_written_wrong() {
    let (_, ok) = reading(json!({"s": {"from": "every art.b.c.d.e.f.g.h.i.j"}}));
    assert!(ok.lowered("s").is_some());
    let (_, over) = reading(json!({"s": {"from": "every art.b.c.d.e.f.g.h.i.j.k"}}));
    assert_eq!(
        texts(&over, "s", "subjects.s.from"),
        ["every over more than ten steps isn't supported yet"]
    );
    let (_, input) = reading(json!({"s": {"from": "every $input.art.b.c.d.e.f.g.h.i.j"}}));
    assert!(input.lowered("s").is_some());
}

#[test]
fn a_from_cannot_start_at_params() {
    let (_, r) = reading(json!({"s": {"from": "$params.x"}}));
    assert_eq!(
        texts(&r, "s", "subjects.s.from"),
        ["a from reads the input, so it can't start at $params"]
    );
}

#[test]
fn a_bare_name_after_named_by_is_an_unknown_alias() {
    let (_, r) = reading(json!({"s": {"from": "art named by foo"}}));
    assert_eq!(texts(&r, "s", "subjects.s.from"), ["unknown alias foo"]);
}

#[test]
fn a_condition_with_a_count_on_the_right_is_read_and_not_marked_unsupported() {
    let (_, r) = reading(json!({"s": {"from": "art whose x is at least count of ys"}}));
    assert!(!r.infos["s"].unsupported);
    assert!(r.infos["s"].problems.is_empty());
    assert!(r.lowered("s").is_some());
}

#[test]
fn a_narrowing_subject_cannot_have_its_own_identified_by() {
    let (_, r) = reading(
        json!({"art": {"from": "arts", "identified_by": "id"}, "b": {"from": "art whose x exists", "identified_by": "team"}}),
    );
    assert_eq!(
        texts(&r, "b", "subjects.b.identified_by"),
        ["not allowed on a subject that narrows another"]
    );
}

#[test]
fn identified_by_on_a_subject_listed_by_named_by_each_of_is_written_wrong() {
    for from in [
        "suites named by each of $params.names",
        "artifact.suites named by each of $params.names",
        "top[$params.g].suites named by each of $params.names",
        "suites named by each of $params.names whose id exists",
        "top named by $params.g named by each of $params.names",
    ] {
        let (_, r) = reading(json!({"s": {"from": from, "identified_by": "id"}}));
        assert_eq!(
            texts(&r, "s", "subjects.s.identified_by"),
            [KEYED_ID_PROBLEM],
            "{from}"
        );
        assert_eq!(r.infos["s"].entry["identified_by"], json!("id"), "{from}");
    }
}

#[test]
fn identified_by_on_a_child_listed_by_named_by_each_of_is_written_wrong() {
    for from in [
        "art.suites named by each of $params.names",
        "art.suites named by each of $params.names whose id exists and whose id is 1",
    ] {
        let (_, r) =
            reading(json!({"art": {"from": "arts"}, "c": {"from": from, "identified_by": "id"}}));
        assert_eq!(
            texts(&r, "c", "subjects.c.identified_by"),
            [KEYED_ID_PROBLEM],
            "{from}"
        );
    }
}

#[test]
fn the_keyed_id_problem_sorts_with_a_problem_of_the_path() {
    let (_, r) = reading(
        json!({"s": {"from": "suites named by each of $params.names", "identified_by": "id is"}}),
    );
    assert_eq!(
        texts(&r, "s", "subjects.s.identified_by"),
        [
            "identified_by is a path, like \"id\" or \"build.number\"".to_string(),
            KEYED_ID_PROBLEM.to_string()
        ]
    );
}

#[test]
fn identified_by_is_allowed_with_named_by_and_under_a_keyed_parent() {
    let (_, r) = reading(json!({
        "a": {"from": "suites named by $params.g", "identified_by": "id"},
        "k": {"from": "suites named by each of $params.names"},
        "c": {"from": "k.runs", "identified_by": "id"}
    }));
    assert!(
        !r.infos["a"]
            .problems
            .contains_key("subjects.a.identified_by")
    );
    assert!(
        !r.infos["c"]
            .problems
            .contains_key("subjects.c.identified_by")
    );
}

#[test]
fn a_subject_that_narrows_a_child_subject_is_written_wrong() {
    let (_, r) = reading(
        json!({"art": {"from": "arts"}, "k": {"from": "art.ks"}, "n": {"from": "k whose x exists"}}),
    );
    assert!(r.infos["n"].problems.contains_key("subjects.n.from"));
}

#[test]
fn parts_are_listed_with_their_paths_written_as_a_sentence_writes_them() {
    let (_, r) = reading(json!({"r": {"from": "rs", "has": {
        "dd": "  dd.b ", "x": "x[$params.k]", "c": {"from": "c.d", "identified_by": "id"}
    }}}));
    assert_eq!(
        r.infos["r"].entry["parts"],
        json!({
            "dd": {"from": "dd.b", "identified_by": null},
            "x": {"from": "x named by $params.k", "identified_by": null},
            "c": {"from": "c.d", "identified_by": "id"}
        })
    );
}

#[test]
fn a_part_written_wrong_is_listed_as_best_it_can_be() {
    let (_, r) = reading(json!({"r": {"from": "rs", "has": {
        "bad": {"from": "art whose x exists", "identified_by": "x y z"},
        "num": 3
    }}}));
    assert_eq!(
        r.infos["r"].entry["parts"]["bad"],
        json!({"from": "<invalid from>", "identified_by": "<invalid identified_by>"})
    );
    assert_eq!(
        r.infos["r"].entry["parts"]["num"]["from"],
        json!("<invalid from>")
    );
}

#[test]
fn part_problems_are_listed_under_the_alias() {
    let (_, r) = reading(json!({"r": {"from": "rs", "has": {
        "who": "art whose x exists", "in_params": "$params.x", "blank": " ",
        "every": "art", "with space": "art", "bare_by": "art named by foo", "$dollar": "art", "": "art"
    }}}));
    let problems = &r.infos["r"].problems;
    assert_eq!(
        problems["subjects.r.has.who"].iter().collect::<Vec<_>>(),
        ["from: a part is a path: whose and named by each of can't go in it"]
    );
    assert!(
        problems["subjects.r.has.in_params"].contains(
            "from: a part reads inside its subject, so it can't start at $params or $input"
        )
    );
    assert!(problems["subjects.r.has.blank"].contains("from: doesn't parse"));
    assert!(problems["subjects.r.has.every"].contains("invalid alias"));
    assert!(problems["subjects.r.has.\"with space\""].contains("invalid alias"));
    assert!(problems["subjects.r.has.$dollar"].contains("a name can't start with $"));
    assert!(problems["subjects.r.has.\"\""].contains("a name can't be empty"));
    assert!(problems["subjects.r.has.bare_by"].contains("from: unknown alias foo"));
}

#[test]
fn an_alias_named_like_a_subject_or_a_part_of_one_it_narrows_is_written_wrong() {
    let (_, r) = reading(json!({
        "base": {"from": "bs", "has": {"x": "x"}},
        "n": {"from": "base whose x exists", "has": {"x": "x", "base": "b"}},
    }));
    let problems = &r.infos["n"].problems["subjects.n.has.x"];
    assert_eq!(
        problems.iter().collect::<Vec<_>>(),
        ["x can't be an alias: it's a part of base"]
    );
    assert_eq!(
        r.infos["n"].problems["subjects.n.has.base"]
            .iter()
            .collect::<Vec<_>>(),
        ["base can't be an alias: it's a subject's name"]
    );
}

#[test]
fn an_alias_named_like_a_part_of_a_parent_is_written_wrong() {
    let (_, r) = reading(json!({
        "gp": {"from": "g", "has": {"cap": "c"}},
        "p": {"from": "gp.ps"},
        "leaf": {"from": "p.ls", "has": {"cap": "d"}},
    }));
    assert_eq!(
        r.infos["leaf"].problems["subjects.leaf.has.cap"]
            .iter()
            .collect::<Vec<_>>(),
        ["cap can't be an alias: it's a part of gp"]
    );
}

#[test]
fn a_narrowing_subject_keeps_the_parts_of_the_subject_it_narrows() {
    let (_, r) = reading(json!({
        "base": {"from": "bs", "has": {"x": {"from": "x", "identified_by": "id"}}},
        "n": {"from": "base whose x.y exists", "has": {"z": "z"}},
    }));
    let parts = r.infos["n"].entry["parts"].as_object().unwrap();
    assert_eq!(parts.keys().collect::<Vec<_>>(), ["x", "z"]);
    assert_eq!(r.lowered("n").unwrap().filters.len(), 1);
}

#[test]
fn the_subjects_a_requirement_uses_are_the_subject_and_everything_it_reads_from() {
    let (_, r) = reading(json!({
        "art": {"from": "arts"}, "b": {"from": "art.bs"}, "c": {"from": "cs"},
        "n": {"from": "c whose x exists"},
    }));
    assert_eq!(r.used("b"), ["art", "b"]);
    assert_eq!(r.used("n"), ["c", "n"]);
    assert_eq!(r.used("c"), ["c"]);
    assert!(r.used("nope").is_empty());
    assert!(r.listed("nope").is_empty());
}

#[test]
fn the_problems_of_a_parent_belong_to_the_requirement_of_its_child() {
    let policy = Policy::read(&json!({
        "ergo_spec": SPEC,
        "subjects": {"art": {"from": "arts whose"}, "b": {"from": "art.bs"}},
        "requirements": {"r": {"subject": "b", "checks": {"c": "x"}}}
    }));
    let reading = Reading::of(&policy);
    let problems = reading.problems_of(&policy, &policy.requirements["r"]);
    assert!(problems.contains_key("subjects.art.from"));
}

#[test]
fn the_condition_texts_of_a_chain_start_with_the_outermost() {
    let (_, r) = reading(json!({
        "art": {"from": "arts whose x exists"}, "n": {"from": "art whose y exists"},
    }));
    assert_eq!(r.filters_text("n").unwrap(), "x exists and y exists");
    assert!(r.filters_text("nope").is_none());
}

fn requirement_problems(subjects: Value) -> Problems {
    let policy = Policy::read(&json!({
        "ergo_spec": SPEC,
        "subjects": subjects,
        "requirements": {"r": {"subject": "kid", "checks": {"c": "n exists"}}}
    }));
    Reading::of(&policy).problems_of(&policy, &policy.requirements["r"])
}

#[test]
fn a_narrowed_child_with_an_unknown_name_lists_its_own_problem_for_the_requirement() {
    let problems = requirement_problems(json!({
        "parent": {"from": "things", "identified_by": "id"},
        "mid": {"from": "parent.items whose zz is $foo", "identified_by": "n"},
        "kid": {"from": "mid whose n is 1"}
    }));
    assert!(problems.contains_key("subjects.mid.from"));
    assert!(problems["subjects.kid.from"].contains(NARROWING_A_CHILD_PROBLEM));
}

#[test]
fn a_narrowed_child_with_mixed_types_lists_its_own_problem_for_the_requirement() {
    let problems = requirement_problems(json!({
        "parent": {"from": "things", "identified_by": "id"},
        "mid": {"from": "parent.items whose n is one of 1, \"a\"", "identified_by": "n"},
        "kid": {"from": "mid whose n is 1"}
    }));
    assert!(problems.contains_key("subjects.mid.from"));
    assert!(problems.contains_key("subjects.kid.from"));
}

#[test]
fn subjects_in_a_loop_each_with_an_identified_by_show_it_as_invalid() {
    let (_, r) = reading(json!({
        "pp": {"from": "kid whose n is 1", "identified_by": "x"},
        "kid": {"from": "pp whose n is 1", "identified_by": "y"}
    }));
    assert_eq!(
        r.infos["pp"].entry["identified_by"],
        "<invalid identified_by>"
    );
    assert_eq!(
        r.infos["kid"].entry["identified_by"],
        "<invalid identified_by>"
    );
    assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["leads to a loop"]);
    assert!(
        !r.infos["kid"]
            .problems
            .contains_key("subjects.kid.identified_by")
    );
}

#[test]
fn subjects_in_a_loop_without_an_identified_by_show_none() {
    let (_, r) = reading(json!({
        "pp": {"from": "kid whose n is 1"},
        "kid": {"from": "pp whose n is 1"}
    }));
    assert_eq!(r.infos["pp"].entry["identified_by"], Value::Null);
    assert_eq!(r.infos["kid"].entry["identified_by"], Value::Null);
}

#[test]
fn a_from_with_an_unknown_name_still_starts_at_its_subject() {
    for from in [
        "parent.items whose zz is $foo",
        "parent.items named by $foo",
        "parent[$foo] whose n is 1",
        "parent.items whose zz is $foo.k",
    ] {
        let (_, r) = reading(json!({
            "parent": {"from": "things"}, "kid": {"from": from}
        }));
        assert_eq!(
            r.infos["kid"].relation,
            Relation::Child("parent".to_string()),
            "{from}"
        );
        assert_eq!(r.listed("kid"), ["kid", "parent"], "{from}");
        assert_eq!(
            texts(&r, "kid", "subjects.kid.from"),
            ["unknown name $foo"],
            "{from}"
        );
        assert_eq!(r.infos["kid"].entry["from"], INVALID_FROM, "{from}");
    }
}

#[test]
fn a_from_with_an_unknown_name_and_a_quoted_parent_with_whose_in_it_starts_at_that_parent() {
    let (_, r) = reading(json!({
        "par whose ent": {"from": "things"},
        "kid": {"from": "\"par whose ent\".items whose zz is $foo"}
    }));
    assert_eq!(
        r.infos["kid"].relation,
        Relation::Child("par whose ent".to_string())
    );
    assert_eq!(r.listed("kid"), ["kid", "par whose ent"]);
}

#[test]
fn a_narrowing_subject_with_an_unknown_name_takes_the_id_and_parts_of_its_parent() {
    let (_, r) = reading(json!({
        "parent": {"from": "things", "identified_by": "id", "has": {"owner": "owner.name"}},
        "kid": {"from": "parent whose n is $foo"}
    }));
    assert_eq!(
        r.infos["kid"].relation,
        Relation::Narrows("parent".to_string())
    );
    assert_eq!(r.infos["kid"].entry["identified_by"], "id");
    assert_eq!(
        r.infos["kid"].entry["parts"]["owner"]["from"],
        r.infos["parent"].entry["parts"]["owner"]["from"]
    );
    assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["unknown name $foo"]);
}

#[test]
fn the_unknown_name_of_a_whose_adds_no_second_problem() {
    let (_, r) = reading(json!({
        "parent": {"from": "things"}, "kid": {"from": "parent.items whose zz is $foo"}
    }));
    assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["unknown name $foo"]);
}

#[test]
fn a_from_with_an_unknown_name_and_a_syntax_error_lists_no_other_subject() {
    let (_, r) = reading(json!({
        "parent": {"from": "things"}, "kid": {"from": "parent.items whose zz is $foo foo bar"}
    }));
    assert_eq!(r.infos["kid"].relation, Relation::Root);
    assert_eq!(r.listed("kid"), ["kid"]);
    assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["doesn't parse"]);
}
