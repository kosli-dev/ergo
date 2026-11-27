use super::*;
use serde_json::json;

fn row(requirement: &str, check: &str, id: Value, passed: bool, message: Option<&str>) -> Value {
    let mut row = json!({
        "requirement": requirement,
        "check": check,
        "passed": passed,
        "subject": {"type": "deployment", "id": id},
    });
    if let Some(message) = message {
        row["message"] = json!(message);
    }
    row
}

fn out_of_scope_row(id: &str, message: &str) -> Value {
    let mut out = row("approved", "$applies", json!(id), false, Some(message));
    out["cause"] = json!("value");
    out
}

fn report() -> Value {
    json!({
        "compliant": false,
        "requirements": {
            "approved": {"status": "not_met"},
            "tested": {"status": "met"}
        },
        "results": [
            row("approved", "$applies", json!("d1"), true, None),
            row("approved", "allowed", json!("d1"), false, Some("approver is missing")),
            row("approved", "allowed", json!("d2"), true, None),
            out_of_scope_row("d3", "env is \"dev\""),
            row("tested", "has_env", json!("d1"), true, None)
        ]
    })
}

const PLAIN: Style = Style {
    color: false,
    glyphs: false,
    show: Show::Failed,
};
const GLYPHS: Style = Style {
    color: false,
    glyphs: true,
    show: Show::Failed,
};
const COLOURS: Style = Style {
    color: true,
    glyphs: true,
    show: Show::Failed,
};

#[test]
fn failed_rows_of_failing_requirements_come_first_and_the_rest_is_counted() {
    assert_eq!(
        render(&report(), &json!({}), &GLYPHS).unwrap(),
        "✗ approved is not met\n    ✗ deployment d1 fails allowed\n      because approver is missing\n✓ tested is met\n\n  5 rows: 3 passed, 1 failed, 1 out of scope\n\n∴ not compliant\n"
    );
}

#[test]
fn plain_words_stand_in_for_the_glyphs() {
    assert_eq!(
        render(&report(), &json!({}), &PLAIN).unwrap(),
        "FAIL approved is not met\n    FAIL deployment d1 fails allowed\n      because approver is missing\nok tested is met\n\n  5 rows: 3 passed, 1 failed, 1 out of scope\n\n-> not compliant\n"
    );
}

#[test]
fn show_all_lists_every_row_with_its_requirement() {
    let style = Style {
        show: Show::All,
        ..GLYPHS
    };
    assert_eq!(
        render(&report(), &json!({}), &style).unwrap(),
        "✗ approved is not met\n    ✓ deployment d1 is in scope\n    ✗ deployment d1 fails allowed\n      because approver is missing\n    ✓ deployment d2 passes allowed\n    – deployment d3 is out of scope (env is \"dev\")\n✓ tested is met\n    ✓ deployment d1 passes has_env\n\n  5 rows: 3 passed, 1 failed, 1 out of scope\n\n∴ not compliant\n"
    );
}

#[test]
fn failures_are_red_passes_have_a_green_mark_and_the_verdict_is_bold() {
    let text = render(&report(), &json!({}), &COLOURS).unwrap();
    assert_eq!(
        text,
        "\x1b[31m✗ approved is not met\x1b[0m\n    \x1b[31m✗ deployment d1 fails allowed\x1b[0m\n      because approver is missing\n\x1b[32m✓\x1b[0m tested is met\n\n  5 rows: 3 passed, 1 failed, 1 out of scope\n\n\x1b[1m∴ not compliant\x1b[0m\n"
    );
}

#[test]
fn out_of_scope_rows_are_dim() {
    let style = Style {
        show: Show::All,
        ..COLOURS
    };
    let text = render(&report(), &json!({}), &style).unwrap();
    assert!(
        text.contains("    \x1b[2m– deployment d3 is out of scope (env is \"dev\")\x1b[0m\n"),
        "{text}"
    );
}

#[test]
fn a_compliant_report_says_so() {
    let report = json!({
        "compliant": true,
        "requirements": {"tested": {"status": "met"}, "skipped": {"status": "not_applicable"}},
        "results": [row("tested", "has_env", json!("d1"), true, None)]
    });
    assert_eq!(
        render(&report, &json!({}), &GLYPHS).unwrap(),
        "– skipped is not applicable\n✓ tested is met\n\n  1 row: 1 passed, 0 failed, 0 out of scope\n\n∴ compliant\n"
    );
}

#[test]
fn a_row_with_no_id_names_only_its_subject_type() {
    let report = json!({
        "compliant": false,
        "requirements": {"tested": {"status": "not_met"}},
        "results": [row("tested", "$min_subjects", json!(null), false, Some("in-scope deployment count is 0"))]
    });
    assert_eq!(
        render(&report, &json!({}), &GLYPHS).unwrap(),
        "✗ tested is not met\n    ✗ deployment fails $min_subjects\n      because in-scope deployment count is 0\n\n  1 row: 0 passed, 1 failed, 0 out of scope\n\n∴ not compliant\n"
    );
}

#[test]
fn an_id_with_a_space_is_quoted() {
    let report = json!({
        "compliant": false,
        "requirements": {"tested": {"status": "not_met"}},
        "results": [row("tested", "c", json!("a b"), false, None)]
    });
    assert!(
        render(&report, &json!({}), &GLYPHS)
            .unwrap()
            .contains("    ✗ deployment \"a b\" fails c\n")
    );
}

#[test]
fn a_status_this_ergo_does_not_know_is_shown_as_the_report_gives_it_among_the_failures() {
    let report = json!({
        "compliant": false,
        "requirements": {"a": {"status": "met"}, "b": {"status": "weird"}},
        "results": []
    });
    assert_eq!(
        render(&report, &json!({}), &GLYPHS).unwrap(),
        "✗ b has status \"weird\"\n✓ a is met\n\n  0 rows: 0 passed, 0 failed, 0 out of scope\n\n∴ not compliant\n"
    );
}

#[test]
fn a_report_it_cannot_read_is_refused_naming_what_is_missing() {
    let cases = [
        (json!({"compliant": true, "requirements": {}}), "results"),
        (json!({"compliant": true, "results": []}), "requirements"),
        (json!({"requirements": {}, "results": []}), "compliant"),
        (
            json!({"compliant": "yes", "requirements": {}, "results": []}),
            "compliant",
        ),
        (
            json!({"compliant": true, "requirements": {"a": {}}, "results": []}),
            "status of requirement a",
        ),
        (
            json!({"compliant": true, "requirements": {"a": {"status": 1}}, "results": []}),
            "status of requirement a",
        ),
        (
            json!({"compliant": true, "requirements": {}, "results": [{"check": "c", "passed": true, "subject": {"type": "d", "id": 1}}]}),
            "requirement of row 1",
        ),
        (
            json!({"compliant": true, "requirements": {}, "results": [row("a", "c", json!(1), true, None)]}),
            "requirement a of row 1",
        ),
        (
            json!({"compliant": true, "requirements": {"a": {"status": "met"}}, "results": [row("a", "c", json!(1), true, None), {"requirement": "a", "check": "c", "subject": {"type": "d", "id": 1}}]}),
            "passed of row 2",
        ),
        (
            json!({"compliant": true, "requirements": {"a": {"status": "met"}}, "results": [{"requirement": "a", "check": "c", "passed": true}]}),
            "subject of row 1",
        ),
        (
            json!({"compliant": true, "requirements": {"a": {"status": "met"}}, "results": [{"requirement": "a", "passed": true, "subject": {"type": "d", "id": 1}}]}),
            "check of row 1",
        ),
        (
            json!({"compliant": true, "requirements": {"a": {"status": "met"}}, "results": [{"requirement": "a", "check": "c", "passed": false, "message": 3, "subject": {"type": "d", "id": 1}}]}),
            "message of row 1",
        ),
    ];
    for (report, named) in cases {
        let problem = render(&report, &json!({}), &GLYPHS).unwrap_err();
        assert!(problem.contains(named), "{report}: {problem}");
    }
}

#[test]
fn a_row_with_a_subject_id_that_is_not_a_scalar_is_printed_as_json() {
    let report = json!({
        "compliant": false,
        "requirements": {"a": {"status": "not_met"}},
        "results": [row("a", "c", json!({"k": 1}), false, None)]
    });
    assert!(
        render(&report, &json!({}), &GLYPHS)
            .unwrap()
            .contains("    ✗ deployment {\"k\":1} fails c\n")
    );
}

#[test]
fn a_failed_row_of_a_met_requirement_is_still_listed_in_the_count_only() {
    let report = json!({
        "compliant": true,
        "requirements": {"a": {"status": "met"}},
        "results": [row("a", "c", json!(1), false, None)]
    });
    assert_eq!(
        render(&report, &json!({}), &GLYPHS).unwrap(),
        "✓ a is met\n\n  1 row: 0 passed, 1 failed, 0 out of scope\n\n∴ compliant\n"
    );
}

#[test]
fn colour_is_on_for_a_terminal_unless_no_color_is_set_and_the_flag_overrides_both() {
    let cases = [
        (Color::Auto, true, false, true),
        (Color::Auto, false, false, false),
        (Color::Auto, true, true, false),
        (Color::Always, false, false, true),
        (Color::Always, false, true, true),
        (Color::Never, true, false, false),
    ];
    for (choice, terminal, no_color, want) in cases {
        assert_eq!(
            color_on(choice, terminal, no_color),
            want,
            "{choice:?} {terminal} {no_color}"
        );
    }
}

#[test]
fn glyphs_need_a_utf8_locale() {
    let cases = [
        (Some("en_US.UTF-8"), true),
        (Some("en_US.utf8"), true),
        (Some("C.UTF-8"), true),
        (Some("C"), false),
        (Some("POSIX"), false),
        (Some(""), false),
        (None, false),
    ];
    for (locale, want) in cases {
        assert_eq!(utf8(locale), want, "{locale:?}");
    }
}

#[test]
fn the_first_locale_variable_that_is_set_decides() {
    let get = |set: &'static [(&'static str, &'static str)]| {
        move |name: &str| {
            set.iter()
                .find(|(n, _)| *n == name)
                .map(|(_, v)| v.to_string())
        }
    };
    let said = |set| locale(get(set));
    assert_eq!(
        said(&[("LC_ALL", "C"), ("LANG", "en_US.UTF-8")]),
        Some("C".to_string())
    );
    assert_eq!(
        said(&[("LC_ALL", ""), ("LC_CTYPE", "en_US.UTF-8"), ("LANG", "C")]),
        Some("en_US.UTF-8".to_string())
    );
    assert_eq!(
        said(&[("LANG", "de_DE.UTF-8")]),
        Some("de_DE.UTF-8".to_string())
    );
    assert_eq!(said(&[]), None);
}

fn applies_report(cause: Option<&str>) -> Value {
    let mut failed = row(
        "approved",
        "$applies",
        json!("d2"),
        false,
        Some("environment is missing"),
    );
    if let Some(cause) = cause {
        failed["cause"] = json!(cause);
    }
    json!({
        "compliant": false,
        "requirements": {"approved": {"status": "not_met"}},
        "results": [failed]
    })
}

#[test]
fn a_subject_is_out_of_scope_only_when_its_applies_row_fails_with_value() {
    assert_eq!(
        render(&applies_report(Some("value")), &json!({}), &GLYPHS).unwrap(),
        "✗ approved is not met\n\n  1 row: 0 passed, 0 failed, 1 out of scope\n\n∴ not compliant\n"
    );
}

#[test]
fn an_applies_row_that_fails_with_any_other_cause_is_a_failed_row_not_an_out_of_scope_subject() {
    for cause in [
        Some("absent"),
        Some("null"),
        Some("unusable"),
        Some("not_an_object"),
        Some("ambiguous"),
        Some("something_new"),
        None,
    ] {
        assert_eq!(
            render(&applies_report(cause), &json!({}), &GLYPHS).unwrap(),
            "✗ approved is not met\n    ✗ deployment d2 fails $applies\n      because environment is missing\n\n  1 row: 0 passed, 1 failed, 0 out of scope\n\n∴ not compliant\n",
            "{cause:?}"
        );
    }
}

#[test]
fn an_applies_row_with_a_cause_other_than_value_is_listed_with_show_all_as_a_failure() {
    let style = Style {
        show: Show::All,
        ..GLYPHS
    };
    assert_eq!(
        render(&applies_report(Some("absent")), &json!({}), &style).unwrap(),
        "✗ approved is not met\n    ✗ deployment d2 fails $applies\n      because environment is missing\n\n  1 row: 0 passed, 1 failed, 0 out of scope\n\n∴ not compliant\n"
    );
}

fn artifacts_policy() -> Value {
    json!({
        "subjects": {
            "deployment": {"from": "deployments", "identified_by": "id"},
            "artifact": {"from": "every deployment.artifacts", "identified_by": "name"}
        }
    })
}

fn artifact_row(check: &str, deployment: &str, passed: bool) -> Value {
    json!({
        "requirement": "tested",
        "check": check,
        "passed": passed,
        "message": "tests is \"failed\"",
        "subject": {"type": "artifact", "id": "web", "in": {"deployment": deployment}}
    })
}

#[test]
fn a_row_names_its_parent_subjects_like_the_outcome_lines_do() {
    let report = json!({
        "compliant": false,
        "requirements": {"tested": {"status": "not_met"}},
        "results": [
            artifact_row("tests_passed", "d1", false),
            artifact_row("tests_passed", "d2", false),
            artifact_row("$min_subjects", "d4", false)
        ]
    });
    let text = render(&report, &artifacts_policy(), &GLYPHS).unwrap();
    assert!(
        text.contains("    ✗ artifact web in deployment d1 fails tests_passed\n"),
        "{text}"
    );
    assert!(
        text.contains("    ✗ artifact web in deployment d2 fails tests_passed\n"),
        "{text}"
    );
    assert!(
        text.contains("    ✗ artifact web in deployment d4 fails $min_subjects\n"),
        "{text}"
    );
}

#[test]
fn a_row_whose_parents_the_policy_cannot_place_still_names_the_ones_the_report_gives() {
    let report = json!({
        "compliant": false,
        "requirements": {"tested": {"status": "not_met"}},
        "results": [artifact_row("tests_passed", "d1", false)]
    });
    let text = render(&report, &json!({}), &GLYPHS).unwrap();
    assert!(
        text.contains("    ✗ artifact web in deployment d1 fails tests_passed\n"),
        "{text}"
    );
}

#[test]
fn the_row_of_a_check_ergo_adds_for_the_policy_names_the_subject_once() {
    let report = json!({
        "compliant": false,
        "requirements": {"$policy": {"status": "not_met"}},
        "results": [{
            "requirement": "$policy",
            "check": "$well_formed",
            "passed": false,
            "message": "policy ergo_spec: missing",
            "subject": {"type": "$policy", "id": "$policy"}
        }]
    });
    let text = render(&report, &json!({}), &GLYPHS).unwrap();
    assert!(
        text.contains("    ✗ $policy fails $well_formed\n"),
        "{text}"
    );
}

#[test]
fn a_report_with_no_requirements_and_no_rows_starts_with_its_count_and_not_an_empty_line() {
    let report = json!({"compliant": true, "requirements": {}, "results": []});
    assert_eq!(
        render(&report, &json!({}), &GLYPHS).unwrap(),
        "  0 rows: 0 passed, 0 failed, 0 out of scope\n\n∴ compliant\n"
    );
}
