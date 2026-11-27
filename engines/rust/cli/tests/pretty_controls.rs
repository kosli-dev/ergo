use ergo_policy_engine::SPEC;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Output};

const POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  "done\e[2J":
    subject: deployment
    checks:
      "approved\e]0;title\a": approved_by is a non-empty string
tests:
  examples:
    - name: "an example\e[2J"
      input: {deployments: [{id: d1}]}
      outcome:
        - "done\e[2J":
            - deployment d1 passes approved
"#;

const INPUT: &str = r#"{"deployments": [{"id": "d1"}]}"#;

fn dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-controls-{}-{name}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn write(name: &str, file: &str, text: &str) -> String {
    let path = dir(name).join(file);
    fs::write(&path, text).unwrap();
    path.to_string_lossy().into_owned()
}

fn ergo(args: &[&str], env: &[(&str, &str)]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ergo"));
    command
        .args(args)
        .env_remove("NO_COLOR")
        .env_remove("ERGO_REGO")
        .env_remove("ERGO_OPA")
        .env_remove("LC_CTYPE")
        .env_remove("LANG")
        .env("LC_ALL", "en_US.UTF-8");
    for (name, value) in env {
        command.env(name, value);
    }
    command.output().unwrap()
}

fn out(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).unwrap()
}

fn only_colour_codes(text: &str) -> bool {
    text.split('\x1b').skip(1).all(|after| {
        let Some(code) = after.strip_prefix('[') else {
            return false;
        };
        let digits: String = code.chars().take_while(char::is_ascii_digit).collect();
        !digits.is_empty() && code[digits.len()..].starts_with('m')
    })
}

fn fake_opa(name: &str, report: &str) -> String {
    use std::os::unix::fs::PermissionsExt;
    let path = write(
        name,
        "opa",
        &format!("#!/bin/sh\nprintf '%s\\n' '{report}'\n"),
    );
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    path
}

const HOSTILE_ROW: &str = r#"{"requirement": "r", "check": "c", "passed": false, "message": "m\u001b[2J\nn\r\u001b]0;title\u0007\u009b", "subject": {"type": "deployment", "id": "d1"}}"#;

fn hostile_report() -> String {
    format!(
        r#"{{"compliant": false, "engine": {{"name": "e\u001b[2J", "version": "1"}}, "requirements": {{"r": {{"status": "not_met"}}}}, "results": [{HOSTILE_ROW}]}}"#
    )
}

#[test]
fn a_policy_name_with_escape_codes_reaches_the_terminal_only_as_visible_escapes() {
    let policy = write("policy", "policy.yaml", &POLICY.replace("{{spec}}", SPEC));
    let input = write("policy", "input.json", INPUT);
    let args = [
        "report", "--format", "pretty", "--policy", &policy, "--input", &input,
    ];
    let never = ergo(&[&args[..], &["--color", "never"]].concat(), &[]);
    let text = out(&never);
    assert!(!never.stdout.contains(&0x1b), "{text:?}");
    assert!(text.contains("done\\u{1b}[2J is not met"), "{text:?}");
    let always = out(&ergo(&[&args[..], &["--color", "always"]].concat(), &[]));
    assert!(
        always.contains('\x1b') && only_colour_codes(&always),
        "{always:?}"
    );
    assert!(always.contains("done\\u{1b}[2J is not met"), "{always:?}");
}

#[test]
fn a_message_from_an_engine_with_escape_codes_reaches_the_terminal_only_as_visible_escapes() {
    let policy = write("engine", "policy.yaml", &POLICY.replace("{{spec}}", SPEC));
    let input = write("engine", "input.json", INPUT);
    let ergo_rego = write("engine", "ergo.rego", "package ergo\n");
    let opa = fake_opa("engine", &format!("{{\"report\": {}}}", hostile_report()));
    let args = [
        "report",
        "--format",
        "pretty",
        "--policy",
        &policy,
        "--input",
        &input,
        "--engine",
        "rego",
        "--ergo-rego",
        &ergo_rego,
    ];
    let never = ergo(
        &[&args[..], &["--color", "never"]].concat(),
        &[("ERGO_OPA", &opa)],
    );
    let text = out(&never);
    assert!(!never.stdout.contains(&0x1b), "{text:?}");
    assert!(!text.contains('\r') && !text.contains('\u{7}') && !text.contains('\u{9b}'));
    assert!(
        text.contains("because m\\u{1b}[2J\\u{a}n\\u{d}\\u{1b}]0;title\\u{7}\\u{9b}\n"),
        "{text:?}"
    );
    let always = out(&ergo(
        &[&args[..], &["--color", "always"]].concat(),
        &[("ERGO_OPA", &opa)],
    ));
    assert!(only_colour_codes(&always), "{always:?}");
}

#[test]
fn the_terminal_form_of_test_escapes_names_problems_warnings_and_the_engine_line() {
    let policy = write("test", "policy.yaml", &POLICY.replace("{{spec}}", SPEC));
    let ergo_rego = write("test", "ergo.rego", "package ergo\n");
    let opa = fake_opa("test", &format!("[{}]", hostile_report()));
    for extra in [
        vec!["--color", "always", "--show", "all"],
        vec![
            "--color",
            "always",
            "--show",
            "all",
            "--engine",
            "rego",
            "--ergo-rego",
            &ergo_rego,
        ],
    ] {
        let mut args = vec!["test", policy.as_str()];
        args.extend(extra.iter().copied());
        let text = out(&ergo(&args, &[("ERGO_OPA", &opa)]));
        assert!(only_colour_codes(&text), "{text:?}");
        assert!(!text.contains('\r') && !text.contains('\u{7}'), "{text:?}");
        assert!(text.contains("an example\\u{1b}[2J"), "{text:?}");
        assert!(
            text.contains(
                "no example shows approved\\u{1b}]0;title\\u{7} of done\\u{1b}[2J failing"
            ),
            "{text:?}"
        );
        if extra.contains(&"--engine") {
            assert!(text.starts_with("engine: e\\u{1b}[2J 1\n"), "{text:?}");
        }
    }
}

#[test]
fn test_on_a_terminal_without_colour_writes_no_escape_byte_at_all() {
    use ergo_policy_cli::{Environment, Outcome, Terminal, run_with};
    let policy = write("terminal", "policy.yaml", &POLICY.replace("{{spec}}", SPEC));
    let terminal = Terminal {
        stdout: true,
        no_color: false,
        locale: Some("en_US.UTF-8".to_string()),
    };
    let arguments: Vec<String> = ["test", &policy, "--color", "never", "--show", "all"]
        .iter()
        .map(|a| a.to_string())
        .collect();
    let Ok(Outcome::PrintAndFail(text, 1)) =
        run_with(&arguments, &Environment::default(), &terminal)
    else {
        panic!("not a failed run")
    };
    assert!(
        !text.contains('\x1b') && !text.contains('\u{7}'),
        "{text:?}"
    );
    assert!(text.starts_with("✗ an example\\u{1b}[2J\n"), "{text:?}");
}
