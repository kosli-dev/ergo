# ergo in Rust

An experiment: ergo written in Rust and checked against the [conformance suite](../../conformance/README.md). So far it knows `equals`, `present`, `all`, `any` and `applies_to`. A requirement that uses anything else fails `$well_formed`, so it never passes by accident.

Run the suite with Docker, so you don't need Rust installed:

```sh
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry \
  -e CARGO_TARGET_DIR=/target -w /src/ports/rust rust:1 cargo test --test conformance -- --nocapture
```

Run it from the root of the repo. Keep the build in `/target` and out of `ports/rust/target`, because Cargo writes JSON files there and `opa test .` would load them as data.

What it doesn't do yet: the other operators, `each`, `as` and nested `all` or `any`, `any_of`, substitutes, selectors and naming steps, custom operators, and the details `$well_formed` gives when a requirement is written wrong.
