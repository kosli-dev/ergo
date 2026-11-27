use ergo_policy_cli::{Environment, Outcome, Terminal, run_with};

fn help(locale: Option<&str>) -> String {
    let terminal = Terminal {
        locale: locale.map(str::to_string),
        ..Terminal::default()
    };
    match run_with(&["--help".to_string()], &Environment::default(), &terminal) {
        Ok(Outcome::Print(text)) => text,
        other => panic!("{other:?}"),
    }
}

#[test]
fn the_commands_list_has_report_and_violations_each_on_its_own_line() {
    let text = help(Some("en_US.UTF-8"));
    assert!(
        text.contains("\n  report       print the report as JSON\n  violations   print what failed in the report as JSON\n  test "),
        "{text}"
    );
}

#[test]
fn the_first_line_of_help_has_the_therefore_sign_in_a_utf8_locale() {
    let text = help(Some("en_US.UTF-8"));
    assert!(
        text.starts_with("∴ ergo: what follows from the evidence\n"),
        "{text}"
    );
}

#[test]
fn the_first_line_of_help_has_the_plain_arrow_when_the_locale_is_not_utf8() {
    for locale in [Some("C"), Some("POSIX"), None] {
        let text = help(locale);
        assert!(
            text.starts_with("-> ergo: what follows from the evidence\n"),
            "{locale:?}: {text}"
        );
        assert!(!text.lines().next().unwrap().contains('∴'));
    }
}

#[test]
fn the_usage_for_a_call_with_no_arguments_has_the_plain_arrow_without_a_utf8_locale() {
    let text = ergo_policy_cli::usage(&Terminal::default());
    assert!(
        text.starts_with("-> ergo: what follows from the evidence\n"),
        "{text}"
    );
}
