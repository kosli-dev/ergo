use serde_json::{Value, json};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const POLICY_YAML: &str = r#"ergo_spec: v0.3-dev
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
requirements:
  prod_deploy:
    description: Every production deployment is approved
    subject: deployment
    checks:
      approved:
        description: Someone approved the deployment
        assert: approved_by is a non-empty string
"#;

const INPUT_JSON: &str = r#"{
  "deployments": [
    { "id": "d-1", "environment": "prod", "approved_by": "alice" },
    { "id": "d-2", "environment": "prod" },
    { "id": "d-3", "environment": "staging" }
  ]
}
"#;

fn dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ergo-cli-{}-{name}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn write(dir: &Path, file: &str, text: &str) -> String {
    let path = dir.join(file);
    fs::write(&path, text).unwrap();
    path.to_string_lossy().into_owned()
}

fn ergo(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ergo"))
        .args(args)
        .output()
        .unwrap()
}

fn out(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).unwrap()
}

fn err(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).unwrap()
}

fn readme(name: &str) -> (String, String) {
    let dir = dir(name);
    (
        write(&dir, "policy.yaml", POLICY_YAML),
        write(&dir, "deployments.json", INPUT_JSON),
    )
}

fn rows(report: &Value) -> Vec<(String, String, bool, String)> {
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| {
            (
                row["subject"]["id"].as_str().unwrap_or("").to_string(),
                row["check"].as_str().unwrap().to_string(),
                row["passed"].as_bool().unwrap(),
                row["cause"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

#[test]
fn report_gives_the_rows_the_readme_shows() {
    let (policy, input) = readme("readme-report");
    let output = ergo(&["report", "--policy", &policy, "--input", &input]);
    assert!(output.status.success(), "{}", err(&output));
    let report: Value = serde_json::from_str(&out(&output)).unwrap();
    assert_eq!(report["compliant"], false);
    let row = |s: &str, c: &str, p: bool, k: &str| (s.to_string(), c.to_string(), p, k.to_string());
    let mut expected = vec![
        row("", "$well_formed", true, "satisfied"),
        row("", "$min_subjects", true, "satisfied"),
        row("", "$unique_ids", true, "satisfied"),
        row("d-1", "$applies", true, "satisfied"),
        row("d-2", "$applies", true, "satisfied"),
        row("d-3", "$applies", false, "value"),
        row("d-1", "approved", true, "satisfied"),
        row("d-2", "approved", false, "absent"),
    ];
    let mut got = rows(&report);
    expected.sort();
    got.sort();
    assert_eq!(got, expected);
}

#[test]
fn violations_gives_the_one_violation_the_readme_shows() {
    let (policy, input) = readme("readme-violations");
    let output = ergo(&["violations", "--policy", &policy, "--input", &input]);
    assert!(output.status.success(), "{}", err(&output));
    let violations: Value = serde_json::from_str(&out(&output)).unwrap();
    assert_eq!(
        violations,
        json!([{
            "cause": "absent",
            "check": "approved",
            "description": "Someone approved the deployment",
            "expression": "approved_by is a non-empty string",
            "inputs": [{"name": "approved_by", "value": null, "locations": ["/deployments/1"]}],
            "requirement": "prod_deploy",
            "subject": {"id": "d-2", "type": "deployment"}
        }])
    );
}

#[test]
fn a_report_that_is_not_compliant_still_exits_zero() {
    let (policy, input) = readme("exit-zero");
    let output = ergo(&["report", "--policy", &policy, "--input", &input]);
    assert_eq!(output.status.code(), Some(0));
    assert!(out(&output).contains("\"compliant\": false"));
}

#[test]
fn output_is_pretty_with_two_spaces_sorted_keys_and_a_trailing_newline() {
    let (policy, input) = readme("pretty");
    let text = out(&ergo(&[
        "violations",
        "--policy",
        &policy,
        "--input",
        &input,
    ]));
    let expected = r#"[
  {
    "cause": "absent",
    "check": "approved",
    "description": "Someone approved the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [
      {
        "locations": [
          "/deployments/1"
        ],
        "name": "approved_by",
        "value": null
      }
    ],
    "requirement": "prod_deploy",
    "subject": {
      "id": "d-2",
      "type": "deployment"
    }
  }
]
"#;
    assert_eq!(text, expected);
}

#[test]
fn compact_prints_one_line_with_sorted_keys() {
    let (policy, input) = readme("compact");
    let text = out(&ergo(&[
        "violations",
        "--policy",
        &policy,
        "--input",
        &input,
        "--compact",
    ]));
    assert_eq!(text.matches('\n').count(), 1);
    assert!(text.ends_with("]\n"));
    assert!(text.starts_with(r#"[{"cause":"absent","check":"approved","#));
}

#[test]
fn pretty_output_escapes_like_opa() {
    let dir = dir("escape");
    let policy = write(
        &dir,
        "policy.json",
        r#"{"ergo_spec":"v0.3-dev","meta":{"k":"a<b>&c\u2028é"}}"#,
    );
    let input = write(&dir, "input.json", "{}");
    let text = out(&ergo(&["report", "--policy", &policy, "--input", &input]));
    assert!(
        text.contains(r#""k": "a\u003cb\u003e\u0026c\u2028é""#),
        "{text}"
    );
}

#[test]
fn params_are_read_from_the_params_file() {
    let dir = dir("params");
    let policy = write(
        &dir,
        "policy.yaml",
        "ergo_spec: v0.3-dev\nsubjects:\n  item:\n    from: items\n    identified_by: id\nrequirements:\n  r:\n    subject: item\n    checks:\n      small: n is at most $params.limit\n",
    );
    let input = write(&dir, "input.json", r#"{"items":[{"id":"a","n":5}]}"#);
    let low = write(&dir, "low.yaml", "limit: 3\n");
    let high = write(&dir, "high.json", r#"{"limit": 9}"#);
    let run = |params: &str| -> Value {
        let o = ergo(&[
            "report", "--policy", &policy, "--input", &input, "--params", params,
        ]);
        assert!(o.status.success(), "{}", err(&o));
        serde_json::from_str(&out(&o)).unwrap()
    };
    assert_eq!(run(&low)["compliant"], false);
    assert_eq!(run(&high)["compliant"], true);
}

fn fails(args: &[&str], needle: &str) {
    let output = ergo(args);
    assert!(!output.status.success(), "{args:?} should fail");
    assert!(out(&output).is_empty(), "stdout: {}", out(&output));
    let message = err(&output);
    assert!(message.contains(needle), "{message:?} lacks {needle:?}");
    assert_eq!(message.trim_end().lines().count(), 1, "{message:?}");
}

#[test]
fn an_unknown_command_fails() {
    fails(&["frobnicate"], "unknown command 'frobnicate'");
}

#[test]
fn a_missing_policy_flag_fails() {
    let (_, input) = readme("no-policy");
    fails(&["report", "--input", &input], "--policy");
}

#[test]
fn a_missing_input_flag_fails() {
    let (policy, _) = readme("no-input");
    fails(&["violations", "--policy", &policy], "--input");
}

#[test]
fn a_flag_without_a_value_fails() {
    let (policy, _) = readme("no-value");
    fails(
        &["report", "--policy", &policy, "--input"],
        "--input needs a value",
    );
    fails(
        &["report", "--input", "--policy", &policy],
        "--input needs a value",
    );
}

#[test]
fn an_empty_value_after_an_equals_sign_is_a_missing_value() {
    let (policy, input) = readme("empty-value");
    for args in [
        ["report", "--policy=", "--input", &input],
        ["report", "--policy", &policy, "--input="],
    ] {
        let output = ergo(&args);
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert!(err(&output).contains("needs a value"), "{}", err(&output));
    }
}

#[test]
fn an_unknown_flag_fails() {
    let (policy, input) = readme("unknown-flag");
    fails(
        &[
            "report",
            "--policy",
            &policy,
            "--input",
            &input,
            "--verbose",
        ],
        "unknown flag '--verbose'",
    );
}

#[test]
fn a_repeated_flag_fails() {
    let (policy, input) = readme("repeated");
    fails(
        &[
            "report", "--policy", &policy, "--policy", &policy, "--input", &input,
        ],
        "--policy given twice",
    );
}

#[test]
fn a_missing_file_fails_and_names_it() {
    let (policy, _) = readme("missing-file");
    fails(
        &[
            "report",
            "--policy",
            &policy,
            "--input",
            "/nonexistent/in.json",
        ],
        "/nonexistent/in.json",
    );
}

#[test]
fn bad_json_fails_and_names_the_file() {
    let (policy, _) = readme("bad-json");
    let bad = write(&dir("bad-json"), "bad.json", "{not json");
    fails(
        &["report", "--policy", &policy, "--input", &bad],
        "bad.json",
    );
}

#[test]
fn bad_yaml_fails_and_names_the_file() {
    let (_, input) = readme("bad-yaml");
    let bad = write(&dir("bad-yaml"), "bad.yaml", "a: [1, 2\nb: : :\n");
    fails(&["report", "--policy", &bad, "--input", &input], "bad.yaml");
}

#[test]
fn an_unknown_extension_fails_and_names_the_file() {
    let (policy, _) = readme("extension");
    let odd = write(&dir("extension"), "input.txt", "{}");
    fails(
        &["report", "--policy", &policy, "--input", &odd],
        "input.txt",
    );
}

#[test]
fn help_prints_usage_and_exits_zero() {
    for args in [&["--help"][..], &["help"][..], &["report", "--help"][..]] {
        let output = ergo(args);
        assert_eq!(output.status.code(), Some(0));
        assert!(out(&output).starts_with("Usage: ergo"));
    }
}

#[test]
fn no_arguments_prints_usage_on_stderr_and_fails() {
    let output = ergo(&[]);
    assert!(!output.status.success());
    assert!(out(&output).is_empty());
    assert!(err(&output).contains("Usage: ergo"));
}

#[test]
fn version_prints_the_crate_version() {
    let output = ergo(&["--version"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        out(&output),
        format!("ergo {}\n", env!("CARGO_PKG_VERSION"))
    );
}
