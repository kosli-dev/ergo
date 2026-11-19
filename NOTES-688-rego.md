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

## Done (third builder, branch `row-parts-688-rego3`)

- D10: an item of a `count of`/`sum of` lists the `named by` key it reads from the item (`xs[0].key`), and an item's text drops a root clause the row already says once (`_tally_unrooted`). Each read of a multi-read item gets its own outcome (`_tally_said_cause`). A focus that isn't an object is named by the path read into it (`xs[0].v.tags`, `not_an_object`), as the walk names it.
- B9 for `count of`, `sum of`, `every` and `some`: when a root of an order or time comparison in a `whose` can't be read, each item is judged again with the root replaced by a number or a time (`_root_stand_in`, `_whose_alone`, `_alone_read` in `lines/roots.rego`), and the items it can't read are said after the root and get entries (`ergo/alone_items`).
- The first Wasm budget is 29 MB, as decided.

- A `named by` key from outside the items is said only when the row fails with its cause (`tally.whose`), and each item's own problem is said after it (decision 36): `_m_record_shown`, `_m_key_flawed`. An item lists a later read of a condition only when no earlier read of it was missing, `null` or not an object (`_tally_path_skipped`).
- Params that aren't an object are said once (`$params is [3], which isn't an object`), never as items of `$params` (`_m_params_item`).
- A `sum of` in an `$applies` row drops its walked read, as the check row does (decision 2).
- 13 of the 15 unit tests moved to the decided shapes; REFERENCE.md's `$min_subjects` and `any_of` examples are the engine's output.

## Fourth builder, branch `row-parts-688-rego4` (in progress)

- D11: a `named by` key from outside the items is said once before every item, whatever the items' causes (`_m_key_root_state_in` only hides a missing or `null` key beside another key that isn't text, which the walks group "two named by keys on an empty list" still pins: decision-silent, see below). An item says only its own paths (`_m_own_clauses`), and an `is in` whose list goes through an unreadable key still says only the key (`_m_list_read_first`). `tally.whose` and `path.ref_step` reworded, spec changelog line added, two cases and three unit tests moved.
- A `count of` whose list is read through a `named by` key or a part gets its `list` entry (`_tally_keyed_list_names`, `_list_clause_name`), read where it stopped (`_list_stop_value`).
- B9 for every phrase: `is`, `equals`, `is in` and `contains` with a root that can't be read judge each item again with the root replaced by the item's own value (`_root_stand_in`), and a count says only the first condition an item can't decide (`_m_undecided_before`). Not when the list itself can't be read.
- D2: `from: $input` with an input that can't be read puts `$input` on the `$min_subjects` row's inputs.
- A root of a `for` line's sentence that is said once is no longer said again under each item, with an `and N more` of its own (`_for_led_more`, `_for_led_once`, `_for_deduped`).
- C7 on `for` lines (first and second list): an `item` or `list` entry takes the worst of its own failed reads and of the entries under it when that is no worse than the cause it had (`_own_caused`). It never raises a cause, and it leaves an entry whose message has more than one clause, because such an entry can say a problem none of its inputs holds (the list beside a root).
- A walk on a `for` line keeps only the reads through an alias on the `for` item; a root like `$input.q` stays on the assertion (B1, `for.failure_inputs`).
- Cases moved to the decided shape (Rego was right, Rust-filled rows stale), all in `known-failures.txt`: C5 `list` entries under a `for` item, decision 3 item entries, D8 `failures: []` in violations, D2 `$input` reads, D11 key first, B3 a null part read where it stopped.
- `--timeout 120s` is `240s` in AGENTS.md, `.github/checks.sh`, `.github/compiled-tests.sh`, `.github/wasm-tests.sh` and `.github/workflows/test.yml`.

Spec cases failing in the Rego engine at the end: 121 (messages 38, sentences 16, for 15, derived 14, list_items 12, walks 10, subject_name 5, list_starts 4, distinct 4, subjects 1, row_parts 1, in 1); 69 of them are in `known-failures.txt`.

Checks run by the fourth builder: full `opa test` (unit: `test_a_count_of_a_position_in_params_that_are_an_empty_list_names_the_params` still fails, a known Rego gap; 2 errors are timeouts under the full run that pass alone; the spec tests fail on the cases above), strict `opa eval` `true`, the three `opa check`, `opa fmt`, `regal lint`, `rego-layers.py`, `rego-folders.sh`, `no-inline-tests.sh`, `spec-placeholder.sh`, `check_rules.py`, `sentences_corpus.py --check`, `spec-schemas.py` (3580 cases, 0 problems), `check_grammar.py` (0 disagreements), no comments in Rego: all pass. Coverage: not done, the `--coverage` run stopped with `context deadline exceeded`. Wasm budgets (budget part of `wasm-js.cjs` only): 28.6 (29), 19.6 (20), 44.4 (45), 113.2 (118), 52.2 (52) MB: the fifth is over by 0.2 MB, up from 51.4. Not run: Rust tests and `spec/sweep.py` (no `ergo-rust` image).

What is left, by rule (the biggest first):
- A root on the right of the phrase (`every es.v is in $params.z`) that is missing or `null` is hidden when the walked list can't be read (messages, 6 cases, D4). `_rooted_row` isn't the path these take; a branch there broke three other cases, so it was taken out.
- A part that is a list read in a `whose` (`pl.z`, an item of `pl` not an object) doesn't raise the row to `unusable` and its input stays `usable` (messages, 3 cases, D4).
- Params that aren't an object still make checks that don't read them `unusable` (messages, 2 cases, D6), and `count of $params[0]` with `[]` says `item 1 of $params is missing` (unit test and a `for` case).
- C7's second plain bug: a `for` line's `whose` roots sit in a `list` entry for the list, not on the row's inputs (for and messages "two roots in one relative clause").
- B9 on a `for` line's `plain` rows (`every ws.n whose v is in pos.name is 2`, C3): the items after the root are still missing (4 for cases).
- D10 rows not filled in (derived, listed above by the third builder) and the two-list `count of`/`sum of` message (row_parts).
- The distinct case "a phrase that also reads a bare name" in a multi-sentence check gives an item entry for a root the subject holds (4 cases).
- list_items/list_starts: a list in the middle of a name read on the right of a phrase, and a named by key from an input that is a list (12 + 4 cases), not looked at.

Gaps found:
- `count of rs whose zz is in $input.k is 1` with `$input.k` `null` and items without `zz`: the message says the root and both items, but the row's cause stays `null`, not `absent` (the count's cause is worked out in `checks/` and can't call the B9 judging in `lines/` without a backward call).
- An item of `count of xs whose v equals pr named by k` whose key names a field the subject lacks (`pr named by k is missing`) gets an entry whose inputs are all `usable`: the read that failed (`pr.z`) has no input. How to name it isn't decided (D9/D10 cover a key read inside the item, not a base read outside through the item's key). Cases "the subject named by a key of each item ... names the item whose key names a field the subject doesn't have" and "the subject's name named by a key ... reads each approver's k inside" stay failing.
- Decision-silent: "an every, a some, a for item or a count whose whose reads two named by keys on an empty list ... one key is missing and the other isn't text" says only the key that isn't text. D11 says a key is always said, but it speaks of items, not of a second key that fails worse.

## Checks run by the third builder

- Full `opa test`: 58 fail and 4 error. The 4 errors are the compiled `walks` and `messages` spec tests hitting the 120 s timeout under the full parallel run; alone they pass in 80 to 90 s. The failures are the 2 unit tests below and the spec topics that hold the 160 failing cases.
- Pass: strict `opa eval` (`true`), the three `opa check`, `opa fmt`, `regal lint`, `check_rules.py`, `spec-schemas.py` (3580 cases, 0 problems), `check_grammar.py` (0 disagreements), `sentences_corpus.py`, `rego-layers.py`, `rego-folders.sh`, `no-inline-tests.sh`, `spec-placeholder.sh`.
- Wasm budgets (budget part of `.github/wasm-js.cjs` only): 28.4 MB (29), 19.4 (20), 44.4 (45), 112.8 (118), 51.4 (52).
- Not run: the coverage list, `spec/sweep.py` (no Rust engine of this branch to compare with), the Rust tests (no `ergo-rust` Docker image here), `.github/wasm-tests.sh`.

## Left (third builder, 2026-11-19)

Spec cases: 160 fail in the Rego engine (by a script that skips the cases with long numbers), 88 of them also in `engines/rust/known-failures.txt`. The list is at the end of this file.

1. Not done: C7 on second-list entries, the two-list `count of`/`sum of` message (row_parts group 3), D2 plain bugs (a) and (b), a `count of` list entry through a `named by` key or a dotted field. These are most of the `for`, `messages`, `sentences` and `list_items` failures.
2. Two unit tests still fail, both real Rego gaps: `test_a_count_of_a_position_in_params_that_are_an_empty_list_names_the_params` (`count of $params[0]` with params `[]` says `item 1 of $params is missing`, the test wants `$params is [], which isn't an object`) and `test_a_whose_item_that_isnt_an_object_beside_a_key_that_is_missing_or_null_fails_as_not_an_object` with no `k` (Rego says `$input.k is missing; item 1 of rs is "a", which isn't an object` and leaves out `item 2 of rs: zz is missing`; with `k` `null` it is right). The same gap fails derived "a count whose whose reads a named by key from $input.k that is missing".
3. D10 cases not filled, because Rego doesn't give the D10 shape yet: a root that stops before its last step (`$input.d.m` with `$input.d` missing or `null`: no item entries, the whole message on the assertion), "the root is null and an item's tags mix kinds" (the count says `item 1 of xs: $input.m is null`, decision 38 says the root once with no item), "semicolon and a comma", "the root is 3 and four items", "another root from the params", "params that aren't an object".
4. Looks undecided, not changed: the walks group "a that key that can't be read, on a list item that isn't an object, names the item and never a field under it" names `$params.k is null` beside a worse `not_an_object` item, while `tally.whose` says a key in a path read against the focus is named only when the row fails with its cause. Making Rego follow `tally.whose` there fails those two cases.

### Spec cases failing in the Rego engine

- compare / $refs list the path before named by, with its whole value / lists the path before named by with its whole value, where it was read, and the rows don't change
- compare / a failed row quotes its own long numbers / each message shows the row's numbers with every digit
- compare / a failed row quotes its own long numbers / each message shows the row's numbers with every digit, in the other order
- compare / a number in the policy and a longer one in the input / compares every digit of the input
- compare / a number in the policy and a longer one in the input / compares every digit of the input, in the other order
- (Rust too) derived / a count whose whose reads a named by key from $input.k that is missing / the key is missing
- derived / a count whose whose reads a root outside the item through a key the item holds and another root from the params says the other root as before / the root is missing and the param is missing
- (Rust too) derived / a count whose whose reads a root outside the item through a key the item holds and reads params that aren't an object says the params / the root is null, the first item is null and the second item's key isn't text
- (Rust too) derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is 3 and four items each have a problem, so the last one is counted
- derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is null and an item's tags mix kinds, so the count says what it says when the root reads
- derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is null and the item's key and field print with a semicolon and a comma
- derived / a count whose whose reads a root outside the item through a key the item holds says the root once and first / a root further back is null and the items have no key
- derived / a count whose whose reads a root outside the item through a key the item holds says the root once and first / the root is null and the first item's key isn't text
- (Rust too) derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is a number
- (Rust too) derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is missing
- (Rust too) derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is null
- (Rust too) derived / a path plus a count on the left / fails as unusable when the path is text and the list is null
- derived / days elapsed in the whose of a count / fails as absent when an item cannot be decided because its end is missing
- (Rust too) derived / sum within a distance of a field / the worse cause wins when both sides fail: absent before null
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: higher
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: missing
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: null
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: text
- distinct / distinct with a phrase that reads a bare name, in every place a sentence can stand, part 4 of 5 / it reads the subject's lo, so it reads whatever the dropped copy's lo is: higher
- distinct / distinct with a phrase that reads a bare name, in every place a sentence can stand, part 4 of 5 / it reads the subject's lo, so it reads whatever the dropped copy's lo is: missing
- distinct / distinct with a phrase that reads a bare name, in every place a sentence can stand, part 4 of 5 / it reads the subject's lo, so it reads whatever the dropped copy's lo is: null
- distinct / distinct with a phrase that reads a bare name, in every place a sentence can stand, part 4 of 5 / it reads the subject's lo, so it reads whatever the dropped copy's lo is: text
- (Rust too) for / a $params list that a for line walks fails it on an empty list when an item of it can't be read / fails, with an empty rows, when an item of it has no name
- (Rust too) for / a $params list that a for line walks fails it on an empty list when an item of it is null / fails, with an empty rows
- (Rust too) for / a count or sum of a name read from outside the item on a for line says how many more of its items can't be read / 5 items without the name
- (Rust too) for / a count or sum of a name read from outside the item on a for line says how many more of its items can't be read / 5 items without the name, and items of the line without their own
- (Rust too) for / a count or sum of a name read from outside the item on a for line says how many more of its items can't be read / 7 items without the name
- for / a for line runs the sentences that don't read the alias of an empty first list it tolerates, for each item of the second list / fails each approver that didn't approve when the whose of the first line leaves no commit
- for / a for line that reads an alias and a path through it / lists the alias paths first and then the other names, in a failed assertion
- (Rust too) for / a for line whose sentence counts two subject fields that can't be counted / names each field once on an empty list
- (Rust too) for / a for line whose sentence counts two subject fields that can't be counted / names each field once, and not again after them, with items
- (Rust too) for / a name read from outside the item and walked on the right of is in on a for line is said once, with no item / items that aren't objects fail as unusable and are said once
- (Rust too) for / a part that holds a list is walked in the whose of a for line and in a whose under it / an empty part leaves every item out
- (Rust too) for / a second for list whose whose reads a root through the first alias that can't be read, and a field its items lack, says the root for each item of the first list, then each item of the second / w.z isn't a number and no item of ys has u
- for / a some walk on a for line whose whose reads $input / lists the alias first, then what the whose reads
- for / a walk on a for line of a child subject whose whose reads the parent / lists the alias first, then the parent's field
- for / a walk on a for line whose assertion reads $input and whose whose reads the alias / lists the alias first, then $input
- for / a walk on a for line whose whose reads $input after the item's alias / lists the alias first, then what the whose reads
- for / a walk on a for line whose whose reads $input on its left / lists the alias first, then what the whose reads
- for / a walk over the second item of a for line whose whose reads $input / lists the alias first in the inputs of each second item
- (Rust too) for / a whose on the second for item that reads $params text after is in says the root once, with no item of its list / fails as unusable with the root once and then the item that can't be read on its own
- (Rust too) for / a whose on the second for item that reads a $params object after is in says the root once, with no item of its list / fails as unusable with the root once and then the item that can't be read on its own
- (Rust too) for / a whose on the second for item with every that reads $input after is in says the root once, with no item of its list / fails as unusable with the root once when it is an object, and then the item that can't be read on its own
- (Rust too) for / a whose on the second for item with first of that reads $input after is in says the root once, with no item of its list / fails as unusable with the root once when it is an object, and then the item that can't be read on its own
- (Rust too) for / a whose on the second for item with last of that reads $input after is in says the root once, with no item of its list / fails as unusable with the root once when it is an object, and then the item that can't be read on its own
- (Rust too) for / a whose on the second for item with some that reads $input after is in says the root once, with no item of its list / fails as unusable with the root once when it is an object, and then the item that can't be read on its own
- (Rust too) for / an item's own problem on a for line is said after a $params or $input root of its whose that can't be read / an item without v, with $input.os that is text
- (Rust too) for / an item's own problem on a for line is said after a parent's root of its whose that can't be read / an item without v, with a parent list that is text
- (Rust too) for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item that is null, with an item of the part without the name
- (Rust too) for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with a null part
- (Rust too) for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with an item of the part without the name
- (Rust too) for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with names of more than one kind
- (Rust too) for / and N more counts each problem of a part of a subject that is a list once / four items that aren't objects are three shown and one more
- (Rust too) for / count of a position of the params, with params as an empty list / fails as unusable and names what it can't read
- for / every on a position of the params with nothing after it, with params as a number / fails as unusable and names the params and what they are
- for / every over the subs of the first item that whose kept, with every leaf checked / fails, and the subs under the item whose left out aren't shown
- (Rust too) in / count of and sum of read the field named like a part and list it with the dot / lists the field with the dot and the part without it, and names the item of the part
- list_items / a for line over items that aren't objects, with a sum of or a count of whose named by key is read from the params and isn't text, on an input that is an object / say the key isn't text, and then the item that isn't an object
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item whose name is null is listed as null, at the name
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item with no name is listed as null, at the item
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / each item's value is listed with its location, and a part keeps its tag
- list_items / a name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it / a text value among numbers, and a number among patterns
- (Rust too) list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key holds text: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- (Rust too) list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is a number: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- (Rust too) list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is missing: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- (Rust too) list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is null: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- list_items / a parent's name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it / a text value among numbers, and a number among patterns
- list_items / a path from $input with named by on an input that is a list / fails as not_an_object and names the input once
- list_items / an any_of option that reads a field of a subject that is a list outside what it reads item by item fails on its own / the option that reads each item decides
- (Rust too) list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is a list isn't read into, is listed as null, at the item, and fails as unusable
- (Rust too) list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is a number is listed as null, at the item, and fails as unusable
- (Rust too) list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is null is listed as null, at the item, and fails as unusable
- (Rust too) list_starts / every, some, count of and sum of walk a subject that is a list / an item that isn't an object fails as not_an_object, and a missing field as absent
- messages / a count of a list in a list item of a for alias / the key read from the field names the value
- messages / a count of a path with a key from a field names the value once / a number is named the same way
- messages / a count of a path with a key from a field names the value once / a value that isn't a list or an object is named after the key it was read at
- messages / a count of a path with a key from a field, in a for line, names the value once / a value that isn't a list or an object is named after the key it was read at
- messages / a count of over a part that can't be reached / the part is named once
- (Rust too) messages / a for item with a whose that reads a part over items that aren't all objects / names the part first, once, then each item in turn
- messages / a for item with a whose that reads a part over items that aren't all objects / names the part first, once, then the inner items
- messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a colon is printed as the input had it
- messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a comma is printed as the input had it
- messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a dot is printed as the input had it
- messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a space is printed as the input had it
- messages / a for line over a list of lists whose values spell the alias / an object that holds the alias in a key is printed as the input had it
- messages / a for line over a list of lists whose values spell the alias / an object that holds the alias in a value is printed as the input had it
- messages / a for line over two lists / the inner items are named without a dollar sign before the alias
- messages / a for line whose alias is named applies and whose value spells it / a value that holds the alias is printed as the input had it
- messages / a parent's part read in a whose inside an any_of option, next to a list that can't be read / names the part that is missing, then the list that is null
- messages / a parent's part read in a whose inside an any_of option, next to a list that can't be read / names the part that is null, then the list that is missing
- (Rust too) messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is empty
- (Rust too) messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is missing
- (Rust too) messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is null
- messages / a root and the list it is read beside that both can't be read are both said, roots first, with the worst cause / a root that is missing and a list that is null fail as absent
- (Rust too) messages / a root in a count of beside a list that is missing, when the params aren't an object / says the params, or the root, once, and then the list, and a check that doesn't read the params fails with the worst cause of what it says
- (Rust too) messages / a root in a whose beside an empty list, when the params aren't an object / says the root, and then the empty list where it fails, and a check that doesn't read the params fails with the worst cause of what it says
- (Rust too) messages / a root in a whose that is missing, beside a list in a list whose inner lists can't be read, is said first and then each item / an inner list that is null and one that is missing
- (Rust too) messages / a root name after is in inside a relative clause that isn't a list, on a list with items / names the root once, with no item, on a for line too
- (Rust too) messages / a root name after is in inside a relative clause that isn't a list, on an empty list / fails as unusable and names the root, because the list it looks in is read before any item, then the empty list
- (Rust too) messages / a root on the right of the phrase and a root in a whose, both missing, beside a list that can't be read, are all said, then the list / no params and no list
- (Rust too) messages / a root on the right of the phrase and a root in a whose, both null, beside a list that is null, are all said, then the list / both params and the list null
- (Rust too) messages / a root on the right of the phrase of the wrong type, beside a list that can't be read, is said first and then the list / a list that is missing
- (Rust too) messages / a root on the right of the phrase of the wrong type, beside a list that can't be read, is said first and then the list / a list that is text
- (Rust too) messages / a root on the right of the phrase that is missing, beside a list that can't be read, is said first and then the list, with the worst cause / a list that is missing
- (Rust too) messages / a root on the right of the phrase that is missing, beside a list that can't be read, is said first and then the list, with the worst cause / a list that is null
- (Rust too) messages / a subject read at the position of a list of the input / names the list when it is missing
- (Rust too) messages / a subject read at the position of a list of the input / says what the list is when it isn't a list or an object
- (Rust too) messages / a subject read at the position of a list of the input / says which item of the list is missing
- (Rust too) messages / a subject read from the first item of a list of the input / says the first item is missing when the list is empty
- (Rust too) messages / a subject read from the first item of a list of the input / says the list is missing
- (Rust too) messages / two roots after is in that aren't lists, in one relative clause / names both on an empty list too
- (Rust too) messages / two roots after is in that aren't lists, in one relative clause / names both, in the order the sentence reads them, on a list with items
- (Rust too) messages / two roots in one relative clause that can't be read / names every root that failed, in the order the sentence reads them
- (Rust too) messages / two roots in one relative clause that fail in different ways / names every root that failed, whatever its cause, in the order the sentence reads them
- (Rust too) messages / two roots in one relative clause that fail in different ways / names them in front of what the items say when an item fails in a worse way
- messages / two worked-out values that can't be used / the values are joined with a comma and and
- (Rust too) requirements / a position on the whole input when it is a list / names the position from $input in the expression
- (Rust too) requirements / subjects from a list / fails min_subjects as value on an empty list
- (Rust too) requirements / the whole input as the subject / fails min_subjects as null on a null input
- (Rust too) row_parts / a count of and a sum of on a for line name the items they can't read under the item of the for line / items named through the alias, an inner list that is missing, a sentence that doesn't read the alias, and a second list
- (Rust too) sentences / a for alias inside an item's scope / an alias on the right is the alias, the left of a whose and a dotted name are the field, and the report prints the dot where it matters
- sentences / a for line item that reads a null before a named by field / fails as null whatever the field holds, and failed_items names the null, as the item does without the field, whether it reads the first alias or not
- (Rust too) sentences / a list walked before a named by field / is walked, so a field that's missing, null or not a string decides the cause, but a plain check can't read the list and ends unusable
- sentences / a root name on the right of some in a from line's condition, read up front / fails the candidate once, with no item named, even when its list is empty
- sentences / a sum of whose that or whose reads a named by key against the focus / is written wrong naming the key, and a key from the subject or a count of is fine
- sentences / an any_of of sentences with a param that isn't a list / fails as unusable even when another option passes
- (Rust too) sentences / every and some walk a list read with named by a field / lists the field right after the walked list
- (Rust too) sentences / list positions with more than 15 digits / aren't numbers in the policy, so they're written correctly in from, a sentence and a for line
- sentences / the examples the rules for where a name resolves were decided on / a focus that is missing fails as absent, and one that is null as not_an_object, naming the item and the value
- sentences / the examples the rules for where a name resolves were decided on / each check reads its names where the rules say, on the pull request of the decision
- (Rust too) sentences / the path before a named by field that can't be read / decides the cause before the field is read, whatever the field holds
- (Rust too) sentences / the path before a named by field that can't be read / reads the field when the null is just before it, so the field decides, and a good one ends the path null, as a plain path through null does
- (Rust too) sentences / the path before a named by field that can't be read, in a count, a sum, a plus, an elapsed time, a some and a for line / ends absent when the path is missing, whatever the field holds
- (Rust too) sentences / the path before a named by field that can't be read, in a count, a sum, a plus, an elapsed time, a some and a for line / ends unusable when the path goes through a string, whatever the field holds
- sentences / the subject named by a key of each item, inside a relative clause / names the item that has no key
- sentences / the subject named by a key of each item, inside a relative clause / names the item whose key names a field the subject doesn't have
- sentences / the subject's field read by name inside a relative clause, when it isn't usable / fails as unusable when the field's type differs
- sentences / the subject's name named by a key, inside and outside a relative clause / an approver without k fails as absent, whatever the subject's k
- sentences / the subject's name named by a key, inside and outside a relative clause / reads each approver's k inside, and is written wrong outside
- (Rust too) subject_name / a count of a field named like the subject, written with a dot / a field that isn't a list or an object is said once, as the walk says it
- subject_name / a count of a field named like the subject, written with a dot / a missing field is named with its dot in the inputs and in the message
- subject_name / a count whose reads a field named like the subject and a part / an item that isn't an object is named with the dot of the field the whose reads
- (Rust too) subject_name / every on a position of region / names the item and the list it came from
- (Rust too) subject_name / the subject name is read in every position of a one-line check on a list subject / a list subject is walked, counted and summed as a field that holds the list would be
- (Rust too) subjects / a child subject of a from line with named by each of, with a parent that isn't an object / fails min_subjects as not_an_object under each parent, even with min_subjects 0, and gives no subject, though the parents aren't all of one type
- walks / a for line with a walk next to a parent / lists the for line's list and the parent's value, and never the alias's value
- walks / a that clause whose key from $params is missing reads the value before the key on the focus / the focus holds m
- (Rust too) walks / a walk whose parent path is named by a bare name, read from the subject / fails as absent when the subject has no such field, even when each item has one
- (Rust too) walks / a walk whose parent path is named by a bare name, read from the subject / fails as absent when the subject has no such field, whatever the parent and the items hold
- (Rust too) walks / a whose key from $params that is missing, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said / the list holds text
- (Rust too) walks / a whose key from $params that is null, beside items that fail on their own fields, says the key once and each item's own problem / an item without zz and an item whose m is null
- (Rust too) walks / a whose key from $params that is null, beside items that fail on their own fields, says the key once and each item's own problem / five mixed items
- (Rust too) walks / a whose key from $params that is null, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said / the list holds text
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name / an item of $input.os is null and $params.z is missing
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name, with a null param / an item of $input.os has no name and $params.z is null
