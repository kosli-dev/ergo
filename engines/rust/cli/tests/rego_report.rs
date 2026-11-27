use ergo_policy_cli::args::{Command, Engine, Format, Options, Parsed, parse};
use ergo_policy_cli::opa;
use ergo_policy_cli::{Environment, Failure, Outcome, run, run_in};
use serde_json::{Value, json};

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
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
      allowed: approver is in $params.approvers
"#;

const INPUT: &str = r#"{"deployments": [{"id": "d1"}, {"id": "d2", "approver": "bob"}, {"id": "d3", "approver": "eve"}]}"#;
const PARAMS: &str = r#"{"approvers": ["bob"]}"#;

fn file(name: &str, file: &str, text: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-rego-report-{}-{name}",
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

#[test]
fn report_and_violations_take_an_engine_and_the_path_of_ergo_rego() {
    let cases = [
        (vec![], Engine::Rust, None, Command::Report),
        (
            vec!["--engine", "rust"],
            Engine::Rust,
            None,
            Command::Report,
        ),
        (vec!["--engine=rego"], Engine::Rego, None, Command::Report),
        (
            vec!["--engine", "rego", "--ergo-rego", "e.rego"],
            Engine::Rego,
            Some("e.rego".to_string()),
            Command::Violations,
        ),
    ];
    for (extra, engine, ergo_rego, command) in cases {
        let name = if command == Command::Report {
            "report"
        } else {
            "violations"
        };
        let all = [vec![name, "--policy", "p.yaml", "--input", "i.json"], extra].concat();
        assert_eq!(
            parse(&args(&all)),
            Ok(Parsed::Run(Options {
                command,
                policy: "p.yaml".to_string(),
                input: "i.json".to_string(),
                params: None,
                compact: false,
                fail: false,
                format: Format::Json,
                engine,
                ergo_rego,
            })),
            "{all:?}"
        );
    }
}

#[test]
fn opa_reads_one_policy_input_and_params_from_one_data_file_and_runs_one_query() {
    let policy = json!({"ergo_spec": "v0", "requirements": {}});
    assert_eq!(
        opa::one_data(&policy, &json!({"n": 1.50}), &json!({"p": true})),
        json!({"ergo_cli": {"policy": policy, "input": {"n": 1.50}, "params": {"p": true}}})
    );
    assert_eq!(
        opa::REPORT_QUERY,
        "{\"report\": data.ergo.report(data.ergo_cli.input, data.ergo_cli.policy, data.ergo_cli.params)}"
    );
    assert_eq!(
        opa::VIOLATIONS_QUERY,
        "[x | report := data.ergo.report(data.ergo_cli.input, data.ergo_cli.policy, data.ergo_cli.params); x := {\"report\": report, \"violations\": data.ergo.violations(report)}][0]"
    );
}

#[test]
fn opa_output_is_read_as_one_report_and_its_violations_or_refused() {
    let report =
        json!({"compliant": true, "engine": {"name": "ergo-rego", "version": "1"}, "results": []});
    let only = json!({"report": report}).to_string();
    assert_eq!(opa::one_report(&only, false), Ok((report.clone(), None)));
    let both = json!({"report": report, "violations": []}).to_string();
    assert_eq!(
        opa::one_report(&both, true),
        Ok((report.clone(), Some(json!([]))))
    );
    for (printed, violations) in [
        ("", false),
        ("[]", false),
        ("{\"report\": 1} trailing", false),
    ] {
        assert_eq!(
            opa::one_report(printed, violations),
            Err("opa printed something that isn't a report".to_string()),
            "{printed}"
        );
    }
}

#[test]
fn report_with_engine_rego_without_a_path_says_how_to_get_ergo_rego() {
    let policy = file("none", "policy.yaml", POLICY);
    let input = file("none", "input.json", INPUT);
    for command in ["report", "violations"] {
        assert_eq!(
            run_in(
                &args(&[
                    command, "--policy", &policy, "--input", &input, "--engine", "rego"
                ]),
                &Environment::default()
            ),
            Err(Failure::Usage(ergo_policy_cli::get::missing(command))),
        );
    }
}

#[test]
fn report_with_ergo_rego_in_the_environment_is_refused_on_the_rust_engine() {
    let policy = file("env", "policy.yaml", POLICY);
    let input = file("env", "input.json", INPUT);
    assert_eq!(
        run_in(
            &args(&["report", "--policy", &policy, "--input", &input]),
            &with_rego("ergo.rego")
        ),
        Err(Failure::Usage(
            "ERGO_REGO is set, and it only goes with --engine rego".to_string()
        ))
    );
}

#[test]
fn report_with_engine_rego_fails_closed_when_ergo_rego_cannot_be_read_or_has_a_colon() {
    let policy = file("unreadable", "policy.yaml", POLICY);
    let input = file("unreadable", "input.json", INPUT);
    let folder = std::path::Path::new(&policy)
        .parent()
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let missing = format!("{folder}/none.rego");
    for command in ["report", "violations"] {
        let all = args(&[
            command, "--policy", &policy, "--input", &input, "--engine", "rego",
        ]);
        assert_eq!(
            run_in(&all, &with_rego(&missing)),
            Err(Failure::Engine(ergo_policy_cli::get::unreadable(
                &format!(
                    "can't read ergo.rego at {missing}: No such file or directory (os error 2)"
                ),
                command
            )))
        );
        assert_eq!(
            run_in(&all, &with_rego(&folder)),
            Err(Failure::Engine(ergo_policy_cli::get::unreadable(
                &format!("can't read ergo.rego at {folder}: it isn't a file"),
                command
            )))
        );
        assert_eq!(
            run_in(&all, &with_rego("c:d/ergo.rego")),
            Err(Failure::Engine(
                "the path of ergo.rego (c:d/ergo.rego) holds a ':', which opa reads as a prefix; move the file".to_string()
            ))
        );
    }
}

#[test]
fn opa_output_that_is_not_one_report_says_what_is_wrong_with_it() {
    let engine = r#""engine": {"name": "ergo-rego", "version": "1"}"#;
    let good = format!(r#"{{{engine}, "results": []}}"#);
    let cases = [
        (
            r#"{"report": {"results": []}}"#.to_string(),
            false,
            "report: engine.name isn't text",
        ),
        (
            r#"{"report": {"engine": {"name": "x", "version": 1}, "results": []}}"#.to_string(),
            false,
            "report: engine.version isn't text",
        ),
        (
            format!(r#"{{"report": {{{engine}, "results": {{}}}}}}"#),
            false,
            "report: results isn't a list",
        ),
        (r#"{}"#.to_string(), false, "report is missing"),
        (
            format!(r#"{{"report": {good}}}"#),
            true,
            "violations is missing",
        ),
        (
            format!(r#"{{"report": {good}, "violations": null}}"#),
            true,
            "violations isn't a list",
        ),
        (
            format!(r#"{{"report": {good}, "violations": {{}}}}"#),
            true,
            "violations isn't a list",
        ),
    ];
    for (printed, violations, reason) in cases {
        assert_eq!(
            opa::one_report(&printed, violations),
            Err(format!(
                "opa printed something that isn't a report: {reason}"
            )),
            "{printed}"
        );
    }
    assert_eq!(
        opa::one_report(&format!(r#"{{"report": {good}, "violations": []}}"#), true),
        Ok((serde_json::from_str(&good).unwrap(), Some(json!([]))))
    );
}

#[cfg(unix)]
#[test]
fn violations_with_engine_rego_refuses_violations_that_are_not_a_list_and_exits_2() {
    let policy = file("opa-null", "policy.yaml", POLICY);
    let input = file("opa-null", "input.json", INPUT);
    let ergo_rego = file("opa-null", "ergo.rego", "package ergo\n");
    let report =
        r#"{"compliant": true, "engine": {"name": "fake", "version": "9"}, "results": []}"#;
    let opa = fake_opa(
        "opa-null",
        &format!("echo '{{\"report\": {report}, \"violations\": null}}'\n"),
    );
    let environment = Environment {
        ergo_rego: Some(ergo_rego.clone()),
        opa: Some(opa),
    };
    let got = run_in(
        &args(&[
            "violations",
            "--policy",
            &policy,
            "--input",
            &input,
            "--engine",
            "rego",
            "--fail",
        ]),
        &environment,
    );
    assert_eq!(
        got,
        Err(Failure::Engine(format!(
            "opa printed something that isn't a report: violations isn't a list, with ergo.rego at {ergo_rego}"
        )))
    );
    assert_eq!(got.unwrap_err().code(), 2);
}

#[cfg(unix)]
fn fake_opa(name: &str, script: &str) -> std::ffi::OsString {
    use std::os::unix::fs::PermissionsExt;
    let path = file(name, "opa", &format!("#!/bin/sh\n{script}"));
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    path.into()
}

#[cfg(unix)]
#[test]
fn report_with_engine_rego_fails_closed_when_opa_is_missing_fails_or_prints_no_report() {
    let policy = file("opa-wrong", "policy.yaml", POLICY);
    let input = file("opa-wrong", "input.json", INPUT);
    let ergo_rego = file("opa-wrong", "ergo.rego", "package ergo\n");
    let missing = ergo_rego.replace("ergo.rego", "no-opa");
    let not_report =
        format!("opa printed something that isn't a report, with ergo.rego at {ergo_rego}");
    let cases = [
        (
            std::ffi::OsString::from(&missing),
            format!(
                "can't run {missing}: No such file or directory (os error 2); put opa on the PATH or set ERGO_OPA"
            ),
        ),
        (
            fake_opa("opa-fails", "echo 'first line' >&2\nexit 3\n"),
            format!("opa failed on ergo.rego at {ergo_rego}: first line"),
        ),
        (fake_opa("opa-silent", "exit 0\n"), not_report.clone()),
        (
            fake_opa("opa-junk", "echo '{\"report\": 1}'\n"),
            format!(
                "opa printed something that isn't a report: report isn't an object, with ergo.rego at {ergo_rego}"
            ),
        ),
    ];
    for command in ["report", "violations"] {
        for (opa, message) in &cases {
            let environment = Environment {
                ergo_rego: Some(ergo_rego.clone()),
                opa: Some(opa.clone()),
            };
            let got = run_in(
                &args(&[
                    command, "--policy", &policy, "--input", &input, "--engine", "rego",
                ]),
                &environment,
            );
            assert_eq!(got, Err(Failure::Engine(message.clone())), "{message}");
            assert_eq!(got.unwrap_err().code(), 2);
        }
    }
}

#[cfg(unix)]
#[test]
fn report_with_engine_rego_gives_opa_one_data_file_it_removes() {
    let policy = file("opa-seen", "policy.yaml", POLICY);
    let input = file("opa-seen", "input.json", INPUT);
    let params = file("opa-seen", "params.json", PARAMS);
    let ergo_rego = file("opa-seen", "ergo.rego", "package ergo\n");
    let seen = file("opa-seen", "seen", "");
    let report =
        r#"{"compliant": false, "engine": {"name": "fake", "version": "9"}, "results": []}"#;
    let opa = fake_opa(
        "opa-seen",
        &format!(
            "printf '%s\\n' \"$@\" > {seen}\n/bin/cp -f \"$7\" {seen}.json\necho '{{\"report\": {report}}}'\n"
        ),
    );
    let environment = Environment {
        ergo_rego: Some(ergo_rego.clone()),
        opa: Some(opa),
    };
    let (printed, code) = text(run_in(
        &args(&[
            "report",
            "--policy",
            &policy,
            "--input",
            &input,
            "--params",
            &params,
            "--engine",
            "rego",
            "--compact",
        ]),
        &environment,
    ));
    assert_eq!(
        printed,
        "{\"compliant\":false,\"engine\":{\"name\":\"fake\",\"version\":\"9\"},\"results\":[]}\n"
    );
    assert_eq!(code, 0);
    let given = std::fs::read_to_string(&seen).unwrap();
    let given: Vec<&str> = given.lines().collect();
    assert_eq!(given[..4], ["eval", "--format", "raw", "-d"]);
    assert_eq!(given[4], ergo_rego);
    assert_eq!(given[7..], [opa::REPORT_QUERY]);
    let folder = std::path::Path::new(given[6]).parent().unwrap();
    assert!(!folder.exists());
    assert!(
        folder
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with("ergo-report-"),
        "{folder:?}"
    );
    let data: Value =
        serde_json::from_str(&std::fs::read_to_string(format!("{seen}.json")).unwrap()).unwrap();
    assert_eq!(data["ergo_cli"]["params"], json!({"approvers": ["bob"]}));
    assert_eq!(data["ergo_cli"]["input"]["deployments"][1]["id"], "d2");
    let (_, code) = text(run_in(
        &args(&[
            "report", "--policy", &policy, "--input", &input, "--engine", "rego", "--fail",
        ]),
        &environment,
    ));
    assert_eq!(code, 3);
}

#[test]
fn report_with_engine_rego_refuses_a_policy_whose_spec_ergo_rego_does_not_support() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let policy = file(
        "old-spec",
        "policy.yaml",
        &POLICY.replace("ergo_spec: {{spec}}", "ergo_spec: v0.1"),
    );
    let input = file("old-spec", "input.json", INPUT);
    for command in ["report", "violations"] {
        let got = run_in(
            &args(&[
                command, "--policy", &policy, "--input", &input, "--engine", "rego",
            ]),
            &with_rego(&ergo_rego),
        );
        assert_eq!(
            got,
            Err(Failure::Engine(format!(
                "the ergo.rego at {ergo_rego} refuses the policy file {policy}: policy ergo_spec: unsupported version v0.1, expected {}",
                ergo_policy_engine::SPEC
            )))
        );
    }
}

fn without_engine(printed: &str) -> Value {
    let mut report: Value = serde_json::from_str(printed).unwrap();
    report.as_object_mut().unwrap().remove("engine");
    report
}

#[test]
fn the_rego_engine_and_the_rust_engine_print_the_same_report_and_violations() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let policy = file("agree", "policy.yaml", POLICY);
    let input = file("agree", "input.json", INPUT);
    let params = file("agree", "params.json", PARAMS);
    let base = ["--policy", &policy, "--input", &input, "--params", &params];
    for options in [vec![], vec!["--compact"], vec!["--fail"]] {
        for command in ["report", "violations"] {
            let rust = text(run(&args(&[&[command], &base[..], &options[..]].concat())));
            let rego = text(run_in(
                &args(&[&[command], &base[..], &options[..], &["--engine", "rego"]].concat()),
                &with_rego(&ergo_rego),
            ));
            assert_eq!(rust.1, rego.1, "{command} {options:?}");
            if options.contains(&"--compact") {
                assert_eq!(rust.0.lines().count(), 1);
                assert_eq!(rego.0.lines().count(), 1);
            }
            if command == "report" {
                let engine: Value = serde_json::from_str(&rego.0).unwrap();
                assert_eq!(engine["engine"]["name"], "ergo-rego");
                assert_eq!(without_engine(&rust.0), without_engine(&rego.0));
            } else {
                assert_eq!(rust.0, rego.0, "{command} {options:?}");
            }
        }
    }
    let (_, code) = text(run(&args(&[
        "report", "--policy", &policy, "--input", &input, "--params", &params, "--fail",
    ])));
    assert_eq!(code, 1);
}

#[test]
fn the_ergo_command_says_how_to_get_ergo_rego_and_exits_2() {
    let policy = file("binary", "policy.yaml", POLICY);
    let input = file("binary", "input.json", INPUT);
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_ergo"))
        .args([
            "report", "--policy", &policy, "--input", &input, "--engine", "rego",
        ])
        .env_remove("ERGO_REGO")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        String::from_utf8(output.stderr).unwrap(),
        format!("ergo: {}\n", ergo_policy_cli::get::missing("report"))
    );
    assert!(output.stdout.is_empty());
}

#[test]
fn report_and_violations_need_only_ergo_report_and_ergo_violations_from_ergo_rego() {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let renamed = std::fs::read_to_string(&ergo_rego)
        .unwrap()
        .replace("\ncompile(", "\ncompile_v2(");
    let renamed = file("no-compile", "ergo.rego", &renamed);
    let policy = file("no-compile", "policy.yaml", POLICY);
    let input = file("no-compile", "input.json", INPUT);
    for command in ["report", "violations"] {
        let all = args(&[
            command, "--policy", &policy, "--input", &input, "--engine", "rego",
        ]);
        let same = text(run_in(&all, &with_rego(&ergo_rego)));
        let got = text(run_in(&all, &with_rego(&renamed)));
        assert_eq!(got, same, "{command}");
    }
}
