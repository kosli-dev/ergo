# #688 step 3: the Rego engine

Branch `row-parts-688-rego`, on top of `row-parts-688-rust`.

## Done

- Decision 3 for plain checks: a `count of` or `sum of` says every item it can't read, whatever its cause, roots first and then lists and items in list order (`_m_tally_walked_side`, `_m_tally_shown`), and the assertion gets an `item` entry per item and a `list` entry per inner list, nested under the outer items (`_tally_item_parts` in `report/parts.rego`). The list entry of a `count of` holds the list's own read (B3).
- Decision 2: a walk, a `count of` or a `sum of` in a multi-sentence check, an `any_of` option and an `$applies` row (one or several conditions) has the same tree as alone. B2: an option says `""`. B6: a walk's own list read leaves the assertion when it has entries.
- `$min_subjects` (B10, C1, C8, D1, D2, D8): `failures` in place of `failed_items` on every failed row, `[]` when empty; `every.same` said per item; a clause both rules give said once; no cut at three; list entries' reads, a broken path of a line without `every` and an unreadable key on the row's inputs (`_ms_*` in `report/requirements.rego`).
- Wasm: the subject and requirement ride on the raw row only for checks that need them (`_anchored_row`), and the tally work is gated on the words `count of`/`sum of`. Numbers at the last measure: 28.1 (28), 19.4 (20), 44.9 (45), 112.1 (118), 51.4 (52). Main: 28.0, 19.4, 44.9, 112.1, 51.4.

## Left

- Decision 1 and B8 on `for` lines (row_parts groups 3-6, 11, 12): items under the `for` item, one entry per list level; count/sum items under the `for` item.
- B9 (row_parts group 9): a root in a `whose` that can't be read, then each item's own read.
- B11c (row_parts group 10).
- Cases: D8 `"failures": []` on every failed `$min_subjects` row without entries (script), and the stale cases still in main's shape that the decisions change (fill in from Rego where the difference is decided, add the Rust lines to `engines/rust/known-failures.txt`).
- Checks, coverage tests, REFERENCE.md examples, changelogs, sweep.
