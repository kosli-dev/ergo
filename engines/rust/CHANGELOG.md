# Changes to the Rust engine

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](../../spec/CHANGELOG.md), and those of `ergo.rego` in [CHANGELOG.md](../../CHANGELOG.md).

## 0.1.0 (not released yet)

### New

- The first version of the Rust engine. It follows spec 0.3, so a policy says `ergo_spec: v0.3`, and it's experimental: anything in it may still change.
- `ergo-policy-sentences` reads check sentences, `for` lines, `from` lines and paths, without the engine.
- `ergo-policy-engine` builds the report and the violations from a policy, an input and params, as JSON.
- `ergo-policy-cli` is the `ergo` command, which prints the report or the violations from policy, input and params files in JSON or YAML.
- `ergo-policy-wasm` builds the report in a browser, from JSON text. It isn't published: it's built from the repository for the editor.
- `ergo-policy-sentences-wasm` reads check sentences in a browser, from and to JSON text. It isn't published either: it's built from the repository for the editor.
- A `for` item whose path goes on into a list item that isn't an object, `null` included, fails that item as `not_an_object`, as `every` and `some` do, where it failed as `unusable`.
