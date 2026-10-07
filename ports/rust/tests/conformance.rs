use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

fn exact(text: &str) -> (bool, String, i64) {
    let (negative, unsigned) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text),
    };
    let (mantissa, exponent) = match unsigned.split_once(['e', 'E']) {
        Some((m, e)) => (m, e.trim_start_matches('+').parse::<i64>().unwrap()),
        None => (unsigned, 0),
    };
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let digits = format!("{whole}{fraction}");
    let trimmed = digits.trim_start_matches('0');
    let point = exponent + whole.len() as i64 - (digits.len() - trimmed.len()) as i64;
    let significant = trimmed.trim_end_matches('0');
    if significant.is_empty() {
        return (false, String::new(), 0);
    }
    (negative, significant.to_string(), point)
}

fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => exact(&x.to_string()) == exact(&y.to_string()),
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| same(p, q)),
        (Value::Object(x), Value::Object(y)) => x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w))),
        _ => a == b,
    }
}

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
    let mut recorded = vec![];
    let mut total = 0;
    for file in &files {
        let topic = file.parent().unwrap().strip_prefix(&root).unwrap().display().to_string();
        let groups: Vec<Value> = serde_json::from_str(&fs::read_to_string(file).unwrap()).unwrap();
        for group in &groups {
            for case in group["cases"].as_array().unwrap() {
                total += 1;
                let name = format!("{topic} / {} / {}", group["description"].as_str().unwrap(), case["description"].as_str().unwrap());
                let report = ergo::report(&case["input"], group.get("params"), &group["requirements"]);
                if !same(&report, &case["report"]) {
                    recorded.push(serde_json::json!({"case": name, "expected": case["report"], "actual": report}).to_string());
                    failures.push(format!("{name}\n  expected report: {}\n  actual report:   {report}", case["report"]));
                    continue;
                }
                if let Some(expected) = case.get("violations") {
                    let actual = ergo::violations(&report);
                    if !same(&actual, expected) {
                        recorded.push(serde_json::json!({"case": name, "expected_violations": expected, "actual_violations": actual}).to_string());
                        failures.push(format!("{name}\n  expected violations: {expected}\n  actual violations:   {actual}"));
                    }
                }
            }
        }
    }
    if let Ok(path) = std::env::var("ERGO_FAILURES") {
        fs::write(path, recorded.join("\n")).unwrap();
    }
    assert!(failures.is_empty(), "{} of {total} cases failed:\n\n{}", failures.len(), failures.join("\n\n"));
    println!("{total} cases passed");
}
