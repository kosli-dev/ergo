# ergo in Rust

An experiment: ergo written in Rust and checked against the [conformance suite](../../conformance/README.md). It passes 1,682 of the 1,683 cases. The one it fails has a wrong expected report, because OPA 1.19 compares some numbers wrongly (see [FINDINGS.md](../../conformance/FINDINGS.md)).

Run the suite with Docker, so you don't need Rust installed:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry \
  -e CARGO_TARGET_DIR=/target -w /src/ports/rust rust:1 cargo test --test conformance -- --nocapture
```

To time a report, `examples/report.rs` takes an input file, a requirements file and a number of runs, prints the report and says how long a run took:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry \
  -e CARGO_TARGET_DIR=/target -w /src/ports/rust rust:1 cargo run --release -q --example report -- input.json requirements.json 5
```

`bench/make_inputs.py <folder>` writes the inputs and requirements used to compare it with `ergo.rego`, 1,000 and 10,000 deployments, along with a `data.json` and `bench.rego` for OPA:

```sh
opa eval -d ergo.rego -d <folder>/bench.rego -d <folder>/data.json -i <folder>/input-1000.json --metrics 'count(data.bench.report.results)'
```

On 7 October 2026 both gave the same reports. OPA 1.19 took 0.9 s and 8.5 s to evaluate them, and the Rust port 12.5 ms and 200 ms.

Run the Docker commands from the root of the repo. Keep the build in `/target` and out of `ports/rust/target`, because Cargo writes JSON files there and `opa test .` would load them as data.

What it doesn't do: custom operators, which only exist in Rego for now.
