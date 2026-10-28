use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Value, json};

fn regression_files() -> Vec<PathBuf> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/regressions");
    let mut files: Vec<PathBuf> = fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("can't read {}: {e}", dir.display()))
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .collect();
    files.sort();
    files
}

fn without_engine(mut report: Value) -> Value {
    if let Some(object) = report.as_object_mut() {
        object.remove("engine");
    }
    report
}

#[test]
fn every_regression_gives_the_report_it_pins() {
    let files = regression_files();
    assert!(!files.is_empty(), "no regression files");
    let mut failures = Vec::new();
    let mut count = 0;
    for file in files {
        let text = fs::read_to_string(&file).unwrap();
        let entries: Value = serde_json::from_str(&text)
            .unwrap_or_else(|e| panic!("can't parse {}: {e}", file.display()));
        let name = file.file_name().unwrap().to_string_lossy().into_owned();
        for entry in entries.as_array().expect("a regression file holds a list") {
            count += 1;
            let description = entry["description"]
                .as_str()
                .expect("a regression has a description");
            let params = entry.get("params").cloned().unwrap_or_else(|| json!({}));
            let got = without_engine(ergo_engine::report(
                &entry["input"],
                &entry["policy"],
                &params,
            ));
            let wanted = without_engine(entry["report"].clone());
            if got != wanted {
                failures.push(format!(
                    "{name}: {description}\n  wanted {wanted}\n  got    {got}"
                ));
            }
        }
    }
    println!("{count} regressions");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
