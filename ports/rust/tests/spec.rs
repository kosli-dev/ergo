use serde_json::Value;
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

const KNOWN_DIFFERENCES: &[&str] = &[
    "present / present written wrong / fails every check as ill_formed whatever the subject holds",
    "present / present as a filter / rules a subject out when the field is missing, even though the other filter can't read it",
    "present / present as a filter / rules a subject out when the field is null",
    "present / present as a filter / keeps a subject in scope when the field is there",
];

fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.to_string() == y.to_string(),
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| same(p, q)),
        (Value::Object(x), Value::Object(y)) => x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w))),
        _ => a == b,
    }
}

fn compared(check: &str, expected: &[Value]) -> bool {
    !check.starts_with('$') || check == "$applies" || expected.iter().any(|r| r["check"] == check)
}

fn passes(group: &Value, case: &Value) -> Result<(), String> {
    let report = ergo::report(&case["input"], group.get("params"), &group["policy"]);
    let expected = case["results"].as_array().unwrap();
    let rows: Vec<Value> = report["results"].as_array().unwrap().iter().filter(|r| compared(r["check"].as_str().unwrap(), expected)).cloned().collect();
    if !same(&Value::Array(rows.clone()), &case["results"]) {
        return Err(format!("expected rows: {}\n  actual rows:   {}", case["results"], Value::Array(rows)));
    }
    if let Some(statuses) = case.get("status").and_then(Value::as_object) {
        for (name, status) in statuses {
            if report["requirements"][name]["status"] != *status {
                return Err(format!("expected {name} to be {status}, but it is {}", report["requirements"][name]["status"]));
            }
        }
    }
    if let Some(compliant) = case.get("compliant") {
        if report["compliant"] != *compliant {
            return Err(format!("expected compliant to be {compliant}, but it is {}", report["compliant"]));
        }
    }
    Ok(())
}

#[test]
fn every_spec_case_passes_except_the_known_differences() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/cases");
    let mut topics: Vec<_> = fs::read_dir(&root).unwrap().map(|e| e.unwrap().path()).collect();
    topics.sort();
    assert!(!topics.is_empty(), "no topics under {}", root.display());

    let mut failed = BTreeSet::new();
    let mut messages = vec![];
    for dir in topics {
        let topic = dir.file_name().unwrap().to_string_lossy().to_string();
        let groups: Vec<Value> = serde_json::from_str(&fs::read_to_string(dir.join("cases.json")).unwrap()).unwrap();
        for group in &groups {
            for case in group["cases"].as_array().unwrap() {
                let name = format!("{topic} / {} / {}", group["description"].as_str().unwrap(), case["description"].as_str().unwrap());
                if let Err(why) = passes(group, case) {
                    messages.push(format!("{name}\n  {why}"));
                    failed.insert(name);
                }
            }
        }
    }
    let known: BTreeSet<String> = KNOWN_DIFFERENCES.iter().map(|s| s.to_string()).collect();
    let fixed: Vec<_> = known.difference(&failed).collect();
    assert!(fixed.is_empty(), "these cases pass now, so take them out of KNOWN_DIFFERENCES: {fixed:?}");
    let new: Vec<_> = messages.iter().filter(|m| !known.iter().any(|k| m.starts_with(&format!("{k}\n")))).collect();
    assert!(new.is_empty(), "{} cases failed:\n\n{}", new.len(), new.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("\n\n"));
}
