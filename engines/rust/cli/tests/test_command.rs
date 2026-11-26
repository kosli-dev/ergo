use ergo_policy_cli::{Failure, Outcome, run};
use ergo_policy_engine::SPEC;
use std::fs;

const POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  approved:
    subject: deployment
    checks:
      approver_set: approver is a non-empty string
      not_self_approved: approver does not equal author
"#;

const EXAMPLES: &str = r#"example_params: {}
examples:
  - name: a deployment needs an approver
    input: {deployments: [{id: d1, author: ann}, {id: d2, author: ann, approver: bob}]}
    outcome:
      - approved:
          - deployment d1 fails approver_set because approver is missing
          - deployment d2 passes approver_set
  - name: nobody approves their own deployment
    input: {deployments: [{id: d1, author: ann, approver: ann}]}
    outcome:
      - approved is not met:
          - deployment d1 fails not_self_approved because approver is "ann", and author is "ann"
"#;

fn file(name: &str, file: &str, text: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-test-{}-{name}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join(file);
    fs::write(&path, text.replace("{{spec}}", SPEC)).unwrap();
    path.to_string_lossy().into_owned()
}

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

#[test]
fn help_lists_test_format_outcome_and_strict_as_experimental() {
    let usage = ergo_policy_cli::USAGE;
    for needle in [
        "\n       ergo report --format outcome --policy <file> --input <file> [--params <file>] [--fail]\n       ergo test <policy file> [--strict]\n",
        "\n  test         experimental: run the examples in a policy\n",
        "\n  1  with --fail, a check failed; with test, an example failed, or --strict and a warning\n",
    ] {
        assert!(usage.contains(needle), "{usage}");
    }
}

#[test]
fn report_with_format_outcome_prints_the_outcome_as_yaml() {
    let policy = file("format", "policy.yaml", POLICY);
    let input = file(
        "format",
        "input.json",
        r#"{"deployments": [{"id": "d1", "author": "ann", "approver": "ann"}]}"#,
    );
    assert_eq!(
        run(&args(&["report", "--policy", &policy, "--input", &input, "--format", "outcome"])),
        Ok(Outcome::Print(
            "- not compliant\n- approved is not met:\n    - deployment d1 passes approver_set\n    - deployment d1 fails not_self_approved because approver is \"ann\", and author is \"ann\"\n".to_string()
        ))
    );
    assert_eq!(
        run(&args(&["report", "--policy", &policy, "--input", &input, "--format=outcome", "--fail"])),
        Ok(Outcome::PrintAndFail(
            "- not compliant\n- approved is not met:\n    - deployment d1 passes approver_set\n    - deployment d1 fails not_self_approved because approver is \"ann\", and author is \"ann\"\n".to_string(),
            1
        ))
    );
    let json = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--format", "json",
    ]));
    assert!(matches!(json, Ok(Outcome::Print(text)) if text.starts_with('{')));
}

#[test]
fn format_outcome_fails_on_a_row_it_cannot_show_yet() {
    let policy = file("format-not-yet", "policy.yaml", POLICY);
    let input = file("format-not-yet", "input.json", r#"{"deployments": []}"#);
    let got = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--format", "outcome",
    ]));
    let Err(Failure::Unsupported(message)) = got else {
        panic!("{got:?}");
    };
    assert!(message.contains("checks Ergo adds"), "{message}");
}

const NAMED_WITH_A_STATUS: &str = r#"ergo_spec: {{spec}}
subjects:
  t: {from: ts, identified_by: id}
requirements:
  x: {subject: t, checks: {c: p is true}}
  x is met: {subject: t, checks: {c: w is true}}
"#;

#[test]
fn format_outcome_refuses_a_heading_that_could_name_two_requirements() {
    let policy = file("format-two-names", "policy.yaml", NAMED_WITH_A_STATUS);
    let input = file(
        "format-two-names",
        "input.json",
        r#"{"ts": [{"id": "t1", "p": true, "w": false}]}"#,
    );
    let got = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--format", "outcome",
    ]));
    let Err(failure) = got else {
        panic!("{got:?}");
    };
    assert_eq!(failure.code(), 2, "{failure:?}");
    assert!(
        failure.message().contains(
            "the heading x is met, for the status of x, would also name the requirement x is met"
        ),
        "{failure:?}"
    );
}

#[test]
fn format_outcome_with_fail_exits_three_on_a_policy_written_wrong_as_json_does() {
    let wrong = POLICY.replace("approver is a non-empty string", "approver sparkles");
    let policy = file("format-written-wrong", "policy.yaml", &wrong);
    let input = file(
        "format-written-wrong",
        "input.json",
        r#"{"deployments": [{"id": "d1", "author": "ann", "approver": "bob"}]}"#,
    );
    let json = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--fail",
    ]));
    assert!(matches!(json, Ok(Outcome::PrintAndFail(_, 3))), "{json:?}");
    let got = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--format", "outcome", "--fail",
    ]));
    let Err(failure) = got else {
        panic!("{got:?}");
    };
    assert_eq!(failure.code(), 3, "{failure:?}");
    assert!(
        failure.message().starts_with(&format!(
            "the policy file {policy} is written wrong, so the report can't be shown as an outcome: "
        )),
        "{failure:?}"
    );
    let without_fail = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--format", "outcome",
    ]));
    assert!(
        matches!(&without_fail, Err(failure) if failure.code() == 2),
        "{without_fail:?}"
    );
}

#[test]
fn format_takes_json_or_outcome_and_outcome_only_with_report() {
    let policy = file("format-wrong", "policy.yaml", POLICY);
    let input = file("format-wrong", "input.json", r#"{"deployments": []}"#);
    let cases = [
        (
            vec!["report", "--format", "xml"],
            "--format must be json or outcome",
        ),
        (
            vec!["violations", "--format", "outcome"],
            "--format outcome only goes with report",
        ),
        (
            vec!["report", "--format", "outcome", "--compact"],
            "--compact can't go with --format outcome",
        ),
        (vec!["report", "--strict"], "--strict only goes with test"),
    ];
    for (start, message) in cases {
        let mut all = start.clone();
        all.extend(["--policy", &policy, "--input", &input]);
        assert_eq!(
            run(&args(&all)),
            Err(Failure::Usage(message.to_string())),
            "{start:?}"
        );
    }
}

#[test]
fn test_runs_every_example_and_passes_when_each_says_what_its_report_says() {
    let policy = file("test-pass", "policy.yaml", &format!("{POLICY}{EXAMPLES}"));
    assert_eq!(
        run(&args(&["test", &policy])),
        Ok(Outcome::Print(
            "passed: a deployment needs an approver\npassed: nobody approves their own deployment\nwarning: no example shows not_self_approved of approved passing\n2 examples: 2 passed, 0 failed\n".to_string()
        ))
    );
    assert_eq!(
        run(&args(&["test", &policy, "--strict"])),
        Ok(Outcome::PrintAndFail(
            "passed: a deployment needs an approver\npassed: nobody approves their own deployment\nwarning: no example shows not_self_approved of approved passing\n2 examples: 2 passed, 0 failed\n".to_string(),
            1
        ))
    );
}

#[test]
fn test_shows_a_failed_example_with_its_lines_next_to_the_report_and_exits_one() {
    let failing = EXAMPLES.replace(
        "deployment d2 passes approver_set",
        "deployment d2 fails approver_set",
    );
    let policy = file("test-fail", "policy.yaml", &format!("{POLICY}{failing}"));
    assert_eq!(
        run(&args(&["test", &policy])),
        Ok(Outcome::PrintAndFail(
            "failed: a deployment needs an approver
  the report says deployment d2 passes approver_set
  expected:
    - approved:
        - deployment d1 fails approver_set because approver is missing
        - deployment d2 fails approver_set
  actual:
    - approved:
        - deployment d1 fails approver_set because approver is missing
        - deployment d2 passes approver_set
passed: nobody approves their own deployment
warning: no example shows approver_set of approved failing
warning: no example shows approver_set of approved passing
warning: no example shows not_self_approved of approved passing
2 examples: 1 passed, 1 failed
"
            .to_string(),
            1
        ))
    );
}

#[test]
fn test_counts_one_example_as_one_example() {
    let one = EXAMPLES.split("  - name: nobody").next().unwrap();
    let policy = file("test-one", "policy.yaml", &format!("{POLICY}{one}"));
    let Ok(Outcome::Print(text)) = run(&args(&["test", &policy])) else {
        panic!();
    };
    assert!(
        text.ends_with("\n1 example: 1 passed, 0 failed\n"),
        "{text}"
    );
}

#[test]
fn test_refuses_examples_written_wrong() {
    let twice = EXAMPLES.replace(
        "nobody approves their own deployment",
        "a deployment needs an approver",
    );
    let policy = file("test-twice", "policy.yaml", &format!("{POLICY}{twice}"));
    assert_eq!(
        run(&args(&["test", &policy])),
        Err(Failure::File(format!(
            "the examples in the policy file {policy} are written wrong: two examples are called a deployment needs an approver"
        )))
    );
}

#[test]
fn test_refuses_a_key_written_twice_in_examples_or_example_params() {
    let cases = [
        (
            format!("{EXAMPLES}    outcome:\n      - compliant\n"),
            "the key outcome is written twice in examples[1]",
        ),
        (
            EXAMPLES.replace("example_params: {}", "example_params: {a: 1, a: 2}"),
            "the key a is written twice in example_params",
        ),
        (
            EXAMPLES.replace(
                "{id: d1, author: ann}",
                "{id: d1, author: ann, author: bob}",
            ),
            "the key author is written twice in examples[0].input.deployments[0]",
        ),
        (
            format!("{EXAMPLES}examples: []\n"),
            "the key examples is written twice",
        ),
    ];
    for (n, (examples, problem)) in cases.into_iter().enumerate() {
        let policy = file(
            &format!("test-key-twice-{n}"),
            "policy.yaml",
            &format!("{POLICY}{examples}"),
        );
        assert_eq!(
            run(&args(&["test", &policy])),
            Err(Failure::File(format!(
                "the examples in the policy file {policy} are written wrong: {problem}"
            ))),
            "{problem}"
        );
    }
    let elsewhere = POLICY.replace(
        "    identified_by: id\n",
        "    identified_by: id\n    identified_by: id\n",
    );
    let policy = file(
        "test-key-twice-elsewhere",
        "policy.yaml",
        &format!("{elsewhere}{EXAMPLES}"),
    );
    assert!(matches!(
        run(&args(&["test", &policy])),
        Ok(Outcome::Print(_))
    ));
}

#[test]
fn test_refuses_an_outcome_written_wrong_as_it_refuses_a_missing_one() {
    for (n, (outcome, problem)) in [
        ("    outcome:\n", "example e: the outcome isn't a list"),
        ("    outcome: []\n", "example e: the outcome is empty"),
        (
            "    outcome: compliant\n",
            "example e: the outcome isn't a list",
        ),
        (
            "    outcome:\n      - approved:\n",
            "example e: the heading approved lists no lines",
        ),
    ]
    .into_iter()
    .enumerate()
    {
        let examples = format!("examples:\n  - name: e\n    input: {{}}\n{outcome}");
        let policy = file(
            &format!("test-outcome-wrong-{n}"),
            "policy.yaml",
            &format!("{POLICY}{examples}"),
        );
        let got = run(&args(&["test", &policy]));
        assert_eq!(
            got,
            Err(Failure::File(format!(
                "the examples in the policy file {policy} are written wrong: {problem}"
            ))),
            "{outcome}"
        );
        assert_eq!(got.unwrap_err().code(), 2);
    }
}

#[test]
fn test_takes_one_policy_file_and_strict() {
    let cases = [
        (vec!["test"], "test needs a policy file"),
        (
            vec!["test", "a.yaml", "b.yaml"],
            "unexpected argument 'b.yaml'",
        ),
        (
            vec!["test", "a.yaml", "--input", "i.json"],
            "--input only goes with report and violations",
        ),
        (
            vec!["test", "a.yaml", "--strict=yes"],
            "--strict takes no value",
        ),
    ];
    for (all, message) in cases {
        assert_eq!(
            run(&args(&all)),
            Err(Failure::Usage(message.to_string())),
            "{all:?}"
        );
    }
}

const ODD_POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  pull:
    from: pulls
    identified_by: id
  pull request:
    from: prs
    identified_by: id
  t:
    from: ts
    identified_by: id
  t x:
    from: txs
    identified_by: id
requirements:
  pulled:
    subject: pull
    checks:
      c: name is "ok"
  reviewed:
    subject: pull request
    min_subjects: 0
    checks:
      c: name is "ok"
  checked:
    subject: t
    checks:
      c: name is "ok"
      'c because name is "x"': name exists
  'a: b':
    subject: t x
    checks:
      'c #1': name is "ok"
"#;

fn ascii_json(value: &serde_json::Value) -> String {
    value
        .to_string()
        .chars()
        .map(|c| {
            if c.is_ascii() && !c.is_control() {
                c.to_string()
            } else {
                format!("\\u{:04x}", c as u32)
            }
        })
        .collect()
}

fn odd_input() -> serde_json::Value {
    let mut odd = vec!["request".to_string()];
    for c in [
        '\u{7f}', '\u{80}', '\u{85}', '\u{9b}', '\u{9f}', '\u{2028}', '\u{2029}', '\u{1}', '\t',
        '\n', '"', '\\', ':', '#', '\'',
    ] {
        odd.push(format!("a{c}b"));
        odd.push(c.to_string());
    }
    let pulls: Vec<serde_json::Value> = odd
        .iter()
        .enumerate()
        .map(|(n, id)| serde_json::json!({"id": id, "name": if n % 2 == 0 { "ok" } else { id }}))
        .collect();
    let txs: Vec<serde_json::Value> = ["7.0", "1.50", "1e3", "-0", "1e400"]
        .iter()
        .map(|n| serde_json::json!({"id": serde_json::from_str::<serde_json::Value>(n).unwrap(), "name": "no"}))
        .collect();
    serde_json::json!({
        "pulls": pulls,
        "prs": [],
        "ts": [{"id": "x", "name": "x"}, {"id": "y", "name": "ok"}],
        "txs": txs,
    })
}

enum RoundTrip {
    PastedBack,
    Refused,
}

fn round_trip(name: &str, policy_text: &str, input: &serde_json::Value) -> RoundTrip {
    let policy = file(name, "policy.yaml", policy_text);
    let input_file = file(name, "input.json", &ascii_json(input));
    let printed = match run(&args(&[
        "report",
        "--policy",
        &policy,
        "--input",
        &input_file,
        "--format",
        "outcome",
    ])) {
        Ok(Outcome::Print(printed)) => printed,
        Err(failure) if failure.code() == 2 => return RoundTrip::Refused,
        got => panic!("{name}: --format outcome gave {got:?}"),
    };
    let pasted: String = printed
        .lines()
        .map(|line| format!("      {line}\n"))
        .collect();
    let with_example = format!(
        "{policy_text}examples:\n  - name: round trip\n    input: {}\n    outcome:\n{pasted}",
        ascii_json(input)
    );
    let tested = file(name, "tested.yaml", &with_example);
    let got = run(&args(&["test", &tested]));
    assert!(
        matches!(&got, Ok(Outcome::Print(text)) if text.starts_with("passed: round trip\n")),
        "{name}: printed\n{printed}\nbut ergo test gave {got:?}"
    );
    RoundTrip::PastedBack
}

const NAMED_NOT_MET: &str = r#"ergo_spec: {{spec}}
subjects:
  t: {from: ts, identified_by: id}
requirements:
  a: {subject: t, checks: {c: p is true}}
  a is not met: {subject: t, checks: {c: w is true}}
"#;

const CHILD_POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  pull request:
    from: prs
    identified_by: number
  release:
    from: 'every "pull request".releases'
    identified_by: tag
  test run:
    from: every release.runs
    identified_by: id
  release train:
    from: trains
    identified_by: id
requirements:
  shipped:
    subject: release
    checks:
      signed: signed is true
  ran:
    subject: test run
    checks:
      ok: ok is true
  spare:
    subject: release train
    min_subjects: 0
    checks:
      ok: ok is true
"#;

fn child_input() -> serde_json::Value {
    serde_json::json!({"trains": [], "prs": [
        {"number": 7, "releases": [
            {"tag": "release", "signed": true, "runs": [
                {"id": true, "ok": true},
                {"id": "pull request", "ok": false},
                {"id": "in", "ok": true}
            ]},
            {"tag": "train", "signed": false, "runs": [{"id": 1.50, "ok": true}]},
            {"tag": "v 1", "signed": true, "runs": [{"id": "release", "ok": false}]}
        ]},
        {"number": 8, "releases": [
            {"tag": "release", "signed": true, "runs": [{"id": true, "ok": false}]}
        ]}
    ]})
}

const NUMBER_PARENT_POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  deployment:
    from: deployments
    identified_by: id
  deployment 7:
    from: sevens
    identified_by: id
  artifact:
    from: every deployment.artifacts
    identified_by: name
requirements:
  tested:
    subject: artifact
    checks:
      ok: ok is true
  spare:
    subject: deployment 7
    min_subjects: 0
    checks:
      ok: ok is true
"#;

#[test]
fn format_outcome_prints_a_child_subject_with_each_parent_after_in() {
    let policy = file("format-child", "policy.yaml", CHILD_POLICY);
    let input = file("format-child", "input.json", &ascii_json(&child_input()));
    let Ok(Outcome::Print(printed)) = run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--format", "outcome",
    ])) else {
        panic!();
    };
    assert_eq!(
        printed,
        r#"- not compliant
- ran is not met:
    - test run true in release release in pull request 7 passes ok
    - test run "pull request" in release release in pull request 7 fails ok because ok is false
    - test run in in release release in pull request 7 passes ok
    - test run 1.5 in release "train" in pull request 7 passes ok
    - test run release in release "v 1" in pull request 7 fails ok because ok is false
    - test run true in release release in pull request 8 fails ok because ok is false
- shipped is not met:
    - release release in pull request 7 passes signed
    - release "train" in pull request 7 fails signed because signed is false
    - release "v 1" in pull request 7 passes signed
    - release release in pull request 8 passes signed
- spare is not applicable
"#
    );
}

fn without_spare(policy: &str) -> &str {
    policy.split("  spare:\n").next().unwrap()
}

#[test]
fn format_outcome_prints_the_same_lines_whether_or_not_a_requirement_uses_every_subject() {
    let input = file("format-unused", "input.json", &ascii_json(&child_input()));
    let printed = |policy_text: &str| {
        let policy = file("format-unused", "policy.yaml", policy_text);
        let Ok(Outcome::Print(printed)) = run(&args(&[
            "report", "--policy", &policy, "--input", &input, "--format", "outcome",
        ])) else {
            panic!();
        };
        printed
    };
    let used = printed(CHILD_POLICY);
    assert_eq!(
        printed(without_spare(CHILD_POLICY)),
        used.strip_suffix("- spare is not applicable\n").unwrap()
    );
}

#[test]
fn what_format_outcome_prints_pasted_under_outcome_passes_ergo_test_or_is_refused() {
    let met = serde_json::json!({"ts": [{"id": "t1", "p": true, "w": false}]});
    let not_met = serde_json::json!({"ts": [{"id": "t1", "p": false, "w": false}]});
    let number_parent = serde_json::json!({"sevens": [], "deployments": [
        {"id": 7, "artifacts": [{"name": "a", "ok": true}]}
    ]});
    for (name, policy, input, pasted_back) in [
        ("round-trip", ODD_POLICY, odd_input(), true),
        ("round-trip-child", CHILD_POLICY, child_input(), true),
        (
            "round-trip-child-unused",
            without_spare(CHILD_POLICY),
            child_input(),
            true,
        ),
        (
            "round-trip-number-parent",
            NUMBER_PARENT_POLICY,
            number_parent.clone(),
            false,
        ),
        (
            "round-trip-number-parent-unused",
            without_spare(NUMBER_PARENT_POLICY),
            number_parent,
            false,
        ),
        ("round-trip-x-met", NAMED_WITH_A_STATUS, met.clone(), false),
        (
            "round-trip-x-not-met",
            NAMED_WITH_A_STATUS,
            not_met.clone(),
            true,
        ),
        ("round-trip-a-met", NAMED_NOT_MET, met, true),
        ("round-trip-a-not-met", NAMED_NOT_MET, not_met, false),
    ] {
        let got = round_trip(name, policy, &input);
        assert_eq!(matches!(got, RoundTrip::PastedBack), pasted_back, "{name}");
    }
}
