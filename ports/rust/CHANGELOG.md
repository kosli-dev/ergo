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
- `ergo-sentences` reads any `$<name>` other than `$params` and `$input` as a start or a reference, so a line with an unknown name is read by the grammar and then listed as written wrong with `unknown name $<name>`, next to its other problems, as `ergo.rego` does. `Start` has a new variant, `Start::Unknown(String)`, and `Reference` has a new one, `Reference::Unknown { name, key }`, so a `match` on either that lists every variant needs an arm for them. `parse_check`, `parse_for` and `parse_from` accept a `$foo` they rejected, `parse_path` rejects a path that holds one, and `check_problems`, `for_problems` and `from_problems` list `unknown name $foo`. `check_problems` and `for_problems` also list `compared with itself` when every other problem is an unknown name.

### Fixed

- A child read through a part of a subject whose name has a `$`, like `"$x".pa.items`, writes that name quoted in its `from` and in the `$min_subjects` and `$unique_ids` expressions, as `ergo.rego` does. It was written `$x.pa.items`.
- A subject definition with `identified_by` whose `from` uses `named by each of` is written wrong, with `not allowed with named by each of: the key is the id` under `subjects.<name>.identified_by`, as in `ergo.rego`. An `identified_by` that is not a string lists both problems.
- A `first of p` or `item 2 of p` after a subject's name is read as a child subject, like `p[1]`, where it was read as an input field called `p`. A subject with `every` whose `named by` reads a param that can't be read lists `failed_items: []` on its `$min_subjects` row, as `ergo.rego` does.
- A position after a keyed parent's name, like `p[0]` with `p` from `m named by each of $params.ks`, fails as `absent` when the object lacks the key, where it failed as `unusable`.
- A `count of` or `sum of` on the right of a `whose` reads a `for` alias and a part's alias, not the item's field of the same name. With `for: every groups as g`, the sentence `every rows.v whose n is count of g is 1` and `{"things": [{"id": "a", "groups": [[1, 1]], "rows": [{"n": 2, "v": 1, "g": [5, 5, 5, 5, 5]}, {"n": 5, "v": 9, "g": [5, 5, 5, 5, 5]}]}]}`, it counted each row's own `g` (5), kept the row with `n` 5 and failed as `value`. It now counts the group `g` (2), keeps the row with `n` 2 and is satisfied. With a part `x: "p"`, `every xs.v whose n is count of x.z is 1` on `{"things": [{"id": "a", "p": {"z": [1]}, "xs": [{"n": 1, "v": 1, "x": {"z": [1, 1, 1]}}, {"n": 3, "v": 5, "x": {"z": [1, 1, 1]}}]}]}` was `value` and is now satisfied, with an `x.z` entry tagged with the part.
- A `count of` or `sum of` entry has the part's tag when its list starts at the part. With a part `pa: "pa"`, `count of pa.items whose w is pa.w is 1` listed `{"name": "count of pa.items whose w equals pa.w", "value": 1, ...}` with no `part`, and now has `"part": {"id": null, "name": "pa"}`, as the list entry below it did.
- A parent subject's name on the right of a `whose` inside a `count of` or `sum of` reads the parent, as `ergo.rego` does.
- A failed `for` line sentence like `count of items whose w is pa.w is 5` listed `pa.w`, a part, in the row's `inputs` with `value: null` and no locations. It now lists the value and its location, as `ergo.rego` does.
- `from: $input` makes a subject of each item when the whole input is a list, as a `from` path that ends on a list does. It failed `$min_subjects` as `unusable`, and on an empty list it now fails as `value`.
- `failed_items` and expressions name a place in the input from `$input`, like `$input[1].commits` or `item 1 of $input`, as in `ergo.rego`. When `every` breaks on the input itself, `failed_items` names it `$input`.
