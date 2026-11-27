use ergo_policy_cli::{Environment, Outcome, Terminal, run_with};
use ergo_policy_engine::SPEC;
use std::fs;

const POLICY: &str = r#"ergo_spec: {{spec}}
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  approved:
    subject: deployment
    checks:
      approver_set: approver is a non-empty string
      not_self_approved: approver does not equal author
tests:
  params: {}
  examples:
    - name: a deployment needs an approver
      input: {deployments: [{id: d1, author: ann}, {id: d2, author: ann, approver: bob}]}
      outcome:
        - approved:
            - deployment d1 fails approver_set because approver is missing
            - deployment d2 passes approver_set
    - name: nobody approves their own deployment
      input: {deployments: [{id: d1, author: ann, approver: ann}]}
      outcome:
        - approved is not met:
            - deployment d1 fails not_self_approved because approver is "ann", and author is "ann"
    - name: this one is written wrong on purpose
      input: {deployments: [{id: d1, author: ann, approver: bob}]}
      outcome:
        - approved is not met
"#;

fn file(name: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "ergo-policy-cli-pretty-test-{}-{name}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("policy.yaml");
    fs::write(&path, POLICY.replace("{{spec}}", SPEC)).unwrap();
    path.to_string_lossy().into_owned()
}

fn args(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| a.to_string()).collect()
}

fn terminal(stdout: bool, locale: &str) -> Terminal {
    Terminal {
        stdout,
        no_color: false,
        locale: Some(locale.to_string()),
    }
}

fn text(extra: &[&str], terminal: &Terminal) -> (String, u8) {
    let policy = file("t");
    let mut all = vec!["test", policy.as_str()];
    all.extend(extra);
    match run_with(&args(&all), &Environment::default(), terminal) {
        Ok(Outcome::Print(text)) => (text, 0),
        Ok(Outcome::PrintAndFail(text, code)) => (text, code),
        Err(failure) => panic!("{failure:?}"),
    }
}

#[test]
fn piped_output_is_the_plain_lines_whatever_the_locale_and_show() {
    let plain = "passed: a deployment needs an approver\npassed: nobody approves their own deployment\nfailed: this one is written wrong on purpose\n";
    for extra in [vec![], vec!["--show", "all"], vec!["--color", "never"]] {
        let (out, code) = text(&extra, &terminal(false, "en_US.UTF-8"));
        assert!(out.starts_with(plain), "{extra:?}: {out}");
        assert!(out.ends_with("3 examples: 2 passed, 1 failed\n"), "{out}");
        assert!(!out.contains('\x1b') && !out.contains('✓'), "{out}");
        assert_eq!(code, 1);
    }
}

#[test]
fn on_a_terminal_failed_examples_and_warnings_get_marks_and_the_summary_has_the_therefore_sign() {
    let (out, code) = text(&["--color", "never"], &terminal(true, "en_US.UTF-8"));
    assert_eq!(code, 1);
    let lines: Vec<&str> = out.lines().collect();
    assert_eq!(lines[0], "✗ this one is written wrong on purpose");
    assert!(lines.contains(&"⚠ no example shows not_self_approved of approved passing"));
    assert!(!out.contains("passed:") && !out.contains("✓"), "{out}");
    assert!(
        out.ends_with("\n\n∴ 3 examples: 2 passed, 1 failed\n"),
        "{out}"
    );
}

#[test]
fn nothing_but_the_summary_has_no_empty_line_before_it() {
    let policy = file("quiet");
    let text = std::fs::read_to_string(&policy).unwrap();
    let passing = format!(
        "{}    - name: a different approver passes\n      input: {{deployments: [{{id: d1, author: ann, approver: bob}}]}}\n      outcome:\n        - approved:\n            - deployment d1 passes not_self_approved\n",
        text.split("    - name: this one").next().unwrap()
    );
    let path = std::path::Path::new(&policy).with_file_name("quiet.yaml");
    std::fs::write(&path, passing).unwrap();
    let arguments = args(&["test", path.to_str().unwrap(), "--color", "never"]);
    let Ok(Outcome::Print(out)) = run_with(
        &arguments,
        &Environment::default(),
        &terminal(true, "en_US.UTF-8"),
    ) else {
        panic!("not printed")
    };
    assert_eq!(out, "∴ 3 examples: 3 passed, 0 failed\n");
}

#[test]
fn show_all_lists_every_example_on_a_terminal() {
    let (out, _) = text(
        &["--show", "all", "--color", "never"],
        &terminal(true, "C.UTF-8"),
    );
    assert!(
        out.starts_with(
            "✓ a deployment needs an approver\n✓ nobody approves their own deployment\n✗ this one is written wrong on purpose\n"
        ),
        "{out}"
    );
}

#[test]
fn a_terminal_without_utf8_gets_words_and_colour_codes_when_asked() {
    let (out, _) = text(&["--show", "all"], &terminal(true, "C"));
    assert!(
        out.starts_with("\x1b[32mok\x1b[0m a deployment needs an approver\n"),
        "{out}"
    );
    assert!(
        out.contains("\x1b[31mFAIL this one is written wrong on purpose\x1b[0m\n"),
        "{out}"
    );
    assert!(
        out.ends_with("\x1b[1m-> 3 examples: 2 passed, 1 failed\x1b[0m\n"),
        "{out}"
    );
}

#[test]
fn color_always_gives_the_terminal_form_when_piped() {
    let (out, _) = text(&["--color", "always"], &terminal(false, "en_US.UTF-8"));
    assert!(
        out.contains("\x1b[31m✗ this one is written wrong on purpose\x1b[0m\n"),
        "{out}"
    );
}

#[test]
fn no_color_turns_colour_off_on_a_terminal() {
    let mut set = terminal(true, "en_US.UTF-8");
    set.no_color = true;
    let (out, _) = text(&[], &set);
    assert!(!out.contains('\x1b'), "{out}");
    assert!(out.contains("✗ this one"), "{out}");
}

#[test]
fn two_calls_with_the_same_name_get_their_own_folder() {
    assert_ne!(file("same"), file("same"));
}
