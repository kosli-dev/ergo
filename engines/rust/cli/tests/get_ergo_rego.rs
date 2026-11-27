use ergo_policy_cli::get;

#[test]
fn a_missing_ergo_rego_is_met_with_a_command_to_paste_for_the_release() {
    let tag = get::LATEST_ERGO_REGO;
    let version = tag.strip_prefix("rego-v").unwrap();
    assert_eq!(
        get::missing("report"),
        format!(
            "--engine rego needs ergo.rego, and it was not found in --ergo-rego or ERGO_REGO.\nGet the release you run in production and pass its path. For ergo.rego {version}, the latest release when this ergo was built:\n  curl -fsSL -o ergo.rego https://github.com/kosli-dev/ergo/releases/download/{tag}/ergo.rego\n  ergo report --engine rego --ergo-rego ergo.rego ..."
        )
    );
    assert!(get::missing("test").ends_with("  ergo test --engine rego --ergo-rego ergo.rego ..."));
}

#[test]
fn an_unreadable_ergo_rego_keeps_its_problem_and_gets_the_same_command() {
    let hint = get::missing("violations");
    let (_, hint) = hint.split_once('\n').unwrap();
    assert_eq!(
        get::unreadable("can't read ergo.rego at x: no", "violations"),
        format!("can't read ergo.rego at x: no\n{hint}")
    );
}
