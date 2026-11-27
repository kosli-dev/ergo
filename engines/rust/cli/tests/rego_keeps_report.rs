use ergo_policy_cli::opa;
use ergo_policy_cli::{Environment, Outcome, run_in};
use serde_json::Value;

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

struct Dir(std::path::PathBuf);

impl Dir {
    fn new(name: &str) -> Dir {
        let dir =
            std::env::temp_dir().join(format!("ergo-cli-keeps-{}-{name}", std::process::id()));
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

const POLICY: &str = "ergo_spec: {{spec}}
subjects:
  d:
    from: ds
    identified_by: id
requirements:
  r:
    subject: d
    checks:
      big: n is 12345678901234567890123
      huge: m is 1e400
      long: q is 0.1000000000000000055511151231257827
";

const INPUT: &str = r#"{"ds": [{"id": 1, "n": 12345678901234567890123, "m": 1e400, "q": 0.1000000000000000055511151231257827}]}"#;

const EXTRA: &str = r#"
report(doc, policy, params) := object.union(report_base(doc, policy, params), {"zextra": {"big": 12345678901234567890123, "tiny": 1e400, "pi": 0.1000000000000000055511151231257827, "a": 1.50}, "aextra": 1, "engine": {"extra": [1e400]}})
"#;

fn opa_raw(ergo_rego: &str, data: &std::path::Path, query: &str) -> String {
    let output = std::process::Command::new("opa")
        .args(["eval", "--format", "raw", "-d", ergo_rego, "-d"])
        .arg(data)
        .arg(query)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}

fn print(ergo_rego: &str, policy: &str, input: &str, command: &str, compact: bool) -> String {
    let environment = Environment {
        ergo_rego: Some(ergo_rego.to_string()),
        opa: None,
    };
    let mut all = vec![
        command, "--policy", policy, "--input", input, "--engine", "rego",
    ];
    if compact {
        all.push("--compact");
    }
    match run_in(&args(&all), &environment) {
        Ok(Outcome::Print(text) | Outcome::PrintAndFail(text, _)) => text,
        other => panic!("{other:?}"),
    }
}

#[test]
fn the_report_printed_with_engine_rego_keeps_new_fields_digits_and_key_order_that_opa_gave_except_the_sign_of_an_exponent() {
    if std::env::var_os("ERGO_TEST_NO_OPA").is_some() {
        return;
    }
    let built = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../dist/ergo.rego");
    let text = std::fs::read_to_string(built).unwrap();
    let dir = Dir::new("extra");
    let changed = text.replace(
        "\nreport(doc, policy, params)",
        "\nreport_base(doc, policy, params)",
    ) + EXTRA;
    let ergo_rego = dir.write("ergo.rego", &changed);
    let policy = dir.write("policy.yaml", POLICY);
    let input = dir.write("input.json", INPUT);
    let policy_value = ergo_policy_cli::files::load("policy", &policy).unwrap();
    let input_value: Value = serde_json::from_str(INPUT).unwrap();
    let data = dir.write(
        "data.json",
        &opa::one_data(&policy_value, &input_value, &serde_json::json!({})).to_string(),
    );
    let raw = opa_raw(
        &ergo_rego,
        std::path::Path::new(&data),
        "data.ergo.report(data.ergo_cli.input, data.ergo_cli.policy, data.ergo_cli.params)",
    );
    let from_opa = raw.trim_end().to_string();
    assert!(from_opa.contains("\"zextra\""), "{from_opa}");
    let printed = print(&ergo_rego, &policy, &input, "report", true);
    assert!(printed.contains("1e+400"), "{printed}");
    assert_eq!(printed.trim_end().replace("e+400", "e400"), from_opa);
    for digits in [
        "12345678901234567890123",
        "e+400",
        "0.1000000000000000055511151231257827",
        "1.50",
    ] {
        assert!(printed.contains(digits), "{digits} in {printed}");
    }
    let pretty = print(&ergo_rego, &policy, &input, "report", false);
    let squeezed: String = pretty.chars().filter(|c| !c.is_whitespace()).collect();
    let from_opa_squeezed: String = from_opa.chars().filter(|c| !c.is_whitespace()).collect();
    assert_eq!(squeezed.replace("e+400", "e400"), from_opa_squeezed);
}
