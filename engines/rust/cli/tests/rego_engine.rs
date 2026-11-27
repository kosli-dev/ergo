use ergo_policy_cli::args::{Engine, Parsed, TestOptions, parse};
use ergo_policy_cli::examples::Example;
use ergo_policy_cli::opa;
use ergo_policy_cli::{Environment, Failure, Outcome, run, run_in};
use serde_json::{Value, json};

fn example(name: &str, input: Value, params: Value) -> Example {
    Example {
        name: name.to_string(),
        input,
        params,
        outcome: json!(["compliant"]),
    }
}

fn report(engine: Value, results: Value) -> Value {
    json!({"compliant": true, "engine": engine, "results": results})
}

#[test]
fn opa_reads_the_policy_and_each_example_input_and_params_from_one_data_file() {
    let policy = json!({"ergo_spec": "v0", "requirements": {}});
    let examples = [
        example("a", json!({"n": 1.50}), json!({})),
        example("b", json!([]), json!({"p": true})),
    ];
    assert_eq!(
        opa::data(&policy, &examples),
        json!({"ergo_cli_test": {
            "policy": policy,
            "examples": [
                {"input": {"n": 1.50}, "params": {}},
                {"input": [], "params": {"p": true}},
            ],
        }})
    );
    assert_eq!(
        opa::QUERY,
        "[reports | compiled := data.ergo.compile(data.ergo_cli_test.policy); reports := [data.ergo.report(e.input, compiled, e.params) | e := data.ergo_cli_test.examples[_]]][0]"
    );
}

#[test]
fn opa_output_is_read_as_one_report_per_example_or_refused() {
    let engine = json!({"name": "ergo-rego", "version": "1.0.0"});
    let one = report(engine.clone(), json!([]));
    let two = format!("[{one}, {one}]\n");
    assert_eq!(opa::reports(&two, 2), Ok(vec![one.clone(), one.clone()]));
    let refused = [
        ("", 1),
        ("\n", 1),
        ("true\n", 1),
        ("[] trailing", 0),
        (&two, 1),
        (&two, 3),
    ];
    for (printed, count) in refused {
        assert_eq!(
            opa::reports(printed, count),
            Err(format!(
                "opa printed something that isn't a report for each of the {count} examples"
            )),
            "{printed} {count}"
        );
    }
}

#[test]
fn opa_output_that_is_not_a_report_says_what_is_wrong_with_it() {
    let reasons = [
        ("[1]", "report 1 isn't an object"),
        ("[{}]", "report 1: results isn't a list"),
        (
            r#"[{"engine": {"name": "ergo-rego", "version": "1"}, "results": {}}]"#,
            "report 1: results isn't a list",
        ),
        (
            r#"[{"engine": {"name": "ergo-rego"}, "results": []}]"#,
            "report 1: engine.version isn't text",
        ),
        (
            r#"[{"engine": "ergo-rego 1", "results": []}]"#,
            "report 1: engine.name isn't text",
        ),
        (r#"[{"results": []}]"#, "report 1: engine.name isn't text"),
    ];
    for (printed, reason) in reasons {
        assert_eq!(
            opa::reports(printed, 1),
            Err(format!(
                "opa printed something that isn't a report for each of the 1 examples: {reason}"
            )),
            "{printed}"
        );
    }
}

#[test]
fn the_engine_line_names_the_engine_the_report_gives() {
    let given = report(json!({"name": "ergo-rego", "version": "0.5.1"}), json!([]));
    assert_eq!(opa::engine_line(&given), "engine: ergo-rego 0.5.1\n");
}

#[test]
fn a_policy_spec_that_ergo_rego_does_not_support_is_found_in_its_well_formed_row() {
    let row = |check: &str, passed: bool, value: Value| {
        json!({"check": check, "passed": passed, "inputs": [
            {"name": "count(checks)", "value": 1, "locations": []},
            {"name": "policy ergo_spec", "value": value, "locations": []},
        ]})
    };
    let engine = json!({"name": "ergo-rego", "version": "0.5.1"});
    let unsupported = json!(["unsupported version v0.5, expected v9.9-dev"]);
    assert_eq!(
        opa::unsupported_spec(&report(
            engine.clone(),
            json!([row("$well_formed", false, unsupported.clone())])
        )),
        Some("policy ergo_spec: unsupported version v0.5, expected v9.9-dev".to_string())
    );
    for results in [
        json!([]),
        json!([row("$well_formed", false, json!(["missing"]))]),
        json!([row("$well_formed", false, json!(["not a version v"]))]),
        json!([row("c", false, unsupported.clone())]),
        json!([row(
            "$well_formed",
            false,
            json!("unsupported version v0.5")
        )]),
    ] {
        assert_eq!(
            opa::unsupported_spec(&report(engine.clone(), results.clone())),
            None,
            "{results}"
        );
    }
}

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
      allowed: approver is in $params.approvers
tests:
  params: {approvers: [bob]}
  examples:
    - name: a deployment needs an approver
      input: {deployments: [{id: d1, author: ann}, {id: d2, author: ann, approver: bob}]}
      outcome:
        - approved:
            - deployment d1 fails approver_set because approver is missing
            - deployment d2 passes approver_set
            - deployment d1 fails allowed because approver is missing
            - deployment d2 passes allowed
    - name: each example can have its own params
      input: {deployments: [{id: d1, author: ann, approver: bob}]}
      params: {approvers: [cat]}
      outcome:
        - approved:
            - deployment d1 fails allowed
"#;

fn file(name: &str, file: &str, text: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-rego-{}-{name}",
        std::process::id()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(file);
    std::fs::write(&path, text.replace("{{spec}}", ergo_policy_engine::SPEC)).unwrap();
    path.to_string_lossy().into_owned()
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

fn with_rego(ergo_rego: &str) -> Environment {
    Environment {
        ergo_rego: Some(ergo_rego.to_string()),
        opa: None,
    }
}

fn text(outcome: Result<Outcome, Failure>) -> (String, u8) {
    match outcome {
        Ok(Outcome::Print(text)) => (text, 0),
        Ok(Outcome::PrintAndFail(text, code)) => (text, code),
        Err(failure) => panic!("{failure:?}"),
    }
}

fn rust_and_rego(policy: &str, ergo_rego: &str) -> ((String, u8), (String, u8)) {
    let rust = text(run(&args(&["test", policy])));
    let (rego, code) = text(run_in(
        &args(&["test", "--engine", "rego", policy]),
        &with_rego(ergo_rego),
    ));
    let (first, rest) = rego.split_once('\n').unwrap();
    assert!(first.starts_with("engine: ergo-rego "), "{rego}");
    (rust, (rest.to_string(), code))
}

#[test]
fn engine_rego_builds_each_report_with_ergo_rego_and_checks_it_as_the_rust_engine_does() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let policy = file("same", "policy.yaml", POLICY);
    let (rust, rego) = rust_and_rego(&policy, &ergo_rego);
    assert_eq!(rust, rego);
    assert_eq!(
        rust,
        (
            "passed: a deployment needs an approver\npassed: each example can have its own params\nwarning: no example shows not_self_approved of approved failing\nwarning: no example shows not_self_approved of approved passing\n2 examples: 2 passed, 0 failed\n".to_string(),
            0
        )
    );
    let failing = file(
        "same-failing",
        "policy.yaml",
        &POLICY.replace("d2 passes approver_set", "d2 fails approver_set"),
    );
    let (rust, rego) = rust_and_rego(&failing, &ergo_rego);
    assert_eq!(rust, rego);
    assert_eq!(rust.1, 1);
}

#[test]
fn engine_rego_refuses_a_policy_whose_spec_ergo_rego_does_not_support() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let policy = file(
        "old-spec",
        "policy.yaml",
        &POLICY.replace("ergo_spec: {{spec}}", "ergo_spec: v0.1"),
    );
    let got = run_in(
        &args(&["test", "--engine", "rego", &policy]),
        &with_rego(&ergo_rego),
    );
    assert_eq!(
        got,
        Err(Failure::Engine(format!(
            "the ergo.rego at {ergo_rego} refuses the policy file {policy}: policy ergo_spec: unsupported version v0.1, expected {}",
            ergo_policy_engine::SPEC
        )))
    );
    assert_eq!(got.unwrap_err().code(), 2);
}

#[test]
fn engine_rego_needs_the_path_of_ergo_rego_and_the_rust_engine_refuses_it() {
    let policy = file("where", "policy.yaml", POLICY);
    assert_eq!(
        run_in(
            &args(&["test", "--engine", "rego", &policy]),
            &Environment::default()
        ),
        Err(Failure::Usage(ergo_policy_cli::get::missing("test")))
    );
    for engine in [vec![], vec!["--engine", "rust"]] {
        let all = [vec!["test", policy.as_str()], engine].concat();
        assert_eq!(
            run_in(&args(&all), &with_rego("ergo.rego")),
            Err(Failure::Usage(
                "ERGO_REGO is set, and it only goes with --engine rego".to_string()
            )),
            "{all:?}"
        );
    }
}

#[test]
fn engine_rego_fails_closed_when_ergo_rego_cannot_be_read() {
    let policy = file("unreadable", "policy.yaml", POLICY);
    let folder = std::path::Path::new(&policy)
        .parent()
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let missing = format!("{folder}/none.rego");
    for (path, problem) in [
        (missing.clone(), "No such file or directory (os error 2)"),
        (folder.clone(), "it isn't a file"),
    ] {
        assert_eq!(
            run_in(
                &args(&["test", "--engine", "rego", &policy]),
                &with_rego(&path)
            ),
            Err(Failure::Engine(ergo_policy_cli::get::unreadable(
                &format!("can't read ergo.rego at {path}: {problem}"),
                "test"
            ))),
        );
    }
    assert_eq!(
        run_in(
            &args(&["test", "--engine", "rego", "--ergo-rego", &missing, &policy]),
            &with_rego(&folder),
        ),
        Err(Failure::Engine(ergo_policy_cli::get::unreadable(
            &format!("can't read ergo.rego at {missing}: No such file or directory (os error 2)"),
            "test"
        )))
    );
}

#[cfg(unix)]
fn fake_opa(name: &str, script: &str) -> std::ffi::OsString {
    use std::os::unix::fs::PermissionsExt;
    let path = file(name, "opa", &format!("#!/bin/sh\n{script}"));
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    path.into()
}

#[cfg(unix)]
fn with_opa(ergo_rego: &str, opa: std::ffi::OsString) -> Environment {
    Environment {
        ergo_rego: Some(ergo_rego.to_string()),
        opa: Some(opa),
    }
}

#[cfg(unix)]
#[test]
fn engine_rego_names_ergo_compile_when_opa_cannot_find_it_in_ergo_rego() {
    let policy = file("no-compile", "policy.yaml", POLICY);
    let ergo_rego = file("no-compile", "ergo.rego", "package ergo\n");
    let opa = fake_opa(
        "no-compile",
        "echo '1 error occurred: 1:18: rego_type_error: undefined function data.ergo.compile' >&2\nexit 2\n",
    );
    assert_eq!(
        run_in(
            &args(&["test", "--engine", "rego", &policy]),
            &with_opa(&ergo_rego, opa)
        ),
        Err(Failure::Engine(format!(
            "opa failed on ergo.rego at {ergo_rego}: 1 error occurred: 1:18: rego_type_error: undefined function data.ergo.compile; ergo test needs ergo.compile, which OPA.md calls experimental, and this ergo.rego doesn't have it"
        )))
    );
}

#[cfg(unix)]
#[test]
fn engine_rego_fails_closed_when_opa_is_missing_fails_or_prints_no_reports() {
    let policy = file("opa-wrong", "policy.yaml", POLICY);
    let ergo_rego = file("opa-wrong", "ergo.rego", "package ergo\n");
    let missing = ergo_rego.replace("ergo.rego", "no-opa");
    let not_reports = format!(
        "opa printed something that isn't a report for each of the 2 examples, with ergo.rego at {ergo_rego}"
    );
    let cases = [
        (
            std::ffi::OsString::from(&missing),
            format!(
                "can't run {missing}: No such file or directory (os error 2); put opa on the PATH or set ERGO_OPA"
            ),
        ),
        (
            fake_opa(
                "opa-fails",
                "echo 'first line' >&2\necho 'second line' >&2\nexit 3\n",
            ),
            format!("opa failed on ergo.rego at {ergo_rego}: first line"),
        ),
        (fake_opa("opa-silent", "exit 0\n"), not_reports.clone()),
        (
            fake_opa("opa-junk", "echo '[1, 2]'\n"),
            not_reports.replace(" examples,", " examples: report 1 isn't an object,"),
        ),
    ];
    for (opa, message) in cases {
        let got = run_in(
            &args(&["test", "--engine", "rego", &policy]),
            &with_opa(&ergo_rego, opa),
        );
        assert_eq!(got, Err(Failure::Engine(message.clone())), "{message}");
        assert_eq!(got.unwrap_err().code(), 2);
    }
}

#[cfg(unix)]
#[test]
fn engine_rego_gives_opa_the_data_in_a_file_it_removes_and_prints_the_engine_it_reports() {
    let policy = file("opa-seen", "policy.yaml", POLICY);
    let ergo_rego = file("opa-seen", "ergo.rego", "package ergo\n");
    let seen = file("opa-seen", "seen", "");
    let report =
        r#"{"compliant": false, "engine": {"name": "fake", "version": "9"}, "results": []}"#;
    let opa = fake_opa(
        "opa-seen",
        &format!(
            "printf '%s\\n' \"$@\" > {seen}\n/bin/cp -f \"$7\" {seen}.json\necho '[{report}, {report}]'\n"
        ),
    );
    let (printed, code) = text(run_in(
        &args(&["test", "--engine", "rego", &policy]),
        &with_opa(&ergo_rego, opa),
    ));
    assert!(
        printed.starts_with("engine: fake 9\nfailed: a deployment needs an approver\n"),
        "{printed}"
    );
    assert_eq!(code, 1);
    let given = std::fs::read_to_string(&seen).unwrap();
    let given: Vec<&str> = given.lines().collect();
    assert_eq!(
        given[..6],
        ["eval", "--format", "raw", "-d", ergo_rego.as_str(), "-d"]
    );
    assert!(given[6].ends_with("/data.json"), "{}", given[6]);
    assert_eq!(given[7..], [opa::QUERY]);
    let data_file = std::path::Path::new(given[6]);
    assert!(!data_file.parent().unwrap().exists(), "{given:?}");
    let data: Value =
        serde_json::from_str(&std::fs::read_to_string(format!("{seen}.json")).unwrap()).unwrap();
    let examples = &data["ergo_cli_test"]["examples"];
    assert_eq!(examples[0]["params"], json!({"approvers": ["bob"]}));
    assert_eq!(examples[1]["params"], json!({"approvers": ["cat"]}));
    assert_eq!(
        data["ergo_cli_test"]["policy"]["requirements"]["approved"]["subject"],
        "deployment"
    );
}

#[test]
fn the_ergo_command_reads_ergo_rego_and_ergo_opa_from_its_environment() {
    let policy = file("environment", "policy.yaml", POLICY);
    let ergo = |all: &[&str], vars: &[(&str, &str)]| {
        let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_ergo"));
        command
            .args(all)
            .env_remove("ERGO_REGO")
            .env_remove("ERGO_OPA");
        command.envs(vars.iter().copied());
        let output = command.output().unwrap();
        (
            output.status.code(),
            String::from_utf8(output.stderr).unwrap(),
        )
    };
    assert_eq!(
        ergo(&["test", &policy], &[("ERGO_REGO", "ergo.rego")]),
        (
            Some(2),
            "ergo: ERGO_REGO is set, and it only goes with --engine rego\n".to_string()
        )
    );
    assert_eq!(
        ergo(
            &["test", "--engine", "rego", &policy],
            &[("ERGO_REGO", &policy), ("ERGO_OPA", "/no/such/opa")]
        ),
        (
            Some(2),
            "ergo: can't run /no/such/opa: No such file or directory (os error 2); put opa on the PATH or set ERGO_OPA\n".to_string()
        )
    );
    assert!(matches!(
        ergo(&["test", &policy], &[("ERGO_REGO", "")]),
        (Some(0), _)
    ));
}

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

#[test]
fn test_takes_an_engine_and_the_path_of_ergo_rego() {
    let cases = [
        (vec!["test", "p.yaml"], Engine::Rust, None),
        (
            vec!["test", "p.yaml", "--engine", "rust"],
            Engine::Rust,
            None,
        ),
        (vec!["test", "p.yaml", "--engine=rego"], Engine::Rego, None),
        (
            vec![
                "test",
                "--engine",
                "rego",
                "--ergo-rego",
                "e.rego",
                "p.yaml",
            ],
            Engine::Rego,
            Some("e.rego".to_string()),
        ),
    ];
    for (all, engine, ergo_rego) in cases {
        assert_eq!(
            parse(&args(&all)),
            Ok(Parsed::Test(TestOptions {
                policy: "p.yaml".to_string(),
                strict: false,
                engine,
                ergo_rego,
                show: ergo_policy_cli::pretty::Show::Failed,
                color: ergo_policy_cli::pretty::Color::Auto,
            })),
            "{all:?}"
        );
    }
}

#[test]
fn engine_and_ergo_rego_are_refused_where_they_do_not_go() {
    let cases = [
        (
            vec!["test", "p.yaml", "--engine", "opa"],
            "--engine must be rust or rego",
        ),
        (vec!["test", "p.yaml", "--engine"], "--engine needs a value"),
        (
            vec!["test", "p.yaml", "--ergo-rego", "e.rego"],
            "--ergo-rego only goes with --engine rego",
        ),
        (
            vec![
                "test",
                "p.yaml",
                "--engine",
                "rust",
                "--ergo-rego",
                "e.rego",
            ],
            "--ergo-rego only goes with --engine rego",
        ),
        (
            vec![
                "report",
                "--policy",
                "p.yaml",
                "--input",
                "i.json",
                "--ergo-rego",
                "e.rego",
            ],
            "--ergo-rego only goes with --engine rego",
        ),
        (
            vec![
                "violations",
                "--policy",
                "p.yaml",
                "--input",
                "i.json",
                "--engine",
                "opa",
            ],
            "--engine must be rust or rego",
        ),
        (
            vec![
                "report", "--policy", "p.yaml", "--input", "i.json", "--strict",
            ],
            "--strict only goes with test",
        ),
    ];
    for (all, message) in cases {
        assert_eq!(
            parse(&args(&all)),
            Err(Failure::Usage(message.to_string())),
            "{all:?}"
        );
    }
}

#[cfg(unix)]
#[test]
fn engine_rego_keeps_the_folder_and_file_it_gives_opa_private_to_its_user() {
    let policy = file("opa-private", "policy.yaml", POLICY);
    let ergo_rego = file("opa-private", "ergo.rego", "package ergo\n");
    let seen = file("opa-private", "seen", "");
    let opa = fake_opa(
        "opa-private",
        &format!("ls -ld \"$(dirname \"$7\")\" \"$7\" > {seen}\necho '[]'\n"),
    );
    let _ = run_in(
        &args(&["test", "--engine", "rego", &policy]),
        &with_opa(&ergo_rego, opa),
    );
    let listing = std::fs::read_to_string(&seen).unwrap();
    let modes: Vec<&str> = listing
        .lines()
        .map(|l| l.split_whitespace().next().unwrap())
        .collect();
    assert_eq!(modes.len(), 2, "{listing}");
    assert!(modes[0].starts_with("drwx------"), "{listing}");
    assert!(modes[1].starts_with("-rw-------"), "{listing}");
}

#[cfg(unix)]
#[test]
fn engine_rego_refuses_a_path_of_ergo_rego_with_a_colon_before_running_opa() {
    let policy = file("opa-colon", "policy.yaml", POLICY);
    let ran = file("opa-colon", "ran", "");
    let opa = fake_opa("opa-colon", &format!("echo ran > {ran}\necho '[]'\n"));
    let path = "c:d/ergo.rego";
    assert_eq!(
        run_in(
            &args(&["test", "--engine", "rego", &policy]),
            &with_opa(path, opa)
        ),
        Err(Failure::Engine(format!(
            "the path of ergo.rego ({path}) holds a ':', which opa reads as a prefix; move the file"
        ))),
    );
    assert_eq!(std::fs::read_to_string(&ran).unwrap(), "");
}
