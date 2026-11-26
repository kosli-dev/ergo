use ergo_policy_cli::{Environment, Failure, Outcome, run, run_in};

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

fn cli_md_policies() -> Vec<String> {
    let page =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../CLI.md")).unwrap();
    let section = page
        .split("\n## Test a policy with examples")
        .nth(1)
        .and_then(|rest| rest.split("\n## ").next())
        .unwrap();
    section
        .split("```yaml\n")
        .skip(1)
        .filter_map(|block| block.split("\n```").next())
        .filter(|block| block.starts_with("ergo_spec: ") && block.contains("\ntests:\n"))
        .map(|block| {
            let (_, rest) = block.split_once('\n').unwrap();
            format!("ergo_spec: {}\n{rest}\n", ergo_policy_engine::SPEC)
        })
        .collect()
}

fn printed(outcome: Result<Outcome, Failure>) -> (String, u8) {
    match outcome {
        Ok(Outcome::Print(text)) => (text, 0),
        Ok(Outcome::PrintAndFail(text, code)) => (text, code),
        Err(failure) => panic!("{failure:?}"),
    }
}

#[test]
fn every_example_of_cli_md_passes_or_fails_the_same_way_and_prints_the_same_failures_on_both_engines()
 {
    let Some(ergo_rego) = built_ergo_rego() else {
        return;
    };
    let policies = cli_md_policies();
    assert_eq!(policies.len(), 3);
    let dir = std::env::temp_dir().join(format!("ergo-policy-cli-agree-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let environment = Environment {
        ergo_rego: Some(ergo_rego),
        opa: None,
    };
    let mut failed = 0;
    for (n, policy) in policies.iter().enumerate() {
        for (m, text) in [policy.clone(), policy.replace(" passes ", " fails ")]
            .iter()
            .enumerate()
        {
            let path = dir.join(format!("{n}-{m}.yaml"));
            std::fs::write(&path, text).unwrap();
            let path = path.to_string_lossy().into_owned();
            let rust = printed(run(&[String::from("test"), path.clone()]));
            let (rego, code) = printed(run_in(
                &["test", "--engine", "rego", &path].map(String::from),
                &environment,
            ));
            let (engine, rego) = rego.split_once('\n').unwrap();
            assert!(engine.starts_with("engine: ergo-rego "), "{engine}");
            assert_eq!(rust, (rego.to_string(), code), "{text}");
            failed += rust.1;
        }
    }
    assert!(failed > 0);
}
