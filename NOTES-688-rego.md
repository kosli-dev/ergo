# #688 step 3: the Rego engine

Branch `row-parts-688-rego2`, on top of `row-parts-688-rego`. Not finished: a fresh agent picks up from "Left" below.

## Done (first builder)

- Decision 3 for plain checks, decision 2 (multi-sentence, `any_of`, `$applies`, B12), B2, B6 for one-line walks, `$min_subjects` (B10, C1, C8, D1, D2, D8). See the commits before `ec43fdbf`.

## Done (second builder)

- Decision 1 on `for` lines: a walk or a `count of`/`sum of` on a one-list or two-list `for` line holds its own tree under the `for` item (or the second-list item). `_for_item_of`, `_for_second_of` and `_for_sentence_part` in `report/parts.rego` rerun the sentence with the alias bound (`_bound`, `with input as {"ergo/names": ...}`) and reuse `_walk_assertion_entry` or `_tallied_entry`. The alias marker `\u0002` is taken out with `_alias_unmarked` and `_unmarked_entries`.
- B8: `_m_list_leads` in `messages/for_lines.rego` orders the clauses under a `for` item by list (in the order the lists first appear) and then by item position. A `count of`/`sum of` line's text is split into one clause per item (`_m_tally_pieces`), so each gets the `for` item in front.
- B11c: a field that `exists` finds missing gets the outcome `absent` (`_said_missing`).
- B12 for `count of`/`sum of` that don't read the alias: `_for_free_entry` no longer needs the sentence to be off the item lines.
- A `count of`/`sum of` item whose text is only a root's text gets no entry (decision 38, `_tally_root_said`).
- B6 everywhere: the walked read leaves a walk's assertion even with no entries (`_walked_path_read`), and leaves a `for` line's assertion too (`_sentence_walked_read`). A `count of` keeps its list read only when no list entry holds it and it isn't read through a `named by` key (`_tally_own_read`).
- C4/C5 for walks with a `whose`: when the walk has no item entries and the message says the walked list (missing, null, not a list, or picked nothing), it gets a `list` entry with the list's read (`_walk_flaw_lists`). The subject rides on failed walk rows with a `whose` for this (`_reads_items_later`).
- Whole-value items of a `sum of` get their own read as input (`_item_input_name`).
- `opa check --strict` errors left by the first builder (unused arguments in `requirements.rego`) are fixed.

## Left

See the bottom of this file, rewritten at each checkpoint.
