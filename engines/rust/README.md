# Ergo in Rust

**Experimental.** Nothing here is released, and every crate, function and output may change without notice. Use `ergo.rego` for real policies.

A second engine for Ergo, in Rust, that should give the same report as `ergo.rego` for every case in [`spec/cases`](../../spec/cases). It's in progress: see [#319](https://github.com/kosli-dev/ergo/issues/319).

It has five crates. The first three, `ergo-policy-sentences`, `ergo-policy-engine` and `ergo-policy-cli`, are published on crates.io from `rust-v*` tags, see [CONTRIBUTING.md](../../CONTRIBUTING.md#releases). The two Wasm crates are not published:

- `ergo-policy-sentences` (`sentences/`) reads check sentences, `for` lines, `from` lines and paths, and nothing else, so an editor or a linter can use it without the engine.
- `ergo-policy-engine` (`engine/`) builds the report, and reads sentences with `ergo-policy-sentences`.
- `ergo-policy-cli` (`cli/`) is the `ergo` command: it reads a policy, an input and params from JSON or YAML files, or from standard input with `-`, and prints the report or the violations, as JSON or with `--format pretty` or `--format outcome` for a person. `ergo test` runs the examples a policy carries, and `--engine rego` builds the reports with `ergo.rego` through `opa`. [CLI.md](../../CLI.md) has the details.
- `ergo-policy-wasm` (`wasm/`) wraps the engine for a browser: one function, `report`, that takes the input, the policy and the params as JSON text and gives the report back as JSON text.
- `ergo-policy-sentences-wasm` (`sentences-wasm/`) wraps `ergo-policy-sentences` for a browser: `parseCheck`, `parseFor`, `parseFrom` and `parsePath` give a tree or the syntax errors as JSON text, and there are functions for the problems and for printing a tree back.

## The cases

`engine/tests/cases.rs` builds the report for every case in `spec/cases` and compares it the way [`spec_test.rego`](../rego/tests/spec_test.rego) does, as [`spec/README.md`](../../spec/README.md#cases) describes. It prints how many cases pass, like `1365 of 1365 cases pass`.

`known-failures.txt` lists the cases the engine fails, one per line, named like in [`spec_test.rego`](../rego/tests/spec_test.rego): the folder, the group's description and the case's description, joined by ` / `. The test fails when a case fails that isn't listed, and when a listed case passes, so the list only shrinks. When a case starts passing, the test names it, and you delete its line.

Most failing cases can't show whether a change moved a report, so the test can also write every report it builds: with `ERGO_DUMP` set to a folder, `cargo test -p ergo-policy-engine --test cases` writes the report of case `n` of a topic to `<folder>/<topic>/<n>.json`. Run it once before a change and once after, into two folders, and `.github/dump-diff.sh <before> <after>` prints each file that differs. A change that should keep every report prints nothing.

To get the numbers a pull request body needs, run `.github/pr-facts.sh [BASE]` (`origin/main` by default). It builds both dumps, with BASE in a temporary worktree and no Docker, and prints how many reports changed and which cases, which cases pass or fail now and did not before, and, first and in capitals, any case that passed on BASE and fails or is gone now. It pairs cases by their key, and follows a key that was reworded when the topic has the same number of cases on both sides, so it reads right when cases were added, removed or renamed.

`.github/dump-diff.sh` pairs files by case number, so use it when no cases were added or removed, and `.github/pr-facts.sh` when some were.

## Running the checks

You don't need Rust installed, only Docker. From the root of the repo, build the image once:

```sh
docker build -t ergo-rust engines/rust
```

Then run the same checks as CI:

```sh
docker run --rm -e ERGO_TEST_NO_OPA=1 -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo fmt --check &&
  cargo clippy -j 4 --locked --all-targets --all-features -- -D warnings &&
  cargo test -j 4 --locked --all-features -- --show-output &&
  RUSTDOCFLAGS="-D warnings" cargo doc -j 4 --locked --no-deps --all-features &&
  cargo test -j 4 --locked -p ergo-policy-engine --features serde_json/preserve_order --test key_order &&
  cargo build -j 4 --locked -p ergo-policy-sentences --target wasm32-unknown-unknown'
```

`ergo-policy-sentences` has an example, `sentences/examples/read.rs`, that reads `{"rows": [{"kinds": [...], "text": "..."}]}` on stdin and prints, for each row and kind (`check`, `for-line`, `from-line`), the `SyntaxError` messages of `parse_check`, `parse_for` or `parse_from`. `spec/check_grammar.py --rust <command>` runs it on the corpus, the cases and a few thousand generated sentences, and fails when Rust accepts a sentence that the ABNF rejects, or the reverse. CI builds it with `cargo build --locked --release -p ergo-policy-sentences --example read` and gives the script `engines/rust/target/release/examples/read`.

The second `cargo test` runs `tests/key_order.rs` again with serde_json's `preserve_order`, which keeps an object's keys in the order they were read. The report must stay byte for byte the same whatever order a policy, an input or params write their keys in, and if a dependency ever turned that feature on, `meta` and any object copied from the input would follow the order they were written in. The engine sorts every object in the report, and this run checks it does.

The image is `rust:1.99.0`, the version in `rust-toolchain.toml`, with rustfmt, Clippy and the Wasm target added. It has no `opa`, so `ERGO_TEST_NO_OPA=1` skips the CLI tests of `ergo test --engine rego`, which need `opa` and `dist/ergo.rego`. CI runs them, and so does a native `cargo test` with `opa` on the PATH after `.github/build-ergo.sh`. Without `ERGO_TEST_NO_OPA` those tests fail when `opa` or `dist/ergo.rego` is missing, and they never skip on their own. `touch` is there because Cargo in Docker can miss an edit made outside the container, and then tests the old code.

The build goes to the `ergo-rust-target` volume and not to `engines/rust/target`, so the build stays out of your checkout. When several sessions or people run the checks at the same time, each should give the target volume their own name, like `ergo-rust-target-<name>`, because two builds sharing one volume can fail with "Permission denied". Change the `-v ergo-rust-target:/target` part of the command and keep the rest.

## Mutation testing the changed lines

`cargo-mutants` changes the source one small way at a time, like returning `true` where a function returned a condition, and runs the tests on each change. A change no test notices is a missed mutant, which points at a line the tests don't pin down. `.github/mutants-facts.sh BASE` runs it only on the lines of Rust source that `git diff BASE...HEAD` changes, and prints how many mutants were caught, missed, unviable or timed out, and the missed ones. It runs in your checkout, because the engine tests read `spec/cases`, and `cargo-mutants` puts each file back after it mutates it. When `engines/rust` has no uncommitted changes at the start, the script also runs `git checkout -- engines/rust` when it ends or is stopped, so a killed `cargo-mutants` leaves nothing mutated. When it has some, the script warns and restores nothing. It stops after `MUTANTS_FACTS_TIMEOUT` seconds (900 by default), says so, and counts the mutants that ran. It only informs, and the `mutants-facts` job writes it in the summary of a pull request.

```sh
cargo install cargo-mutants --locked
.github/mutants-facts.sh origin/main
```

## Building the CLI

`ergo` is documented in [CLI.md](../../CLI.md): how to install it, how to run it, its exit codes and how it reads YAML. This section builds it from the repo.

To build it and run it with Docker, put the policy and the input from the [README](../../README.md#a-first-policy) in a folder, and run this from that folder, with `$REPO` set to the root of the repo:

```sh
docker run --rm -v "$REPO":/src -v "$PWD":/work -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build -j 4 --locked --release -p ergo-policy-cli &&
  cd /work &&
  /target/release/ergo violations --policy policy.yaml --input deployments.json'
```

`violations` prints what the [README](../../README.md#violations) shows.

## Building for a browser

The Markdown playground can run this engine in the page, so it needs `ergo-policy-wasm` built to Wasm and wrapped in JavaScript. This builds it into `engines/rust/wasm/pkg`, which Git ignores, and `packages/playground/build.mjs` reads it from there. The playground is in `packages/playground`. Run it with the image from above, from the root of the repo:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build --locked -j 4 --profile wasm -p ergo-policy-wasm --target wasm32-unknown-unknown &&
  wasm-bindgen --target web --out-dir wasm/pkg /target/wasm32-unknown-unknown/wasm/ergo_policy_wasm.wasm &&
  wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --enable-reference-types --enable-multivalue wasm/pkg/ergo_policy_wasm_bg.wasm -o wasm/pkg/ergo_policy_wasm_bg.wasm'
```

The `wasm` profile in `Cargo.toml` builds for size, and `wasm-opt` from [Binaryen](https://github.com/WebAssembly/binaryen) shrinks the result further. Together they take the Wasm file from about 2.9 MB to about 1.5 MB, and from about 840 KB to about 550 KB gzipped. Without `wasm-opt` the file is 1.6 MB, and a little smaller gzipped, at about 510 KB. The `release` profile stays as it was, because the other builds and the timings use it.

The `wasm-bindgen` tool has to be the same version as the `wasm-bindgen` crate, `=0.2.130` in `wasm/Cargo.toml`. The version is also in the `Dockerfile` and in the `tests-rust` job of `.github/workflows/test.yml`, so change all three together. The same goes for the Binaryen version, `version_133`, which is in the `Dockerfile` and in that job, together with the SHA-256 of each tarball. Both check the download against it before they unpack it.

`ergo-policy-sentences-wasm` builds the same way, with its own folder and no engine. It comes to about 740 KB, or 256 KB gzipped:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build --locked -j 4 --profile wasm -p ergo-policy-sentences-wasm --target wasm32-unknown-unknown &&
  wasm-bindgen --target web --out-dir sentences-wasm/pkg /target/wasm32-unknown-unknown/wasm/ergo_policy_sentences_wasm.wasm &&
  wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --enable-reference-types --enable-multivalue sentences-wasm/pkg/ergo_policy_sentences_wasm_bg.wasm -o sentences-wasm/pkg/ergo_policy_sentences_wasm_bg.wasm'
```

CI loads it in Node with `sentences-wasm/check-node.mjs`, which reads one check sentence and fails when it doesn't give a tree.

CI also loads the built module in Node with `wasm/check-node.mjs`, which builds one report and fails when that throws or the report doesn't come from `ergo-rust`. Run it with `node engines/rust/wasm/check-node.mjs` after the build.

The `wasm` profile aborts on a panic. In JavaScript that is a `WebAssembly.RuntimeError: unreachable` with no message about the cause, and the module's memory may be half way through a call, so don't call it again. Calling `initSync` or `init` again gives back the same instance, so load the module again, in a browser by reloading the page. Invalid JSON is not a panic: `report` throws an `Error` that says which of the three isn't JSON, and the module stays usable. An argument that isn't a string makes it throw a `TypeError` that names it, like `input must be a string, not number`.

## Timing it against `ergo.rego`

`bench/make_inputs.py <folder> [deployments]` writes an input with 1,000 deployments (or the number you give), a policy with three checks on the production ones, and the `data.json` and `bench.rego` that OPA needs. The policy's `ergo_spec` is the one `ergo.rego` follows. From the root of the repo:

```sh
python3 engines/rust/bench/make_inputs.py /tmp/ergo-bench
.github/build-ergo.sh
opa eval -d dist/ergo.rego -d /tmp/ergo-bench/bench.rego -d /tmp/ergo-bench/data.json -i /tmp/ergo-bench/input-1000.json --metrics --format json 'data.bench.report' > /tmp/ergo-bench/opa.json
jq '.result[0].expressions[0].value' /tmp/ergo-bench/opa.json > /tmp/ergo-bench/rego.json
jq '.metrics.timer_rego_query_eval_ns / 1e9' /tmp/ergo-bench/opa.json
docker run --rm -v "$PWD":/src -v /tmp/ergo-bench:/bench -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust \
  cargo run -j 4 --locked --release -q --example report -- /bench/input-1000.json /bench/policy.json 5 > /tmp/ergo-bench/rust.json
python3 engines/rust/bench/compare.py /tmp/ergo-bench/rego.json /tmp/ergo-bench/rust.json
```

The `jq` line prints how many seconds OPA took. The `report` example builds the report the given number of times, here 5, prints the time per run on stderr and the report on stdout. It also takes a params file after the number of runs. `compare.py` fails when the two reports differ, apart from `engine`. It also fails when either file holds no report.
