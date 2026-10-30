mod oracle;
mod support;

use ergo_policy_sentences::*;
use serde_json::Value;
use std::fs;
use std::path::PathBuf;

struct Lines {
    from: Vec<String>,
    paths: Vec<String>,
    checks: Vec<String>,
    fors: Vec<String>,
}

fn strings_of(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_str)
        .map(str::to_string)
        .into_iter()
        .collect()
}

fn strings_in(value: &Value) -> Vec<String> {
    match value {
        Value::String(text) => vec![text.clone()],
        Value::Array(items) => items.iter().flat_map(strings_in).collect(),
        _ => Vec::new(),
    }
}

fn collect(value: &Value, lines: &mut Lines) {
    match value {
        Value::Object(map) => {
            for (key, inner) in map {
                match key.as_str() {
                    "assert" => lines.checks.extend(strings_in(inner)),
                    "for" => lines.fors.extend(strings_in(inner)),
                    "checks" => {
                        if let Some(checks) = inner.as_object() {
                            for check in checks.values() {
                                lines.checks.extend(strings_in(check));
                            }
                        }
                    }
                    "any_of" => {
                        if let Some(options) = inner.as_object() {
                            for option in options.values() {
                                lines.checks.extend(strings_in(option));
                            }
                        }
                    }
                    _ => {}
                }
                collect(inner, lines);
            }
        }
        Value::Array(items) => items.iter().for_each(|item| collect(item, lines)),
        _ => {}
    }
}

fn read_cases() -> Lines {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../spec/cases");
    let mut lines = Lines {
        from: Vec::new(),
        paths: Vec::new(),
        checks: Vec::new(),
        fors: Vec::new(),
    };
    let mut folders: Vec<PathBuf> = fs::read_dir(&root)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    folders.sort();
    for folder in folders {
        let groups: Value =
            serde_json::from_str(&fs::read_to_string(folder.join("cases.json")).unwrap()).unwrap();
        for group in groups.as_array().unwrap() {
            collect(&group["policy"], &mut lines);
            let Some(subjects) = group["policy"]["subjects"].as_object() else {
                continue;
            };
            for subject in subjects.values() {
                lines.from.extend(strings_of(subject.get("from")));
                lines.paths.extend(strings_of(subject.get("identified_by")));
                let Some(parts) = subject.get("has").and_then(Value::as_object) else {
                    continue;
                };
                for part in parts.values() {
                    lines.from.extend(strings_of(Some(part)));
                    lines.paths.extend(strings_of(Some(part)));
                    lines.from.extend(strings_of(part.get("from")));
                    lines.paths.extend(strings_of(part.get("from")));
                    lines.paths.extend(strings_of(part.get("identified_by")));
                }
            }
        }
    }
    lines
}

fn known_from(line: &str) -> Option<bool> {
    let reads = |list: &[(&str, &str)]| list.iter().any(|(l, _)| *l == line);
    let fails = |list: &[(&str, &[&str])]| list.iter().any(|(l, _)| *l == line);
    if reads(oracle::FROM_OK) || fails(oracle::FROM_WRITTEN_WRONG) {
        Some(true)
    } else if fails(oracle::FROM_ERRORS) || fails(oracle::FROM_PARTIAL) {
        Some(false)
    } else {
        None
    }
}

#[test]
fn the_cases_hold_from_lines_and_paths() {
    let lines = read_cases();
    assert!(lines.from.len() > 100, "{}", lines.from.len());
    assert!(lines.paths.len() > 40, "{}", lines.paths.len());
}

#[test]
fn every_from_line_in_the_cases_reads_as_ergo_rego_reads_it() {
    for line in read_cases().from {
        let expected =
            known_from(&line).unwrap_or_else(|| panic!("{line:?} is not in tests/oracle"));
        assert_eq!(parse_from(&line).is_ok(), expected, "{line:?}");
    }
}

#[test]
fn every_path_in_the_cases_reads_as_ergo_rego_reads_it() {
    for line in read_cases().paths {
        let expected = oracle::PATH_OK.iter().find(|(l, _)| *l == line);
        let fails = oracle::PATH_ERRORS.contains(&line.as_str());
        assert!(
            expected.is_some() || fails,
            "{line:?} is not in tests/oracle"
        );
        match expected {
            Some((_, printed)) => {
                let read = parse_path(&line).unwrap_or_else(|e| panic!("{line:?}: {e:?}"));
                assert_eq!(&print_path(&read, Side::Left, &[]), printed, "{line:?}");
            }
            None => assert!(parse_path(&line).is_err(), "{line:?}"),
        }
    }
}

#[test]
fn every_check_in_the_cases_reads_as_ergo_rego_reads_it() {
    let lines = read_cases();
    assert!(lines.checks.len() > 300, "{}", lines.checks.len());
    for line in lines.checks {
        let all = oracle::checks::CHECK_OK.iter().any(|(l, ..)| *l == line);
        let wrong = oracle::checks::CHECK_WRITTEN_WRONG
            .iter()
            .any(|(l, _)| *l == line);
        let fails = oracle::checks::CHECK_ERRORS.iter().any(|(l, _)| *l == line);
        assert!(all || wrong || fails, "{line:?} is not in tests/oracle");
        assert_eq!(parse_check(&line).is_ok(), all || wrong, "{line:?}");
    }
}

#[test]
fn every_for_line_in_the_cases_reads_as_ergo_rego_reads_it() {
    let lines = read_cases();
    assert!(lines.fors.len() > 40, "{}", lines.fors.len());
    for line in lines.fors {
        let all = oracle::checks::FOR_OK.iter().any(|(l, ..)| *l == line);
        let wrong = oracle::checks::FOR_WRITTEN_WRONG
            .iter()
            .any(|(l, _)| *l == line);
        let fails = oracle::checks::FOR_ERRORS.iter().any(|(l, _)| *l == line);
        assert!(all || wrong || fails, "{line:?} is not in tests/oracle");
        assert_eq!(parse_for(&line).is_ok(), all || wrong, "{line:?}");
    }
}

#[test]
fn every_sentence_in_the_corpus_reads_as_a_check_a_for_line_or_a_from_line() {
    let path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../spec/sentences-corpus.json");
    let corpus: Value = serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
    let sentences = corpus["sentence_corpus"].as_array().unwrap();
    assert!(sentences.len() > 300, "{}", sentences.len());
    for sentence in sentences {
        let line = sentence.as_str().unwrap();
        assert!(
            parse_check(line).is_ok() || parse_for(line).is_ok() || parse_from(line).is_ok(),
            "{line:?}"
        );
    }
}
