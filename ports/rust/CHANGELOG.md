# Changes to the Rust engine

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](../../spec/CHANGELOG.md), and those of `ergo.rego` in [CHANGELOG.md](../../CHANGELOG.md).

## 0.1.0 (not released yet)

### New

- The first version of the Rust engine. It follows spec 0.3, so a policy says `ergo_spec: v0.3`, and it's experimental: anything in it may still change.
- `ergo-sentences` reads check sentences, `for` lines, `from` lines and paths, without the engine.
- `ergo-engine` builds the report and the violations from a policy, an input and params, as JSON.
- `ergo-cli` is the `ergo` command, which prints the report or the violations from policy, input and params files in JSON or YAML.
- `ergo-wasm` builds the report in a browser, from JSON text.
- `ergo-sentences-wasm` reads check sentences in a browser, from and to JSON text.
- A `for` item whose path goes on into a list item that isn't an object, `null` included, fails that item as `not_an_object`, as `every` and `some` do, where it failed as `unusable`.
- A check written wrong lists `values of mixed types` with every other problem it has, a field compared with itself included, also in a `whose`, and every problem of a `for` line starts with `for: `. `ergo-sentences` gives `check_self_problems`, the problems that come from comparing a field with itself.
