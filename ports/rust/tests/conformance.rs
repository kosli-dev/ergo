use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

fn case_files(dir: &Path, found: &mut Vec<PathBuf>) {
    let mut entries: Vec<PathBuf> = fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            case_files(&path, found);
        } else if path.file_name().is_some_and(|n| n == "cases.json") {
            found.push(path);
        }
    }
}

#[test]
fn every_conformance_case_gives_its_expected_report() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../conformance");
    let mut files = vec![];
    case_files(&root, &mut files);
    assert!(!files.is_empty(), "no cases.json under {}", root.display());

    let mut failures = vec![];
    let mut total = 0;
    for file in &files {
        let topic = file.parent().unwrap().strip_prefix(&root).unwrap().display().to_string();
        let groups: Vec<Value> = serde_json::from_str(&fs::read_to_string(file).unwrap()).unwrap();
        for group in &groups {
            for case in group["cases"].as_array().unwrap() {
                total += 1;
                let name = format!("{topic} / {} / {}", group["description"].as_str().unwrap(), case["description"].as_str().unwrap());
                let report = ergo::report(&case["input"], group.get("params"), &group["requirements"]);
                if report != case["report"] {
                    failures.push(format!("{name}\n  expected report: {}\n  actual report:   {report}", case["report"]));
                    continue;
                }
                if let Some(expected) = case.get("violations") {
                    let actual = ergo::violations(&report);
                    if &actual != expected {
                        failures.push(format!("{name}\n  expected violations: {expected}\n  actual violations:   {actual}"));
                    }
                }
            }
        }
    }
    assert!(failures.is_empty(), "{} of {total} cases failed:\n\n{}", failures.len(), failures.join("\n\n"));
    println!("{total} cases passed");
}
