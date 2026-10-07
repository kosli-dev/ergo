use std::time::Instant;

fn load(path: &str) -> serde_json::Value {
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let input = load(&args[1]);
    let requirements = load(&args[2]);
    let runs: u32 = args.get(3).map_or(1, |n| n.parse().unwrap());
    let started = Instant::now();
    let mut report = serde_json::Value::Null;
    for _ in 0..runs {
        report = ergo::report(&input, None, &requirements);
    }
    eprintln!("report: {:.1} ms per run", started.elapsed().as_secs_f64() * 1000.0 / runs as f64);
    println!("{report}");
}
