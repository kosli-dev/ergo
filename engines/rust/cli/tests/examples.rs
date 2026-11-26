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
    examples::check(&outcome, &report).problems
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
            examples::check(&json!([{"reviewed": [line]}]), &report).problems,
            Vec::<String>::new(),
            "{id}"
        );
    }
    let problems = examples::check(
        &json!([{"reviewed": ["pull request \"7\" passes peer_approved"]}]),
        &report,
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
            "child subjects",
        ),
        (
            "deployment d1 is out of scope",
            "subjects in or out of scope",
        ),
        (
            "fails $min_subjects because in-scope deployment count is 0",
            "checks Ergo adds",
        ),
        ("deployment d1 fails $unique_ids", "checks Ergo adds"),
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
    );
    assert_eq!(checked.problems.len(), 1, "{:?}", checked.problems);
    assert!(
        checked.problems[0].starts_with("the policy is written wrong: reviewed: "),
        "{:?}",
        checked.problems
    );
}

#[test]
fn a_failure_the_lines_cover_but_cannot_name_yet_fails_the_example() {
    let mut policy = policy();
    policy["requirements"]["reviewed"]["min_subjects"] = json!(2);
    let report = ergo_policy_engine::report(&input(), &policy, &json!({}));
    let problems = examples::check(
        &json!([{"reviewed is not met": ["pull request 7 passes peer_approved"]}]),
        &report,
    )
    .problems;
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems[0].starts_with("can't check this yet: lines for checks Ergo adds"),
        "{problems:?}"
    );
    let problems = examples::check(
        &json!([{"reviewed": ["pull request 7 passes peer_approved"]}]),
        &report,
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
        &report,
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
            &report
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
            &report
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
