use ergo_policy_cli::examples::{self, Example};
use ergo_policy_cli::outcome::Item;
use serde_json::{Value, json};

fn policy() -> Value {
    json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {
            "deployment": {"from": "deployments", "identified_by": "id"},
            "pull request": {"from": "prs", "identified_by": "number"},
            "pull": {"from": "pulls", "identified_by": "id"}
        },
        "requirements": {
            "approved": {"subject": "deployment", "checks": {
                "approver_set": "approver is a non-empty string",
                "has approvals": "approvals is at least 1"
            }},
            "reviewed": {"subject": "pull request", "checks": {"peer_approved": "approved is true"}},
            "pulled": {"subject": "pull", "checks": {"peer_approved": "approved is true"}}
        }
    })
}

fn input() -> Value {
    json!({
        "deployments": [{"id": "d1", "approvals": 1}, {"id": "d2", "approver": "", "approvals": 1}],
        "prs": [{"number": 7, "approved": true}],
        "pulls": [{"id": "request 7", "approved": false}]
    })
}

fn problems(outcome: Value) -> Vec<String> {
    let report = ergo_policy_engine::report(&input(), &policy(), &json!({}));
    examples::check(&outcome, &report, &policy()).problems
}

#[test]
fn an_outcome_that_says_what_the_report_says_has_no_problem() {
    assert_eq!(
        problems(json!([
            "not compliant",
            {"approved is not met": [
                "deployment d1 fails approver_set because approver is missing",
                "deployment d2 fails approver_set",
                "deployment d1 passes has approvals"
            ]},
            {"reviewed": ["pull request 7 passes peer_approved"]},
            {"pulled is not met": ["pull \"request 7\" fails peer_approved because approved is false"]}
        ])),
        Vec::<String>::new()
    );
}

#[test]
fn a_line_that_disagrees_with_its_row_names_what_the_report_says() {
    assert_eq!(
        problems(json!([
            "compliant",
            "reviewed is not met",
            {"approved": [
                "deployment d1 fails approver_set because approver is \"\"",
                "deployment d2 fails approver_set",
                "deployment d1 fails has approvals",
                "deployment d9 passes has approvals"
            ]}
        ])),
        vec![
            "the report says not compliant",
            "the report says reviewed is met",
            "the report says deployment d1 fails approver_set because approver is missing",
            "the report says deployment d1 passes has approvals",
            "the report has no row for deployment d9 and has approvals in approved",
            "no line says pull \"request 7\" fails peer_approved because approved is false",
        ]
    );
}

#[test]
fn a_number_in_a_line_matches_an_id_of_the_same_value_however_either_is_written() {
    let input: Value =
        serde_json::from_str(r#"{"prs": [{"number": 7.0, "approved": true}]}"#).unwrap();
    let report = ergo_policy_engine::report(&input, &policy(), &json!({}));
    for id in ["7", "7.0", "7.00", "7e0", "0.7e1"] {
        let line = format!("pull request {id} passes peer_approved");
        assert_eq!(
            examples::check(&json!([{"reviewed": [line]}]), &report, &policy()).problems,
            Vec::<String>::new(),
            "{id}"
        );
    }
    let problems = examples::check(
        &json!([{"reviewed": ["pull request \"7\" passes peer_approved"]}]),
        &report,
        &policy(),
    )
    .problems;
    assert_eq!(
        problems,
        vec!["the report has no row for pull request \"7\" and peer_approved in reviewed"]
    );
}

#[test]
fn a_check_line_covers_its_check_so_every_failure_of_that_check_must_be_listed() {
    assert_eq!(
        problems(
            json!([{"approved": ["deployment d1 fails approver_set because approver is missing"]}])
        ),
        vec!["no line says deployment d2 fails approver_set because approver is \"\""]
    );
    assert_eq!(
        problems(json!([{"approved": ["deployment d1 passes has approvals"]}])),
        Vec::<String>::new()
    );
}

#[test]
fn a_heading_with_a_status_covers_the_whole_requirement() {
    assert_eq!(
        problems(json!([{"approved is not met": ["deployment d1 passes has approvals"]}])),
        vec![
            "no line says deployment d1 fails approver_set because approver is missing",
            "no line says deployment d2 fails approver_set because approver is \"\"",
        ]
    );
}

#[test]
fn a_line_the_policy_cannot_read_is_a_problem() {
    let read = |line: &str| problems(json!([{"approved": [line]}]));
    let cases = [
        ("deployment d1 passes nothing", "names no check of approved"),
        (
            "robot d1 passes approver_set",
            "doesn't start with a subject",
        ),
        (
            "deployment d1 approves approver_set",
            "needs passes or fails",
        ),
        (
            "deployment d1 passes approver_set because x",
            "names no check of approved",
        ),
        (
            "deployment d1 in release r1 passes approver_set",
            "no subject of the policy after in",
        ),
        (
            "deployment d1 passes $applies",
            "is in scope or is out of scope",
        ),
        ("deployment d1 fails $unique_ids", "a check Ergo adds has no id"),
    ];
    for (line, reason) in cases {
        let got = read(line);
        assert!(
            got.first()
                .is_some_and(|p| p.starts_with(&format!("can't read the line '{line}'"))
                    && p.contains(reason)),
            "{line}: {got:?}"
        );
    }
    let top = problems(
        json!(["deployment d1 passes approver_set", {"nobody": ["x"]}, {"approved": []}, 5, []]),
    );
    assert_eq!(top.len(), 1, "{top:?}");
    assert!(top[0].contains("outcome item 4"), "{top:?}");
    let shapes = [
        (
            json!(["deployment d1 passes approver_set"]),
            "isn't compliant, not compliant or a requirement",
        ),
        (
            json!([{"nobody": ["x"]}]),
            "no requirement is called nobody",
        ),
        (json!([{"approved": []}]), "lists no lines"),
        (json!([{"approved": null}]), "lists no lines"),
        (json!([]), "outcome is empty"),
        (json!({"approved": []}), "outcome isn't a list"),
    ];
    for (outcome, reason) in shapes {
        let got = problems(outcome.clone());
        assert!(
            got.first().is_some_and(|p| p.contains(reason)),
            "{outcome}: {got:?}"
        );
    }
}

#[test]
fn a_heading_with_a_status_and_no_lines_covers_the_requirement() {
    assert_eq!(
        problems(json!([{"reviewed is met": null}])),
        Vec::<String>::new()
    );
}

#[test]
fn a_policy_written_wrong_breaks_every_example_whatever_the_lines_say() {
    let mut policy = policy();
    policy["requirements"]["reviewed"]["checks"]["typo"] = json!("approved sparkles");
    let report = ergo_policy_engine::report(&input(), &policy, &json!({}));
    let checked = examples::check(
        &json!([{"approved": ["deployment d1 passes has approvals"]}]),
        &report,
        &policy,
    );
    assert_eq!(checked.problems.len(), 1, "{:?}", checked.problems);
    assert!(
        checked.problems[0].starts_with("the policy is written wrong: reviewed: "),
        "{:?}",
        checked.problems
    );
}

#[test]
fn a_failure_of_a_check_ergo_adds_that_the_lines_cover_must_be_listed() {
    let mut policy = policy();
    policy["requirements"]["reviewed"]["min_subjects"] = json!(2);
    let report = ergo_policy_engine::report(&input(), &policy, &json!({}));
    let problems = examples::check(
        &json!([{"reviewed is not met": ["pull request 7 passes peer_approved"]}]),
        &report,
        &policy,
    )
    .problems;
    assert_eq!(
        problems,
        vec!["no line says fails $min_subjects because in-scope pull request count is 1"]
    );
    let problems = examples::check(
        &json!([{"reviewed": ["pull request 7 passes peer_approved"]}]),
        &report,
        &policy,
    )
    .problems;
    assert_eq!(problems, Vec::<String>::new());
}

#[test]
fn a_subject_out_of_scope_is_not_a_failure() {
    let mut policy = policy();
    policy["subjects"]["deployment"]["from"] = json!("deployments whose approvals is 1");
    let mut input = input();
    input["deployments"][1]["approvals"] = json!(0);
    let report = ergo_policy_engine::report(&input, &policy, &json!({}));
    let problems = examples::check(
        &json!([{"approved is not met": ["deployment d1 fails approver_set", "deployment d1 passes has approvals"]}]),
        &report, &policy,
    )
    .problems;
    assert_eq!(problems, Vec::<String>::new());
}

#[test]
fn the_check_lines_of_an_outcome_say_which_checks_it_shows_passing_and_failing() {
    let report = ergo_policy_engine::report(&input(), &policy(), &json!({}));
    let checked = examples::check(
        &json!([{"approved": ["deployment d1 fails approver_set", "deployment d2 fails approver_set", "deployment d1 passes has approvals"]}]),
        &report,
        &policy(),
    );
    let shown: Vec<_> = checked.shown.into_iter().collect();
    assert_eq!(
        shown,
        vec![
            ("approved".to_string(), "approver_set".to_string(), false),
            ("approved".to_string(), "has approvals".to_string(), true),
        ]
    );
}

#[test]
fn a_failed_example_shows_its_lines_next_to_those_of_the_report_for_what_they_cover() {
    let report = ergo_policy_engine::report(&input(), &policy(), &json!({}));
    let checked = examples::check(
        &json!([{"approved": ["deployment d1 passes approver_set"]}]),
        &report,
        &policy(),
    );
    assert_eq!(
        checked.expected,
        vec![Item::Group(
            "approved".to_string(),
            vec!["deployment d1 passes approver_set".to_string()]
        )]
    );
    assert_eq!(
        checked.actual,
        vec![Item::Group(
            "approved".to_string(),
            vec![
                "deployment d1 fails approver_set because approver is missing".to_string(),
                "deployment d2 fails approver_set because approver is \"\"".to_string(),
            ]
        )]
    );
}

fn example(name: &str) -> Value {
    json!({"name": name, "input": {}, "outcome": ["compliant"]})
}

#[test]
fn examples_are_read_in_order_with_their_params() {
    let mut policy = policy();
    policy["example_params"] = json!({"max": 1});
    let mut own = example("own params");
    own["params"] = json!({"other": 2});
    own["description"] = json!("Replaces example_params");
    policy["examples"] = json!([example("shared params"), own]);
    assert_eq!(
        examples::read(&policy),
        Ok(vec![
            Example {
                name: "shared params".to_string(),
                input: json!({}),
                params: json!({"max": 1}),
                outcome: json!(["compliant"]),
            },
            Example {
                name: "own params".to_string(),
                input: json!({}),
                params: json!({"other": 2}),
                outcome: json!(["compliant"]),
            },
        ])
    );
    policy["example_params"] = Value::Null;
    policy.as_object_mut().unwrap().remove("example_params");
    assert_eq!(examples::read(&policy).unwrap()[0].params, json!({}));
}

#[test]
fn a_line_must_agree_with_every_row_that_shares_its_check_and_subject() {
    let mut input = input();
    input["deployments"] =
        json!([{"id": "d1", "approver": "ann", "approvals": 1}, {"id": "d1", "approvals": 1}]);
    let report = ergo_policy_engine::report(&input, &policy(), &json!({}));
    assert_eq!(
        examples::check(
            &json!([{"approved": ["deployment d1 passes approver_set"]}]),
            &report,
            &policy()
        )
        .problems,
        vec![
            "the report says deployment d1 fails approver_set because approver is missing",
            "no line says deployment d1 fails approver_set because approver is missing",
        ]
    );
    assert_eq!(
        examples::check(
            &json!([{"approved": ["deployment d1 fails approver_set"]}]),
            &report,
            &policy()
        )
        .problems,
        vec!["the report says deployment d1 passes approver_set"]
    );
}

#[test]
fn only_the_lines_of_an_example_that_passed_count_for_the_warnings() {
    let mut policy = policy();
    policy["requirements"] = json!({"reviewed": policy["requirements"]["reviewed"].clone()});
    policy["examples"] = json!([
        {"name": "fails", "input": {"prs": [{"number": 7, "approved": true}]},
         "outcome": [{"reviewed": ["pull request 7 fails peer_approved"]}]},
        {"name": "passes", "input": {"prs": [{"number": 7, "approved": true}]},
         "outcome": [{"reviewed": ["pull request 7 passes peer_approved"]}]}
    ]);
    let (text, code) = examples::run(&policy, false).unwrap();
    assert_eq!(code, 1);
    assert!(
        text.contains("\nwarning: no example shows peer_approved of reviewed failing\n"),
        "{text}"
    );
    assert!(!text.contains("passing\n"), "{text}");
}

#[test]
fn examples_written_wrong_are_refused() {
    let mut missing_input = example("a");
    missing_input.as_object_mut().unwrap().remove("input");
    let cases = [
        (Value::Null, "the policy has no examples"),
        (json!({}), "examples isn't a list"),
        (json!([]), "the policy has no examples"),
        (json!([5]), "example 1 isn't an object"),
        (
            json!([{"input": {}, "outcome": ["compliant"]}]),
            "example 1 has no name",
        ),
        (json!([example("")]), "example 1 has no name"),
        (json!([missing_input]), "example a has no input"),
        (
            json!([{"name": "a", "input": {}}]),
            "example a has no outcome",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": [], "extra": 1}]),
            "example a has an unknown field extra",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": [], "description": 1}]),
            "example a has a description that isn't text",
        ),
        (
            json!([example("a"), example("b"), example("a")]),
            "two examples are called a",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": []}]),
            "example a: the outcome is empty",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": null}]),
            "example a: the outcome isn't a list",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": "compliant"}]),
            "example a: the outcome isn't a list",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": [{"approved": []}]}]),
            "example a: the heading approved lists no lines",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": ["compliant", {"approved": null}]}]),
            "example a: the heading approved lists no lines",
        ),
        (
            json!([{"name": "a", "input": {}, "outcome": ["compliant", 5]}]),
            "example a: outcome item 2 isn't a line or a heading with its lines",
        ),
    ];
    for (examples, problem) in cases {
        let mut policy = policy();
        if !examples.is_null() {
            policy["examples"] = examples.clone();
        }
        assert_eq!(
            examples::read(&policy),
            Err(problem.to_string()),
            "{examples}"
        );
    }
}

fn colliding_policy() -> Value {
    json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {
            "t": {"from": "ts", "identified_by": "id"},
            "t 7": {"from": "others", "identified_by": "id"},
            "t 1 passes": {"from": "extra", "identified_by": "id"}
        },
        "requirements": {
            "r": {"subject": "t", "checks": {"c": "ok is true"}},
            "q": {"subject": "t 7", "min_subjects": 0, "checks": {"d": "ok is true"}},
            "p": {"subject": "t 1 passes", "min_subjects": 0, "checks": {"e": "ok is true"}}
        }
    })
}

fn colliding_problems(ok: bool, outcome: Value) -> Vec<String> {
    let input =
        json!({"ts": [{"id": 7, "ok": ok}, {"id": 1, "ok": ok}], "others": [], "extra": []});
    let report = ergo_policy_engine::report(&input, &colliding_policy(), &json!({}));
    examples::check(&outcome, &report, &colliding_policy()).problems
}

#[test]
fn a_line_that_disagrees_with_a_row_no_line_reads_back_as_is_still_a_problem() {
    let passing = [
        json!(["compliant", {"r is met": ["t 7.0 fails c because anything at all"]}]),
        json!([{"r": ["t 7.0 fails c"]}]),
        json!([{"r": ["t 7e0 fails c"]}]),
        json!([{"r": ["t 1.0 fails c"]}]),
    ];
    for outcome in passing {
        let got = colliding_problems(true, outcome.clone());
        assert!(
            got.iter()
                .any(|p| p.starts_with("the report says t ") && p.ends_with(" passes c")),
            "{outcome}: {got:?}"
        );
    }
    let failing = [
        json!([{"r": ["t 7.0 passes c"]}]),
        json!([{"r": ["t 7.0 fails c because wrong"]}]),
    ];
    for outcome in failing {
        let got = colliding_problems(false, outcome.clone());
        assert!(
            got.contains(&"the report says t 7 fails c because ok is false".to_string()),
            "{outcome}: {got:?}"
        );
    }
}

#[test]
fn a_line_that_disagrees_with_its_row_shows_no_check_passing_or_failing() {
    let input = json!({"ts": [{"id": 7, "ok": true}], "others": [], "extra": []});
    let report = ergo_policy_engine::report(&input, &colliding_policy(), &json!({}));
    for outcome in [
        json!([{"r": ["t 7.0 fails c"]}]),
        json!([{"r": ["t 8 passes c"]}]),
    ] {
        let checked = examples::check(&outcome, &report, &colliding_policy());
        assert!(checked.shown.is_empty(), "{outcome}: {:?}", checked.shown);
    }
}

fn requirements_named(names: &[&str]) -> Value {
    let requirements: serde_json::Map<String, Value> = names
        .iter()
        .map(|name| {
            (
                name.to_string(),
                json!({"subject": "t", "checks": {"c": "ok is true"}}),
            )
        })
        .collect();
    json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {"t": {"from": "ts", "identified_by": "id"}},
        "requirements": requirements
    })
}

#[test]
fn a_heading_that_is_one_requirement_on_its_own_and_another_with_a_status_is_refused() {
    let ambiguous = [
        (&["x", "x is met"][..], "x is met"),
        (&["a", "a is not met"][..], "a is not met"),
        (&["a", "a is not applicable"][..], "a is not applicable"),
    ];
    for (names, heading) in ambiguous {
        for lines in [json!(["t t1 passes c"]), Value::Null] {
            let mut policy = requirements_named(names);
            policy["examples"] = json!([
                {"name": "e", "input": {"ts": [{"id": "t1", "ok": true}]}, "outcome": [{heading: lines}]}
            ]);
            let got = examples::read(&policy);
            assert!(
                got.as_ref().is_err_and(|problem| problem.starts_with(&format!(
                    "example e: the heading {heading} could name the requirement {heading} or the status of "
                ))),
                "{names:?} {heading} {lines}: {got:?}"
            );
            let input = json!({"ts": [{"id": "t1", "ok": true}]});
            let report = ergo_policy_engine::report(&input, &policy, &json!({}));
            let problems = examples::check(&json!([{heading: lines}]), &report, &policy).problems;
            assert_eq!(problems.len(), 1, "{problems:?}");
            assert!(
                problems[0].starts_with(&format!("the heading {heading} could name")),
                "{problems:?}"
            );
        }
    }
    let clear = [
        (&["x is met"][..], json!([{"x is met": ["t t1 passes c"]}])),
        (
            &["x", "x is met"][..],
            json!([{"x is met is met": ["t t1 passes c"]}, "x is met", {"x": ["t t1 passes c"]}]),
        ),
    ];
    for (names, outcome) in clear {
        let mut policy = requirements_named(names);
        policy["examples"] = json!([
            {"name": "e", "input": {"ts": [{"id": "t1", "ok": true}]}, "outcome": outcome.clone()}
        ]);
        assert_eq!(
            examples::run(&policy, false).map(|(_, code)| code),
            Ok(0),
            "{outcome}"
        );
    }
}

fn children() -> Value {
    json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {
            "release": {"from": "releases", "identified_by": "id"},
            "artifact": {"from": "every release.artifacts", "identified_by": "name"},
            "test run": {"from": "every artifact.runs", "identified_by": "n"}
        },
        "requirements": {
            "tested": {"subject": "artifact", "checks": {"passed": "status is \"passed\""}},
            "ran": {"subject": "test run", "min_subjects": 0, "checks": {"ok": "ok is true"}}
        }
    })
}

fn child_problems(outcome: Value) -> Vec<String> {
    let input = json!({"releases": [
        {"id": "r1", "artifacts": [
            {"name": "web", "status": "failed", "runs": [{"n": 1, "ok": true}]},
            {"name": "api", "status": "passed", "runs": []}
        ]},
        {"id": "r2", "artifacts": [{"name": "web", "status": "passed", "runs": []}]}
    ]});
    let report = ergo_policy_engine::report(&input, &children(), &json!({}));
    examples::check(&outcome, &report, &children()).problems
}

#[test]
fn a_line_for_a_child_subject_matches_the_row_with_its_id_and_the_ids_of_its_parents() {
    assert_eq!(
        child_problems(json!([
            {"tested is not met": [
                "artifact web in release r1 fails passed because status is \"failed\"",
                "artifact web in release r2 passes passed"
            ]},
            {"ran is met": ["test run 1 in artifact web in release r1 passes ok"]}
        ])),
        Vec::<String>::new()
    );
    assert_eq!(
        child_problems(json!([{"tested": [
            "artifact web in release r2 fails passed",
            "artifact web in release r9 passes passed"
        ]}])),
        vec![
            "the report says artifact web in release r2 passes passed",
            "the report has no row for artifact web in release r9 and passed in tested",
            "no line says artifact web in release r1 fails passed because status is \"failed\"",
        ]
    );
}

#[test]
fn a_line_for_a_child_subject_without_the_in_its_from_line_gives_cannot_be_read() {
    let cases = [
        (
            "artifact web passes passed",
            "artifact is read inside release, so its id is followed by in release <id>",
        ),
        (
            "artifact web in artifact web passes passed",
            "artifact is read inside release, so its id is followed by in release <id>",
        ),
        (
            "artifact web in release r1 in release r1 passes passed",
            "artifact is read inside release, so its id is followed by in release <id>",
        ),
        (
            "test run 1 in release r1 in artifact web passes ok",
            "test run is read inside artifact inside release, so its id is followed by in artifact <id> in release <id>",
        ),
        (
            "release r1 in release r1 passes ok",
            "release isn't read inside another subject, so nothing follows its id but passes or fails",
        ),
    ];
    for (line, reason) in cases {
        let requirement = if line.contains(" passed") {
            "tested"
        } else {
            "ran"
        };
        let got = child_problems(json!([{requirement: [line]}]));
        assert_eq!(
            got.first(),
            Some(&format!("can't read the line '{line}': {reason}")),
            "{line}: {got:?}"
        );
    }
}

fn unused_names(parent: &str, used: bool) -> Value {
    let mut policy = json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {
            "deployment": {"from": "deployments", "identified_by": "id"},
            parent: {"from": "others", "identified_by": "id"},
            "artifact": {"from": "every deployment.artifacts", "identified_by": "name"},
            "pull": {"from": "pulls", "identified_by": "id"},
            "pull request": {"from": "prs", "identified_by": "number"}
        },
        "requirements": {
            "q": {"subject": "artifact", "checks": {"c": "x is 1"}},
            "p": {"subject": "pull", "checks": {"c": "x is 1"}}
        }
    });
    if used {
        policy["requirements"]["spare"] =
            json!({"subject": parent, "min_subjects": 0, "checks": {"c": "x is 1"}});
        policy["requirements"]["spare pr"] =
            json!({"subject": "pull request", "min_subjects": 0, "checks": {"c": "x is 1"}});
    }
    policy
}

fn unused_names_input(parent_id: Value) -> Value {
    json!({
        "others": [], "prs": [],
        "deployments": [{"id": parent_id, "artifacts": [{"name": "web", "x": 2}]}],
        "pulls": [{"id": "request", "x": 2}]
    })
}

#[test]
fn a_line_is_read_with_every_subject_name_of_the_policy_even_one_no_requirement_uses() {
    for (parent, id, unreadable, readable) in [
        (
            "deployment 7",
            json!(7),
            "artifact web in deployment 7 fails c",
            None,
        ),
        (
            "deployment x",
            json!("x"),
            "artifact web in deployment x fails c",
            Some("artifact web in deployment \"x\" fails c"),
        ),
    ] {
        for used in [false, true] {
            let policy = unused_names(parent, used);
            let report =
                ergo_policy_engine::report(&unused_names_input(id.clone()), &policy, &json!({}));
            let check = |lines: Value| examples::check(&lines, &report, &policy).problems;
            assert_eq!(
                check(json!([{"q": [unreadable]}])),
                vec![format!(
                    "can't read the line '{unreadable}': it needs passes or fails after the id"
                )],
                "{parent} used: {used}"
            );
            if let Some(readable) = readable {
                assert_eq!(
                    check(json!([{"q": [readable]}])),
                    Vec::<String>::new(),
                    "{parent} used: {used}"
                );
            }
            assert_eq!(
                check(json!([{"p": ["pull request fails c"]}])),
                vec![
                    "can't read the line 'pull request fails c': it needs passes or fails after the id"
                ],
                "{parent} used: {used}"
            );
            assert_eq!(
                check(json!([{"p": ["pull \"request\" fails c"]}])),
                Vec::<String>::new(),
                "{parent} used: {used}"
            );
        }
    }
}

fn artifacts() -> Value {
    json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {
            "deployment": {"from": "deployments", "identified_by": "id"},
            "artifact": {"from": "every deployment.artifacts", "identified_by": "name"}
        },
        "requirements": {"q": {"subject": "artifact", "checks": {"c": "x is 1"}}}
    })
}

fn artifact_problems(items: Value, line: &str) -> Vec<String> {
    let input = json!({"deployments": [{"id": 7, "artifacts": items}]});
    let report = ergo_policy_engine::report(&input, &artifacts(), &json!({}));
    examples::check(&json!([{"q": [line]}]), &report, &artifacts()).problems
}

#[test]
fn a_parent_id_in_a_line_matches_the_id_of_the_same_value_however_it_is_written() {
    let web = json!([{"name": "web", "x": 2}]);
    for line in [
        "artifact web in deployment 7 fails c",
        "artifact web in deployment 7.0 fails c",
        "artifact web in deployment 7e0 fails c",
    ] {
        assert_eq!(
            artifact_problems(web.clone(), line),
            Vec::<String>::new(),
            "{line}"
        );
    }
    assert_eq!(
        artifact_problems(web, "artifact web in deployment \"7\" fails c"),
        vec![
            "the report has no row for artifact web in deployment \"7\" and c in q",
            "no line says artifact web in deployment 7 fails c because x is 2",
        ]
    );
}

#[test]
fn a_line_for_a_child_subject_must_agree_with_every_row_that_shares_its_check_and_subject() {
    let twins = json!([{"name": "web", "x": 1}, {"name": "web", "x": 2}]);
    assert_eq!(
        artifact_problems(twins.clone(), "artifact web in deployment 7 passes c"),
        vec![
            "the report says artifact web in deployment 7 fails c because x is 2",
            "no line says artifact web in deployment 7 fails c because x is 2",
        ]
    );
    assert_eq!(
        artifact_problems(twins, "artifact web in deployment 7 fails c"),
        vec!["the report says artifact web in deployment 7 passes c"]
    );
}

#[test]
fn the_lines_for_a_child_subject_count_for_the_warnings() {
    let mut policy = artifacts();
    let example = |name: &str, x: i64, line: &str| {
        json!({"name": name,
               "input": {"deployments": [{"id": 7, "artifacts": [{"name": "web", "x": x}]}]},
               "outcome": [{"q": [line]}]})
    };
    policy["examples"] = json!([example("fails", 2, "artifact web in deployment 7 fails c")]);
    let (text, code) = examples::run(&policy, false).unwrap();
    assert_eq!(code, 0, "{text}");
    assert_eq!(
        text,
        "passed: fails\nwarning: no example shows c of q passing\n1 example: 1 passed, 0 failed\n"
    );
    policy["examples"] = json!([
        example("fails", 2, "artifact web in deployment 7 fails c"),
        example("passes", 1, "artifact web in deployment 7 passes c")
    ]);
    assert_eq!(
        examples::run(&policy, true).unwrap(),
        (
            "passed: fails\npassed: passes\n2 examples: 2 passed, 0 failed\n".to_string(),
            0
        )
    );
}

fn scoped() -> Value {
    json!({
        "ergo_spec": ergo_policy_engine::SPEC,
        "subjects": {
            "deployment": {"from": "deployments whose env is \"prod\"", "identified_by": "id"},
            "artifact": {"from": "every deployment.artifacts", "identified_by": "name"}
        },
        "requirements": {
            "approved": {"subject": "deployment", "checks": {"approver_set": "approver is a non-empty string"}},
            "tested": {"subject": "artifact", "checks": {"scanned": "scan is 0"}}
        }
    })
}

fn scoped_problems(input: Value, outcome: Value) -> Vec<String> {
    let report = ergo_policy_engine::report(&input, &scoped(), &json!({}));
    examples::check(&outcome, &report, &scoped()).problems
}

fn three_deployments() -> Value {
    json!({"deployments": [
        {"id": "d1", "env": "prod", "approver": "a", "artifacts": [{"name": "x", "scan": 0}]},
        {"id": "d3", "env": "dev"},
        {"id": "d4", "approver": "a"}
    ]})
}

#[test]
fn a_scope_line_agrees_with_the_applies_row_of_its_subject() {
    let mut two_deployments = three_deployments();
    two_deployments["deployments"].as_array_mut().unwrap().pop();
    for line in [
        "deployment d3 is out of scope because env is \"dev\"",
        "deployment d3 is out of scope",
        "deployment d1 is in scope",
    ] {
        assert_eq!(
            scoped_problems(two_deployments.clone(), json!([{"approved": [line]}])),
            Vec::<String>::new(),
            "{line}"
        );
    }
    for (line, problem) in [
        (
            "deployment d3 is in scope",
            "the report says deployment d3 is out of scope because env is \"dev\"",
        ),
        (
            "deployment d3 is out of scope because env is missing",
            "the report says deployment d3 is out of scope because env is \"dev\"",
        ),
        (
            "deployment d1 is out of scope",
            "the report says deployment d1 is in scope",
        ),
        (
            "deployment d9 is in scope",
            "the report has no row for deployment d9 and $applies in approved",
        ),
    ] {
        let problems = scoped_problems(two_deployments.clone(), json!([{"approved": [line]}]));
        assert_eq!(problems, vec![problem.to_string()], "{line}");
    }
}

#[test]
fn a_scope_line_covers_applies_so_a_subject_ergo_cannot_tell_is_in_scope_fails_the_example() {
    assert_eq!(
        scoped_problems(
            three_deployments(),
            json!([{"approved": ["deployment d3 is out of scope"]}])
        ),
        vec!["can't check this yet: lines for an $applies row that failed with absent, not value, aren't supported yet, as for deployment d4 in approved"]
    );
}

#[test]
fn an_out_of_scope_line_never_agrees_with_a_subject_ergo_cannot_tell_is_in_scope() {
    let unreadable = "can't check this yet: lines for an $applies row that failed with absent, not value, aren't supported yet, as for deployment d4 in approved";
    for line in [
        "deployment d4 is out of scope because env is missing",
        "deployment d4 is out of scope",
        "deployment d4 is in scope",
    ] {
        let problems = scoped_problems(three_deployments(), json!([{"approved": [line]}]));
        assert_eq!(
            problems.first().map(String::as_str),
            Some(unreadable),
            "{line}"
        );
    }
    assert_eq!(
        scoped_problems(
            three_deployments(),
            json!([{"approved": ["deployment d1 passes approver_set"]}])
        ),
        Vec::<String>::new()
    );
    assert_eq!(
        scoped_problems(
            three_deployments(),
            json!([{"approved is not met": ["deployment d1 passes approver_set"]}])
        ),
        vec![unreadable]
    );
}

#[test]
fn a_line_for_a_check_ergo_adds_agrees_with_its_row_that_has_no_id() {
    let empty =
        json!({"deployments": [{"id": "d1", "env": "prod", "approver": "a", "artifacts": []}]});
    assert_eq!(
        scoped_problems(
            json!({"deployments": []}),
            json!([
                {"approved is not met": ["fails $min_subjects because in-scope deployment count is 0"]},
                {"tested is not met": ["fails $min_subjects because in-scope artifact count is 0"]}
            ])
        ),
        Vec::<String>::new()
    );
    assert_eq!(
        scoped_problems(
            empty.clone(),
            json!([{"tested is not met": ["artifact in deployment d1 fails $min_subjects because in-scope artifact count is 0"]}])
        ),
        Vec::<String>::new()
    );
    for (outcome, problem) in [
        (
            json!([{"approved": ["fails $min_subjects"]}]),
            "the report says passes $min_subjects",
        ),
        (
            json!([{"tested": ["artifact in deployment d2 fails $min_subjects"]}]),
            "the report has no row for artifact in deployment d2 and $min_subjects in tested",
        ),
        (
            json!([{"tested": ["fails $min_subjects"]}]),
            "the report has no row for artifact and $min_subjects in tested",
        ),
        (
            json!([{"tested is not met": ["artifact in deployment d1 passes $unique_ids"]}]),
            "no line says artifact in deployment d1 fails $min_subjects because in-scope artifact count is 0",
        ),
    ] {
        let problems = scoped_problems(empty.clone(), outcome.clone());
        assert_eq!(
            problems.first().map(String::as_str),
            Some(problem),
            "{outcome}"
        );
    }
}

#[test]
fn a_line_for_a_check_ergo_adds_on_a_child_subject_names_every_parent_or_none() {
    let input =
        json!({"deployments": [{"id": "d1", "env": "prod", "approver": "a", "artifacts": []}]});
    for (line, reason) in [
        (
            "artifact fails $min_subjects",
            "the row of a check Ergo adds for artifact itself has no subject to name, so its line starts with passes or fails",
        ),
        (
            "deployment in deployment d1 fails $unique_ancestor_ids",
            "deployment isn't read inside another subject, so nothing follows it but passes or fails",
        ),
    ] {
        assert_eq!(
            scoped_problems(input.clone(), json!([{"tested": [line]}])),
            vec![format!("can't read the line '{line}': {reason}")],
            "{line}"
        );
    }
}

fn round_trip(policy: &Value, input: &Value) {
    let report = ergo_policy_engine::report(input, policy, &json!({}));
    let printed =
        ergo_policy_cli::outcome::yaml(&ergo_policy_cli::outcome::of(&report, policy).unwrap());
    let outcome = ergo_policy_cli::yaml::parse(&printed).unwrap();
    assert_eq!(
        examples::check(&outcome, &report, policy).problems,
        Vec::<String>::new(),
        "{printed}"
    );
}

#[test]
fn the_printed_outcome_with_checks_ergo_adds_and_subjects_out_of_scope_passes_when_pasted_back() {
    for input in [
        json!({"deployments": []}),
        json!({"deployments": [
            {"id": "d1", "env": "prod", "approver": "a", "artifacts": []},
            {"id": "d3", "env": "dev"},
            {"id": "d2", "env": "prod", "approver": "", "artifacts": [{"name": "x", "scan": 1}, {"name": "x", "scan": 1}]}
        ]}),
        json!({"deployments": [
            {"id": "d1", "env": "prod", "approver": "a", "artifacts": []},
            {"id": "d1", "env": "prod", "approver": "a", "artifacts": []}
        ]}),
        json!({"deployments": [{"id": "in", "env": "prod", "approver": "a", "artifacts": [{"name": "in", "scan": 0}]}]}),
    ] {
        round_trip(&scoped(), &input);
    }
}

#[test]
fn the_lines_of_checks_ergo_adds_and_of_scope_count_for_no_warning() {
    let mut policy = scoped();
    policy["examples"] = json!([
        {"name": "no deployment", "input": {"deployments": []},
         "outcome": [{"approved is not met": ["fails $min_subjects because in-scope deployment count is 0"]}]},
        {"name": "dev is left out", "input": {"deployments": [{"id": "d3", "env": "dev"}]},
         "outcome": [{"approved": ["deployment d3 is out of scope"]}]}
    ]);
    let (text, code) = examples::run(&policy, false).unwrap();
    assert_eq!(code, 0, "{text}");
    assert_eq!(
        text,
        "passed: no deployment\npassed: dev is left out\nwarning: no example shows approver_set of approved failing\nwarning: no example shows approver_set of approved passing\nwarning: no example shows scanned of tested failing\nwarning: no example shows scanned of tested passing\n2 examples: 2 passed, 0 failed\n"
    );
}

#[test]
fn a_line_for_well_formed_does_not_stop_a_policy_written_wrong_from_breaking_the_example() {
    let mut policy = scoped();
    policy["requirements"]["approved"]["subject"] = json!("nothing");
    let report = ergo_policy_engine::report(&json!({"deployments": []}), &policy, &json!({}));
    let checked = examples::check(
        &json!([{"approved": ["fails $well_formed because subject: not in subjects"]}]),
        &report,
        &policy,
    );
    assert_eq!(
        checked.problems,
        vec!["the policy is written wrong: approved: subject: not in subjects"]
    );
}

#[test]
fn a_subject_out_of_scope_under_require_some_is_not_a_failure_but_a_failed_subject_is() {
    let mut policy = scoped();
    policy["requirements"]["approved"]["require"] = json!("some");
    let input = json!({"deployments": [
        {"id": "d1", "env": "prod", "approver": "a"},
        {"id": "d2", "env": "prod"},
        {"id": "d3", "env": "dev"}
    ]});
    let report = ergo_policy_engine::report(&input, &policy, &json!({}));
    let check = |outcome: Value| examples::check(&outcome, &report, &policy).problems;
    assert_eq!(
        check(json!([{"approved is met": [
            "deployment d2 fails approver_set because approver is missing"
        ]}])),
        Vec::<String>::new()
    );
    assert_eq!(
        check(json!([{"approved is met": ["deployment d3 is out of scope"]}])),
        vec!["no line says deployment d2 fails approver_set because approver is missing"]
    );
}
