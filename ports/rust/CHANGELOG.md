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
- `ergo-sentences` reads any `$<name>` other than `$params` and `$input` as a start or a reference, so a line with an unknown name is read by the grammar and then listed as written wrong with `unknown name $<name>`, next to its other problems, as `ergo.rego` does. `Start` has a new variant, `Start::Unknown(String)`, and `Reference` has a new one, `Reference::Unknown { name, key }`, so a `match` on either that lists every variant needs an arm for them. `parse_check`, `parse_for` and `parse_from` accept a `$foo` they rejected, `parse_path` rejects a path that holds one, and `check_problems`, `for_problems` and `from_problems` list `unknown name $foo`. `check_problems` and `for_problems` also list `compared with itself` when every other problem is an unknown name.
