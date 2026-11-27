use ergo_policy_cli::args::{Parsed, StdinFormat, parse};
use ergo_policy_cli::{Failure, files};
use std::io::Cursor;

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

fn usage(all: &[&str]) -> String {
    match parse(&args(all)) {
        Err(Failure::Usage(m)) => m,
        other => panic!("{all:?}: {other:?}"),
    }
}

fn run_options(all: &[&str]) -> ergo_policy_cli::args::Options {
    match parse(&args(all)) {
        Ok(Parsed::Run(o)) => o,
        other => panic!("{all:?}: {other:?}"),
    }
}

#[test]
fn each_of_policy_input_and_params_can_be_dash_with_a_stdin_format() {
    let cases = [
        (["-", "i.json"], None),
        (["p.yaml", "-"], None),
        (["p.yaml", "i.json"], Some("-")),
    ];
    for ([policy, input], params) in cases {
        let mut all = vec!["report", "--policy", policy, "--input", input];
        all.extend(params.iter().flat_map(|p| ["--params", *p]));
        all.extend(["--stdin-format", "yaml"]);
        let options = run_options(&all);
        assert_eq!(options.policy, policy, "{all:?}");
        assert_eq!(options.input, input, "{all:?}");
        assert_eq!(options.params.as_deref(), params, "{all:?}");
        assert_eq!(options.stdin_format, Some(StdinFormat::Yaml), "{all:?}");
    }
}

#[test]
fn stdin_format_json_and_the_attached_form_are_read() {
    let o = run_options(&[
        "violations",
        "--policy=p.yaml",
        "--input",
        "-",
        "--stdin-format=json",
    ]);
    assert_eq!(o.stdin_format, Some(StdinFormat::Json));
}

#[test]
fn a_dash_without_stdin_format_is_refused() {
    let m = usage(&["report", "--policy", "p.yaml", "--input", "-"]);
    assert_eq!(m, "--stdin-format json or yaml is needed when a value is -");
}

#[test]
fn an_unknown_stdin_format_names_the_allowed_values() {
    let m = usage(&[
        "report",
        "--policy",
        "p.yaml",
        "--input",
        "-",
        "--stdin-format",
        "toml",
    ]);
    assert_eq!(m, "--stdin-format must be json or yaml");
}

#[test]
fn stdin_format_without_a_dash_is_refused() {
    let m = usage(&[
        "report",
        "--policy",
        "p.yaml",
        "--input",
        "i.json",
        "--stdin-format",
        "yaml",
    ]);
    assert_eq!(m, "--stdin-format only goes with a value of -");
}

#[test]
fn two_dashes_are_refused() {
    let m = usage(&[
        "report",
        "--policy",
        "-",
        "--input",
        "-",
        "--stdin-format",
        "yaml",
    ]);
    assert_eq!(
        m,
        "only one of --policy, --input and --params can be read from standard input"
    );
    let m = usage(&[
        "violations",
        "--policy",
        "p.yaml",
        "--input",
        "-",
        "--params",
        "-",
        "--stdin-format",
        "json",
    ]);
    assert!(m.starts_with("only one of"), "{m}");
}

#[test]
fn test_takes_a_dash_policy_with_a_stdin_format() {
    match parse(&args(&["test", "-", "--stdin-format", "yaml"])) {
        Ok(Parsed::Test(o)) => {
            assert_eq!(o.policy, "-");
            assert_eq!(o.stdin_format, Some(StdinFormat::Yaml));
        }
        other => panic!("{other:?}"),
    }
    assert_eq!(
        usage(&["test", "-"]),
        "--stdin-format json or yaml is needed when a value is -"
    );
    assert_eq!(
        usage(&["test", "p.yaml", "--stdin-format", "yaml"]),
        "--stdin-format only goes with a value of -"
    );
}

#[test]
fn a_flag_value_of_dash_alone_is_a_value_and_not_a_flag() {
    let o = run_options(&[
        "report",
        "--policy",
        "p.yaml",
        "--input",
        "-",
        "--stdin-format",
        "json",
        "--compact",
    ]);
    assert_eq!(o.input, "-");
    assert!(o.compact);
}

#[test]
fn stdin_is_read_whole_and_parsed_as_the_format_says() {
    let text =
        files::read_stdin_from("input", false, &mut Cursor::new(b"a: 1\n".to_vec())).unwrap();
    assert_eq!(text, "a: 1\n");
    let value = files::parse_stdin("input", &text, StdinFormat::Yaml).unwrap();
    assert_eq!(value, serde_json::json!({"a": 1}));
}

#[test]
fn the_format_decides_how_010_is_read() {
    let yaml = files::parse_stdin("input", "010", StdinFormat::Yaml).unwrap();
    assert_eq!(yaml.to_string(), "8");
    let json = files::parse_stdin("input", "010", StdinFormat::Json).unwrap_err();
    assert!(
        json.message()
            .starts_with("the input on standard input isn't valid JSON"),
        "{}",
        json.message()
    );
}

#[test]
fn empty_standard_input_reads_as_an_empty_file_does() {
    let json = files::parse_stdin("policy", "", StdinFormat::Json).unwrap_err();
    assert!(
        json.message()
            .starts_with("the policy on standard input isn't valid JSON"),
        "{}",
        json.message()
    );
    let yaml = files::parse_stdin("policy", "", StdinFormat::Yaml);
    assert_eq!(yaml.unwrap(), serde_json::Value::Null);
}

#[test]
fn standard_input_that_is_not_utf8_is_an_error() {
    let failure = files::read_stdin_from("input", false, &mut Cursor::new(vec![0xff, 0xfe, 0x00]))
        .unwrap_err();
    assert!(
        failure
            .message()
            .starts_with("can't read the input on standard input: "),
        "{}",
        failure.message()
    );
}

#[test]
fn names_say_standard_input_for_a_dash_and_the_file_otherwise() {
    assert_eq!(files::name("policy", "-"), "the policy on standard input");
    assert_eq!(files::name("policy", "a.yaml"), "the policy file a.yaml");
}

#[test]
fn standard_input_that_is_a_terminal_is_refused_without_reading() {
    let failure =
        files::read_stdin_from("input", true, &mut Cursor::new(b"a: 1\n".to_vec())).unwrap_err();
    assert_eq!(
        failure.message(),
        "standard input is a terminal; pipe the input in"
    );
}

#[test]
fn params_on_standard_input_are_named_in_the_plural() {
    let failure = files::parse_stdin("params", "{", StdinFormat::Json).unwrap_err();
    assert!(
        failure
            .message()
            .starts_with("standard input as params isn't valid JSON: "),
        "{}",
        failure.message()
    );
}

#[test]
fn repeated_keys_in_yaml_text_are_listed_and_other_text_has_none() {
    assert_eq!(
        files::repeated_keys_in("a: 1\nb:\n  c: 1\n  c: 2\n"),
        vec![vec!["b".to_string(), "c".to_string()]]
    );
    assert!(files::repeated_keys_in("a: [").is_empty());
    assert!(files::repeated_keys_in("a: 1\n").is_empty());
}

#[test]
fn the_test_usage_line_names_stdin_format() {
    let line = ergo_policy_cli::USAGE
        .lines()
        .find(|l| l.trim_start().starts_with("ergo test <policy file>"))
        .unwrap();
    assert!(line.contains("[--stdin-format json|yaml]"), "{line}");
}
