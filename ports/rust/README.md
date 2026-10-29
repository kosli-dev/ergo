# Ergo in Rust

**Experimental.** Nothing here is released, and every crate, function and output may change without notice. Use `ergo.rego` for real policies.

A second engine for Ergo, in Rust, that should give the same report as `ergo.rego` for every case in [`spec/cases`](../../spec/cases). It's in progress: see [#319](https://github.com/kosli-dev/ergo/issues/319).

It has four crates:

- `ergo-sentences` (`sentences/`) reads check sentences, `for` lines, `from` lines and paths, and nothing else, so an editor or a linter can use it without the engine.
- `ergo-engine` (`engine/`) builds the report, and reads sentences with `ergo-sentences`.
- `ergo-wasm` (`wasm/`) wraps the engine for a browser: one function, `report`, that takes the input, the policy and the params as JSON text and gives the report back as JSON text.
- `ergo-sentences-wasm` (`sentences-wasm/`) wraps `ergo-sentences` for a browser: `parse_check`, `parse_for`, `parse_from` and `parse_path` give a tree or the syntax errors as JSON text, and there are functions for the problems and for printing a tree back.

## The cases

`engine/tests/cases.rs` builds the report for every case in `spec/cases` and compares it the way `spec_test.rego` does, as [`spec/README.md`](../../spec/README.md#cases) describes. It prints how many cases pass, like `1365 of 1365 cases pass`.

`known-failures.txt` lists the cases the engine fails, one per line, named like in `spec_test.rego`: the folder, the group's description and the case's description, joined by ` / `. The test fails when a case fails that isn't listed, and when a listed case passes, so the list only shrinks. When a case starts passing, the test names it, and you delete its line.

## Running the checks

You don't need Rust installed, only Docker. From the root of the repo, build the image once:

```sh
docker build -t ergo-rust ports/rust
```

Then run the same checks as CI:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo fmt --check &&
  cargo clippy -j 4 --locked --all-targets --all-features -- -D warnings &&
  cargo test -j 4 --locked --all-features -- --show-output &&
  RUSTDOCFLAGS="-D warnings" cargo doc -j 4 --locked --no-deps --all-features &&
  cargo test -j 4 --locked -p ergo-engine --features serde_json/preserve_order --test key_order &&
  cargo build -j 4 --locked -p ergo-sentences --target wasm32-unknown-unknown'
```

`ergo-sentences` has an example, `sentences/examples/read.rs`, that reads `{"rows": [{"kinds": [...], "text": "..."}]}` on stdin and prints, for each row and kind (`check`, `for-line`, `from-line`), the `SyntaxError` messages of `parse_check`, `parse_for` or `parse_from`. `spec/check_grammar.py --rust <command>` runs it on the corpus, the cases and a few thousand generated sentences, and fails when Rust accepts a sentence that the ABNF rejects, or the reverse. CI builds it with `cargo build --locked --release -p ergo-sentences --example read` and gives the script `ports/rust/target/release/examples/read`.

The second `cargo test` runs `tests/key_order.rs` again with serde_json's `preserve_order`, which keeps an object's keys in the order they were read. The report must stay byte for byte the same whatever order a policy, an input or params write their keys in, and if a dependency ever turned that feature on, `meta` and any object copied from the input would follow the order they were written in. The engine sorts every object in the report, and this run checks it does.

The image is `rust:1.99.0`, the version in `rust-toolchain.toml`, with rustfmt, Clippy and the Wasm target added. `touch` is there because Cargo in Docker can miss an edit made outside the container, and then tests the old code.

The build goes to the `ergo-rust-target` volume and not to `ports/rust/target`, because Cargo writes JSON files there and `opa test .` would load them as data. When several sessions or people run the checks at the same time, each should give the target volume their own name, like `ergo-rust-target-<name>`, because two builds sharing one volume can fail with "Permission denied". Change the `-v ergo-rust-target:/target` part of the command and keep the rest.

## Building for a browser

The Markdown editor can run this engine in the page, so it needs `ergo-wasm` built to Wasm and wrapped in JavaScript. This builds it into `ports/rust/wasm/pkg`, which Git ignores, and `packages/editor/build.mjs` reads it from there. That editor is on the `markdown/sentences` branch for now. Run it with the image from above, from the root of the repo:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build --locked -j 4 --profile wasm -p ergo-wasm --target wasm32-unknown-unknown &&
  wasm-bindgen --target web --out-dir wasm/pkg /target/wasm32-unknown-unknown/wasm/ergo_wasm.wasm &&
  wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --enable-reference-types --enable-multivalue wasm/pkg/ergo_wasm_bg.wasm -o wasm/pkg/ergo_wasm_bg.wasm'
```

The `wasm` profile in `Cargo.toml` builds for size, and `wasm-opt` from [Binaryen](https://github.com/WebAssembly/binaryen) shrinks the result further. Together they take the Wasm file from about 2.9 MB to about 1.5 MB, and from about 840 KB to about 550 KB gzipped. Without `wasm-opt` the file is 1.6 MB, and a little smaller gzipped, at about 510 KB. The `release` profile stays as it was, because the other builds and the timings use it.

The `wasm-bindgen` tool has to be the same version as the `wasm-bindgen` crate, `=0.2.129` in `wasm/Cargo.toml`. The version is also in the `Dockerfile` and in the `tests-rust` job of `.github/workflows/test.yml`, so change all three together. The same goes for the Binaryen version, `version_133`, which is in the `Dockerfile` and in that job, together with the SHA-256 of each tarball. Both check the download against it before they unpack it.

`ergo-sentences-wasm` builds the same way, with its own folder and no engine. It comes to about 740 KB, or 256 KB gzipped:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build --locked -j 4 --profile wasm -p ergo-sentences-wasm --target wasm32-unknown-unknown &&
  wasm-bindgen --target web --out-dir sentences-wasm/pkg /target/wasm32-unknown-unknown/wasm/ergo_sentences_wasm.wasm &&
  wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --enable-reference-types --enable-multivalue sentences-wasm/pkg/ergo_sentences_wasm_bg.wasm -o sentences-wasm/pkg/ergo_sentences_wasm_bg.wasm'
```

CI loads it in Node with `sentences-wasm/check-node.mjs`, which reads one check sentence and fails when it doesn't give a tree.

CI also loads the built module in Node with `wasm/check-node.mjs`, which builds one report and fails when that throws or the report doesn't come from `ergo-engine`. Run it with `node ports/rust/wasm/check-node.mjs` after the build.

The `wasm` profile aborts on a panic. In JavaScript that is a `WebAssembly.RuntimeError: unreachable` with no message about the cause, and the module's memory may be half way through a call, so don't call it again. Make a new instance with `initSync` or `init` instead. Invalid JSON is not a panic: `report` throws an `Error` that says which of the three isn't JSON, and the module stays usable. An argument that isn't a string makes it throw a `TypeError` that names it, like `input must be a string, not number`.

## Timing it against `ergo.rego`

`bench/make_inputs.py <folder> [deployments]` writes an input with 1,000 deployments (or the number you give), a policy with three checks on the production ones, and the `data.json` and `bench.rego` that OPA needs. The policy's `ergo_spec` is the one `ergo.rego` follows. From the root of the repo:

```sh
python3 ports/rust/bench/make_inputs.py /tmp/ergo-bench
opa eval -d ergo.rego -d /tmp/ergo-bench/bench.rego -d /tmp/ergo-bench/data.json -i /tmp/ergo-bench/input-1000.json --metrics --format json 'data.bench.report' > /tmp/ergo-bench/opa.json
jq '.result[0].expressions[0].value' /tmp/ergo-bench/opa.json > /tmp/ergo-bench/rego.json
jq '.metrics.timer_rego_query_eval_ns / 1e9' /tmp/ergo-bench/opa.json
docker run --rm -v "$PWD":/src -v /tmp/ergo-bench:/bench -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust \
  cargo run -j 4 --locked --release -q --example report -- /bench/input-1000.json /bench/policy.json 5 > /tmp/ergo-bench/rust.json
python3 ports/rust/bench/compare.py /tmp/ergo-bench/rego.json /tmp/ergo-bench/rust.json
```

The `jq` line prints how many seconds OPA took. The `report` example builds the report the given number of times, here 5, prints the time per run on stderr and the report on stdout. It also takes a params file after the number of runs. `compare.py` fails when the two reports differ, apart from `engine`. It also fails when either file holds no report.
