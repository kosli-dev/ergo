# Spec cases still failing in the Rego engine on `row-parts-688-rego4`

121 cases, 69 of them also in `engines/rust/known-failures.txt` (marked Rust). `M` means the row message or cause differs, `S` only the structure. Classified by a script over the case names, by the decision that explains each one.

## other: structure of the tree (decision 1/2/3 shapes), not yet looked at one by one (27)

- S Rust for / a $params list that a for line walks fails it on an empty list when an item of it can't be read / fails, with an empty rows, when an item of it has no name
- S Rust for / a $params list that a for line walks fails it on an empty list when an item of it is null / fails, with an empty rows
- S for / a for line runs the sentences that don't read the alias of an empty first list it tolerates, for each item of the second list / fails each approver that didn't approve when the whose of the first line leaves no commit
- S for / a for line that reads an alias and a path through it / lists the alias paths first and then the other names, in a failed assertion
- S Rust for / a for line whose sentence counts two subject fields that can't be counted / names each field once on an empty list
- S Rust for / a for line whose sentence counts two subject fields that can't be counted / names each field once, and not again after them, with items
- S Rust for / a part that holds a list is walked in the whose of a for line and in a whose under it / an empty part leaves every item out
- S for / every over the subs of the first item that whose kept, with every leaf checked / fails, and the subs under the item whose left out aren't shown
- S list_items / a name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it / a text value among numbers, and a number among patterns
- S list_items / a parent's name read from outside the item that reads fine leaves a value of the wrong type to the item that holds it / a text value among numbers, and a number among patterns
- S messages / a for item with a whose that reads a part over items that aren't all objects / names the part first, once, then the inner items
- S messages / a parent's part read in a whose inside an any_of option, next to a list that can't be read / names the part that is missing, then the list that is null
- S messages / a parent's part read in a whose inside an any_of option, next to a list that can't be read / names the part that is null, then the list that is missing
- S messages / a root and the list it is read beside that both can't be read are both said, roots first, with the worst cause / a root that is missing and a list that is null fail as absent
- S Rust messages / a root name after is in inside a relative clause that isn't a list, on a list with items / names the root once, with no item, on a for line too
- S Rust messages / a root name after is in inside a relative clause that isn't a list, on an empty list / fails as unusable and names the root, because the list it looks in is read before any item, then the empty list
- S messages / two worked-out values that can't be used / the values are joined with a comma and and
- S Rust sentences / a for alias inside an item's scope / an alias on the right is the alias, the left of a whose and a dotted name are the field, and the report prints the dot where it matters
- S sentences / a root name on the right of some in a from line's condition, read up front / fails the candidate once, with no item named, even when its list is empty
- S sentences / an any_of of sentences with a param that isn't a list / fails as unusable even when another option passes
- S sentences / the examples the rules for where a name resolves were decided on / a focus that is missing fails as absent, and one that is null as not_an_object, naming the item and the value
- S sentences / the examples the rules for where a name resolves were decided on / each check reads its names where the rules say, on the pull request of the decision
- S sentences / the subject's field read by name inside a relative clause, when it isn't usable / fails as unusable when the field's type differs
- S Rust subjects / a child subject of a from line with named by each of, with a parent that isn't an object / fails min_subjects as not_an_object under each parent, even with min_subjects 0, and gives no subject, though the parents aren't all of one type
- S walks / a for line with a walk next to a parent / lists the for line's list and the parent's value, and never the alias's value
- S Rust walks / a walk whose parent path is named by a bare name, read from the subject / fails as absent when the subject has no such field, even when each item has one
- S Rust walks / a walk whose parent path is named by a bare name, read from the subject / fails as absent when the subject has no such field, whatever the parent and the items hold

## D10/D11: a named by key or root read outside the items (18)

- S derived / a count whose whose reads a root outside the item through a key the item holds and another root from the params says the other root as before / the root is missing and the param is missing
- M Rust derived / a count whose whose reads a root outside the item through a key the item holds and reads params that aren't an object says the params / the root is null, the first item is null and the second item's key isn't text
- S Rust derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is 3 and four items each have a problem, so the last one is counted
- S derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is null and an item's tags mix kinds, so the count says what it says when the root reads
- S derived / a count whose whose reads a root outside the item through a key the item holds says each item's own problems after the root, and stops after three problems / the root is null and the item's key and field print with a semicolon and a comma
- S derived / a count whose whose reads a root outside the item through a key the item holds says the root once and first / a root further back is null and the items have no key
- S derived / a count whose whose reads a root outside the item through a key the item holds says the root once and first / the root is null and the first item's key isn't text
- M Rust derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is a number
- M Rust derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is missing
- M Rust derived / a count, a sum or an add whose sides can't be read in different ways, with a named by key from $input.k / the key is null
- S list_items / a for line over items that aren't objects, with a sum of or a count of whose named by key is read from the params and isn't text, on an input that is an object / say the key isn't text, and then the item that isn't an object
- S messages / a count of a list in a list item of a for alias / the key read from the field names the value
- S sentences / the subject named by a key of each item, inside a relative clause / names the item whose key names a field the subject doesn't have
- M walks / a that clause whose key from $params is missing reads the value before the key on the focus / the focus holds m
- M Rust walks / a whose key from $params that is missing, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said / the list holds text
- M Rust walks / a whose key from $params that is null, beside items that fail on their own fields, says the key once and each item's own problem / an item without zz and an item whose m is null
- M Rust walks / a whose key from $params that is null, beside items that fail on their own fields, says the key once and each item's own problem / five mixed items
- M Rust walks / a whose key from $params that is null, in a walk beside another sentence or option, a for line beside a sentence that doesn't read the alias, and a count of that, is said wherever the walk is said / the list holds text

## decision 1: two-list count of/sum of and nested for items (row_parts group 3, B8) (10)

- S for / a walk over the second item of a for line whose whose reads $input / lists the alias first in the inputs of each second item
- S messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a colon is printed as the input had it
- S messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a comma is printed as the input had it
- S messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a dot is printed as the input had it
- S messages / a for line over a list of lists whose values spell the alias / a value that holds the alias before a space is printed as the input had it
- S messages / a for line over a list of lists whose values spell the alias / an object that holds the alias in a key is printed as the input had it
- S messages / a for line over a list of lists whose values spell the alias / an object that holds the alias in a value is printed as the input had it
- S messages / a for line over two lists / the inner items are named without a dollar sign before the alias
- S messages / a for line whose alias is named applies and whose value spells it / a value that holds the alias is printed as the input had it
- M Rust row_parts / a count of and a sum of on a for line name the items they can't read under the item of the for line / items named through the alias, an inner list that is missing, a sentence that doesn't read the alias, and a second list

## decision 1/3: entries of a list in the middle of a name or a part, read on the right of a phrase (8)

- S list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item whose name is null is listed as null, at the name
- S list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item with no name is listed as null, at the item
- S list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / each item's value is listed with its location, and a part keeps its tag
- S list_items / an any_of option that reads a field of a subject that is a list outside what it reads item by item fails on its own / the option that reads each item decides
- M Rust list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is a list isn't read into, is listed as null, at the item, and fails as unusable
- M Rust list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is a number is listed as null, at the item, and fails as unusable
- M Rust list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is null is listed as null, at the item, and fails as unusable
- M Rust list_starts / every, some, count of and sum of walk a subject that is a list / an item that isn't an object fails as not_an_object, and a missing field as absent

## D2 plain bugs (a)/(b): a position or first item of a walked list (8)

- S Rust messages / a subject read at the position of a list of the input / names the list when it is missing
- S Rust messages / a subject read at the position of a list of the input / says what the list is when it isn't a list or an object
- S Rust messages / a subject read at the position of a list of the input / says which item of the list is missing
- S Rust messages / a subject read from the first item of a list of the input / says the first item is missing when the list is empty
- S Rust messages / a subject read from the first item of a list of the input / says the list is missing
- S Rust sentences / list positions with more than 15 digits / aren't numbers in the policy, so they're written correctly in from, a sentence and a for line
- S Rust subject_name / every on a position of region / names the item and the list it came from
- S Rust subject_name / the subject name is read in every position of a one-line check on a list subject / a list subject is walked, counted and summed as a field that holds the list would be

## named by a field: base read outside through the item's key (gap, decision-silent) (8)

- S sentences / a for line item that reads a null before a named by field / fails as null whatever the field holds, and failed_items names the null, as the item does without the field, whether it reads the first alias or not
- S Rust sentences / a list walked before a named by field / is walked, so a field that's missing, null or not a string decides the cause, but a plain check can't read the list and ends unusable
- S Rust sentences / every and some walk a list read with named by a field / lists the field right after the walked list
- S Rust sentences / the path before a named by field that can't be read / decides the cause before the field is read, whatever the field holds
- S Rust sentences / the path before a named by field that can't be read / reads the field when the null is just before it, so the field decides, and a good one ends the path null, as a plain path through null does
- S Rust sentences / the path before a named by field that can't be read, in a count, a sum, a plus, an elapsed time, a some and a for line / ends absent when the path is missing, whatever the field holds
- S Rust sentences / the path before a named by field that can't be read, in a count, a sum, a plus, an elapsed time, a some and a for line / ends unusable when the path goes through a string, whatever the field holds
- S sentences / the subject's name named by a key, inside and outside a relative clause / reads each approver's k inside, and is written wrong outside

## B9/C3: items a whose can't read after a root, on for lines and in a list in a list (7)

- M Rust for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item that is null, with an item of the part without the name
- M Rust for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with a null part
- M Rust for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with an item of the part without the name
- M Rust for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with names of more than one kind
- M Rust messages / a root in a whose that is missing, beside a list in a list whose inner lists can't be read, is said first and then each item / an inner list that is null and one that is missing
- M walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name / an item of $input.os is null and $params.z is missing
- M walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name, with a null param / an item of $input.os has no name and $params.z is null

## D4/C4: a root on the right of the phrase beside a list that can't be read is hidden (6)

- M Rust messages / a root on the right of the phrase and a root in a whose, both missing, beside a list that can't be read, are all said, then the list / no params and no list
- M Rust messages / a root on the right of the phrase and a root in a whose, both null, beside a list that is null, are all said, then the list / both params and the list null
- M Rust messages / a root on the right of the phrase of the wrong type, beside a list that can't be read, is said first and then the list / a list that is missing
- S Rust messages / a root on the right of the phrase of the wrong type, beside a list that can't be read, is said first and then the list / a list that is text
- M Rust messages / a root on the right of the phrase that is missing, beside a list that can't be read, is said first and then the list, with the worst cause / a list that is missing
- M Rust messages / a root on the right of the phrase that is missing, beside a list that can't be read, is said first and then the list, with the worst cause / a list that is null

## path.not_an_object: a named by key from an input that is a list (5)

- S Rust list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key holds text: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- S Rust list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is a number: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- S Rust list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is missing: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- S Rust list_items / a named by key read from an input that is a list, in a count of, a sum of, a whose, a that, a one-line every or some, a for line, an any_of, a child subject and a from line / the key is null: every check that reads the key fails as not_an_object and says once that the input isn't an object, and so do the $applies rows and the $min_subjects row of the from line that reads it
- S list_items / a path from $input with named by on an input that is a list / fails as not_an_object and names the input once

## C7 second bug: a for line's whose roots in a list entry, not the row's inputs (5)

- S Rust messages / two roots after is in that aren't lists, in one relative clause / names both on an empty list too
- S Rust messages / two roots after is in that aren't lists, in one relative clause / names both, in the order the sentence reads them, on a list with items
- S Rust messages / two roots in one relative clause that can't be read / names every root that failed, in the order the sentence reads them
- S Rust messages / two roots in one relative clause that fail in different ways / names every root that failed, whatever its cause, in the order the sentence reads them
- S Rust messages / two roots in one relative clause that fail in different ways / names them in front of what the items say when an item fails in a worse way

## D9/D10 derived rows not filled (count/sum/plus sides) (4)

- S derived / a count on the left and a field on the right / fails as the worse cause when both sides fail
- M Rust derived / a path plus a count on the left / fails as unusable when the path is text and the list is null
- S derived / days elapsed in the whose of a count / fails as absent when an item cannot be decided because its end is missing
- M Rust derived / sum within a distance of a field / the worse cause wins when both sides fail: absent before null

## distinct: a bare name the subject holds gets an item entry (4)

- S distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: higher
- S distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: missing
- S distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: null
- S distinct / distinct with a phrase that also reads a bare name / it reads the subject's lo, so it reads whatever the dropped copy's lo is: text

## D6/C2: params that aren't an object (4)

- M Rust for / count of a position of the params, with params as an empty list / fails as unusable and names what it can't read
- S for / every on a position of the params with nothing after it, with params as a number / fails as unusable and names the params and what they are
- M Rust messages / a root in a count of beside a list that is missing, when the params aren't an object / says the params, or the root, once, and then the list, and a check that doesn't read the params fails with the worst cause of what it says
- M Rust messages / a root in a whose beside an empty list, when the params aren't an object / says the root, and then the empty list where it fails, and a check that doesn't read the params fails with the worst cause of what it says

## subject name read with a dot (4)

- M Rust in / count of and sum of read the field named like a part and list it with the dot / lists the field with the dot and the part without it, and names the item of the part
- S Rust subject_name / a count of a field named like the subject, written with a dot / a field that isn't a list or an object is said once, as the walk says it
- S subject_name / a count of a field named like the subject, written with a dot / a missing field is named with its dot in the inputs and in the message
- S subject_name / a count whose reads a field named like the subject and a part / an item that isn't an object is named with the dot of the field the whose reads

## D4: a part that is a list in a whose doesn't give the row its cause (3)

- M Rust messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is empty
- M Rust messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is missing
- M Rust messages / a part that is a list, read in a whose beside a list that can't be read, is said first and then the list, and the row takes the part's cause when it is the worst / a list that is null
