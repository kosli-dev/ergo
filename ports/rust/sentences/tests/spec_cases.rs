mod oracle;
mod support;

use ergo_sentences::*;
use serde_json::Value;
use std::fs;
use std::path::PathBuf;

struct Lines {
    from: Vec<String>,
    paths: Vec<String>,
}

fn strings_of(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_str)
        .map(str::to_string)
        .into_iter()
        .collect()
}

fn read_cases() -> Lines {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../spec/cases");
    let mut lines = Lines {
        from: Vec::new(),
        paths: Vec::new(),
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
