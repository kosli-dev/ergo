use ergo_policy_engine::SPEC;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output};

const APPLIES_POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
requirements:
  approved:
    subject: deployment
    checks:
      approver_set: approver is a non-empty string
"#;

const APPLIES_INPUT: &str = r#"{"deployments": [
  {"id": "d1", "environment": "prod", "approver": "bob"},
  {"id": "d2", "approver": ""}
]}"#;

const ARTIFACTS_POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  deployment:
    from: deployments
    identified_by: id
  artifact:
    from: every deployment.artifacts
    identified_by: name
requirements:
  tested:
    subject: artifact
    checks:
      tests_passed: tests is "passed"
"#;

const ARTIFACTS_INPUT: &str = r#"{"deployments": [
  {"id": "d1", "artifacts": [{"name": "web", "tests": "failed"}]},
  {"id": "d2", "artifacts": [{"name": "web", "tests": "failed"}]},
  {"id": "d3", "artifacts": []}
]}"#;

fn files(name: &str, policy: &str, input: &str) -> (String, String) {
    let dir: PathBuf = std::env::temp_dir().join(format!(
        "ergo-policy-cli-applies-{}-{name}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).unwrap();
    let policy_path = dir.join("policy.yaml");
    fs::write(&policy_path, policy.replace("{{spec}}", SPEC)).unwrap();
    let input_path = dir.join("input.json");
    fs::write(&input_path, input).unwrap();
    (
        policy_path.to_string_lossy().into_owned(),
        input_path.to_string_lossy().into_owned(),
    )
}

fn ergo(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ergo"))
        .args(args)
        .env_remove("NO_COLOR")
        .env_remove("LC_CTYPE")
        .env_remove("LANG")
        .env_remove("ERGO_REGO")
        .env_remove("ERGO_OPA")
        .env("LC_ALL", "en_US.UTF-8")
        .output()
        .unwrap()
}

fn pretty(policy: &str, input: &str, extra: &[&str]) -> String {
    let output = ergo(
        &[
            &[
                "report", "--format", "pretty", "--policy", policy, "--input", input,
            ][..],
            extra,
        ]
        .concat(),
    );
    String::from_utf8(output.stdout).unwrap()
}

fn built_ergo_rego() -> Option<String> {
    if std::env::var_os("ERGO_TEST_NO_OPA").is_some() {
        eprintln!("skipped: ERGO_TEST_NO_OPA is set");
        return None;
    }
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../dist/ergo.rego");
    assert!(
        std::path::Path::new(path).is_file(),
        "no {path}: build it with .github/build-ergo.sh from the root of the repo, or set ERGO_TEST_NO_OPA to skip the tests that need opa and ergo.rego"
    );
    Some(path.to_string())
}

#[test]
fn an_applies_row_that_fails_with_absent_is_a_failure_in_both_engines() {
    let (policy, input) = files("absent", APPLIES_POLICY, APPLIES_INPUT);
    let rust = pretty(&policy, &input, &[]);
    assert_eq!(
        rust,
        "✗ approved is not met\n    ✗ deployment d2 fails $applies\n      because environment is missing\n\n  6 rows: 5 passed, 1 failed, 0 out of scope\n\n∴ not compliant\n"
    );
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let rego = pretty(
        &policy,
        &input,
        &["--engine", "rego", "--ergo-rego", &ergo_rego],
    );
    assert_eq!(rego, rust);
}

#[test]
fn a_subject_out_of_scope_with_a_value_cause_is_still_only_counted() {
    let (policy, input) = files(
        "value",
        APPLIES_POLICY,
        r#"{"deployments": [{"id": "d1", "environment": "prod", "approver": "bob"}, {"id": "d2", "environment": "dev"}]}"#,
    );
    assert_eq!(
        pretty(&policy, &input, &[]),
        "✓ approved is met\n\n  6 rows: 5 passed, 0 failed, 1 out of scope\n\n∴ compliant\n"
    );
}

#[test]
fn rows_of_child_subjects_say_which_parent_they_are_in_in_both_engines() {
    let (policy, input) = files("parents", ARTIFACTS_POLICY, ARTIFACTS_INPUT);
    let rust = pretty(&policy, &input, &[]);
    assert!(
        rust.contains("    ✗ artifact web in deployment d1 fails tests_passed\n"),
        "{rust}"
    );
    assert!(
        rust.contains("    ✗ artifact web in deployment d2 fails tests_passed\n"),
        "{rust}"
    );
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let rego = pretty(
        &policy,
        &input,
        &["--engine", "rego", "--ergo-rego", &ergo_rego],
    );
    assert_eq!(rego, rust);
}
