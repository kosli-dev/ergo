# Changes to the Rust engine

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](../../spec/CHANGELOG.md), and those of `ergo.rego` in [CHANGELOG.md](../../CHANGELOG.md).

## 0.2.0 (not released yet)

### Changed

- The report's `engine` name is `ergo-rust`, where it was `ergo-policy-engine`, so it matches the Rego engine's `ergo-rego` and the `rust-v*` tag. Every report changes in that field only, and the hash leaves `engine` out, so hashes stay the same. The version is the same.
- The engine follows spec 0.4, so a policy says `ergo_spec: v0.4-dev` until the spec is released.
- An input that reads the item's own field named like a parent subject keeps its dot, like `.art.k`, as spec 0.4 says. A `from` that starts at the input with a `named by` step is written as it is in the `$min_subjects` and `$unique_ids` expressions, so `every $input named by $params.k` is no longer `count(matching(every [$params.k]))`. Reports change for such policies. The `from` a subject gets in `subjects` keeps every dot the policy wrote on the left of a `whose`, like `.art.k`, `.art.xs[0]` or a part's `.att.id`, where it dropped them.

## 0.1.0

### New

- The first version of the Rust engine. It follows spec 0.3, so a policy says `ergo_spec: v0.3`, and it's experimental: anything in it may still change.
- `ergo-policy-sentences` reads check sentences, `for` lines, `from` lines and paths, without the engine.
- `ergo-policy-engine` builds the report and the violations from a policy, an input and params, as JSON.
- `ergo-policy-cli` is the `ergo` command, which prints the report or the violations from policy, input and params files in JSON or YAML.
- `ergo-policy-wasm` builds the report in a browser, from JSON text. It isn't published: it's built from the repository for the editor.
- `ergo-policy-sentences-wasm` reads check sentences in a browser, from and to JSON text. It isn't published either: it's built from the repository for the editor.
- A `for` item whose path goes on into a list item that isn't an object, `null` included, fails that item as `not_an_object`, as `every` and `some` do, where it failed as `unusable`.
