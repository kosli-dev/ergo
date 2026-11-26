use ergo_policy_cli::Failure;
use ergo_policy_cli::args::{Engine, Parsed, TestOptions, parse};

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
