use ergo_policy_cli::Failure;
use ergo_policy_cli::args::{Format, Parsed, parse};
use ergo_policy_cli::pretty::{Color, Show};

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

fn run_options(extra: &[&str]) -> ergo_policy_cli::args::Options {
    let mut all = vec!["report", "--policy", "p.yaml", "--input", "i.json"];
    all.extend(extra);
    match parse(&args(&all)) {
        Ok(Parsed::Run(options)) => options,
        other => panic!("{other:?}"),
    }
}

fn test_options(extra: &[&str]) -> ergo_policy_cli::args::TestOptions {
    let mut all = vec!["test", "p.yaml"];
    all.extend(extra);
    match parse(&args(&all)) {
        Ok(Parsed::Test(options)) => options,
        other => panic!("{other:?}"),
    }
}

#[test]
fn report_takes_format_pretty_show_and_color_and_defaults_to_failed_and_auto() {
    let plain = run_options(&[]);
    assert_eq!((plain.show, plain.color), (Show::Failed, Color::Auto));
    let all = run_options(&["--format", "pretty", "--show", "all", "--color", "always"]);
    assert_eq!(all.format, Format::Pretty);
    assert_eq!((all.show, all.color), (Show::All, Color::Always));
    let attached = run_options(&["--format=pretty", "--show=failed", "--color=never"]);
    assert_eq!(attached.format, Format::Pretty);
    assert_eq!(
        (attached.show, attached.color),
        (Show::Failed, Color::Never)
    );
}

#[test]
fn test_takes_show_and_color() {
    let defaults = test_options(&[]);
    assert_eq!((defaults.show, defaults.color), (Show::Failed, Color::Auto));
    let set = test_options(&["--show", "all", "--color", "never"]);
    assert_eq!((set.show, set.color), (Show::All, Color::Never));
}

#[test]
fn a_value_that_is_not_one_of_the_allowed_ones_is_refused_naming_them() {
    let cases = [
        (
            vec!["report", "--format", "xml"],
            "--format must be json, outcome or pretty",
        ),
        (
            vec!["report", "--format", "pretty", "--show", "some"],
            "--show must be failed or all",
        ),
        (
            vec!["report", "--format", "pretty", "--color", "red"],
            "--color must be auto, always or never",
        ),
        (
            vec!["test", "--show", "some"],
            "--show must be failed or all",
        ),
        (
            vec!["test", "--color", "red"],
            "--color must be auto, always or never",
        ),
    ];
    for (start, message) in cases {
        let mut all = start.clone();
        if start[0] == "report" {
            all.extend(["--policy", "p.yaml", "--input", "i.json"]);
        } else {
            all.push("p.yaml");
        }
        assert_eq!(
            parse(&args(&all)),
            Err(Failure::Usage(message.to_string())),
            "{start:?}"
        );
    }
}

#[test]
fn pretty_goes_only_with_report_and_show_and_color_only_where_they_matter() {
    let cases = [
        (
            vec!["violations", "--format", "pretty"],
            "--format pretty only goes with report",
        ),
        (
            vec!["report", "--format", "pretty", "--compact"],
            "--compact can't go with --format pretty",
        ),
        (
            vec!["report", "--show", "all"],
            "--show only goes with --format pretty and test",
        ),
        (
            vec!["report", "--format", "outcome", "--color", "always"],
            "--color only goes with --format pretty and test",
        ),
        (
            vec!["violations", "--color", "never"],
            "--color only goes with --format pretty and test",
        ),
    ];
    for (start, message) in cases {
        let mut all = start.clone();
        all.extend(["--policy", "p.yaml", "--input", "i.json"]);
        assert_eq!(
            parse(&args(&all)),
            Err(Failure::Usage(message.to_string())),
            "{start:?}"
        );
    }
}
