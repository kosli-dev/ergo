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
