# Fixes after the review of #701

## Finding 1: a later condition's problem was dropped

`_m_undecided_before` kept only the first condition of a `whose` that an item couldn't decide. It is gone. A `count of` or `sum of` now says each condition the item can't decide, in the order the sentence reads them, and the item keeps one entry in `failures` whose message joins them with `; `.

Probes after the fix, on the Rego branch, Rego `main` and the Rust branch:

- `count of es whose v is 1 and whose w is 1 is 0`, `es` `[{}]`: all three say `item 1 of es: v is missing; item 1 of es: w is missing`.
- `count of es whose v is 1 and whose zz is m named by $params.j is 0`, params `{"j": 3}`, `es` `[{"zz": 2}]`: the Rego branch and the Rust engine say `item 1 of es: v is missing; item 1 of es: $params.j is 3, which isn't text`, and `main` says only the key.
- The same with `{"j": "a"}`: all three say `item 1 of es: v is missing; item 1 of es: m named by $params.j is missing`.
- Finding 1, `count of es whose zz is m named by $params.k and whose v is m named by $params.j is 0`, params `{"k": "a", "j": 3}`, `es` `[{"zz": 2, "v": 2}]`: the Rego branch says `item 1 of es: m named by $params.k is missing; item 1 of es: $params.j is 3, which isn't text`, and `main` and the Rust engine say only `item 1 of es: $params.j is 3, which isn't text`.
- The same with both keys read from `$input`: the same shapes as from `$params`.

All rows fail with the same cause in the three engines. In finding 1 the Rego engine now says both problems and the Rust engine only the key.

Left as they are:

- `every es whose v is 1 and whose w is 1, if any, exists` and the `some` form say only the first condition, in both engines and on `main`, where `count of` says each. The `every` and `for` rows of `messages` "two roots in one relative clause that can't be read" show it.
- With `$params.j` `null` the Rego engine says `$params.j is null; item 1 of es: m named by $params.k is missing; item 1 of es: the check is false` (`main` says the same without the key), and the Rust engine says only `item 1 of es: m named by $params.k is missing`.
- With no `j` in the params, the Rust engine also says `item 1 of es: $params.j is missing` after the item.

New cases, both in `known-failures.txt` because the Rust engine lists the item's reads differently (D9):

- `walks / a whose key from $params that isn't text, read by a later condition than one an item can't decide, is said after that condition's problem / an item without v says that v is missing and then the key`
- `walks / two whose keys from $params, the second one not text, beside an item that fails the first condition, say both problems / an item without m says that m named by the first key is missing and then the second key`

## Finding 3: reads that worked, marked absent or null

Found with a script over `spec/cases`: an `item` entry with an input that holds a value but has the outcome `absent` or `null`. All 13 cases of the review are pinned to today's Rego output, none fixed. Added to "Left for a later PR" in `spec/OPEN.md`:

- `list_items / a name read from outside the item and walked on the right of is in is said once, with no item / an item without the name fails as absent and is said once`
- `list_items / a name read from outside the item and walked on the right of is in is said once, with no item / an item whose name is null fails as null and is said once`
- `list_items / a name of a subject that is a list, walked on the right of is in, is said once / an item without the name fails as absent and is said once`
- `list_items / a name of a subject that is a list, walked on the right of is in, is said once / an item whose name is null fails as null and is said once`
- `list_items / a part that holds a list, walked after matches in a whose, is said once / an item without the name fails as absent and is said once`
- `list_items / a part that holds a list, walked after matches in a whose, is said once / an item whose name is null fails as null and is said once`
- `list_items / a parent's name with a list in the middle, read on the right of a list phrase, is listed as a plain check lists it / each item's value is listed, and null at an item with no name`
- `list_items / a parent's name with a list in the middle, read on the right of a list phrase, is listed as a plain check lists it / an item whose name is null is listed as null, at the name`
- `list_items / a part whose own path has a list in the middle, read on the right of a list phrase, is named from the subject / an item with no names fails as absent, and the message names the list as a plain check does`
- `list_starts / a subject that is a list, read on the right of the phrase after every, isn't said to be anything but a list / an item with no names fails as absent`
- `walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name, with a null param / an item of $input.os has no name and $params.z is null`

Already listed, under "A list in the middle of a name, or a subject that is a list":

- `list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item with no name is listed as null, at the item`
- `list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item whose name is null is listed as null, at the name`

The Rust engine passes the first ten with the pinned shape, so they can't go in `known-failures.txt`, which fails on a listed case that passes. The intro of "Left for a later PR" now says the Rust engine lists the ones it fails.

The same script also finds these, outside the review's list and not looked at here: four `distinct` "distinct with a phrase that also reads a bare name" cases (already pinned), and cases in `for`, `messages` and `sentences` whose item input holds `[]` or a value next to a `for` alias.

## B9 narrowed

`spec/semantics.md` (`message.items`) now says B9 holds after `is`, `is not`, `is one of`, `is in` and the phrases that order numbers or times, and that `starts with`, `matches` and `contains` say only the root for now. `spec/OPEN.md` lists what is left for #700 under "Left for a later PR": those three phrases, the root from `$params` missing from the assertion's inputs, the Rust engine's missing B9 after `is`, `is not`, `is one of` and `is in`, and the `null` root after `is in` or `is one of` that fails a `count of` as `null` and an `every` as `absent`. `REFERENCE.md` makes no claim about B9 for a given phrase, so it is unchanged.

The review's table has the `is in` row with `{"l": 3}` the wrong way round. Run again on this branch, `count of xs whose v is in $params.l is 1` with `xs` `[{"v": 1}, {}]` and `l` `3` gives `$params.l is 3, which isn't a list; item 2 of xs: v is missing` in `ergo.rego` and only `$params.l is 3, which isn't a list` in the Rust engine, in the `every` and `some` forms too. So `ergo.rego` already builds B9 for `is in` with a root of the wrong kind, and only the Rust engine is left for it.
