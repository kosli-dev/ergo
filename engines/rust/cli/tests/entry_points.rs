use ergo_policy_cli::opa;
use ergo_policy_cli::{Environment, Failure, run_in};

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

const PATH: &str = "/x/ergo.rego";

#[test]
fn opa_saying_a_function_is_undefined_names_that_entry_point() {
    for name in ["ergo.report", "ergo.violations", "ergo.compile"] {
        let stderr =
            format!("1 error occurred: 1:12: rego_type_error: undefined function data.{name}\n");
        assert_eq!(
            opa::missing_entry_point(
                &["ergo.compile", "ergo.report", "ergo.violations"],
                "",
                &stderr
            ),
            Some(name.to_string()),
            "{name}"
        );
    }
}

#[test]
fn opa_saying_a_ref_is_undefined_names_that_entry_point() {
    assert_eq!(
        opa::missing_entry_point(
            &["ergo.report"],
            "",
            "rego_type_error: undefined ref: data.ergo.report"
        ),
        Some("ergo.report".to_string())
    );
}

#[test]
fn an_undefined_entry_point_that_merely_starts_like_a_name_is_not_that_name() {
    assert_eq!(
        opa::missing_entry_point(
            &["ergo.report"],
            "",
            "undefined function data.ergo.report_v2"
        ),
        None
    );
}

#[test]
fn an_error_about_something_else_names_no_entry_point() {
    assert_eq!(
        opa::missing_entry_point(&["ergo.report"], "", "rego_parse_error: unexpected token"),
        None
    );
}

#[test]
fn blank_output_names_every_entry_point_the_query_needs() {
    assert_eq!(
        opa::missing_entry_point(&["ergo.report"], "\n", ""),
        Some("ergo.report".to_string())
    );
    assert_eq!(
        opa::missing_entry_point(&["ergo.report", "ergo.violations"], "", ""),
        Some("ergo.report or ergo.violations".to_string())
    );
}

#[test]
fn output_that_is_not_blank_names_no_entry_point() {
    assert_eq!(opa::missing_entry_point(&["ergo.report"], "{}", ""), None);
}

#[test]
fn the_message_names_the_file_and_the_entry_point() {
    assert_eq!(
        opa::no_entry_point(PATH, "ergo.report"),
        "the ergo.rego at /x/ergo.rego has no ergo.report"
    );
}

fn built_ergo_rego() -> Option<String> {
    if std::env::var_os("ERGO_TEST_NO_OPA").is_some() {
        return None;
    }
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../dist/ergo.rego");
    assert!(
        std::path::Path::new(path).is_file(),
        "no {path}: build it with .github/build-ergo.sh"
    );
    Some(path.to_string())
}

struct Dir(std::path::PathBuf);

impl Dir {
    fn new(name: &str) -> Dir {
        let dir =
            std::env::temp_dir().join(format!("ergo-cli-entry-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        Dir(dir)
    }
    fn write(&self, file: &str, text: &str) -> String {
        let path = self.0.join(file);
        std::fs::write(&path, text.replace("{{spec}}", ergo_policy_engine::SPEC)).unwrap();
        path.to_string_lossy().into_owned()
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

const POLICY: &str = "ergo_spec: {{spec}}\nsubjects:\n  d:\n    from: ds\n    identified_by: id\nrequirements:\n  r:\n    subject: d\n    checks:\n      c: ok is true\ntests:\n  examples:\n    - name: one\n      input: {ds: [{id: 1, ok: true}]}\n      outcome:\n        - r:\n            - d 1 passes c\n";

#[test]
fn real_opa_on_an_ergo_rego_without_one_entry_point_names_it_and_exits_2() {
    let Some(built) = built_ergo_rego() else {
        return;
    };
    let text = std::fs::read_to_string(&built).unwrap();
    let dir = Dir::new("missing");
    let policy = dir.write("policy.yaml", POLICY);
    let input = dir.write("input.json", "{\"ds\": [{\"id\": 1, \"ok\": true}]}");
    let no_report = dir.write(
        "no-report.rego",
        &text.replace("\nreport(doc", "\nreport_v2(doc"),
    );
    let no_violations = dir.write(
        "no-violations.rego",
        &text.replace("\nviolations(report)", "\nviolations_v2(report)"),
    );
    let cases = [
        ("report", &no_report, "ergo.report"),
        ("violations", &no_report, "ergo.report"),
        ("violations", &no_violations, "ergo.violations"),
    ];
    for (command, ergo_rego, name) in cases {
        let environment = Environment {
            ergo_rego: Some(ergo_rego.clone()),
            opa: None,
        };
        let got = run_in(
            &args(&[
                command, "--policy", &policy, "--input", &input, "--engine", "rego",
            ]),
            &environment,
        );
        assert_eq!(
            got,
            Err(Failure::Engine(format!(
                "the ergo.rego at {ergo_rego} has no {name}"
            ))),
            "{command} {name}"
        );
        assert_eq!(got.unwrap_err().code(), 2);
    }
}

#[test]
fn real_opa_on_an_ergo_rego_without_ergo_compile_says_ergo_test_needs_it() {
    let Some(built) = built_ergo_rego() else {
        return;
    };
    let text = std::fs::read_to_string(&built).unwrap();
    let dir = Dir::new("no-compile");
    let policy = dir.write("policy.yaml", POLICY);
    let ergo_rego = dir.write(
        "no-compile.rego",
        &text.replace("\ncompile(", "\ncompile_v2("),
    );
    let environment = Environment {
        ergo_rego: Some(ergo_rego.clone()),
        opa: None,
    };
    assert_eq!(
        run_in(&args(&["test", "--engine", "rego", &policy]), &environment),
        Err(Failure::Engine(format!(
            "the ergo.rego at {ergo_rego} has no ergo.compile; ergo test needs it, and OPA.md calls it experimental"
        )))
    );
}
