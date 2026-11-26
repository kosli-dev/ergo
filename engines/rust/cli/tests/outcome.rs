use ergo_policy_cli::outcome::{self, Item};
use serde_json::{Value, json};

fn row(check: &str, id: Value, passed: bool, message: Option<&str>) -> Value {
    let mut row = json!({
        "requirement": "approved",
        "subject": {"type": "pull request", "id": id},
        "check": check,
        "passed": passed,
        "cause": if passed { "satisfied" } else { "value" },
    });
    if let Some(message) = message {
        row["message"] = json!(message);
    }
    row
}

#[test]
fn a_plain_word_id_is_written_bare_and_anything_else_as_json() {
    let cases = [
        (json!("d1"), "d1"),
        (json!(7), "7"),
        (json!("7"), "\"7\""),
        (json!("true"), "\"true\""),
        (json!("null"), "\"null\""),
        (json!("1e3"), "\"1e3\""),
        (json!("web app"), "\"web app\""),
        (json!("\"q"), "\"\\\"q\""),
        (json!(""), "\"\""),
        (json!(true), "true"),
        (json!(null), "null"),
        (serde_json::from_str("1.50").unwrap(), "1.50"),
    ];
    for (id, text) in cases {
        assert_eq!(outcome::id_text(&id).as_deref(), Some(text), "{id}");
        assert_eq!(
            outcome::read_id(&format!("{text} rest")),
            Some((id, " rest"))
        );
    }
}

#[test]
fn ids_that_are_numbers_are_the_same_when_their_values_are() {
    let number = |text: &str| serde_json::from_str::<Value>(text).unwrap();
    for (a, b) in [
        ("7.0", "7"),
        ("7.00", "7"),
        ("1.50", "1.5"),
        ("1e3", "1000"),
        ("1E+3", "1000"),
        ("-0", "0"),
        ("-0.0", "0"),
        ("0.0010", "1e-3"),
        ("1e400", "10e399"),
    ] {
        assert!(outcome::same_id(&number(a), &number(b)), "{a} and {b}");
    }
    for (a, b) in [("7", "8"), ("-1", "1"), ("1e400", "1e401"), ("0.1", "1")] {
        assert!(!outcome::same_id(&number(a), &number(b)), "{a} and {b}");
    }
    assert!(!outcome::same_id(&json!(7), &json!("7")));
    assert!(!outcome::same_id(&json!(1), &json!(true)));
    assert!(outcome::same_id(&json!("d1"), &json!("d1")));
    assert!(!outcome::same_id(&json!("7.0"), &json!("7")));
    assert!(outcome::same_id(&json!(null), &json!(null)));
}

#[test]
fn an_id_that_is_an_object_or_a_list_has_no_text_yet() {
    assert_eq!(outcome::id_text(&json!({"a": 1})), None);
    assert_eq!(outcome::id_text(&json!([1])), None);
}

#[test]
fn a_row_of_a_check_is_a_passes_or_fails_line() {
    assert_eq!(
        outcome::row_line(&row("peer_approved", json!(7), true, None), &json!({})),
        Ok(Some("pull request 7 passes peer_approved".to_string()))
    );
    assert_eq!(
        outcome::row_line(
            &row("peer_approved", json!("a b"), false, Some("x is 1")),
            &json!({})
        ),
        Ok(Some(
            "pull request \"a b\" fails peer_approved because x is 1".to_string()
        ))
    );
}

#[test]
fn a_passed_row_of_a_check_ergo_adds_is_not_a_line() {
    assert_eq!(
        outcome::row_line(&row("$applies", json!(7), true, None), &json!({})),
        Ok(None)
    );
    assert_eq!(
        outcome::row_line(&row("$min_subjects", json!(null), true, None), &json!({})),
        Ok(None)
    );
}

#[test]
fn a_row_the_outcome_form_cannot_show_yet_is_an_error() {
    let mut child = row("c", json!("web"), true, None);
    child["subject"]["in"] = json!({"type": "deployment", "id": "d1"});
    let shown = [
        child,
        row("$applies", json!("d3"), false, Some("env is \"dev\"")),
        row("$min_subjects", json!(null), false, Some("count is 0")),
        row("c", json!({"a": 1}), true, None),
    ];
    for row in shown {
        assert!(outcome::row_line(&row, &json!({})).is_err(), "{row}");
    }
}

#[test]
fn yaml_quotes_only_the_lines_yaml_would_read_otherwise() {
    let items = vec![
        Item::Line("not compliant".to_string()),
        Item::Line("released is met".to_string()),
        Item::Group(
            "approved is not met".to_string(),
            vec![
                "deployment d1 fails a because item 2 of xs: status is \"failed\"".to_string(),
                "deployment d2 fails a because x is 'q' #1".to_string(),
                "deployment d3 fails a because x is \"a\tb\"".to_string(),
                "deployment d4 passes a".to_string(),
            ],
        ),
    ];
    let text = outcome::yaml(&items);
    assert_eq!(
        text,
        "- not compliant\n- released is met\n- approved is not met:\n    - 'deployment d1 fails a because item 2 of xs: status is \"failed\"'\n    - 'deployment d2 fails a because x is ''q'' #1'\n    - \"deployment d3 fails a because x is \\\"a\\tb\\\"\"\n    - deployment d4 passes a\n"
    );
    let read = ergo_policy_cli::yaml::parse(&text).unwrap();
    assert_eq!(read, outcome::to_json(&items));
}

#[test]
fn yaml_quotes_a_heading_that_yaml_would_read_otherwise() {
    let items = vec![Item::Group(
        "a: b is met".to_string(),
        vec!["t 1 passes c".to_string()],
    )];
    let text = outcome::yaml(&items);
    assert_eq!(text, "- 'a: b is met':\n    - t 1 passes c\n");
    assert_eq!(
        ergo_policy_cli::yaml::parse(&text).unwrap(),
        json!([{"a: b is met": ["t 1 passes c"]}])
    );
}

fn report(policy: Value, input: Value) -> Value {
    let mut policy = policy;
    policy["ergo_spec"] = json!(ergo_policy_engine::SPEC);
    ergo_policy_engine::report(&input, &policy, &json!({}))
}

fn two_requirements() -> Value {
    json!({
        "subjects": {
            "pull request": {"from": "prs", "identified_by": "number"},
            "scan": {"from": "scans", "identified_by": "name"}
        },
        "requirements": {
            "reviewed": {"subject": "pull request", "checks": {
                "approved": "approver is a non-empty string",
                "small": "lines is at most 10"
            }},
            "scanned": {"subject": "scan", "checks": {"clean": "findings is 0"}},
            "spare": {"subject": "scan", "min_subjects": 0, "checks": {"never": "findings is 0"}}
        }
    })
}

fn two_requirements_input() -> Value {
    json!({
        "prs": [{"number": 7, "approver": "ann", "lines": 3}, {"number": 8, "lines": 3}],
        "scans": [{"name": "sast", "findings": 0}]
    })
}

fn lines(lines: &[&str]) -> Vec<String> {
    lines.iter().map(|line| line.to_string()).collect()
}

#[test]
fn the_outcome_of_a_report_has_compliant_then_each_requirement_with_its_status_and_rows() {
    let report = report(two_requirements(), two_requirements_input());
    assert_eq!(
        outcome::of(&report),
        Ok(vec![
            Item::Line("not compliant".to_string()),
            Item::Group(
                "reviewed is not met".to_string(),
                lines(&[
                    "pull request 7 passes approved",
                    "pull request 7 passes small",
                    "pull request 8 fails approved because approver is missing",
                    "pull request 8 passes small",
                ])
            ),
            Item::Group(
                "scanned is met".to_string(),
                lines(&["scan sast passes clean"])
            ),
            Item::Group(
                "spare is met".to_string(),
                lines(&["scan sast passes never"])
            ),
        ])
    );
}

#[test]
fn the_outcome_of_a_report_with_a_row_it_cannot_show_yet_is_an_error() {
    let mut policy = two_requirements();
    policy["subjects"]["pull request"]["from"] = json!("prs whose lines is 3");
    let mut input = two_requirements_input();
    input["prs"][1]["lines"] = json!(5);
    let error = outcome::of(&report(policy, input)).unwrap_err();
    assert!(error.contains("subjects out of scope"), "{error}");
    let error =
        outcome::of(&report(two_requirements(), json!({"prs": [], "scans": []}))).unwrap_err();
    assert!(error.contains("checks Ergo adds"), "{error}");
}

#[test]
fn a_requirement_with_no_row_to_show_is_a_line_on_its_own() {
    let mut policy = two_requirements();
    policy["requirements"] = json!({"spare": policy["requirements"]["spare"].clone()});
    assert_eq!(
        outcome::of(&report(policy, json!({"scans": []}))),
        Ok(vec![
            Item::Line("compliant".to_string()),
            Item::Line("spare is not applicable".to_string()),
        ])
    );
}

fn named_with_a_status(short: &str, long: &str) -> Value {
    json!({
        "subjects": {"t": {"from": "ts", "identified_by": "id"}},
        "requirements": {
            short: {"subject": "t", "checks": {"c": "p is true"}},
            long: {"subject": "t", "checks": {"c": "w is true"}}
        }
    })
}

#[test]
fn the_outcome_of_a_report_with_a_heading_that_could_name_two_requirements_is_an_error() {
    let input = json!({"ts": [{"id": "t1", "p": true, "w": false}]});
    let error =
        outcome::of(&report(named_with_a_status("x", "x is met"), input.clone())).unwrap_err();
    assert_eq!(
        error,
        "the heading x is met, for the status of x, would also name the requirement x is met, so it can't read back"
    );
    let input = json!({"ts": [{"id": "t1", "p": false, "w": true}]});
    let error = outcome::of(&report(named_with_a_status("a", "a is not met"), input)).unwrap_err();
    assert_eq!(
        error,
        "the heading a is not met, for the status of a, would also name the requirement a is not met, so it can't read back"
    );
}

#[test]
fn the_outcome_of_a_report_whose_headings_name_one_requirement_each_is_shown() {
    let input = json!({"ts": [{"id": "t1", "p": false, "w": false}]});
    assert_eq!(
        outcome::of(&report(named_with_a_status("x", "x is met"), input)),
        Ok(vec![
            Item::Line("not compliant".to_string()),
            Item::Group(
                "x is not met".to_string(),
                lines(&["t t1 fails c because p is false"])
            ),
            Item::Group(
                "x is met is not met".to_string(),
                lines(&["t t1 fails c because w is false"])
            ),
        ])
    );
}

#[test]
fn a_part_of_the_outcome_shows_a_bare_heading_for_a_requirement_only_some_checks_cover() {
    let report = report(two_requirements(), two_requirements_input());
    let mut part = outcome::Region::default();
    part.checks
        .insert(("reviewed".to_string(), "approved".to_string()));
    part.requirements.insert("scanned".to_string());
    assert_eq!(
        outcome::part(&report, &part),
        vec![
            Item::Group(
                "reviewed".to_string(),
                lines(&[
                    "pull request 7 passes approved",
                    "pull request 8 fails approved because approver is missing",
                ])
            ),
            Item::Group(
                "scanned is met".to_string(),
                lines(&["scan sast passes clean"])
            ),
        ]
    );
}

#[test]
fn yaml_escapes_the_characters_yaml_cannot_hold_as_they_are() {
    for c in [
        '\u{7f}', '\u{80}', '\u{85}', '\u{9b}', '\u{9f}', '\u{2028}', '\u{2029}', '\u{1}',
    ] {
        let line = format!("t \"a{c}b\" fails c because x is \"a{c}b\"");
        let items = vec![Item::Group("r is not met".to_string(), vec![line.clone()])];
        let text = outcome::yaml(&items);
        assert!(!text.contains(c), "U+{:04X}: {text:?}", c as u32);
        assert_eq!(
            ergo_policy_cli::yaml::parse(&text),
            Ok(json!([{"r is not met": [line]}])),
            "U+{:04X}: {text:?}",
            c as u32
        );
    }
}

#[test]
fn a_check_line_names_the_longest_subject_and_the_longest_check_that_fit() {
    let subjects = ["t", "t x"];
    let checks = ["c", "c because d"];
    let read = |text: &str| outcome::read_check_line(text, "r", &subjects, &checks);
    let line = |subject: &str, id: Value, passes: bool, check: &str, because: Option<&str>| {
        Ok(outcome::CheckLine {
            subject: subject.to_string(),
            id,
            passes,
            check: check.to_string(),
            because: because.map(str::to_string),
            parents: Vec::new(),
        })
    };
    assert_eq!(
        read("t x 1 passes c"),
        line("t x", json!(1), true, "c", None)
    );
    assert_eq!(
        read("t \"x\" passes c"),
        line("t", json!("x"), true, "c", None)
    );
    assert_eq!(
        read("t 1 fails c because d"),
        line("t", json!(1), false, "c because d", None)
    );
    assert_eq!(
        read("t 1 fails c because d because e"),
        line("t", json!(1), false, "c because d", Some("e"))
    );
    assert_eq!(
        read("t 1 fails c because e"),
        line("t", json!(1), false, "c", Some("e"))
    );
    assert_eq!(
        read("t 1 passes c because d"),
        line("t", json!(1), true, "c because d", None)
    );
    assert!(read("t 1 passes c because e").is_err());
}

fn colliding() -> Value {
    json!({
        "subjects": {
            "pull": {"from": "pulls", "identified_by": "id"},
            "pull request": {"from": "prs", "identified_by": "id"},
            "t": {"from": "ts", "identified_by": "id"},
            "t x": {"from": "txs", "identified_by": "id"}
        },
        "requirements": {
            "pulled": {"subject": "pull", "checks": {"c": "ok is true"}},
            "reviewed": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "ok is true"}},
            "checked": {"subject": "t", "checks": {"c": "ok is true", "c because ok is false": "ok exists"}},
            "crossed": {"subject": "t x", "min_subjects": 0, "checks": {"c": "ok is true"}}
        }
    })
}

fn line_of(report: &Value, requirement: &str, id: &str) -> Result<Option<String>, String> {
    let rows = report["results"].as_array().unwrap();
    let row = rows
        .iter()
        .find(|row| {
            row["requirement"] == requirement && row["check"] == "c" && row["subject"]["id"] == id
        })
        .unwrap();
    outcome::line_for(row, report)
}

#[test]
fn a_line_for_a_row_quotes_an_id_that_would_read_as_part_of_a_longer_subject_name() {
    let report = report(
        colliding(),
        json!({"pulls": [{"id": "request", "ok": true}], "prs": [], "ts": [{"id": "x", "ok": true}], "txs": []}),
    );
    assert_eq!(
        line_of(&report, "pulled", "request"),
        Ok(Some("pull \"request\" passes c".to_string()))
    );
    assert_eq!(
        line_of(&report, "checked", "x"),
        Ok(Some("t \"x\" passes c".to_string()))
    );
}

#[test]
fn a_line_for_a_row_leaves_out_a_because_that_would_read_as_part_of_a_longer_check_name() {
    let report = report(
        colliding(),
        json!({"pulls": [], "prs": [], "ts": [{"id": "y", "ok": false}, {"id": "z", "ok": 3}], "txs": []}),
    );
    assert_eq!(
        line_of(&report, "checked", "y"),
        Ok(Some("t y fails c".to_string()))
    );
    assert_eq!(
        line_of(&report, "checked", "z"),
        Ok(Some(
            "t z fails c because ok is 3, which isn't true or false".to_string()
        ))
    );
}

fn children() -> Value {
    json!({
        "subjects": {
            "release": {"from": "releases", "identified_by": "id"},
            "artifact": {"from": "every release.artifacts", "identified_by": "name"},
            "test run": {"from": "every artifact.runs", "identified_by": "n"}
        },
        "requirements": {
            "tested": {"subject": "artifact", "checks": {"passed": "status is \"passed\""}},
            "ran": {"subject": "test run", "min_subjects": 0, "checks": {"ok": "ok is true"}}
        }
    })
}

fn children_input() -> Value {
    json!({"releases": [
        {"id": "r1", "artifacts": [
            {"name": "web", "status": "passed", "runs": [{"n": 1, "ok": true}]},
            {"name": "api", "status": "failed"}
        ]},
        {"id": "r2", "artifacts": [{"name": "web", "status": "passed"}]}
    ]})
}

#[test]
fn the_ancestors_of_a_subject_come_from_the_from_lines_the_report_keeps() {
    let report = report(children(), children_input());
    assert_eq!(
        outcome::ancestors(&report, "test run"),
        vec!["artifact", "release"]
    );
    assert_eq!(outcome::ancestors(&report, "artifact"), vec!["release"]);
    assert_eq!(outcome::ancestors(&report, "release"), Vec::<String>::new());
}

#[test]
fn the_outcome_of_a_report_names_the_parents_of_a_child_subject_outermost_last() {
    let report = report(children(), children_input());
    assert_eq!(
        outcome::of(&report),
        Ok(vec![
            Item::Line("not compliant".to_string()),
            Item::Group(
                "ran is met".to_string(),
                lines(&["test run 1 in artifact web in release r1 passes ok"])
            ),
            Item::Group(
                "tested is not met".to_string(),
                lines(&[
                    "artifact web in release r1 passes passed",
                    "artifact api in release r1 fails passed because status is \"failed\"",
                    "artifact web in release r2 passes passed",
                ])
            ),
        ])
    );
}

#[test]
fn a_row_whose_in_does_not_follow_the_from_lines_of_the_report_has_no_line() {
    let report = report(children(), children_input());
    let mut row = report["results"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["check"] == "ok")
        .unwrap()
        .clone();
    assert!(outcome::line_for(&row, &report).is_ok());
    for parents in [
        json!({"artifact": "web"}),
        json!({"release": "r1", "deployment": "d1"}),
        json!({"artifact": "web", "release": "r1", "deployment": "d1"}),
        json!({}),
        json!(["web", "r1"]),
        json!({"artifact": {"a": 1}, "release": "r1"}),
    ] {
        row["subject"]["in"] = parents.clone();
        assert!(outcome::line_for(&row, &report).is_err(), "{parents}");
    }
    row["subject"].as_object_mut().unwrap().remove("in");
    assert!(outcome::line_for(&row, &report).is_err());
}

#[test]
fn a_check_line_reads_each_in_after_the_id_with_the_longest_subject_name_that_fits() {
    let subjects = ["artifact", "deployment", "release", "release train"];
    let checks = ["c"];
    let read = |text: &str| outcome::read_check_line(text, "r", &subjects, &checks);
    let parents = |pairs: &[(&str, Value)]| -> Vec<(String, Value)> {
        pairs
            .iter()
            .map(|(name, id)| (name.to_string(), id.clone()))
            .collect()
    };
    let line = read("artifact web in deployment d1 fails c because x in y").unwrap();
    assert_eq!(
        (line.subject.as_str(), &line.id, line.because.as_deref()),
        ("artifact", &json!("web"), Some("x in y"))
    );
    assert_eq!(line.parents, parents(&[("deployment", json!("d1"))]));
    let line =
        read("artifact deployment in deployment 7 in release train \"r 1\" passes c").unwrap();
    assert_eq!(line.id, json!("deployment"));
    assert_eq!(
        line.parents,
        parents(&[("deployment", json!(7)), ("release train", json!("r 1"))])
    );
    let line = read("artifact in in release r1 passes c").unwrap();
    assert_eq!(line.id, json!("in"));
    assert_eq!(line.parents, parents(&[("release", json!("r1"))]));
    for (text, reason) in [
        (
            "artifact web in robot r1 passes c",
            "it has no subject of the policy after in",
        ),
        (
            "artifact web in deployment",
            "it has no id after in deployment",
        ),
        (
            "artifact web in deployment ",
            "it has no id after in deployment",
        ),
        (
            "artifact web in deployment d1 is out of scope",
            "lines for subjects in or out of scope aren't supported yet",
        ),
        (
            "artifact in deployment d4 fails $min_subjects because in-scope artifact count is 0",
            "lines for checks Ergo adds aren't supported yet",
        ),
    ] {
        assert_eq!(read(text), Err(reason.to_string()), "{text}");
    }
}

fn shadowed() -> Value {
    json!({
        "subjects": {
            "deployment": {"from": "deployments", "identified_by": "id"},
            "deployment x": {"from": "xs", "identified_by": "id"},
            "artifact": {"from": "every deployment.artifacts", "identified_by": "name"},
            "artifact web": {"from": "webs", "identified_by": "id"}
        },
        "requirements": {
            "tested": {"subject": "artifact", "checks": {"c": "ok is true"}},
            "spare": {"subject": "deployment x", "min_subjects": 0, "checks": {"c": "ok is true"}},
            "spare web": {"subject": "artifact web", "min_subjects": 0, "checks": {"c": "ok is true"}}
        }
    })
}

#[test]
fn a_line_for_a_child_row_quotes_the_ids_that_would_read_as_part_of_a_longer_subject_name() {
    let report = report(
        shadowed(),
        json!({"xs": [], "webs": [], "deployments": [
            {"id": "x", "artifacts": [{"name": "deployment", "ok": true}]},
            {"id": "d1", "artifacts": [{"name": "web", "ok": true}]}
        ]}),
    );
    let rows = report["results"].as_array().unwrap();
    let printed: Vec<String> = rows
        .iter()
        .filter(|row| row["requirement"] == "tested" && row["check"] == "c")
        .map(|row| outcome::line_for(row, &report).unwrap().unwrap())
        .collect();
    assert_eq!(
        printed,
        vec![
            "artifact \"deployment\" in deployment \"x\" passes c",
            "artifact \"web\" in deployment \"d1\" passes c",
        ]
    );
}
