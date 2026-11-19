# #688 step 2: the Rust engine

Branch `row-parts-688-rust`, on top of `row-parts-688-d` (step 1). No Rego part changed.

## Where it stands

- `cargo fmt --check`, Clippy with `-D warnings`, every test, `cargo doc`, the `key_order` test and the Wasm build of `ergo-policy-sentences` pass in Docker.
- The Rust engine passes 2992 of 3580 spec cases. `engines/rust/known-failures.txt` lists 588: 456 of them were already on `main`'s list (the PR 1 gaps of #691, 722 lines on `main`, 266 of which pass now), and 132 are new, all cases that step 1 changed or added.
- 5 of the 28 `row_parts` cases still fail (listed below).
- The sentence oracle has the 42 rows it lacked; `validate.py` finds none missing and none that differ from `ergo.rego`.
- The unit tests and `engines/rust/engine/tests/regressions` were updated to the new shape: `$min_subjects` rows have `failures` and the reads of D2 on their inputs, a walk's own list is off its assertion, and a walk in an option has its items.

## What the Rust engine does now

- Decision 3: a `count of` or `sum of` gives an `item` entry for every item it can't read, whatever its cause, in list order, and a `list` entry for a list it can't read (decision 37, B3). The assertion keeps the count and the roots, not the walked list, and says `""` when the entries say everything. The row message says every item, after the roots, and `and N more` counts only items (decision 22), so roots no longer use up the three. An item whose text names a root or a key from outside (`$`, `named by`) is said only when its cause is the row's cause, as on `main`, so decision 38's "said once, no item in front" holds.
- B9: a root in a `whose` that can't be read is said once, then each item's own read, for `count of`, `sum of`, `every` and `some`. The item's own read is checked with the root replaced by a value of the kind the comparison needs (a number for an order, a time for `is before`/`is after`), so only `is at least`-like and time comparisons do this; `is`, `is in`, `contains` and the rest keep `main`'s behaviour.
- Decision 2: a walk, a `count of` or a `sum of` has the same tree beside other sentences, in an `any_of` option and on a `from` line with conditions (`$applies`) as alone. B2: an option says `""`.
- Decision 1: a walk or count on a one-list `for` line puts its items under the `for` item, named with the alias. It is used only when the nested entries say every clause the old leaf said; otherwise the leaf stays. Two-list `for` lines are not done.
- B6: a walk's own list read leaves its assertion when the assertion has entries or its `named by` key can't be read.
- B10, C1, C8, D1, D2: a failed `$min_subjects` row has `failures` in place of `failed_items` (a passed row has neither). `every.same` is said per item (`item 1 of $input: commits is a list, item 2 of $input: commits is a number`), each item named by `one_type` or `every.same` is an `item` entry with outcome `usable`, a clause both rules give is said once, and the `$min_subjects` message of an `every` line is not cut at three. A list the line can't walk is a `list` entry and its read is on the row's inputs. A `from` line without `every` whose path can't be read, and a `named by` key that can't be read, put the read on the row's inputs.

## Cases filled in from the Rust engine

`dist/` scripts (not committed) compared each failing case with the engine's report and took the engine's rows only when every difference was of one kind: the row's inputs gained reads (D2, 92 cases), entries under a `count of`/`sum of` assertion and the item clauses of the row message (D3, about 90), entries under a `for` item with the row message unchanged (D1, 25), an `outcome` going from `usable` to `absent` or `null` (D7, 2), or only the violations. Everything else in the row had to match. 208 cases differ from step 1's last commit (compare 2, derived 43, distinct 8, for 2, in 1, list_items 8, list_starts 2, messages 44, parts 1, requirements 16, sentences 9, subject_name 5, subjects 61, walks 5). Checks on those rows: every row matches `spec/report/schema.json`; every clause of a row message comes from an entry, except the count clause and root clauses of `$min_subjects` rows, which sit on the row's inputs; items are in list order. A first pass also took cases that removed C5 picked-nothing `list` entries, one C2 `$params` entry and a hand-written `row_parts` case; those were put back to step 1's rows.

Not filled in, because the engine still differs from them for another reason (mostly the PR 1 gaps of #691): most of the C7 `for` groups (no case was taken by the C7 rule), most of the D7 roots, and the D1 and D3 groups in NOTES-688-cases.md whose rows also differ in the assertion's inputs, root order or causes. They stay in step 1's shape and in `known-failures.txt`.

## Gaps (not decided)

1. D2 says `failures: []` for lines without `every`; `row.parts`, `subjects.failed_items` and the schema say such a row has `failures` only when its message names items. The Rust engine follows the schema: no key. Undecided.
2. `count of $params whose v is 1 is 1` with params `[3]`: `main` says `$params is [3], which isn't an object`. The branch says the same and doesn't add `item 1 of $params is 3, which isn't an object` (C2 would say the root and then the item). Kept as on `main`.
3. `every $input[1].commits` on `[{"commits": []}, 5]`: the engine gives an `item` entry `item 2 of $input` with the input `$input[1]`; D2 for a position that isn't there (subjects 164/1) asks for a `list` entry holding the read as written. Not done for a position that holds a value of the wrong kind; subjects 161-166 stay failing.
4. subjects "a child subject under a parent line that mixes types": the parent's own `$min_subjects` row says `item 1 of ds is an object, item 2 of ds is text` with no item entries in the case, while `subjects.failed_items` asks for them.

## Still failing in `row_parts`

- a count of and a sum of on a for line (decision 1 and 3 on a two-list line and beside a sentence that doesn't read the alias)
- a list walked on a for line with two lists (decision 1, two lists)
- an every or a some that asks whether a field exists (B11c, two cases)
- two sentences on a for line that walk the same list (B8 order)

## Sweep

`spec/sweep.py` with the Docker `--rust` command, default limit (468 cells sampled from 4588, 12 per shape and key), once on `main` (500ea825) and once on this branch. Rego is the same on both. 329 cells differ on `main`, 387 here. Comparing the Rust reports of the two runs cell by cell: 300 rows change, 262 only in `failures` or `inputs` and 38 in their message (none in their cause). The 38:

- C4, a list said after a root that `main` hid (`$input.k is true, which isn't text, and es is missing`, `a: $params.k is missing; es is null; b: id is "t"`): 13 cells in `sum-of-named-by`, `sum-of-phrase`, `count-of-whose-two-keys`, `any-of-count` and `applies-count-is`.
- Roots before the list instead of after (`$input.k is [], which isn't text; es is "s", which isn't a list or an object`, `$params.k is null; es is null`): 10 cells in `count-of-whose-two-keys`, `count-of-that` and `any-of-count`.
- `main`'s fallback text (`count of es.v that equals m named by $input.k is 0 is false`, `sum of es.v equals m named by $input.k is false`, `... needs more than 15 digits`) replaced by the list's problem (`es is null`, `es is missing`): 10 cells in `count-of-that`, `sum-of-phrase` and `applies-count-is`, with `k` missing, `null` or `"a"`. With `k` missing or `null` the branch says only the list, not the key: C4 says the key first; this is a gap left in the Rust engine.

All 38 are cells where Rego says what `main`'s Rust said or its own older text, so Rego changes with this PR, as the list below says. The full list of cells is in `dist/sweep-diff.txt` when the run is repeated with `dist/t/sweepcmp.py`.

## What Rego has to change

- Decision 3 and B9 for `count of`, `sum of`, `every` and `some`: item entries, every item said, roots first, `and N more` counting items only.
- Decision 2 (option, multi-sentence, `$applies`) and decision 1 (one-list `for` lines), B2, B6.
- The `$min_subjects` conversion (B10, C1, C8, D1, D2), including the uncut message of an `every` line.
- C4 in the sweep cells above.
- Everything in the cases this branch filled in from the Rust engine, since they now pin the Rust engine's output (the 208 cases above).
