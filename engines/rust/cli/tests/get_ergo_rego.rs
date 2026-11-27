use ergo_policy_cli::get;

#[test]
fn the_latest_released_ergo_rego_is_named_in_one_constant() {
    assert_eq!(get::LATEST_ERGO_REGO, "rego-v0.6.0");
}

#[test]
fn a_missing_ergo_rego_is_met_with_a_command_to_paste_for_the_release() {
    assert_eq!(
        get::missing("report"),
        "--engine rego needs ergo.rego, and it was not found.\nGet the release you run in production and pass its path. For the current release:\n  curl -fsSL -o ergo.rego https://github.com/kosli-dev/ergo/releases/download/rego-v0.6.0/ergo.rego\n  ergo report --engine rego --ergo-rego ergo.rego ..."
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
