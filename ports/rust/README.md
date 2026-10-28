# Ergo in Rust

A second engine for Ergo, in Rust, that should give the same report as `ergo.rego` for every case in [`spec/cases`](../../spec/cases). It's in progress: see [#319](https://github.com/kosli-dev/ergo/issues/319).

It has two crates:

- `ergo-sentences` (`sentences/`) reads check sentences, `for` lines, `from` lines and paths, and nothing else, so an editor or a linter can use it without the engine.
- `ergo-engine` (`engine/`) builds the report, and reads sentences with `ergo-sentences`.

## The cases

`engine/tests/cases.rs` builds the report for every case in `spec/cases` and compares it the way `spec_test.rego` does, as [`spec/README.md`](../../spec/README.md#cases) describes. It prints how many cases pass, like `0 of 1328 cases pass`.

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
  cargo clippy -j 4 --all-targets -- -D warnings &&
  cargo test -j 4 -- --show-output &&
  cargo build -j 4 -p ergo-sentences --target wasm32-unknown-unknown'
```

The image is `rust:1.99.0`, the version in `rust-toolchain.toml`, with rustfmt, Clippy and the Wasm target added. `touch` is there because Cargo in Docker can miss an edit made outside the container, and then tests the old code.

The build goes to the `ergo-rust-target` volume and not to `ports/rust/target`, because Cargo writes JSON files there and `opa test .` would load them as data.
