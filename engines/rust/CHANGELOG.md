# Changes to the Rust engine

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](../../spec/CHANGELOG.md), and those of `ergo.rego` in [CHANGELOG.md](../../CHANGELOG.md).

## 0.2.0 (not released yet)

### New

- Every phrase that lacked an opposite has one, as spec 0.4 says: `does not start with`, `does not end with`, `is not a <type>`, `is not a non-empty string`, `is not between`, `is not <value> within <number>`, `does not equal <field> within <number>`, `contains some of` and `does not contain all of`, plus `is alphabetically on or before` and `is alphabetically on or after`. The sentence reader's `Phrase` has the variants `NotStartsWith`, `NotEndsWith`, `NotType`, `NotNonEmptyString`, `ContainsSome` and `NotContainsAll`, `Between` has a `not` field and `Alphabetically` an `or_equal` field. A count, a sum, a plus or an elapsed time can now be followed by `is not ... within` too, which the engine refused before.
- Text can be joined on the right side with `followed by`, as spec 0.4 says: `rego.version is tag.version followed by "-dev"`. The sentence reader's `Operand` has a new variant `Joined`, with the pieces in order, and `compare` and `contains` read it.

### Changed

- A path that names its key by a field lists the field in a row's `inputs` for a `count of`, a `sum of`, an `every` and a `some` too, right after the list's entry, and the check of a `for` line keeps its whole path, `m named by p` and then `p`, where it showed only `m`, as spec 0.4 says. When the path before the field can't be read, an `every` or `some` fails with that path's cause, not the field's, so `every zz.x named by p is 1` with `zz` missing or a string is `absent` or `unusable` when `p` is `null`, where it was `null`. A list it walks before the field doesn't count, so `every rows.w named by k is "xy"` still fails as `null` when `k` is `null`. With `rows` `null` it fails as `null` whatever `k` holds, where a missing or number `k` gave `absent` or `unusable`, and `failed_items` names `rows`, where it was empty when `k` couldn't be read. A `for` line whose own path has such a field, like `every rows.w named by p as w`, lists `p` too, sorted with the rest by name, as `ergo.rego` does. A `plus` or an elapsed time that reads such a path no longer has the field's location in its own entry, as spec 0.4 says. Reports change for such policies.
- The report's `engine` name is `ergo-rust`, where it was `ergo-policy-engine`, so it matches the Rego engine's `ergo-rego` and the `rust-v*` tag. Every report changes in that field only, and the hash leaves `engine` out, so hashes stay the same. The version is the same.
- The engine follows spec 0.4, so a policy says `ergo_spec: v0.4-dev` until the spec is released.
- An empty name, `""`, is written wrong too, whether it names a requirement, a check, an `any_of` option or a part, with `a name can't be empty`.
- The CLI has its own page, [`CLI.md`](../../CLI.md): install, how to run it, its exit codes and how it reads YAML. They were in the README and in this folder's README.
- The `$well_formed` row lists the problems of fields, parts and checks sorted by name as the report writes it, quotes and escapes included, by code point, where the quotes were left out, and lists the requirement's own fields first, then the subject's, then the checks. Reports change for names that need quoting and for a requirement with both a field and a subject problem.
- An own field named like a part of the subject or like a `for` alias keeps its dot in the name of an input, like `.cov.pct`, and so does the list a `count of`, `sum of` or a walk reads, like `.art.xs[]`. A policy written wrong keeps the dots it was written with in the expression and in `from`: a check whose `for` isn't a string, and a part named like one of its parent's.
- An input that reads the item's own field named like a parent subject keeps its dot, like `.art.k`, as spec 0.4 says. A `from` that starts at the input with a `named by` step is written as it is in the `$min_subjects` and `$unique_ids` expressions, so `every $input named by $params.k` is no longer `count(matching(every [$params.k]))`. Reports change for such policies. The `from` a subject gets in `subjects` keeps every dot the policy wrote on the left of a `whose`, like `.art.k`, `.art.xs[0]` or a part's `.att.id`, where it dropped them.
- A policy with no requirement, because `requirements` is missing, `null`, not an object or empty, gets Ergo's own requirement `$policy` with a failing `$well_formed` row that says what is wrong, as spec 0.4 says, where the report had no row and `violations` was empty while `compliant` was `false`. A requirement called `$policy` is written wrong. Reports change for such policies.
- A name that starts with `$` is written wrong, whether it names a subject, a requirement, a check, an `any_of` option or a part, with `a name can't start with $`, as spec 0.4 says, in place of `name reserved`, `a subject can't be named $input` and `invalid alias` for a part called `$dollar`. A check with such a name has no entry in `requirements`. Reports change for such policies.
- A name that starts or ends with a space or an invisible character (Unicode White_Space or general category Cf, like U+200B or U+FEFF) is written wrong too, with `a name can't start or end with a space or an invisible character`, as spec 0.4 says, for a subject, a requirement, a check, an `any_of` option and a part. Reports change for such policies.
- A key read from `$params` or `$input`, after `named by` or in brackets, has to be a string, as spec 0.4 says. A whole number used to read that item of a list, so `m named by $input.k is 1` with `k` holding `1` and `m` holding `[5, 1]` passed by reading `1`, and `commits[$params.n]` read a commit. It fails as `unusable` now, and a `from` line with such a key gives no subjects. Reports change for such policies.

### Fixed

- A check could pass when it should fail. A path named by a `for` alias that holds a number read the number as a list position, so `m named by k is 1` under `every ks as k` passed on `{"ks": [1], "m": [5, 1]}`, by reading `m[1]`. So did a later item, `every ks as k, every m named by k as x`, and a one-line `every` or `some` under the `for` line. A `for` alias that holds anything but a string now fails as `unusable`, as [for.named_by](../../spec/semantics.md#for) says, and as `ergo.rego` does. When the path before it is an object, the failed item is named `m named by k`, where it was `item 4 of m` for a `3`. A number from `$params` or `$input` is still a position. Reports change for such policies: some that passed now fail.

## 0.1.0

### New

- The first version of the Rust engine. It follows spec 0.3, so a policy says `ergo_spec: v0.3`, and it's experimental: anything in it may still change.
- `ergo-policy-sentences` reads check sentences, `for` lines, `from` lines and paths, without the engine.
- `ergo-policy-engine` builds the report and the violations from a policy, an input and params, as JSON.
- `ergo-policy-cli` is the `ergo` command, which prints the report or the violations from policy, input and params files in JSON or YAML.
- `ergo-policy-wasm` builds the report in a browser, from JSON text. It isn't published: it's built from the repository for the editor.
- `ergo-policy-sentences-wasm` reads check sentences in a browser, from and to JSON text. It isn't published either: it's built from the repository for the editor.
- A `for` item whose path goes on into a list item that isn't an object, `null` included, fails that item as `not_an_object`, as `every` and `some` do, where it failed as `unusable`.
