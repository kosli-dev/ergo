# #688 PR 2: final state

## What this round did

- Pinned the 67 spec cases that the Rego engine still failed to what it gives now (derived 10, distinct 4, for 10, in 1, list_items 9, messages 18, sentences 7, subject_name 3, subjects 1, walks 4). Only the `results` and the other expected fields the case already had were rewritten, and only for failing cases.
- Added 30 of them to `engines/rust/known-failures.txt` (the other 37 were there already). The Rust tests were not run: no `ergo-rust` Docker image exists.
- Listed them in `spec/OPEN.md` under "Left for a later PR", with D14, D15 and the open gaps.
- The unit test `test_a_count_of_a_position_in_params_that_are_an_empty_list_names_the_params` now says `item 1 of $params is missing` and is renamed `..._names_the_missing_item`. The `for` case "count of a position of the params, with params as an empty list" already says the same, so the shape follows a spec case.
- Deleted `_fl_fail_name` in `from_lines.rego`: nothing called it.
- Wrote unit tests for helpers that coverage listed as not reached: `tests/report/parts_test.rego`, `tests/report/chains_test.rego` and one in `tests/shared/path_names_test.rego`.

## Left for a later PR: uncovered lines

Coverage listed 23 lines before this round. These are left (checked again after the round, see the final report):

- `report/parts.rego`: the branches of `_tally_list_read` that read an unkeyed list field (`_tally_unkeyed_list_paths`, 636, 638, 669 to 673) and `_item_input_name` with parents (1644). They need a `count of` over a field before a `named by` key on a policy with parents; no test reaches them yet.
- `shared/path_names.rego:20` is now reached by a direct call only: its callers check `path != []` first.

## The pinned cases

Grouped by the decision they still break ("no single rule" for the group with none).

### D9/D10 derived rows not filled (count/sum/plus sides) (4)

- derived / sum within a distance of a field / the worse cause wins when both sides fail: absent before null
- derived / a path plus a count on the left / fails as unusable when the path is text and the list is null
- derived / a count on the left and a field on the right / fails as the worse cause when both sides fail
- derived / days elapsed in the whose of a count / fails as absent when an item cannot be decided because its end is missing

### D10/D11: a named by key or root read outside the items (18)

- derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is a number
- derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is null and an item's tags mix kinds, so the count says what it says when the root reads
- derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is null and the item's key and field print with a semicolon and a comma
- derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is 3 and four items each have a problem, so the last one is counted
- derived / a count whose whose reads a root outside the item through a key the item holds and another root from the params says the other root as before / the root is missing and the param is missing
- derived / a count whose whose reads a root outside the item through a key the item holds and reads params that aren't an object says the params / the root is null, the first item is null and the second item's key isn't text
- list_items / a for line over items that aren't objects, with a sum of or a count of whose named by key is read from the params and isn't text, on an input that is an object / say the key isn't text, and then the item that isn't an object
- walks / a whose key from $params that is null, beside items that fail on their own fields, says the key once and each item's own problem / five mixed items

### distinct: a bare name the subject holds gets an item entry (4)

- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: higher
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: missing
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: null
- distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: text

### other: structure of the tree (decision 1/2/3 shapes), not yet looked at one by one (27)

- for / every over the subs of the first item that whose kept, with every leaf checked / fails, and the subs under the item whose left out aren't shown
- for / a for line whose sentence counts two subject fields that can't be counted / names each field once, and not again after them, with items
- for / a for line whose sentence counts two subject fields that can't be counted / names each field once on an empty list
- for / a for line that reads an alias and a path through it / lists the alias paths first and then the other names, in a failed assertion
- for / a part that holds a list is walked in the whose of a for line and in a whose under it / an empty part leaves every item out
- for / a for line runs the sentences that don't read the alias of an empty first list it tolerates, for each item of the second list / fails each approver that didn't approve when the whose of the first line leaves no commit
- for / a $params list that a for line walks fails it on an empty list when an item of it can't be read / fails, with an empty rows, when an item of it has no name
- for / a $params list that a for line walks fails it on an empty list when an item of it is null / fails, with an empty rows
- list_items / a name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it / a text value among numbers, and a number among patterns
- list_items / a parent's name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it / a text value among numbers, and a number among patterns
- messages / two worked-out values that can't be used / the values are joined with a comma and and
- messages / a for item with a whose that reads a part over items that aren't all objects / names the part first, once, then the inner items
- messages / a root name after is in inside a relative clause that isn't a list, on an empty list / fails as unusable and names the root, because the list it looks in is read before any item, then the empty list
- messages / a root name after is in inside a relative clause that isn't a list, on a list with items / names the root once, with no item, on a for line too
- messages / a parent's part read in a whose inside an any_of option, next to a list that can't be read / names the part that is null, then the list that is missing
- messages / a parent's part read in a whose inside an any_of option, next to a list that can't be read / names the part that is missing, then the list that is null
- messages / a root and the list it is read beside that both can't be read are both said, roots first, with the worst cause / a root that is missing and a list that is null fail as absent
- sentences / a for alias inside an item's scope / an alias on the right is the alias, the left of a whose and a dotted name are the field, and the report prints the dot where it matters
- sentences / an any_of of sentences with a param that isn't a list / fails as unusable even when another option passes
- sentences / the examples the rules for where a name resolves were decided on / each check reads its names where the rules say, on the pull request of the decision
- sentences / the examples the rules for where a name resolves were decided on / a focus that is missing fails as absent, and one that is null as not_an_object, naming the item and the value
- sentences / the subject's field read by name inside a relative clause, when it isn't usable / fails as unusable when the field's type differs
- sentences / a root name on the right of some in a from line's condition, read up front / fails the candidate once, with no item named, even when its list is empty
- subjects / a child subject of a from line with named by each of, with a parent that isn't an object / fails min_subjects as not_an_object under each parent, even with min_subjects 0, and gives no subject, though the parents aren't all of one type
- walks / a for line with a walk next to a parent / lists the for line's list and the parent's value, and never the alias's value
- walks / a walk whose parent path is named by a bare name, read from the subject / fails as absent when the subject has no such field, even when each item has one
- walks / a walk whose parent path is named by a bare name, read from the subject / fails as absent when the subject has no such field, whatever the parent and the items hold

### D6/C2: params that aren't an object (4)

- for / every on a position of the params with nothing after it, with params as a number / fails as unusable and names the params and what they are
- for / count of a position of the params, with params as an empty list / fails as unusable and names what it can't read
- messages / a root in a count of beside a list that is missing, when the params aren't an object / says the params, or the root, once, and then the list, and a check that doesn't read the params fails with the worst cause of what it says
- messages / a root in a whose beside an empty list, when the params aren't an object / says the root, and then the empty list where it fails, and a check that doesn't read the params fails with the worst cause of what it says

### subject name read with a dot (4)

- in / count of and sum of read the field named like a part and list it with the dot / lists the field with the dot and the part without it, and names the item of the part
- subject_name / a count of a field named like the subject, written with a dot / a field that isn't a list or an object is said once, as the walk says it
- subject_name / a count of a field named like the subject, written with a dot / a missing field is named with its dot in the inputs and in the message
- subject_name / a count whose reads a field named like the subject and a part / an item that isn't an object is named with the dot of the field the whose reads

### path.not_an_object: a named by key from an input that is a list (5)

- list_items / a path from $input with named by on an input that is a list / fails as not_an_object and names the input once
- list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key holds text: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is missing: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is null: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is a number: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it

### decision 1/3: entries of a list in the middle of a name or a part, read on the right of a phrase (8)

- list_items / an any_of option that reads a field of a subject that is a list outside what it reads item by item fails on its own / the option that reads each item decides

### C7 second bug: a for line's whose roots in a list entry, not the row's inputs (5)

- messages / two roots in one relative clause that can't be read / names every root that failed, in the order the sentence reads them
- messages / two roots after is in that aren't lists, in one relative clause / names both, in the order the sentence reads them, on a list with items
- messages / two roots after is in that aren't lists, in one relative clause / names both on an empty list too
- messages / two roots in one relative clause that fail in different ways / names every root that failed, whatever its cause, in the order the sentence reads them
- messages / two roots in one relative clause that fail in different ways / names them in front of what the items say when an item fails in a worse way

### D4: a part that is a list in a whose doesn't give the row its cause (3)

- messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is missing
- messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is null
- messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is empty

### B9/C3: items a whose can't read after a root, on for lines and in a list in a list (7)

- messages / a root in a whose that is missing, beside a list in a list whose inner lists can't be read, is said first and then each item / an inner list that is null and one that is missing

### named by a field: base read outside through the item's key (gap, decision-silent) (8)

- sentences / a for line item that reads a null before a named by field / fails as null whatever the field holds, and failed_items names the null, as the item does without the field, whether it reads the first alias or not
