# #688: cases left for a later PR

Julien decided to narrow PR 2. These cases now pin what the Rego engine gives today, not the decided shape. `spec/OPEN.md` lists them under "Differs from the decisions", and every one is in `engines/rust/known-failures.txt`.

## D2 plain bugs (a) and (b): a position or a first item of a list (8)

- messages / a subject read at the position of a list of the input / says which item of the list is missing
- messages / a subject read at the position of a list of the input / names the list when it is missing
- messages / a subject read at the position of a list of the input / says what the list is when it isn't a list or an object
- messages / a subject read from the first item of a list of the input / says the first item is missing when the list is empty
- messages / a subject read from the first item of a list of the input / says the list is missing
- sentences / list positions with more than 15 digits / aren't numbers in the policy, so they're written correctly in from, a sentence and a for line
- subject_name / every on a position of region / names the item and the list it came from
- subject_name / the subject name is read in every position of a one-line check on a list subject / a list subject is walked, counted and summed as a field that holds the list would be

## Decisions 1 and 3: a list in the middle of a name, or a subject that is a list, read on the right of a phrase (6)

- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / each item's value is listed with its location, and a part keeps its tag
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item with no name is listed as null, at the item
- list_items / a list in the middle of a name, or a part that holds a list, read on the right of a list phrase, is listed as a plain check lists it / an item whose name is null is listed as null, at the name
- list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is null is listed as null, at the item, and fails as unusable
- list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is a number is listed as null, at the item, and fails as unusable
- list_starts / a name that walks a subject that is a list, read on the right of a list phrase, is listed as a plain check lists it / an item that is a list isn't read into, is listed as null, at the item, and fails as unusable

## D4 and C4: a root on the right of the phrase beside a list that can't be read (6)

- messages / a root on the right of the phrase that is missing, beside a list that can't be read, is said first and then the list, with the worst cause / a list that is null
- messages / a root on the right of the phrase that is missing, beside a list that can't be read, is said first and then the list, with the worst cause / a list that is missing
- messages / a root on the right of the phrase of the wrong type, beside a list that can't be read, is said first and then the list / a list that is missing
- messages / a root on the right of the phrase of the wrong type, beside a list that can't be read, is said first and then the list / a list that is text
- messages / a root on the right of the phrase and a root in a whose, both missing, beside a list that can't be read, are all said, then the list / no params and no list
- messages / a root on the right of the phrase and a root in a whose, both null, beside a list that is null, are all said, then the list / both params and the list null

## C7 second bug: the roots of a for line's whose in a list entry (5, the `for` rows only)

- messages / two roots in one relative clause that can't be read / names every root that failed, in the order the sentence reads them
- messages / two roots after is in that aren't lists, in one relative clause / names both, in the order the sentence reads them, on a list with items
- messages / two roots after is in that aren't lists, in one relative clause / names both on an empty list too
- messages / two roots in one relative clause that fail in different ways / names every root that failed, whatever its cause, in the order the sentence reads them
- messages / two roots in one relative clause that fail in different ways / names them in front of what the items say when an item fails in a worse way

## B9 and C3: the items after a root, on the `plain` row of a for case (4)

- for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with an item of the part without the name
- for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with names of more than one kind
- for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item without v, with a null part
- for / an item's own problem on a for line is said after a root of its whose that can't be read, even when it fails no worse than the root / an item that is null, with an item of the part without the name

## Narrowed rows of cases that still fail on other rows

The `for` rows of the five C7 cases above are pinned, and their `count` and `every` rows still fail: the `$params` root of the `whose` isn't on the assertion's inputs, and a `count of` item lists a read its message doesn't reach. "messages / a root in a whose that is missing, beside a list in a list whose inner lists can't be read" (B9) fails for the same root. "list_items / an any_of option that reads a field of a subject that is a list outside what it reads item by item fails on its own" says `the subject is …` in its entry and was left as it is.

## Classified as narrowed, but the case was wrong against a decision (moved to the Rego engine's output, not narrowed)

- list_starts / every, some, count of and sum of walk a subject that is a list / an item that isn't an object fails as not_an_object, and a missing field as absent: decision 3 (a `count of` gets an `item` entry, a `sum of` says every item it can't read).
- walks / an item of a list a whose reads from $input is a root, said worst cause first and then by name / an item of $input.os is null and $params.z is missing, and the case "…, with a null param": decision 35 (roots of one sentence, worst cause first); the `count` row now says what the `every` row of the same case already said.
