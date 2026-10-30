#![allow(dead_code)]

use ergo_sentences::{
    SyntaxError, check_problems, for_problems, from_problems, parse_check, parse_for, parse_from,
};
use serde_json::{Value, json};
use std::io::Read;

fn messages<T>(
    read: Result<T, Vec<SyntaxError>>,
    found: impl Fn(&T) -> Vec<String>,
) -> (Vec<String>, Vec<String>) {
    match read {
        Ok(tree) => (Vec::new(), found(&tree)),
        Err(errors) => {
            let syntax: Vec<String> = errors.into_iter().map(|e| e.message).collect();
            (syntax.clone(), syntax)
        }
    }
}

fn read_kind(kind: &str, text: &str) -> Value {
    let (syntax, problems) = match kind {
        "check" => messages(parse_check(text), |c| check_problems(c, &[])),
        "for-line" => messages(parse_for(text), |f| for_problems(f, &[])),
        "from-line" => messages(parse_from(text), from_problems),
        other => {
            let unknown = vec![format!("unknown kind {other}")];
            (unknown.clone(), unknown)
        }
    };
    json!({"kind": kind, "syntax": syntax, "problems": problems})
}

pub fn read_rows(input: &Value) -> Value {
    let rows = input["rows"].as_array().map_or(&[][..], Vec::as_slice);
    let read = rows.iter().map(|row| {
        let text = row["text"].as_str().unwrap_or("");
        let kinds = row["kinds"].as_array().map_or(&[][..], Vec::as_slice);
        Value::Array(
            kinds
                .iter()
                .map(|kind| read_kind(kind.as_str().unwrap_or(""), text))
                .collect(),
        )
    });
    Value::Array(read.collect())
}

fn main() {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .expect("stdin is not text");
    let rows: Value = serde_json::from_str(&input).expect("stdin is not JSON");
    println!("{}", read_rows(&rows));
}
