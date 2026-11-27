use ergo_policy_engine::SPEC;
use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

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

const INPUT_JSON: &str = r#"{"deployments": [{"id": "d1"}, {"id": "d2", "approver": "bob"}]}"#;
const INPUT_YAML: &str = "deployments:\n  - id: d1\n  - id: d2\n    approver: bob\n";
const PARAMS_JSON: &str = r#"{"approvers": ["bob"]}"#;
const PARAMS_YAML: &str = "approvers: [bob]\n";

const EXAMPLES: &str = r#"tests:
  params: {}
  examples:
    - name: a deployment needs an approver
      input: {deployments: [{id: d1}, {id: d2, approver: bob}]}
      outcome:
        - approved:
            - deployment d1 fails approver_set because approver is missing
            - deployment d2 passes approver_set
"#;

static COUNTER: AtomicUsize = AtomicUsize::new(0);

#[derive(Default)]
struct Folders(Vec<std::path::PathBuf>);

impl Drop for Folders {
    fn drop(&mut self) {
        for folder in &self.0 {
            let _ = std::fs::remove_dir_all(folder);
        }
    }
}

thread_local! {
    static FOLDERS: std::cell::RefCell<Folders> = std::cell::RefCell::new(Folders::default());
}

fn policy() -> String {
    POLICY.replace("{{spec}}", SPEC)
}

fn file(name: &str, file: &str, text: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-stdin-{}-{}-{name}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    FOLDERS.with(|f| f.borrow_mut().0.push(dir.clone()));
    let path = dir.join(file);
    std::fs::write(&path, text).unwrap();
    path.to_string_lossy().into_owned()
}

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn run_with(args: &[&str], stdin: &[u8], environment: &[(&str, &str)]) -> Run {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ergo"));
    command
        .args(args)
        .envs(environment.iter().copied())
        .env_remove("ERGO_REGO")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command.spawn().unwrap();
    let mut pipe = child.stdin.take().unwrap();
    let bytes = stdin.to_vec();
    let writer = std::thread::spawn(move || {
        let _ = pipe.write_all(&bytes);
    });
    let output = child.wait_with_output().unwrap();
    writer.join().unwrap();
    Run {
        code: output.status.code().unwrap(),
        stdout: String::from_utf8(output.stdout).unwrap(),
        stderr: String::from_utf8(output.stderr).unwrap(),
    }
}

fn run(args: &[&str], stdin: &str) -> Run {
    run_with(args, stdin.as_bytes(), &[])
}

fn reference() -> String {
    let p = file("p", "p.yaml", &policy());
    let i = file("i", "i.json", INPUT_JSON);
    let q = file("q", "q.json", PARAMS_JSON);
    let r = run(
        &["report", "--policy", &p, "--input", &i, "--params", &q],
        "",
    );
    assert_eq!(r.code, 0, "{}", r.stderr);
    r.stdout
}

#[test]
fn the_policy_can_come_from_standard_input_as_yaml_or_json() {
    let i = file("i", "i.json", INPUT_JSON);
    let q = file("q", "q.json", PARAMS_JSON);
    let want = reference();
    let yaml = run(
        &[
            "report",
            "--policy",
            "-",
            "--stdin-format",
            "yaml",
            "--input",
            &i,
            "--params",
            &q,
        ],
        &policy(),
    );
    assert_eq!(
        (yaml.code, yaml.stdout.as_str()),
        (0, want.as_str()),
        "{}",
        yaml.stderr
    );
    let as_json = policy_as_json();
    let json = run(
        &[
            "report",
            "--policy",
            "-",
            "--stdin-format",
            "json",
            "--input",
            &i,
            "--params",
            &q,
        ],
        &as_json.to_string(),
    );
    assert_eq!(
        (json.code, json.stdout.as_str()),
        (0, want.as_str()),
        "{}",
        json.stderr
    );
}

fn policy_as_json() -> Value {
    serde_json::json!({
        "ergo_spec": SPEC,
        "subjects": {"deployment": {"from": "deployments", "identified_by": "id"}},
        "requirements": {"approved": {"subject": "deployment", "checks": {
            "approver_set": "approver is a non-empty string",
            "allowed": "approver is in $params.approvers"
        }}}
    })
}

#[test]
fn the_input_can_come_from_standard_input_as_yaml_or_json() {
    let p = file("p", "p.yaml", &policy());
    let q = file("q", "q.json", PARAMS_JSON);
    let want = reference();
    for (format, text) in [("yaml", INPUT_YAML), ("json", INPUT_JSON)] {
        let r = run(
            &[
                "report",
                "--policy",
                &p,
                "--input",
                "-",
                "--stdin-format",
                format,
                "--params",
                &q,
            ],
            text,
        );
        assert_eq!(
            (r.code, r.stdout.as_str()),
            (0, want.as_str()),
            "{format}: {}",
            r.stderr
        );
    }
}

#[test]
fn the_params_can_come_from_standard_input_as_yaml_or_json() {
    let p = file("p", "p.yaml", &policy());
    let i = file("i", "i.json", INPUT_JSON);
    let want = reference();
    for (format, text) in [("yaml", PARAMS_YAML), ("json", PARAMS_JSON)] {
        let r = run(
            &[
                "report",
                "--policy",
                &p,
                "--input",
                &i,
                "--params",
                "-",
                "--stdin-format",
                format,
            ],
            text,
        );
        assert_eq!(
            (r.code, r.stdout.as_str()),
            (0, want.as_str()),
            "{format}: {}",
            r.stderr
        );
    }
}

#[test]
fn violations_reads_standard_input_too() {
    let p = file("p", "p.yaml", &policy());
    let q = file("q", "q.json", PARAMS_JSON);
    let r = run(
        &[
            "violations",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "yaml",
            "--params",
            &q,
        ],
        INPUT_YAML,
    );
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert!(r.stdout.contains("approver_set"), "{}", r.stdout);
}

#[test]
fn two_dashes_exit_2_and_print_no_report() {
    let p = file("p", "p.yaml", &policy());
    let r = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--params",
            "-",
            "--stdin-format",
            "json",
        ],
        "{}",
    );
    assert_eq!(r.code, 2);
    assert_eq!(r.stdout, "");
    assert!(
        r.stderr
            .contains("only one of --policy, --input and --params can be read from standard input"),
        "{}",
        r.stderr
    );
}

#[test]
fn a_dash_without_stdin_format_or_with_an_unknown_one_exits_2() {
    let p = file("p", "p.yaml", &policy());
    let missing = run(&["report", "--policy", &p, "--input", "-"], INPUT_JSON);
    assert_eq!((missing.code, missing.stdout.as_str()), (2, ""));
    assert!(
        missing.stderr.contains("json or yaml"),
        "{}",
        missing.stderr
    );
    let unknown = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "toml",
        ],
        INPUT_JSON,
    );
    assert_eq!((unknown.code, unknown.stdout.as_str()), (2, ""));
    assert!(
        unknown.stderr.contains("must be json or yaml"),
        "{}",
        unknown.stderr
    );
}

#[test]
fn stdin_format_without_a_dash_exits_2() {
    let p = file("p", "p.yaml", &policy());
    let i = file("i", "i.json", INPUT_JSON);
    let r = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            &i,
            "--stdin-format",
            "json",
        ],
        "",
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(
        r.stderr
            .contains("--stdin-format only goes with a value of -"),
        "{}",
        r.stderr
    );
}

#[test]
fn empty_standard_input_never_passes_silently() {
    let p = file("p", "p.yaml", &policy());
    let q = file("q", "q.json", PARAMS_JSON);
    let json = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "json",
            "--params",
            &q,
        ],
        "",
    );
    assert_eq!((json.code, json.stdout.as_str()), (2, ""));
    assert!(
        json.stderr
            .contains("the input on standard input isn't valid JSON"),
        "{}",
        json.stderr
    );
    let empty_file = file("empty", "i.yaml", "");
    let from_file = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            &empty_file,
            "--params",
            &q,
        ],
        "",
    );
    let from_stdin = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "yaml",
            "--params",
            &q,
        ],
        "",
    );
    assert_eq!(from_stdin.code, from_file.code);
    assert_eq!(from_stdin.stdout, from_file.stdout);
    let empty_policy = file("emptyp", "p.yaml", "");
    let i = file("i", "i.json", INPUT_JSON);
    let policy_file = run(&["report", "--policy", &empty_policy, "--input", &i], "");
    let policy_stdin = run(
        &[
            "report",
            "--policy",
            "-",
            "--stdin-format",
            "yaml",
            "--input",
            &i,
        ],
        "",
    );
    assert_eq!(policy_stdin.code, policy_file.code);
    assert_eq!(policy_stdin.stdout, policy_file.stdout);
    assert!(
        policy_stdin.stdout.contains("\"compliant\": false"),
        "{}",
        policy_stdin.stdout
    );
}

#[test]
fn invalid_json_and_yaml_on_standard_input_say_standard_input() {
    let p = file("p", "p.yaml", &policy());
    let json = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "json",
        ],
        "{nope",
    );
    assert_eq!((json.code, json.stdout.as_str()), (2, ""));
    assert!(
        json.stderr
            .starts_with("ergo: the input on standard input isn't valid JSON: "),
        "{}",
        json.stderr
    );
    let yaml = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "yaml",
        ],
        "a: [1\n",
    );
    assert_eq!((yaml.code, yaml.stdout.as_str()), (2, ""));
    assert!(
        yaml.stderr
            .starts_with("ergo: the input on standard input isn't valid YAML: "),
        "{}",
        yaml.stderr
    );
    let json_for_yaml_only = run(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "json",
        ],
        "010",
    );
    assert_eq!(json_for_yaml_only.code, 2);
}

#[test]
fn in_multi_document_yaml_on_standard_input_the_first_counts_and_a_malformed_later_one_is_refused()
{
    let p = file("p", "p.yaml", &policy());
    let q = file("q", "q.json", PARAMS_JSON);
    let want = reference();
    let args = [
        "report",
        "--policy",
        &p,
        "--input",
        "-",
        "--stdin-format",
        "yaml",
        "--params",
        &q,
    ];
    let first = run(&args, &format!("{INPUT_YAML}---\nkind: Other\n"));
    assert_eq!(
        (first.code, first.stdout.as_str()),
        (0, want.as_str()),
        "{}",
        first.stderr
    );
    let later = run(&args, &format!("{INPUT_YAML}---\na: [1\n"));
    assert_eq!((later.code, later.stdout.as_str()), (2, ""));
    assert!(
        later
            .stderr
            .contains("the input on standard input isn't valid YAML"),
        "{}",
        later.stderr
    );
}

#[test]
fn standard_input_that_is_not_utf8_exits_2() {
    let p = file("p", "p.yaml", &policy());
    let r = run_with(
        &[
            "report",
            "--policy",
            &p,
            "--input",
            "-",
            "--stdin-format",
            "json",
        ],
        &[0xff, 0xfe],
        &[],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(
        r.stderr.contains("can't read the input on standard input"),
        "{}",
        r.stderr
    );
}

#[test]
fn test_reads_its_policy_from_standard_input() {
    let r = run(
        &["test", "-", "--stdin-format", "yaml"],
        &format!("{}{}", policy(), EXAMPLES),
    );
    assert_eq!(r.code, 0, "{}{}", r.stdout, r.stderr);
    let on_file = {
        let f = file("t", "t.yaml", &format!("{}{}", policy(), EXAMPLES));
        run(&["test", &f], "")
    };
    assert_eq!(r.stdout, on_file.stdout);
}

#[test]
fn test_refuses_a_dash_without_a_format_and_a_format_without_a_dash() {
    let f = file("t", "t.yaml", &format!("{}{}", policy(), EXAMPLES));
    let a = run(&["test", "-"], "");
    assert_eq!((a.code, a.stdout.as_str()), (2, ""));
    let b = run(&["test", &f, "--stdin-format", "yaml"], "");
    assert_eq!((b.code, b.stdout.as_str()), (2, ""));
}

#[test]
fn test_names_standard_input_when_its_examples_are_written_wrong() {
    let r = run(
        &["test", "-", "--stdin-format", "yaml"],
        &format!("{}examples: []\n", policy()),
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(
        r.stderr
            .contains("the examples in the policy on standard input are written wrong"),
        "{}",
        r.stderr
    );
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
fn engine_rego_works_with_standard_input_for_each_flag_and_for_test() {
    let Some(rego) = built_ergo_rego() else {
        return;
    };
    let p = file("p", "p.yaml", &policy());
    let i = file("i", "i.json", INPUT_JSON);
    let q = file("q", "q.json", PARAMS_JSON);
    let rust = reference();
    let engine = ["--engine", "rego", "--ergo-rego", rego.as_str()];
    let mut want: Value = serde_json::from_str(&rust).unwrap();
    want["engine"] = Value::Null;
    let same = |r: &Run| {
        assert_eq!(r.code, 0, "{}", r.stderr);
        let mut got: Value = serde_json::from_str(&r.stdout).unwrap();
        got["engine"] = Value::Null;
        assert_eq!(got["results"], want["results"]);
    };
    let base = |p: &str, i: &str, q: &str, fmt: &str| {
        let mut v = vec!["report", "--policy", p, "--input", i, "--params", q];
        v.extend(["--stdin-format", fmt]);
        v.extend(engine);
        v.into_iter().map(String::from).collect::<Vec<_>>()
    };
    let go = |a: &[String], text: &str| {
        let refs: Vec<&str> = a.iter().map(String::as_str).collect();
        run(&refs, text)
    };
    same(&go(&base("-", &i, &q, "yaml"), &policy()));
    same(&go(&base(&p, "-", &q, "yaml"), INPUT_YAML));
    same(&go(&base(&p, &i, "-", "json"), PARAMS_JSON));
    let t = run(
        &[
            "test",
            "-",
            "--stdin-format",
            "yaml",
            "--engine",
            "rego",
            "--ergo-rego",
            &rego,
        ],
        &format!("{}{}", policy(), EXAMPLES),
    );
    assert_eq!(t.code, 0, "{}{}", t.stdout, t.stderr);
}

fn exits_while_stdin_stays_open(args: &[&str], environment: &[(&str, &str)]) -> Run {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ergo"));
    command
        .args(args)
        .envs(environment.iter().copied())
        .env_remove("ERGO_REGO")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command.spawn().unwrap();
    let held = child.stdin.take().unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(4);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break Some(status);
        }
        if std::time::Instant::now() >= deadline {
            break None;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    };
    if status.is_none() {
        let _ = child.kill();
    }
    let output = child.wait_with_output().unwrap();
    drop(held);
    assert!(
        status.is_some(),
        "{args:?} was still waiting for standard input after 4 seconds"
    );
    Run {
        code: output.status.code().unwrap(),
        stdout: String::from_utf8(output.stdout).unwrap(),
        stderr: String::from_utf8(output.stderr).unwrap(),
    }
}

#[test]
fn a_missing_input_file_is_reported_while_the_policy_on_standard_input_is_still_open() {
    let r = exits_while_stdin_stays_open(
        &[
            "report",
            "--policy",
            "-",
            "--input",
            "/no/such/input.json",
            "--stdin-format",
            "yaml",
        ],
        &[],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(
        r.stderr
            .contains("can't read the input file /no/such/input.json"),
        "{}",
        r.stderr
    );
}

#[test]
fn a_bad_ergo_rego_path_is_reported_while_standard_input_is_still_open() {
    let i = file("i", "i.json", INPUT_JSON);
    let r = exits_while_stdin_stays_open(
        &[
            "report",
            "--policy",
            "-",
            "--input",
            &i,
            "--stdin-format",
            "yaml",
            "--engine",
            "rego",
            "--ergo-rego",
            "/no/such/ergo.rego",
        ],
        &[],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(r.stderr.contains("/no/such/ergo.rego"), "{}", r.stderr);
}

#[test]
fn a_missing_ergo_rego_is_reported_while_standard_input_is_still_open() {
    let i = file("i", "i.json", INPUT_JSON);
    let r = exits_while_stdin_stays_open(
        &[
            "report",
            "--policy",
            "-",
            "--input",
            &i,
            "--stdin-format",
            "yaml",
            "--engine",
            "rego",
        ],
        &[],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(r.stderr.contains("ergo.rego"), "{}", r.stderr);
}

#[test]
fn a_missing_policy_file_is_reported_while_the_input_on_standard_input_is_still_open() {
    let r = exits_while_stdin_stays_open(
        &[
            "report",
            "--policy",
            "/no/such/policy.yaml",
            "--input",
            "-",
            "--stdin-format",
            "json",
        ],
        &[],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(
        r.stderr
            .contains("can't read the policy file /no/such/policy.yaml"),
        "{}",
        r.stderr
    );
}

#[test]
fn test_with_a_bad_ergo_rego_path_reports_it_while_the_policy_on_standard_input_is_still_open() {
    let r = exits_while_stdin_stays_open(
        &[
            "test",
            "-",
            "--stdin-format",
            "yaml",
            "--engine",
            "rego",
            "--ergo-rego",
            "/no/such/ergo.rego",
        ],
        &[],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(r.stderr.contains("/no/such/ergo.rego"), "{}", r.stderr);
}

#[test]
fn test_refuses_a_repeated_key_in_the_examples_on_standard_input_like_a_file() {
    let text = format!(
        "{}tests:\n  examples:\n    - name: one\n      name: two\n      input: {{}}\n      outcome: []\n",
        policy()
    );
    let on_stdin = run(&["test", "-", "--stdin-format", "yaml"], &text);
    let f = file("t", "t.yaml", &text);
    let on_file = run(&["test", &f], "");
    assert_eq!((on_stdin.code, on_file.code), (2, 2));
    assert!(
        on_stdin
            .stderr
            .contains("the examples in the policy on standard input are written wrong"),
        "{}",
        on_stdin.stderr
    );
    assert_eq!(
        on_stdin.stderr.replace("the policy on standard input", "X"),
        on_file.stderr.replace(&format!("the policy file {f}"), "X")
    );
}

#[test]
fn engine_rego_refuses_a_policy_on_standard_input_whose_spec_it_does_not_support() {
    let Some(rego) = built_ergo_rego() else {
        return;
    };
    let i = file("i", "i.json", INPUT_JSON);
    let old = policy().replace(SPEC, "v0.1");
    let r = run(
        &[
            "report",
            "--policy",
            "-",
            "--input",
            &i,
            "--stdin-format",
            "yaml",
            "--engine",
            "rego",
            "--ergo-rego",
            &rego,
        ],
        &old,
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""));
    assert!(
        r.stderr.contains(&format!(
            "refuses the policy on standard input: policy ergo_spec: unsupported version v0.1, expected {SPEC}"
        )),
        "{}",
        r.stderr
    );
}

#[test]
fn format_outcome_says_the_policy_on_standard_input_is_written_wrong() {
    let i = file("i", "i.json", INPUT_JSON);
    let bad = policy().replace("approver is a non-empty string", "approver is");
    let r = run(
        &[
            "report",
            "--policy",
            "-",
            "--input",
            &i,
            "--stdin-format",
            "yaml",
            "--format",
            "outcome",
            "--fail",
        ],
        &bad,
    );
    assert_eq!((r.code, r.stdout.as_str()), (3, ""));
    assert!(
        r.stderr.contains(
            "the policy on standard input is written wrong, so the report can't be shown as an outcome"
        ),
        "{}",
        r.stderr
    );
}

#[test]
fn format_pretty_says_standard_input_when_it_cannot_show_the_report() {
    use std::os::unix::fs::PermissionsExt;
    let i = file("i", "i.json", INPUT_JSON);
    let rego = file("e", "ergo.rego", "package ergo\n");
    let report = r#"{"report": {"compliant": false, "engine": {"name": "e", "version": "1"}, "requirements": {"r": {"status": "not_met"}}, "results": [{"requirement": "r", "passed": false}]}}"#;
    let opa = file(
        "o",
        "opa",
        &format!("#!/bin/sh\nprintf '%s\\n' '{report}'\n"),
    );
    std::fs::set_permissions(&opa, std::fs::Permissions::from_mode(0o755)).unwrap();
    let r = run_with(
        &[
            "report",
            "--policy",
            "-",
            "--input",
            &i,
            "--stdin-format",
            "yaml",
            "--format",
            "pretty",
            "--engine",
            "rego",
            "--ergo-rego",
            &rego,
        ],
        policy().as_bytes(),
        &[("ERGO_OPA", &opa)],
    );
    assert_eq!((r.code, r.stdout.as_str()), (2, ""), "{}", r.stderr);
    assert!(
        r.stderr
            .contains("--format pretty can't show the report from standard input:"),
        "{}",
        r.stderr
    );
}
