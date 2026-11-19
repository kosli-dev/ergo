# #688 step 1: cases and spec text

## Fourth round (D1-D7)

Scripts edit only the cases they change, as before. The row schema check finds 0 failing rows, and `check_rules.py`, `sentences_corpus.py --check` and `spec-placeholder.sh` pass.

- D1: 7 `$min_subjects` rows say a clause that both rules give once (requirements 9/1, 10/1, subjects 74/3, 80/0, 81/0, 144/0, 251/0), and cite `message.join`. Text in `subjects.failed_items` and `message.join`, and the OPEN.md quote of subjects 74/3.
- D2: subjects 164/1, 166/1-3 get a `list` entry; 232 keeps its entry. The rule "the row's inputs keep the read too" is applied to every `from: every` row with a `list` entry (23 more rows: distinct 0/5-7, requirements 3/3-5, 109/3-4, subjects 0/1, 24/0, 25/0, 74/4, 232/0, 233/1-3, 238/1, 250/0, that 20/0-1). subjects 21/1 gets its path read `artifacts named by $params.name` on the row's inputs. The `named by $params.k` key that can't be read goes on the row's inputs in subjects 22-23, 26-33 and messages 91-92. 166/2 keeps `absent` (OPEN.md gap), and its entry and input say `absent` too.
- D2's plain bugs: (a) is in subject_name 24/0 and 57/0 (`every first of region is 1`): `item 1 of region` is now a `list` entry, and the assertion's inputs are `[]` (B6). (b) is in sentences 315/0 `f` (`for: every kids[1234567890123456] as k`): a `list` entry on the row. (c) has no case.
- D4: the five OPEN.md lines are gone. No existing case had any of the five shapes, so 6 new groups (10 cases) after messages 146 pin lines 2-5. Line 1 (an empty `first of` list after a missing root) has no case, because it needs the C7 roots on a `for` row: the Rust builder adds it, with `$params.z is missing; ys is []`.
- D5: derived 90 `plus_left`/`plus_right` say `$input.k is missing, and k is missing`. The key of the wrong type (case 2) hid `k is missing` the same way, so it says `$input.k is 3, which isn't text, and k is missing` too. Ask Julien if that reading is too broad.
- D6: messages 145 and 146 stay `absent`; their case descriptions say why, cite `problems.all_said`, and `problems.all_said` says the cause comes only from what is said. The known-failures line follows the new description.
- D7: for 261 `plain` cases 0 and 3: `pos[].name` is `absent` on the row and the assertion. Text in the `inputs` paragraph of `row.parts`.
- CHANGELOG: the C1 sentence is rewritten for D1/D2, and five lines added. REFERENCE.md: one sentence on `$min_subjects` inputs and the `list` entry.

### Count

`diffmain.py cf8337aa`: 59 existing cases change, 12 are new (10 D4 cases, and messages 145 and 146 under their new descriptions).

### Left for the Rust builder

- D2 for lines without `every`: 209 failed `$min_subjects` rows still lack the path read or key on their `inputs` (messages 84-90, 93, requirements 0, 1, 2, 8, 11, 12, 24, 28, subjects 35-49, 61, 152-270). Values and locations need the engine.
- D7 everywhere: a root read through a list whose items the message says are missing or `null` still says `usable` in many groups, like the `pos`, `os`, `$input.os`, `$params.os` and `lock.pkgs` roots in for 255-293, in 9-32, list_items 0-24 and walks 52-56, 85. A rough scan (inputs with `[]`, outcome `usable` and a `null` in the value) lists 163 groups, most of them walked paths on rows, which don't change.
- The sentence oracle lacks 42 rows, 4 of them for the D4 sentences (`validate.py` prints them).

### Gaps found (undecided)

1. D2 says `failures` `[]` for subjects 21/1 and 28, lines without `every`, but `row.parts`, `subjects.failed_items` and the schema say such a row has `failures` only when its message names items. I left `failures` off them. If D2 means `[]`, every failed `$min_subjects` row of a line without `every` (about 240) gets it, and the schema's description changes.
2. D2's 166/2 entry: I gave the input the outcome `absent`, to match the cause the row keeps. A `null` parent reads `null` elsewhere (the OPEN.md gap).

### Changes the report

- A `$min_subjects` row says a clause both rules give once.
- A `from` line's list that can't be read is a `list` entry, a position that isn't there included, and its read is on the row's `inputs`; a `from` line's key that can't be read, and the path of a line without `every`, are on the row's `inputs`.
- A position at the start of a walk that isn't there or isn't a list is a `list` entry.
- A missing key or a key of the wrong type no longer hides a missing value across a `plus`.
- A root read through a list with an item that lacks the value is `absent`.
- Params that aren't an object no longer make a check that doesn't read them `unusable`.

## Third round (C1-C8)

The scripts edit only the `results` of the cases they change, as before. The 23 rows that failed `spec/report/schema.json` now pass: a small jsonschema script over every row of every case (the row part of the schema, with `{{spec}}` filled in) finds none that fail. `.github/spec-schemas.py` wasn't run, because it builds a report with the engine for every case.

- C1 and C8: the 23 `$min_subjects` rows that kept `failed_items` now have `failures` (requirements 9/1, 10/1, subject_name 78, 79, 81, 82, subjects 74/3, 80, 81, 144, 164/1, 166/1, 232, 237, 241, 245, 248, 251, 253, 254, that 1). Each item a `subjects.one_type` or `subjects.every.same` clause names is an `item` entry with its own clause and the value it read as its input, with `outcome` `usable` (C8 says `usable` for `$input[1].commits` and "like the one_type items"; ties use `usable` the same way). An item that is itself the value keeps its name in its message (`item 1 of xs is an object`, input `xs[0]`). The 9 `every.same` rows get the C8 message, in list order. An inner item, like `item 1 of commits`, is an entry under its item. subjects 164/1 and 166/1 get the path read (`$input[0].y`, `artifact[0].c`) on the row's `inputs` after the count, with `absent`, and `failures` `[]`.
- C2 and C4: derived 90 (cases 0 and 2, `count_is` and `sum_is`), derived 105, messages 145 and messages 146 say the root, then the list or each item, with a `list` entry or `item` entries, and the missing `$params` roots on the assertion. messages 146 is the second half of the OPEN.md line C2 removes (`every`/`some` with `es` `[]` and the params `3`), so it changes too. Its case description and the matching line in `engines/rust/known-failures.txt` changed, and so did messages 145's description.
- C3: for 261 `plain`, all four cases.
- C5: 12 rows (derived 33/1, 71/2, for 264/1 `some_exists`, list_items 15/1, messages 70/0, parts 20/0, 21/0 three checks, sentences 296/1, walks 7/2, 8/4).
- C6: new group at the end of `row_parts`, one case.
- C7: the 21 entries whose cause was worse than their own problems now take their own (for 261-263, 306-312, messages 79/1, 111/0, 112/1). The `for` rows of messages 103, 104, 110, 111 and 112 lose the `list` entry `xs` that held the roots, and the roots go on the row's `inputs`, copied from the same case's other rows. Three count rows of that family also get the `$params` root that was missing from the assertion (messages 103/0 `params`, 111/1 and 112/0 `count`).
- Spec text: `row.parts` (C5, C7), `message.items` (C2, C3), `tally.walk` (C4), `message.join` (C6), `subjects.one_type`, `subjects.failed_items`, `subjects.every.same`, `subjects.every.broken`, `subjects.every.child` (C1, C8). OPEN.md: the `$min_subjects` line and C2's line are gone, and the `pull_requests` quote follows C8. REFERENCE.md: three prose sentences about `failed_items` and `every.same`. CHANGELOG: five lines, and two old sentences about `failed_items` gone.

### Count

`diffmain.py 61f3758c` (in the session scratchpad: loads every case file at the second round's last commit and on this branch, matches cases by group and case description, compares `results`): 55 existing cases change and 3 are new. 21 of the 55 are C1/C8 (23 rows), 34 are C2-C7. Two of the 3 new ones are messages 145 and 146 under their new descriptions, and the third is the C6 case.

### Gaps found (undecided)

1. `item 2 of $input` in requirements 9/10 gets one entry, but the C8 message says `item 2 of $input: commits is a number` twice (once per rule), and the message's order is by rule, not by item. So the row message can't be built from the entries in tree order.
2. subjects 232, `every builds[0].tests[0]` where `tests[0]` is an object: I made it a `list` entry named `item 1 of builds: item 1 of tests`, as the message names it. It could also be the line's own read on the row's `inputs`, like C1's missing position.
3. C1's "a `from` line's own path read sits on the row's inputs" may apply to from-line keys that can't be read (subjects 22-28), to lines without `every` (subjects 21/1 `artifacts.web is missing`) and to positions on a `null` or text parent (subjects 166/2, 166/3, whose cause `absent` OPEN.md already flags). Not changed.
4. The C7 root rule applies to about 50 more `for` groups (listed below), where a `list` entry holds a `whose` root's clause while the list reads fine. Their roots' values, outcomes and locations need the engine, so they are left.
5. OPEN.md lines that C4 and B9 may settle, left as they are: "An empty `first of` or `last of` list after a missing root", "A part that is a list, read in a `whose` beside a list that can't be read" (cause rank), "The items of a list inside a list, beside a root", and the other way round, "A root on the right of the phrase beside a list that can't be read" (the list hides the root) and "A root on the right of the phrase that is missing or `null`, beside a root in a `whose`" (a root hides a root).
6. derived 90 `plus_left` and `plus_right` with no key say only `$input.k is missing`, hiding `k is missing`, which the null-key case says. A root hiding a root on the other side, not a list, so C4 doesn't cover it.
7. for 261 `plain`: the root `pos[].name` keeps `outcome` `usable` on the assertion and the row, as it had, though `item 2 of pos` has no `name`.
8. messages 145 and 146 `count`, `every`, `some`: `main` fails them as `unusable` though every problem they say is `absent` or `value`. I set the worst of what they say (`absent`), by C7 and `problems.all_said`.

### Changes the report

- A `$min_subjects` row whose message names items by type or by list kind has an `item` entry per item, and a `from` line's missing position is on the row's `inputs`.
- `every.same` says the kind in each item: `item 1 of builds: tags is a list, item 2 of builds: tags is text`.
- A root that can't be read no longer hides a list that can't be read (and `$params` that isn't an object no longer hides the items or the list), and the cause is the worst of what is said.
- An `every … whose` that picks nothing has a `list` entry.
- An entry keeps its own cause; a `for` line's `whose` roots move from a `list` entry to the row's `inputs`.

## Cases still in main's shape, for the Rust builder

Found by `scan_left.py` in the session scratchpad, which looks for these shapes in the expected rows, so it may miss a case or name one too many. One line per group and shape, with the number of cases. D1 is decision 1 (a walk on a `for` line), D3 is decision 3 (the items of a `count of` or `sum of`), and C7 is the `for` line's `whose` root held in a `list` entry. REFERENCE.md still has two JSON examples in the old shape: the `failed_items` row near "A list that's missing, like `sha-3`'s" and the option `message`s in "Finding the evidence for a failed row". Both need engine output.
- compare / $refs list a path whose walk fails on an item that isn't an object with what the walk read (D3: count of or sum of with items said in its message and no item entries): 1 case
- deep_walks / ten steps after count of, starting at a for alias (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- deep_walks / ten steps after every, one of them a position (D1: an item whose message names inner items, with no entries for them): 1 case
- derived / count of a list with whose (D3: count of or sum of with items said in its message and no item entries): 3 cases
- derived / count of two lists (D3: count of or sum of with items said in its message and no item entries): 3 cases
- derived / sum of a field (D3: count of or sum of with items said in its message and no item entries): 5 cases
- derived / sum within a distance (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a sum is at least a number (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count under a for line reading the line's name (D1: an item holding a walked path like x.ys[].n as its input): 2 cases
- derived / a sum with is between (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / count of on subjects and items that aren't objects (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / days elapsed in the whose of a count (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count in the whose of a count (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / count of a field over a null item (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / sum of a field over a null item (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / count of a list with whose, over items it cannot decide (D3: count of or sum of with items said in its message and no item entries): 3 cases
- derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k (D3: count of or sum of with items said in its message and no item entries): 3 cases
- derived / a count whose whose reads a named by key from $input.k that is null (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count whose whose reads a named by key from $input.k that is missing (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count whose whose reads a named by key from $input.k that isn't text (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count whose whose reads a root with a named by key from the item, problems inside an item in the order the sentence reads them (D3: count of or sum of with items said in its message and no item entries): 4 cases
- derived / a count whose whose reads a field of the subject with a named by key from the item, a null root next to the key (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count whose whose reads a field of the parent with a named by key from the item, a null root next to the key (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count whose whose reads a root outside the item through a key the item holds says the root once and first (D3: count of or sum of with items said in its message and no item entries): 3 cases
- derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems (D3: count of or sum of with items said in its message and no item entries): 5 cases
- derived / a count, some or every over a list reached through a list, whose whose reads a root with a named by key from the item, names each item as before (D3: count of or sum of with items said in its message and no item entries): 1 case
- derived / a count whose whose reads a part of the subject with a named by key from the item says the part once, first (D3: count of or sum of with items said in its message and no item entries): 2 cases
- derived / a count whose whose reads a part of the subject that is a path, with a named by key from the item, says the part once, first (D3: count of or sum of with items said in its message and no item entries): 2 cases
- distinct / count of distinct (D3: count of or sum of with items said in its message and no item entries): 2 cases
- distinct / count of distinct with a whose (D3: count of or sum of with items said in its message and no item entries): 1 case
- distinct / sum of distinct (D3: count of or sum of with items said in its message and no item entries): 1 case
- distinct / distinct with a phrase that reads a bare name, in every place a sentence can stand, part 4 of 5 (D1: an item whose message names inner items, with no entries for them): 4 cases
- distinct / distinct with a phrase that reads a bare name, in every place a sentence can stand, part 4 of 5 (D1: an item holding a walked path like x.ys[].n as its input): 4 cases
- distinct / distinct with a list read through an alias or a part (D1: an item whose message names inner items, with no entries for them): 1 case
- distinct / distinct with a list read through an alias or a part (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a whose that reads a $params list that isn't a list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a position at the start of a path that starts at a for alias holding a list (D1: an item whose message names inner items, with no entries for them): 1 case
- for / every over the subs of the first item that whose kept, with every leaf checked (D1: an item whose message names inner items, with no entries for them): 1 case
- for / every over the subs of the first item that whose kept, with every leaf checked (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a failed sentence that counts through an alias lists the count and what it counted (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a for line that reads its alias as a list (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a for line that reads a position of a field of its alias (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a for line whose sentence reads the same value twice (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a failed sentence on a for line lists its inputs in the order of its kind (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a failed sentence on a for line lists its inputs in the order of its kind (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a walk on a for line whose path is named with a character that sorts before $ (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a for alias that is a list, read by a position and then by a key: w[0].a does not exist (D1: an item whose message names inner items, with no entries for them): 2 cases
- for / a for alias read by a position and then by a key from a field: w[0] named by zz is 1 (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a for alias read by a position and then by a key from a field: w[0] named by zz does not exist (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a for alias read by a position, then a key, then a key from a field: w[0].a named by zz exists (D1: an item whose message names inner items, with no entries for them): 4 cases
- for / a count of a field in a position of the params (D3: count of or sum of with items said in its message and no item entries): 1 case
- for / a for alias that is a list, read by a position and then by a key: w[0].a does not exist, with true at the position (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a for line over $input whose sentence reads a list on the right, as in MI-18.11 (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a for line that reads an alias and a path through it (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / a root in a for line's relative clause doesn't hide an item's own problem (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a root in one of two relative clauses, in either order (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a part that holds a list is walked by a whose in `count of m.ys whose v is in pl.z is 0` (D1: an item holding a walked path like x.ys[].n as its input): 2 cases
- for / a count of on a for line walks a list in the middle of a part, a parent or $input (D3: count of or sum of with items said in its message and no item entries): 1 case
- for / a part that holds a list is walked on the right of is in on a for line (C7: a list entry on a for row that holds a root's clause while the list reads fine): 4 cases
- for / a name read from outside the item and walked on the right of is in on a for line is said once, with no item (C7: a list entry on a for row that holds a root's clause while the list reads fine): 5 cases
- for / a name read from outside the item and walked on the right of is in on a for line is said once, with no item (D3: count of or sum of with items said in its message and no item entries): 3 cases
- for / a name read from outside the item and walked on the right of is in on a for line is said once, with no item (D1: an item whose message names inner items, with no entries for them): 3 cases
- for / a name read from outside the item and walked on a for line is said once, before what each item says on its own (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a count or sum of a name read from outside the item on a for line says how many more of its items can't be read (C7: a list entry on a for row that holds a root's clause while the list reads fine): 3 cases
- for / a count or sum of a name read from outside the item on a for line says how many more of its items can't be read (D3: count of or sum of with items said in its message and no item entries): 3 cases
- for / a count or sum of a name read from outside the item on a for line says how many more of its items can't be read (D1: an item whose message names inner items, with no entries for them): 3 cases
- for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root (C7: a list entry on a for row that holds a root's clause while the list reads fine): 4 cases
- for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root (D1: an item whose message names inner items, with no entries for them): 2 cases
- for / an item's own problem on a for line is said after a $params or $input root of its whose that can't be read (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / an item's own problem on a for line is said after a $params or $input root of its whose that can't be read (D1: an item whose message names inner items, with no entries for them): 2 cases
- for / an item's own problem on a for line is said after a parent's root of its whose that can't be read (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / an item's own problem on a for line is said after a parent's root of its whose that can't be read (D1: an item whose message names inner items, with no entries for them): 1 case
- for / a part that holds a list is walked in the whose of a for line and in a whose under it (C7: a list entry on a for row that holds a root's clause while the list reads fine): 3 cases
- for / a part of a subject that is a list is walked in the whose of a count of on a for line (D3: count of or sum of with items said in its message and no item entries): 3 cases
- for / a count of a part of a subject that is a list, in a for line's own whose, is said once (D1: an item whose message names inner items, with no entries for them): 3 cases
- for / and N more counts each problem of a part of a subject that is a list once (D1: an item whose message names inner items, with no entries for them): 1 case
- for / and N more counts each problem of a part of a subject that is a list once (D3: count of or sum of with items said in its message and no item entries): 1 case
- for / a parent's part that holds a list is walked in the whose of a for line (C7: a list entry on a for row that holds a root's clause while the list reads fine): 3 cases
- for / a count of or a sum of in a whose on a for line reads its list before any item, so a list it can't read fails the check on an empty list too (C7: a list entry on a for row that holds a root's clause while the list reads fine): 6 cases
- for / a count of or a sum of in a whose on a for line reads its list before any item, so a list it can't read fails the check on an empty list too (D3: count of or sum of with items said in its message and no item entries): 4 cases
- for / a for line's own whose lists a list it walks, as a check without a for line does (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a for line's own whose that sums a list read from outside the item says an item it can't add once (C7: a list entry on a for row that holds a root's clause while the list reads fine): 5 cases
- for / a for line runs the sentences that don't read the alias of an empty list it tolerates, for each item of the list before it (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- for / an alias that a pick on an empty list leaves without a value, read on a later line (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a part that a for line walks as a list fails it on an empty list when an item of it can't be read (C7: a list entry on a for row that holds a root's clause while the list reads fine): 3 cases
- for / a parent's part that a for line's sentence walks fails it on an empty list when an item of it can't be read (D3: count of or sum of with items said in its message and no item entries): 2 cases
- for / an alias of an earlier line that walks a list fails a second line on an empty list when an item of it can't be read (D3: count of or sum of with items said in its message and no item entries): 3 cases
- for / a whose on the second for item that reads a root says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 4 cases
- for / a whose on the second for item that reads a root says the root once, with no item of its list, with some (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a first of on the second for item whose whose reads a root says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / first of a list whose whose reads $params, with $params.k missing (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / a whose on the second for item that reads a root and the first item's alias says the root once and the alias for each item (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a whose on the second for item that reads $params text after is in says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a whose on the second for item that reads a $params object after is in says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a whose on the second for item with every that reads $input after is in says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a whose on the second for item with some that reads $input after is in says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a whose on the second for item with first of that reads $input after is in says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a whose on the second for item with last of that reads $input after is in says the root once, with no item of its list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- for / a second for list whose whose reads a root from the params that can't be read, and a field its items lack, says the root once, then each item, wherever the root is in the whose (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / first of and last of an empty second for list whose whose reads params that are text, not a list, say the params, then the empty list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- for / first of and last of an empty second for list whose whose reads params that are an object, not a list, say the params, then the empty list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- in / a ref that walks, read by a whose inside count of and sum of (D3: count of or sum of with items said in its message and no item entries): 1 case
- in / a path that walks on the right of a for line (D1: an item whose message names inner items, with no entries for them): 1 case
- in / a leading dot on the right of a for line (D1: an item whose message names inner items, with no entries for them): 1 case
- in / a leading dot on the right of a for line keeps its dot when an item of the field is not an object (D1: an item whose message names inner items, with no entries for them): 1 case
- in / count of and sum of read the field named like a part and list it with the dot (D3: count of or sum of with items said in its message and no item entries): 1 case
- list_items / an alias that is a list is read item by item on the right of a list phrase, after every, in a whose and in a that (D1: an item whose message names inner items, with no entries for them): 3 cases
- list_items / an alias that is a list is read item by item on the right of a list phrase, after every, in a whose and in a that (D1: an item holding a walked path like x.ys[].n as its input): 4 cases
- list_items / a list in the middle of a name on the right of a list phrase after every is read item by item (D1: an item whose message names inner items, with no entries for them): 1 case
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it (D1: an item whose message names inner items, with no entries for them): 2 cases
- list_items / a parent's name with a list in the middle, read on the right of a list phrase, is listed as a plain check lists it (D1: an item whose message names inner items, with no entries for them): 5 cases
- list_items / a name read from outside the item and walked on the right of is in is said once, with no item (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_items / a name read from outside the item and walked on the right of is in is said once, with no item (D1: an item whose message names inner items, with no entries for them): 3 cases
- list_items / a name of a subject that is a list, walked on the right of is in, is said once (D1: an item whose message names inner items, with no entries for them): 3 cases
- list_items / a part that holds a list, walked after matches in a whose, is said once (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_items / a part that holds a list, walked after matches in a whose, is said once (D1: an item whose message names inner items, with no entries for them): 3 cases
- list_items / a parent's part that holds a list, walked after matches in a whose, is said once (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_items / a name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it (D3: count of or sum of with items said in its message and no item entries): 1 case
- list_items / a parent's name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it (D3: count of or sum of with items said in its message and no item entries): 1 case
- list_items / two names read from outside the item in a whose, each with items that can't be used, are each named once, worst cause first and then by name (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- list_items / two names read from outside the item in a whose, each with items that can't be used, are each named once, worst cause first and then by name (D3: count of or sum of with items said in its message and no item entries): 1 case
- list_items / two names read from outside the item in a whose, one with an item without the name, are each named once, worst cause first and then by name (D3: count of or sum of with items said in its message and no item entries): 2 cases
- list_items / two names read from outside the item in a whose, one with an item without the name, are each named once, worst cause first and then by name (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- list_items / a missing $params name and a walked part in one whose are each named, with the $params name first only in a count (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- list_items / a missing $params name and a walked part in one whose are each named, with the $params name first only in a count (D3: count of or sum of with items said in its message and no item entries): 1 case
- list_items / a part whose own path has a list in the middle, read on the right of a list phrase, is named from the subject (D3: count of or sum of with items said in its message and no item entries): 1 case
- list_items / a part whose own path has a list in the middle, read on the right of a list phrase, is named from the subject (D1: an item whose message names inner items, with no entries for them): 1 case
- list_items / a name read both item by item and as one value in one check is listed for each read (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- list_items / a count of inside a whose reads its list before any item, so a list it can't read fails the check on an empty list too (D3: count of or sum of with items said in its message and no item entries): 4 cases
- list_items / a count of $params inside a whose reads its list before any item, with an item without the name (D3: count of or sum of with items said in its message and no item entries): 2 cases
- list_items / a count of a parent's list inside a whose reads it before any item (D3: count of or sum of with items said in its message and no item entries): 2 cases
- list_items / a count of a part inside a whose on a subject that is a list reads the part before any item (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_items / a named by key read from an input that is a list, in the second list of a for line and in the whose of a for line (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- list_items / a named by key read from an input that is a list, in a one-line every and on a for line, when the params aren't an object (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- list_items / a part read inside a whose on a subject that is a list, missing, null or not an object (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_items / a part at the start of a path on a subject that is a list, missing, null or not an object (D3: count of or sum of with items said in its message and no item entries): 3 cases
- list_starts / every, some, count of and sum of walk a subject that is a list (D3: count of or sum of with items said in its message and no item entries): 2 cases
- list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it (D1: an item whose message names inner items, with no entries for them): 5 cases
- list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it (D3: count of or sum of with items said in its message and no item entries): 5 cases
- list_starts / a name in a whose is read from the row, so a bad list of the same name on the subject isn't blamed (D3: count of or sum of with items said in its message and no item entries): 2 cases
- messages / a sum of or a count of beside a plus names what it couldn't read (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a one-list for line over a key that holds a colon (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a one-list for line over a key that holds a colon (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a one-list for line with a sentence that walks a list and one that doesn't (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a one-list for line with a sentence that walks a list and one that doesn't (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a one-list for line whose items fail a sentence that walks and one that doesn't (D1: an item whose message names inner items, with no entries for them): 2 cases
- messages / a one-list for line whose items fail a sentence that walks and one that doesn't (D1: an item holding a walked path like x.ys[].n as its input): 2 cases
- messages / a count of a list that holds items that aren't objects (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a sum of a list that holds items that aren't objects (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a count of a list of lists with a whose that counts (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a count of a part's list that holds items that aren't objects (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a count of a list in a list names each item of the inner list by it (D3: count of or sum of with items said in its message and no item entries): 2 cases
- messages / a count of a list in a list in a list names the inner lists by it (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a count of a list in a list item of a for alias (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a count of a list in a list, read by a position and a key from a field, names the list that isn't an object (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a for line over two lists (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for line over two lists (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for line over a list of lists whose values spell the alias (D1: an item whose message names inner items, with no entries for them): 8 cases
- messages / a for line over a list of lists whose values spell the alias (D1: an item holding a walked path like x.ys[].n as its input): 8 cases
- messages / a for line whose alias is named applies and whose value spells it (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for line whose alias is named applies and whose value spells it (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for alias read in a whose keeps its name (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for item that is an object, with a list under it that holds an item that isn't one (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for item that is an object, with a list under it that holds an item that isn't one (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for item that is an object, with a whose over a list that holds an item that isn't one (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for item that is an object, with a whose over a list that holds an item that isn't one (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for item read with a walk of a list under it (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for item read with a walk of a list under it (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for item with a whose that reads a part over items that aren't all objects (D1: an item whose message names inner items, with no entries for them): 2 cases
- messages / a for item with a whose that reads a part over items that aren't all objects (D1: an item holding a walked path like x.ys[].n as its input): 2 cases
- messages / a for line over two lists, with a walk under the first item before a sentence on the second (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for line over two lists, with a walk under the first item before a sentence on the second (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a for line over two lists, with a sentence on the second item before a walk under the first (D1: an item whose message names inner items, with no entries for them): 1 case
- messages / a for line over two lists, with a sentence on the second item before a walk under the first (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- messages / a count of a field in a position of a field that holds objects (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a count of a key in a position of the input that holds objects (D3: count of or sum of with items said in its message and no item entries): 1 case
- messages / a root of a for line, said once (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- messages / a root of a for line and a root that reads the alias in one message (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- messages / a root of a for line with if any, on an empty list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- messages / a parent's part read in a whose, on a for line and in a count of (C7: a list entry on a for row that holds a root's clause while the list reads fine): 3 cases
- messages / a parent's part read in a that on a for line (C7: a list entry on a for row that holds a root's clause while the list reads fine): 3 cases
- messages / a parent's part read in a whose, on an empty list (C7: a list entry on a for row that holds a root's clause while the list reads fine): 4 cases
- messages / two roots in a whose that fail in different ways, beside a list that can be read, take the worst cause (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- messages / a count of or a sum of with more than three items it can't read says the first three and then and N more, last (D3: count of or sum of with items said in its message and no item entries): 2 cases
- parts / a part's alias on the right of a whose, with a part that is missing, null or not a list (D1: an item whose message names inner items, with no entries for them): 1 case
- parts / a part's alias on the right side of a whose, with and without plus (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- parts / a for alias and the input on the right side of a whose with plus (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- parts / a parent's name or a for alias in a count of after that, over items that aren't objects (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- sentences / a for alias inside an item's scope (D1: an item whose message names inner items, with no entries for them): 1 case
- sentences / a for alias on the right of a whose, with items that have a field of the same name (D1: an item whose message names inner items, with no entries for them): 1 case
- sentences / a for alias on the right of a whose, with an alias that is null, text or an object (D1: an item whose message names inner items, with no entries for them): 1 case
- sentences / a sum of is not between two numbers (D3: count of or sum of with items said in its message and no item entries): 2 cases
- sentences / a sum of is not a value within a number (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / a for line that walks a path with a named by field (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- sentences / the examples the rules for where a name resolves were decided on (D3: count of or sum of with items said in its message and no item entries): 2 cases
- sentences / a focus a path couldn't reach, and a focus read by that (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / a field missing on the focus while its item has it (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / the subject's name named by a key, inside and outside a relative clause (D3: count of or sum of with items said in its message and no item entries): 2 cases
- sentences / the subject's field read by name inside a relative clause, when it isn't usable (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / a count whose focus is missing for one item and null for another (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / the subject named by a key of each item, inside a relative clause (D3: count of or sum of with items said in its message and no item entries): 4 cases
- sentences / a list of the params on the right of every, with an item that isn't an object (D1: an item whose message names inner items, with no entries for them): 1 case
- sentences / a list of the params on the right of every, with an item that has no value (D1: an item whose message names inner items, with no entries for them): 1 case
- sentences / a position after the subject's name inside a relative clause (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / a sum of whose that or whose reads a named by key against the focus (D3: count of or sum of with items said in its message and no item entries): 1 case
- sentences / a root name inside a relative clause, read up front (C7: a list entry on a for row that holds a root's clause while the list reads fine): 2 cases
- sentences / a root name of the wrong type inside a relative clause (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- sentences / a root name of the wrong type on the left of a compare inside a relative clause (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- sentences / a second for item whose whose takes its key from the subject (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- sentences / a list of the params on the right of every with many items that can't be read (D1: an item whose message names inner items, with no entries for them): 1 case
- sentences / a second for item whose whose has a root problem, on a row that fails for another reason too (C7: a list entry on a for row that holds a root's clause while the list reads fine): 1 case
- subject_name / count of and sum of on a subject that is a list (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a check that reads plain, on a plain value, a list and a from line that keeps lists (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a field after the subject name inside a whose of a check reads the subject (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a count whose reads a field named like the subject and a part (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a count of a field named like the subject inside a count whose names the field with its dot (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a count whose reads a field named like a subject with "a<b" with its dot (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a count whose reads a field named like a subject with "a\"b" with its dot (D3: count of or sum of with items said in its message and no item entries): 1 case
- subject_name / a count whose reads a field named like a subject with "a\\b" with its dot (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a for line with a walk next to a parent (D1: an item whose message names inner items, with no entries for them): 1 case
- walks / a for line with a walk next to a parent (D1: an item holding a walked path like x.ys[].n as its input): 1 case
- walks / a part that a phrase walks as a list fails a check on an empty list when an item of it can't be read (D3: count of or sum of with items said in its message and no item entries): 2 cases
- walks / a parent's part that a phrase walks fails a check on an empty list when an item of it can't be read (D3: count of or sum of with items said in its message and no item entries): 2 cases
- walks / a one-line walk whose whose reads a named by key from $params that is missing says the key once and each item's own problem (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a one-line walk whose whose reads a named by key from $params that isn't text says the key once, with no item in front (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a whose key from $params that is missing, beside conditions on the same items that read $params and $input (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a that clause whose key from $params isn't text reads the value before the key on the focus, not on the item (D3: count of or sum of with items said in its message and no item entries): 2 cases
- walks / a that clause whose key from $params is missing reads the value before the key on the focus (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name (D1: an item whose message names inner items, with no entries for them): 1 case
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name, with a null param (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name, with a null param (D1: an item whose message names inner items, with no entries for them): 1 case
- walks / a that key that can't be read, on a list item that isn't an object, names the item and never a field under it (D3: count of or sum of with items said in its message and no item entries): 2 cases
- walks / a that key that isn't text, on a list item that isn't an object, names the item and never a field under it (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a whose key from $params that isn't text, said once before the items, doesn't count as one of the three items the message shows (D3: count of or sum of with items said in its message and no item entries): 3 cases
- walks / a whose key from $params that is missing, said once before the items, doesn't count as one of the three items the message shows (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a whose key from $params that isn't text, beside items that fail on their own fields, says the key in each item (D3: count of or sum of with items said in its message and no item entries): 2 cases
- walks / a whose key from $params that is null, beside items that fail on their own fields, says the key once and each item's own problem (D3: count of or sum of with items said in its message and no item entries): 2 cases
- walks / a whose key from $params that is missing, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a whose key from $params that is null, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said (D3: count of or sum of with items said in its message and no item entries): 1 case
- walks / a whose key from $params that isn't text, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said (D3: count of or sum of with items said in its message and no item entries): 2 cases

## Second round (settled points B1-B12)

Scripts edit only the `results` of the cases they change and keep the rest of each file as written. Done so far, on the existing cases:

- B2: every `option` entry says `""` (68 cases).
- Decision 2 in the existing cases: a walk, `count of` or `sum of` beside other sentences, in an option, or on a `for` line without reading the alias now has the entry the same sentence gets alone in a check. Taken from `main` by running the sentence alone, so the D3 items of a `count of` or `sum of` are still missing there.
- B3: the `list` entry of a `count of` or `sum of` holds the list's own read, with its value and where the read stopped, taken from the same list walked by `every`. Done by hand where `main`'s `every` gives no `list` entry either (`$params` that isn't an object, `zz` holding `"str"` with a bad key, an `$applies` row, and `for` case 322's second list).
- B5 and B6: the walked path is no longer an input of an assertion, in every form. Where the list itself failed and had no `list` entry, one is added (B7 and its neighbours), with the read taken from `<list> exists` on `main`.
- Left as `main` has them, and listed in the report: a list problem hidden by another root (15 rows, like messages case 145, which pins it), a whole-list value clause like `approvers is [...]` from an `every … whose` that picks nothing (12 rows), and walked items said in the message with no `item` entries, which are D3 or D1 shapes (9 rows).
- An assertion that got a `list` entry no longer repeats the list's clause in its own `message` (96 entries).
- B9: messages cases 104/0, 111/0, 112/1 and derived 92/0 now say the root and then the items, with `item` entries and the root on the assertion's inputs (`$params` roots added where `main` left them off). New group in `row_parts` with 5 cases (`$input.min` `"s"`, `null` and missing, beside items missing, `null`, of the wrong kind and not objects), for `count of`, `sum of … that`, `every … whose` and `some … whose`.
- B11(c): no existing case had it. New group in `row_parts`, 2 cases.
- B8: new group in `row_parts`, 2 cases, a `for` line and a plain `assert` list side by side.
- B10: 103 passed `$min_subjects` rows lose `failed_items: []`, 42 failed ones get `failures: []`, and 29 failed ones get `list` and `item` entries made from their `failed_items`. 23 rows keep `failed_items` (see gaps). `spec/report/schema.json` drops `failed_items`.
- B12, B2, B3, B5, B6, B8, B9, B10: spec text in `row.parts`, `message.items`, `message.join`, `for.failed_items`, `subjects.*`, `violations`, `syntax.md` names. OPEN.md: the B5 and B9 lines and the old `$min_subjects` lines are gone, one line for the 23 rows is added. CHANGELOG: six lines.
- REFERENCE.md: three prose lines reworded (option message, `$min_subjects` `failures`, violations). Two JSON examples still show the old shape and need output from the engines: the `failed_items` row near line 566 and the option `message`s in "Finding the evidence for a failed row".

### Count

`diffmain.py` (in the session scratchpad) loads every case file at 500ea825 and on this branch, matches cases by group and case description, and compares `results`: 510 existing cases change, 27 `row_parts` cases are new. 86 of the 510 change only by B2 or by losing a passed row's `failed_items`. Only 4 change a row's message or cause, the B9 ones above.

### Not done

- The existing cases the first round listed for decisions 1 and 3 (a walk on a `for` line, the items of a `count of` or `sum of`) still have `main`'s shape. `main` gives these shapes nowhere, so they can't be copied, and they need the engine or hand work one by one.

### Gaps found (settled as C1-C8, done in the third round)

1. `$min_subjects` rows whose message says one clause about several items (`subjects.one_type`, `subjects.every.same`) and `from` lines that read a missing position (`item 1 of $input is missing`): which entry holds which clause. 23 rows keep `failed_items`.
2. B9 when `$params` itself isn't an object: derived case 105 and messages case 145 pin "say only the params". Does B9 add the items there?
3. B9 for `every ws.n whose v is in pos.name is 2` (for case 261): the `whose` reads `v` on a number, so what each item says isn't clear. Left as `main`.
4. A list problem hidden by a root on the other side of a comparison: `count of zzs is m named by $input.k` with no `zzs` and no key says only `$input.k is missing` (derived 90), and `count of es whose v is in $input.z is 0` with no `es` (messages 145). `problems.all_said` says both, but messages 145 pins one.
5. `every … whose` that picks nothing and fails says `approvers is [...]`: is that a `list` entry (12 rows)?
6. B8 when two sentences walk different lists under one item (`x.ys` and `x.zs`): which order.
7. A for-line item's cause takes the row's worst cause, not its own (messages 112/1 `for`: `item 1 of xs` is `unusable` with only an `absent` input).

## First round

- `spec/cases/row_parts/cases.json`: 9 groups, 18 cases, written from the three decisions. All 18 fail on `main` (500ea825), as they should. The rows `main` already gets right are copied from it. The new trees copy the form the decision points to: the one-sentence plain walk for decision 2, the plain nested walk with the alias names for decision 1, and the `every … whose … exists` walk for the items of a `count of` decision 3 names.
- `engines/rego/tests/spec_test.rego`: the new folder and its test. No engine changes.
- `spec/semantics.md`: `row.parts`, `message.items`, `for.failure_inputs`, `scope.failures`. `spec/OPEN.md`: the #688 entry keeps only `$min_subjects`. `spec/CHANGELOG.md`: two lines under 0.7.
- The spec is already `v0.7-dev` (last tag `spec-v0.6`), so `spec-version.sh set` wasn't needed.
- The expected rows match `spec/report/schema.json`, so the schema doesn't change.

## Questions and gaps (not decided)

1. The inputs of a `for` item that holds the items of a `count of` or `sum of`. I put only the count or sum (`sum of w.xs.v`) and dropped `w.xs[].v`, by analogy with decision 1 (`[]` for a walk) and with the plain assertion.
2. An option whose assertion now holds items keeps its message as it is today (the whole text), and the assertion gets `""`.
3. The `list` entry of a list inside a `for` item (`x.ys`, `w.xs` missing): I used value `null` and the place the read stopped, as the plain walk's inner list does. `main` gives `[]` and no location on the `for` line and in the plain `count of xs` list entry.
4. Wording: the `for` line says `x.ys is "s", which isn't a list or an object` and the plain walk says `ys is "s", which isn't a list`. Each entry keeps its own row's text.
5. `count of o named by $params.k whose …` keeps `o named by $params.k[]` in the assertion's inputs on `main`. I followed `row.parts` and dropped it (see OPEN.md, "The list entry of a count of").
6. A one-sentence walk over a missing list puts the walked path (`xs.ys.n`, `[]`) on the assertion and the list's own read on the `list` entry. Decision 2 copies that to the other forms.
7. `every es whose zz is m named by $params.k exists` with no `k` and no `es` gives one assertion with the message `$params.k is missing; es is missing` and no `list` entry, unlike `every o named by $params.k is 1`. I left it out.
8. Two sentences on one `for` line over the same inner list: `main` says the clauses in sentence order, and `message.join` says "in the order of the items". Decision 3 brings more inner items, so this now shows up more often. I wrote no case for it.
9. When a root can't be read and items can't be read either, in a one-line `count of` or `sum of`, `message.items` still says only the root. Does decision 3 ("whatever its cause") change that? I wrote no case for it.
10. `$min_subjects` (decision 12): OPEN.md says it waits for #688, but the #688 design talk doesn't cover it. I wrote no case for it.
11. Bugs on `main` outside the decisions, which the cases avoid: `every xs.ys.v exists` with an outer item `3` says `item 3 of xs: ys is null, which isn't a list`. `every x.ys.n is at least x.min` with neither field says only `x.ys is missing`. `every xs.v exists` gives a missing `v` the outcome `null`.
12. A sentence on a `for` line that doesn't read the alias and walks a list (`count of xs whose k is 1 is 3`) gets its items under its own assertion (decision 2). Decision 15 said `failures` `[]` for such sentences, but it was written about sentences that have no items.
