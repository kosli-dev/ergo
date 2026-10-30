# Ergo in Rust

**Experimental.** Nothing here is released, and every crate, function and output may change without notice. Use `ergo.rego` for real policies.

A second engine for Ergo, in Rust, that should give the same report as `ergo.rego` for every case in [`spec/cases`](../../spec/cases). It's in progress: see [#319](https://github.com/kosli-dev/ergo/issues/319).

It has five crates. The first three, `ergo-policy-sentences`, `ergo-policy-engine` and `ergo-policy-cli`, are published on crates.io from `rust-v*` tags, see [CONTRIBUTING.md](../../CONTRIBUTING.md#releases). The two Wasm crates are not published:

- `ergo-policy-sentences` (`sentences/`) reads check sentences, `for` lines, `from` lines and paths, and nothing else, so an editor or a linter can use it without the engine.
- `ergo-policy-engine` (`engine/`) builds the report, and reads sentences with `ergo-policy-sentences`.
- `ergo-policy-cli` (`cli/`) is the `ergo` command: it reads a policy, an input and params from JSON or YAML files and prints the report or the violations.
- `ergo-policy-wasm` (`wasm/`) wraps the engine for a browser: one function, `report`, that takes the input, the policy and the params as JSON text and gives the report back as JSON text.
- `ergo-policy-sentences-wasm` (`sentences-wasm/`) wraps `ergo-policy-sentences` for a browser: `parseCheck`, `parseFor`, `parseFrom` and `parsePath` give a tree or the syntax errors as JSON text, and there are functions for the problems and for printing a tree back.

## The cases

`engine/tests/cases.rs` builds the report for every case in `spec/cases` and compares it the way [`spec_test.rego`](../rego/spec_test.rego) does, as [`spec/README.md`](../../spec/README.md#cases) describes. It prints how many cases pass, like `1365 of 1365 cases pass`.

`known-failures.txt` lists the cases the engine fails, one per line, named like in [`spec_test.rego`](../rego/spec_test.rego): the folder, the group's description and the case's description, joined by ` / `. The test fails when a case fails that isn't listed, and when a listed case passes, so the list only shrinks. When a case starts passing, the test names it, and you delete its line.

## Running the checks

You don't need Rust installed, only Docker. From the root of the repo, build the image once:

```sh
docker build -t ergo-rust engines/rust
```

Then run the same checks as CI:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
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

The image is `rust:1.99.0`, the version in `rust-toolchain.toml`, with rustfmt, Clippy and the Wasm target added. `touch` is there because Cargo in Docker can miss an edit made outside the container, and then tests the old code.

The build goes to the `ergo-rust-target` volume and not to `engines/rust/target`, so the build stays out of your checkout. When several sessions or people run the checks at the same time, each should give the target volume their own name, like `ergo-rust-target-<name>`, because two builds sharing one volume can fail with "Permission denied". Change the `-v ergo-rust-target:/target` part of the command and keep the rest.

## Running from the command line

`ergo` reads the policy, the input and the params from files, each one `.json`, `.yaml` or `.yml`, and prints the report or the violations as JSON:

```sh
ergo report --policy policy.yaml --input deployments.json
ergo violations --policy policy.yaml --input deployments.json
```

To build it and run it with Docker, put the policy and the input from the [README](../../README.md#2-write-a-policy) in a folder, and run this from that folder, with `$REPO` set to the root of the repo:

```sh
docker run --rm -v "$REPO":/src -v "$PWD":/work -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build -j 4 --locked --release -p ergo-policy-cli &&
  cd /work &&
  /target/release/ergo violations --policy policy.yaml --input deployments.json'
```

`violations` prints:

```json
[
  {
    "cause": "absent",
    "check": "approved",
    "description": "Someone approved the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [
      {
        "locations": [
          "/deployments/1"
        ],
        "name": "approved_by",
        "value": null
      }
    ],
    "requirement": "prod_deploy",
    "subject": {
      "id": "d-2",
      "type": "deployment"
    }
  }
]
```

`--params <file>` gives the policy its params. The file holds the params themselves, like `limit: 9`, without a `params:` key around them, and without `--params` they are `{}`. The output has sorted keys and two-space indents, like `opa eval --format=pretty`, and `--compact` prints one line. `ergo --version` prints the version.

Without `--fail`, the command exits 0 whenever it printed the output, even when `compliant` is `false`. With `--fail` it still prints all of it, then exits with a code that says how the policy did, so a CI job can stop on it:

| Code | When                                                                                                    |
| ---- | ------------------------------------------------------------------------------------------------------- |
| 0    | The output was printed, and the policy is met or `--fail` isn't given.                                  |
| 1    | With `--fail`: a check failed. Input Ergo can't read, like a missing field, counts as a failed check.   |
| 2    | Nothing was printed: the command line is wrong, or a file can't be read or parsed.                      |
| 3    | With `--fail`: the policy is written wrong, so a `$well_formed` row failed. This wins over 1.           |

On 2 the command says why on one line of stderr.

YAML is read the way OPA reads it: `yes`, `no`, `on` and `off` are booleans, `010` is 8, `0x10` is 16, dates stay strings, `<<` merges, and only the first document counts. `ergo` also refuses most files OPA refuses, like one with a control character, a tag that doesn't fit its value like `!!int 1.5`, more than 10,000 levels of nesting, or too many aliases.

These differences are known:

- `ergo` keeps a number as it was written, and OPA turns it into a 64-bit float, so `1.10` stays `1.10` where OPA reads 1.1. Outside the range of a float this changes more than the digits: OPA reads `1e400` as the string `"1e400"` and `1e-400` as 0, and `ergo` reads both as the numbers written. So with `size: 1e400`, `size is at least 5` passes in `ergo` and fails in `ergo.rego`, and with `size: 1e-400`, `size is more than 0` does the same.
- `ergo` reads some malformed files that OPA refuses, so a check can pass on a file `ergo.rego` never reads. These are a line that starts with a tab, or a blank line holding one, a directive other than `%YAML` and `%TAG`, a file of only `...`, an escape YAML 1.1 doesn't have like `\/`, a plain key over two lines or longer than 1,024 characters, `{a` and `: 1}` on separate lines, `&x:` written without a space, and LS or PS used as a line break.
- `ergo` refuses some files OPA reads. These are a tab after a colon, a tag outside YAML's own, a verbatim tag, `!!merge`, UTF-16, a byte order mark inside a value, flow collections nested more than 255 levels, a quoted value whose next line starts with a tab, `*a: v` with no space before the colon, `%YAML 01.1`, and a `!!timestamp` with two spaces before the time.
- A few values differ: LS and PS inside quoted text, the U+FFFD characters for bad UTF-8 in a `!!binary`, and two keys that end up with the same name, like `1:` and `1.0:`, where OPA keeps one at random and `ergo` keeps the last.

## Building for a browser

The Markdown editor can run this engine in the page, so it needs `ergo-policy-wasm` built to Wasm and wrapped in JavaScript. This builds it into `engines/rust/wasm/pkg`, which Git ignores, and `packages/editor/build.mjs` reads it from there. That editor is in `packages/editor`. Run it with the image from above, from the root of the repo:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build --locked -j 4 --profile wasm -p ergo-policy-wasm --target wasm32-unknown-unknown &&
  wasm-bindgen --target web --out-dir wasm/pkg /target/wasm32-unknown-unknown/wasm/ergo_policy_wasm.wasm &&
  wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --enable-reference-types --enable-multivalue wasm/pkg/ergo_policy_wasm_bg.wasm -o wasm/pkg/ergo_policy_wasm_bg.wasm'
```

The `wasm` profile in `Cargo.toml` builds for size, and `wasm-opt` from [Binaryen](https://github.com/WebAssembly/binaryen) shrinks the result further. Together they take the Wasm file from about 2.9 MB to about 1.5 MB, and from about 840 KB to about 550 KB gzipped. Without `wasm-opt` the file is 1.6 MB, and a little smaller gzipped, at about 510 KB. The `release` profile stays as it was, because the other builds and the timings use it.

The `wasm-bindgen` tool has to be the same version as the `wasm-bindgen` crate, `=0.2.129` in `wasm/Cargo.toml`. The version is also in the `Dockerfile` and in the `tests-rust` job of `.github/workflows/test.yml`, so change all three together. The same goes for the Binaryen version, `version_133`, which is in the `Dockerfile` and in that job, together with the SHA-256 of each tarball. Both check the download against it before they unpack it.

`ergo-policy-sentences-wasm` builds the same way, with its own folder and no engine. It comes to about 740 KB, or 256 KB gzipped:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo build --locked -j 4 --profile wasm -p ergo-policy-sentences-wasm --target wasm32-unknown-unknown &&
  wasm-bindgen --target web --out-dir sentences-wasm/pkg /target/wasm32-unknown-unknown/wasm/ergo_policy_sentences_wasm.wasm &&
  wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --enable-reference-types --enable-multivalue sentences-wasm/pkg/ergo_policy_sentences_wasm_bg.wasm -o sentences-wasm/pkg/ergo_policy_sentences_wasm_bg.wasm'
```

CI loads it in Node with `sentences-wasm/check-node.mjs`, which reads one check sentence and fails when it doesn't give a tree.

CI also loads the built module in Node with `wasm/check-node.mjs`, which builds one report and fails when that throws or the report doesn't come from `ergo-policy-engine`. Run it with `node engines/rust/wasm/check-node.mjs` after the build.

The `wasm` profile aborts on a panic. In JavaScript that is a `WebAssembly.RuntimeError: unreachable` with no message about the cause, and the module's memory may be half way through a call, so don't call it again. Calling `initSync` or `init` again gives back the same instance, so load the module again, in a browser by reloading the page. Invalid JSON is not a panic: `report` throws an `Error` that says which of the three isn't JSON, and the module stays usable. An argument that isn't a string makes it throw a `TypeError` that names it, like `input must be a string, not number`.

## Timing it against `ergo.rego`

`bench/make_inputs.py <folder> [deployments]` writes an input with 1,000 deployments (or the number you give), a policy with three checks on the production ones, and the `data.json` and `bench.rego` that OPA needs. The policy's `ergo_spec` is the one `ergo.rego` follows. From the root of the repo:

```sh
python3 engines/rust/bench/make_inputs.py /tmp/ergo-bench
opa eval -d engines/rego/ergo.rego -d /tmp/ergo-bench/bench.rego -d /tmp/ergo-bench/data.json -i /tmp/ergo-bench/input-1000.json --metrics --format json 'data.bench.report' > /tmp/ergo-bench/opa.json
jq '.result[0].expressions[0].value' /tmp/ergo-bench/opa.json > /tmp/ergo-bench/rego.json
jq '.metrics.timer_rego_query_eval_ns / 1e9' /tmp/ergo-bench/opa.json
docker run --rm -v "$PWD":/src -v /tmp/ergo-bench:/bench -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust \
  cargo run -j 4 --locked --release -q --example report -- /bench/input-1000.json /bench/policy.json 5 > /tmp/ergo-bench/rust.json
python3 engines/rust/bench/compare.py /tmp/ergo-bench/rego.json /tmp/ergo-bench/rust.json
```

The `jq` line prints how many seconds OPA took. The `report` example builds the report the given number of times, here 5, prints the time per run on stderr and the report on stdout. It also takes a params file after the number of runs. `compare.py` fails when the two reports differ, apart from `engine`. It also fails when either file holds no report.
