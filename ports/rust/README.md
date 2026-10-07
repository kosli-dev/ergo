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

## Custom operators

A policy uses a custom operator like any other, by name. It doesn't say how the operator works:

```json
{"op": "min_length_at", "path": ["files"], "min_path": ["total_files"]}
```

Whoever runs the policy supplies the definitions, the way Cucumber is given step definitions that the feature files never mention:

```json
{
  "min_length_at": {
    "params": {"path": {"kind": "path", "type": "list"}, "min_path": {"kind": "path", "type": "number"}},
    "expression": "count({path}) >= {min_path}",
    "passes": "size(path) >= min_path"
  }
}
```

```rust
let operators = ergo::Operators::load(&definitions)?;
let report = ergo::report_with(&input, params, &requirements, &operators);
```

- A param's kind is `path`, `paths` (a list of paths), `value`, `number` or `string`. A `path` can say which `type` it must lead to: `list`, `number`, `string`, `object` or `boolean`. Any param can be `optional`, and an optional `value`, `number` or `string` can have a `default`.
- ergo reads the paths itself. A missing, `null` or wrong-typed one fails the check with cause `absent`, `null` or `unusable` before `passes` runs, so a definition doesn't need to guard against them. The row's `inputs` list the paths in param-name order, because JSON doesn't keep the order of an object's keys.
- `passes` is a [CEL](https://cel.dev) expression over the params, and nothing else. The check passes only when it gives `true`. Anything else, an error included, fails it, with cause `value` for `false` and `unusable` otherwise. ergo adds one function, `ergo.sum(list)`, because CEL has no way to add up a list.
- `expression` is how the check is written in the report, with `{param}` replaced by the path or value the policy gave. Without it, the check is written `min_length_at(files, total_files)`.
- A check that's missing a param, has one of the wrong kind, or has a field the definition doesn't list is written wrong, like a basic operator with the same mistake. Without definitions, the op is unknown.
- `Operators::load` refuses definitions that are written wrong, like a `passes` that isn't valid CEL or reads something that isn't a param, and says which.
- The report lists each custom operator it used under `operators`, with the SHA-256 of its definition and its `version` if it has one, so a report can be traced to the definitions behind it.
- A custom operator can go anywhere a basic operator can, inside `all`, `any` and `any_of` too.

`tests/operators.rs` has pr-reviewer's seven custom operators written this way. `ergo.rego` has nothing like it, so these tests aren't in the conformance suite:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry \
  -e CARGO_TARGET_DIR=/target -w /src/ports/rust rust:1 sh -c 'touch src/*.rs tests/*.rs && cargo test --test operators'
```

Docker on a Mac doesn't always tell Cargo that a file changed, which is why the command touches the sources first.
