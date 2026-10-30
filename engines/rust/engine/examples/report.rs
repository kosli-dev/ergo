use std::time::Instant;

use serde_json::{Value, json};

fn load(path: &str) -> Value {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("can't read {path}: {e}"));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("can't parse {path}: {e}"))
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: report <input.json> <policy.json> [runs] [params.json]");
        std::process::exit(2);
    }
    let input = load(&args[1]);
    let policy = load(&args[2]);
    let runs: u32 = args
        .get(3)
        .map_or(1, |n| n.parse().expect("runs is a number"));
    let params = args.get(4).map_or_else(|| json!({}), |path| load(path));
    let started = Instant::now();
    let mut report = Value::Null;
    for _ in 0..runs {
        report = ergo_policy_engine::report(&input, &policy, &params);
    }
    eprintln!(
        "report: {:.1} ms per run",
        started.elapsed().as_secs_f64() * 1000.0 / f64::from(runs.max(1))
    );
    println!("{report}");
}
