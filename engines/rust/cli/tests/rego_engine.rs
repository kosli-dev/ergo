use ergo_policy_cli::Failure;
use ergo_policy_cli::args::{Engine, Parsed, TestOptions, parse};
use ergo_policy_cli::examples::Example;
use ergo_policy_cli::opa;
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
        ("[{}]", 1),
        ("[1]", 1),
        (r#"[{"engine": {"name": "ergo-rego", "version": "1"}, "results": {}}]"#, 1),
        (r#"[{"engine": {"name": "ergo-rego"}, "results": []}]"#, 1),
        (r#"[{"engine": "ergo-rego 1", "results": []}]"#, 1),
        (r#"[{"results": []}]"#, 1),
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
    let unsupported = json!(["unsupported version v0.5, expected v0.7-dev"]);
    assert_eq!(
        opa::unsupported_spec(&report(
            engine.clone(),
            json!([row("$well_formed", false, unsupported.clone())])
        )),
        Some("policy ergo_spec: unsupported version v0.5, expected v0.7-dev".to_string())
    );
    for results in [
        json!([]),
        json!([row("$well_formed", false, json!(["missing"]))]),
        json!([row("$well_formed", false, json!(["not a version v"]))]),
        json!([row("c", false, unsupported.clone())]),
        json!([row("$well_formed", false, json!("unsupported version v0.5"))]),
    ] {
        assert_eq!(
            opa::unsupported_spec(&report(engine.clone(), results.clone())),
            None,
            "{results}"
        );
    }
}

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

#[test]
fn test_takes_an_engine_and_the_path_of_ergo_rego() {
    let cases = [
        (vec!["test", "p.yaml"], Engine::Rust, None),
        (vec!["test", "p.yaml", "--engine", "rust"], Engine::Rust, None),
        (vec!["test", "p.yaml", "--engine=rego"], Engine::Rego, None),
        (
            vec!["test", "--engine", "rego", "--ergo-rego", "e.rego", "p.yaml"],
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
            vec!["test", "p.yaml", "--engine", "rust", "--ergo-rego", "e.rego"],
            "--ergo-rego only goes with --engine rego",
        ),
        (
            vec!["report", "--policy", "p.yaml", "--input", "i.json", "--engine", "rego"],
            "--engine only goes with test",
        ),
        (
            vec!["violations", "--policy", "p.yaml", "--input", "i.json", "--ergo-rego", "e.rego"],
            "--ergo-rego only goes with test",
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
