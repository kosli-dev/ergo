use ergo_policy_engine::SPEC;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output};

const POLICY: &str = r#"ergo_spec: {{spec}}
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

const FAILING: &str = r#"{"deployments": [
  {"id": "d-1", "environment": "prod", "approved_by": "alice"},
  {"id": "d-2", "environment": "prod"},
  {"id": "d-3", "environment": "staging"}
]}"#;

const PASSING: &str = r#"{"deployments": [
  {"id": "d-1", "environment": "prod", "approved_by": "alice"},
  {"id": "d-3", "environment": "staging"}
]}"#;

fn dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-pretty-{}-{name}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn files(name: &str, input: &str) -> (String, String) {
    let dir = dir(name);
    let policy = dir.join("policy.yaml");
    fs::write(&policy, POLICY.replace("{{spec}}", SPEC)).unwrap();
    let input_path = dir.join("input.json");
    fs::write(&input_path, input).unwrap();
    (
        policy.to_string_lossy().into_owned(),
        input_path.to_string_lossy().into_owned(),
    )
}

fn ergo(args: &[&str], env: &[(&str, &str)]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ergo"));
    command
        .args(args)
        .env_remove("NO_COLOR")
        .env_remove("LC_CTYPE")
        .env_remove("LANG")
        .env("LC_ALL", "en_US.UTF-8")
        .env_remove("ERGO_REGO");
    for (name, value) in env {
        command.env(name, value);
    }
    command.output().unwrap()
}

fn out(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).unwrap()
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

const FAILING_VIEW: &str = "✗ prod_deploy is not met\n    ✗ deployment d-2 fails approved\n      because approved_by is missing\n\n  8 rows: 6 passed, 1 failed, 1 out of scope\n\n∴ not compliant\n";

#[test]
fn a_failing_report_is_shown_piped_with_glyphs_and_no_colour() {
    let (policy, input) = files("fail", FAILING);
    let output = ergo(
        &[
            "report", "--format", "pretty", "--policy", &policy, "--input", &input,
        ],
        &[],
    );
    assert_eq!(out(&output), FAILING_VIEW);
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn color_always_writes_ansi_codes_even_when_piped_and_never_does_not() {
    let (policy, input) = files("color", FAILING);
    let base = [
        "report", "--format", "pretty", "--policy", &policy, "--input", &input,
    ];
    let always = out(&ergo(&[&base[..], &["--color", "always"]].concat(), &[]));
    assert!(
        always.contains("\x1b[31m✗ prod_deploy is not met\x1b[0m\n"),
        "{always}"
    );
    assert!(
        always.ends_with("\x1b[1;31m∴ not compliant\x1b[0m\n"),
        "{always}"
    );
    let never = out(&ergo(&[&base[..], &["--color", "never"]].concat(), &[]));
    assert!(!never.contains('\x1b'), "{never}");
    let forced_over_no_color = out(&ergo(
        &[&base[..], &["--color", "always"]].concat(),
        &[("NO_COLOR", "1")],
    ));
    assert!(forced_over_no_color.contains('\x1b'));
}

#[test]
fn no_color_is_read_only_when_it_is_not_empty_and_changes_nothing_piped() {
    let (policy, input) = files("nocolor", FAILING);
    let args = [
        "report", "--format", "pretty", "--policy", &policy, "--input", &input,
    ];
    for value in ["1", ""] {
        let text = out(&ergo(&args, &[("NO_COLOR", value)]));
        assert!(!text.contains('\x1b'), "{value}: {text}");
    }
}

#[test]
fn without_a_utf8_locale_words_stand_in_for_the_glyphs() {
    let (policy, input) = files("words", FAILING);
    let output = ergo(
        &[
            "report", "--format", "pretty", "--policy", &policy, "--input", &input,
        ],
        &[("LC_ALL", "C")],
    );
    let text = out(&output);
    assert!(
        text.starts_with("FAIL prod_deploy is not met\n    FAIL deployment d-2 fails approved\n"),
        "{text}"
    );
    assert!(text.ends_with("-> not compliant\n"), "{text}");
}

#[test]
fn show_all_lists_every_row() {
    let (policy, input) = files("all", FAILING);
    let text = out(&ergo(
        &[
            "report", "--format", "pretty", "--show", "all", "--policy", &policy, "--input", &input,
        ],
        &[],
    ));
    assert!(
        text.contains("    ✓ deployment d-1 passes approved\n"),
        "{text}"
    );
    assert!(
        text.contains("    – deployment d-3 is out of scope (environment is \"staging\")\n"),
        "{text}"
    );
}

#[test]
fn a_compliant_report_ends_with_compliant_and_exits_zero_with_fail() {
    let (policy, input) = files("ok", PASSING);
    let output = ergo(
        &[
            "report", "--format", "pretty", "--fail", "--policy", &policy, "--input", &input,
        ],
        &[],
    );
    assert_eq!(
        out(&output),
        "✓ prod_deploy is met\n\n  6 rows: 5 passed, 0 failed, 1 out of scope\n\n∴ compliant\n"
    );
    assert_eq!(output.status.code(), Some(0));
}

#[test]
fn fail_still_gives_exit_one_for_a_failing_report() {
    let (policy, input) = files("exit", FAILING);
    let output = ergo(
        &[
            "report", "--format", "pretty", "--fail", "--policy", &policy, "--input", &input,
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(out(&output).ends_with("∴ not compliant\n"));
}

#[test]
fn unknown_values_exit_two_and_name_the_allowed_ones() {
    let (policy, input) = files("bad", FAILING);
    for (flags, message) in [
        (
            vec!["--format", "xml"],
            "--format must be json, outcome or pretty",
        ),
        (
            vec!["--format", "pretty", "--show", "some"],
            "--show must be failed or all",
        ),
        (
            vec!["--format", "pretty", "--color", "red"],
            "--color must be auto, always or never",
        ),
    ] {
        let mut args = vec![
            "report",
            "--policy",
            policy.as_str(),
            "--input",
            input.as_str(),
        ];
        args.extend(flags);
        let output = ergo(&args, &[]);
        assert_eq!(output.status.code(), Some(2));
        assert!(String::from_utf8_lossy(&output.stderr).contains(message));
        assert!(out(&output).is_empty());
    }
}

#[test]
fn json_outcome_and_violations_and_version_have_no_colour_or_therefore_sign() {
    let (policy, input) = files("others", FAILING);
    for args in [
        vec!["report", "--policy", &policy, "--input", &input],
        vec![
            "report", "--format", "outcome", "--policy", &policy, "--input", &input,
        ],
        vec!["violations", "--policy", &policy, "--input", &input],
        vec!["--version"],
    ] {
        let text = out(&ergo(&args, &[]));
        assert!(
            !text.contains('\x1b') && !text.contains('∴'),
            "{args:?}: {text}"
        );
    }
    let help = out(&ergo(&["--help"], &[]));
    assert!(help.lines().next().unwrap().contains('∴'));
}

#[test]
fn engine_rego_gives_the_same_view_as_the_rust_engine() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    for (name, input) in [("rego-fail", FAILING), ("rego-ok", PASSING)] {
        let (policy, input) = files(name, input);
        let args = [
            "report", "--format", "pretty", "--policy", &policy, "--input", &input,
        ];
        let rust = out(&ergo(&args, &[]));
        let rego = out(&ergo(
            &[&args[..], &["--engine", "rego", "--ergo-rego", &ergo_rego]].concat(),
            &[],
        ));
        assert_eq!(rego, rust, "{name}");
    }
}

#[test]
fn engine_rego_colours_like_the_rust_engine() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let (policy, input) = files("rego-color", FAILING);
    let text = out(&ergo(
        &[
            "report",
            "--format",
            "pretty",
            "--color",
            "always",
            "--policy",
            &policy,
            "--input",
            &input,
            "--engine",
            "rego",
            "--ergo-rego",
            &ergo_rego,
        ],
        &[],
    ));
    assert!(
        text.contains("\x1b[31m✗ prod_deploy is not met\x1b[0m\n"),
        "{text}"
    );
}

#[test]
fn a_compliant_verdict_line_is_bold_green_with_colour_and_plain_without() {
    let (policy, input) = files("compliant-colour", PASSING);
    let base = [
        "report", "--format", "pretty", "--policy", &policy, "--input", &input,
    ];
    let always = out(&ergo(&[&base[..], &["--color", "always"]].concat(), &[]));
    assert!(
        always.ends_with("\n\x1b[1;32m∴ compliant\x1b[0m\n"),
        "{always}"
    );
    let never = out(&ergo(&[&base[..], &["--color", "never"]].concat(), &[]));
    assert!(!never.contains('\x1b'), "{never}");
    assert!(never.ends_with("\n∴ compliant\n"), "{never}");
}
