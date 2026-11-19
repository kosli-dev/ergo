# #688 step 3: the Rego engine

Branch `row-parts-688-rego`, on top of `row-parts-688-rust`. Not finished: a fresh agent picks up from "Left" below.

## Done

- Decision 3 for plain checks: a `count of` or `sum of` says every item it can't read, whatever its cause, roots first, then lists and items in list order (`_m_tally_walked_side`, `_m_tally_shown` in `messages/walks.rego`). The assertion gets an `item` entry per item and a `list` entry per inner list, nested under the outer items (`_tally_item_parts` in `report/parts.rego`). The list entry holds the list's own read (B3), and the assertion drops the walked list read (B1, `_tally_own_read`).
- Decision 2: a walk, a `count of` or a `sum of` in a multi-sentence check, an `any_of` option, an `$applies` row (one or several conditions) and a sentence on a `for` line that doesn't read the alias (B12) has the same tree as alone (`_tallied_entry`, `_applies_cond_entry`, `_for_free_entry`). B2: an option says `""`. B6: a walk's own list read leaves its assertion once it has entries (`_walked_read`).
- `$min_subjects` (B10, C1, C8, D1, D2, D8): `failures` in place of `failed_items` on every failed row, `[]` when empty (`_ms_*` in `report/requirements.rego`, `_no_items` in `report/chains.rego`); `every.same` said per item in list order (`_fl_note_clauses`); a clause both rules give said once and no cut at three (`_fl_notes_once`); list entries' reads, the broken path of a line without `every` and a key that can't be read on the row's inputs.
- Spec text and schema for D8; cases: D8 `"failures": []` on 242 rows, D2 reads on 25 cases; 173 changed cases added to `engines/rust/known-failures.txt`; `CHANGELOG.md` and `spec/CHANGELOG.md` lines.
- Wasm (wasm-js budget reports only, measured with a copy of the last part of `.github/wasm-js.cjs`): 28.1 (budget 28, main 28.0), 19.4 (20), 44.4 (45), 112.1 (118), 51.4 (52). The first is 0.1 MB over. The subject and requirement ride on the raw row only for checks that need them (`_anchored_row`), and tally work is gated on the words `count of`/`sum of` (`_tally_worded`).

## Left

1. Decision 1 and B8 on `for` lines: a walk or count on a one-list `for` line puts its items under the `for` item (`_for_item_entry` in `report/parts.rego` keeps the whole text and the `x.ys[].n` input on the item). row_parts groups 3-6, 11, 12 and about 40 messages/for/walks cases filled from the Rust engine fail on this. Message order B8 (row_parts group 11) is not done either.
2. B9 (row_parts group 9): with a root in a `whose` that can't be read, say each item's own read after the root (only for order and time comparisons, as the Rust engine does); `_m_tally_dropped` and `_tally_focus_cause` hide them today.
3. B11c (row_parts group 10), the `every $params.a` with params not an object list entry (for groups 170-186), and a few C4 shapes.
4. Unit tests that still pin old shapes (failures from `opa test ... --ignore spec_test.rego`): count_and_sum_test (4), messages_test (1), parents_test (1), report_parts_test (2), sentences_test (3), violations_test (1, the `$applies` one), walks_test (6). Update each to the new shape after checking the new output follows a decision.
5. Spec cases: 447 fail in the Rego engine at the last full count; 260 of them are in the Rust known-failures too (mostly cases still in main's shape that decisions 1-3 change), 187 only in Rego (decision 1, B9, and cases the Rust engine filled). Fill in the stale ones from the engine once a difference is checked against a decision.
6. The from-line list entry of `every artifacts.pull_requests` on `"x"` has the value `null` on its input; check why the doc is null there.
7. Then the full checks list in AGENTS.md, coverage tests, REFERENCE.md's two JSON examples, `spec/sweep.py` on `origin/main` and the branch, and the Wasm budget (0.1 MB over on the first report).

Local `main` in this worktree is stale (d730a768); compare with `origin/main` (500ea825).
