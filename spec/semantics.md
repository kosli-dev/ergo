# How Ergo turns a policy and an input into a report

Draft 0.3-dev. This file says what a check means, whatever syntax it's written in. [syntax.md](syntax.md) says how a policy is written, its sentences included, how it can be written wrong, and how the report names paths. It covers reading values, causes, every operator of the model, and how requirements, scope, statuses and violations work. Questions the spec hasn't settled are in [OPEN.md](OPEN.md).

Each rule has a name in brackets, like `[present.missing]`. The cases in [`cases/`](cases) list the rules they test, so you can find the cases for a rule and the rule behind a case. An implementation follows every rule here, and where it does something else, it's wrong, whatever `ergo.rego` does.

## Terms

- The **input** is the JSON document being checked.
- The **params** are a second JSON document the policy can read, or nothing.
- A **subject** is one thing a requirement checks, found in the input by the `from` of the subject definition it names.
- A **check** is one named test in a requirement's `checks`. A condition after `whose` in a subject's `from` line is a check too, called a **filter**.
- A **row** is the result of one check on one subject, or of one check Ergo adds to a requirement.

## The model of a check

A syntax reads each check into this model. Everything below is said in terms of it.

- A **check** has an operator, like `equals` or `every`, and the parameters that operator takes.
- A **path** has a start and a list of steps. It starts at the subject, at the input, at the params, or at an alias given by a subject's `from` or by an enclosing list check.
- A **step** is a key (a string, which reads a key of an object), an index (a whole number from 0 to 9007199254740991, which reads an item of a list), or a ref step (a ref whose value is the key).
- A **value** is a JSON value or a ref.
- A **ref** is a path that starts at the input or the params and whose steps are all keys or indexes.

**[written_wrong]** A check that can't be read into this model is written wrong. The requirement's `$well_formed` row fails with cause `value` and lists what's wrong, and the requirement gets no other row, as [well_formed](#requirements) says. [syntax.md](syntax.md#written-wrong) says what counts as written wrong in a sentence, and [written_wrong.row](syntax.md#written-wrong) how it's reported.

## Reading a path

Reading a path ends in one of these outcomes. Each one except `found` is also a [cause](#causes).

| Outcome         | When                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `found`         | Every step was read, and the value at the end isn't `null`.                                                              |
| `null`          | Every step was read, and the value at the end is `null`.                                                                 |
| `absent`        | A key isn't in its object, an index is past the end of its list, or a step comes after a value that's missing or `null`. |
| `unusable`      | A step comes after a value that can't hold it, or a number can't be read or compared exactly, see [Values](#values).     |
| `not_an_object` | The path reads a field of a subject that isn't an object.                                                                |

**[path.start]** A path starts at the subject, the input, the params or an alias. With no params, a path into the params ends `absent`. Params that are there but aren't an object fail the whole report, as [REFERENCE.md](../REFERENCE.md#params) says.

**[path.not_an_object]** A path with steps that starts at a subject that isn't an object ends `not_an_object`, `null` subjects included, unless its first step is a position. A position reads the subject as a list, as [path.absent](#reading-a-path) and [path.unusable](#reading-a-path) say, so `first of it` ends `absent` on `[]` and on `null`, and `unusable` on `"s"`. A path that starts at a `for` alias is read the same way.

**[path.absent]** A key the object doesn't have ends `absent`, and so does an index past the end of the list. Once a value is missing or `null` partway along, the path ends `absent`, however many steps are left.

**[path.null]** A path whose last step reads `null` ends `null`.

**[path.unusable]** A key on anything but an object, or an index on anything but a list, ends `unusable`. So does any step after a string, number or boolean. So the key `y` on `"x": "a"` and on `"x": [{"y": 1}]` ends `unusable`, and the index `1` on `"x": {"1": "a"}` does too.

**[path.ref_step]** A ref step reads its ref first and uses the value as the key for that step. If the ref ends anything but `found`, the path ends there with the ref's outcome, and a value that can't be a key ends `unusable`.

**[path.field_step]** A field step reads one field of the value bare keys read from at that point, the subject or, inside a `whose` or the phrase of a one-line `every` or `some`, the item, and uses it as the key for that step. A field that's missing ends the path `absent`, a `null` one `null`, and one that isn't a string, a number included, `unusable`. On a subject or item that isn't an object, the path ends `not_an_object`. The step is part of its path, as a `named_by` step is, so in a check that reads two paths, the other path's cause can come first, where a ref that can't be read would decide the cause. The row's `inputs` show the field too, unless it's read on an item. Sentences write such a step as `<path> named by <field>`.

## Causes

Every row has a cause. When a check reads several values, the row takes the first cause in this order:

1. `satisfied`
2. `not_an_object`
3. `ambiguous`
4. `unusable`
5. `absent`
6. `null`
7. `value`

`satisfied` means the row passed. Every other cause means it failed. `value` means everything was read and the values didn't pass. `ambiguous` means a position on a `for` line picked items that tie, see [for.pick](#for), and the other causes are the outcomes of reading a path.

## Values

**[value.equal]** Two values are equal when they have the same type and the same content. Numbers are compared by value, so `1` equals `1.0` and `1e0`. Strings are equal when they hold the same code points. Lists are equal when they have the same length and equal items in the same order, and objects when they have the same keys with equal values. `"1"` doesn't equal `1`, and `[1, 2]` doesn't equal `[2, 1]`.

**[value.ref]** A value that's a ref is read from the input or the params, and the check runs with the value it reads. If the ref ends anything but `found`, the check fails with the ref's outcome as its cause, whatever the subject holds. A ref that reads `null` fails it as `null`, even when the field is `null` too. A value read through a ref is data, so nothing inside it is read as a ref.

**[value.refs]** A check that has refs gets `$refs` in its definition in the report: one entry for each ref, named as in [syntax.md](syntax.md#naming-a-path), with the value it read, or `null`. They're sorted by name.

The spec only covers numbers in the input and the params that a 64-bit float keeps: `0`, or a magnitude between `2.2250738585072014e-308` and `1.7976931348623157e308`, with at most 15 significant digits. Ergo doesn't control the input or the params, so the spec doesn't say what happens to any other number. An implementation compares such a number and writes it in the report as its runtime does, or fails the check as `unusable` when it can't read or compare the number exactly, like one whose exponent is too long to hold. So reports may differ between implementations. `ergo.rego` compares it exactly up to an exponent of ±1e6, see [OPEN.md](OPEN.md#numbers-with-huge-exponents), and copies it as written, while one in JavaScript reads `1e400` as `Infinity` and `1e-400` as `0`.

## What a row shows

**[path.inputs]** A check that reads one path, like `present`, `missing`, `equals` or `in`, has one entry in its row's `inputs`: the path's name and the value read, or `null` when nothing was.

**[row.inputs_once]** A row shows each entry of its `inputs` once. When a check reads the same value twice, like `count of approvals plus count of approvals is 4`, the second read gives no entry of its own when its name, its value and its locations all match the first's, as [location.merged](#where-a-value-was-read) says, and the rest keep their order.

## Where a value was read

**[location]** Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` has `locations`: a list of where Ergo read its value. A location is a JSON Pointer ([RFC 6901](https://www.rfc-editor.org/rfc/rfc6901)) from the root of the input, like `/deployments/3/approved`, or, for a value read from the params, `$params:` followed by a pointer from the root of the params, like `$params:/max_days/high`. List positions count from 0, and a key is escaped as RFC 6901 says, `~` as `~0` and `/` as `~1`. Locations never change `passed`, `cause` or a value. `[]` means no location could be given, like for a read that starts at a name nothing holds.

**[location.start]** A subject's location is where it is in the input, like `/deployments/3`, or `/services/web` for a subject read from an object's values. A subject listed by `named by each of` whose key isn't in the object points at the object. A child subject's starts at its parent's. A path that starts at the subject, a part, an alias or a parent's name starts at that value's location, one that starts at `$input` at the root of the input, and one that starts at `$params` at the root of the params.

**[location.read]** A path's location goes as far as its read went. A path that ends `found` or `null` points at the value it read. One that ends `absent` or `unusable` points at the last value it read: the object without the key, the list too short for the index, or the value that couldn't hold the step. So a pointer never leads to a value Ergo didn't read, and `item 2 of x` on `{"x": {"1": "a"}}` points at `/x`, not at `"a"`. A path that ends `not_an_object` points at the subject. A ref step or a field step adds the key it read. When that key can't be read, the path stops before the step. A path into params that aren't given is `$params:`. An entry that holds one value for each item of a list follows [location.each](#where-a-value-was-read) instead, so a walk or a `count of` on a list that is missing keeps `value: []` and `locations: []`.

**[location.one]** An entry that shows the value of one path, like the entry of [path.inputs](#what-a-row-shows) or of a field step, has one location.

**[location.refs]** An entry in `$refs` has its ref's location, and keeps it when [violations](#violations) adds it to a violation's `inputs`.

**[location.merged]** When a row lists an input once though several checks or filters read it, like an `all_of`, an `any_of`, a `for` line, an `$applies` row or a check that reads it twice ([row.inputs_once](#what-a-row-shows)), reads merge into one entry only when their name, their value and their locations all match. Two reads that print the same name and value but come from different places, like a parent's `b.x` and a child's own `.b.x`, each keep an entry. The entries are sorted by name, then value, then locations.

**[location.each]** An entry that holds a value for each item, like a walk's ([walk.inputs](#every-and-some)) or a list on a `for` line ([for.inputs](#for)), has one location per value, in the same order. A walk that stopped before it walked anything holds `[]` and has no locations.

**[location.worked_out]** An entry whose value Ergo works out, the number of a `count_of`, `sum_of`, `add` or `elapsed` side, has the locations of the entries shown for that side after it, in their order, once each. The `$min_subjects` entry has the location of each subject it counts, in the order of the rows. The `$unique_ids` entry has the location of the id of every subject that shares one, in the order the ids are listed, then of the subjects. The entries of `$well_formed` read the policy and have no locations, and nor do the entries that list problems with the input or the params.

**[location.failed_items]** An entry in `failed_items`, of a check's row or of an `$applies` row, has one location: where its `value` was read, stopping where the read stopped as [location.read](#where-a-value-was-read) says. When the value is the whole item, that is the item, like `/pull_requests/1`. When it is a field of the item, like the title in `every pull_requests.title as t`, or the sort key that tied in `first of owners sorted by name`, it is the field, like `/pull_requests/1/title` or `/teams/0/owners/0/name`. A walk that stopped before it walked anything gives where it stopped. So do the entries of a `for` line's nested `failed_items`: an alias holds the value it was read as, so `m.commits` after `every prs.meta as m` starts at `/prs/0/meta`.

## `present`

`present` takes a path and asks whether the field is there.

**[present.pass]** It passes when its path ends `found`. Any value counts, `""`, `false`, `0`, `[]` and `{}` included.

**[present.missing]** It fails with cause `value` when its path ends `absent` or `null`. Whether the field is there is the question it asks, so "it isn't" is a sound answer, and the cause says so.

**[present.no_params]** On a path into the params, it fails with cause `absent` instead when there are no params. Then the params weren't given at all, so Ergo can't tell whether the field would be there, and a policy run without its params fails instead of ruling every subject out. When the params are an object without the field, it fails with `value` as usual.

**[present.other]** It fails with the outcome as its cause when its path ends any other way: `not_an_object` or `unusable`. A ref step whose ref can't be read keeps the ref's cause too, even `absent` or `null`, because then the field it looks for is unknown, not missing.

**[present.filter]** A `present` filter that fails with cause `value` rules the subject out, whatever the other filters give. Its `$applies` row fails with cause `value`, and the subject gets no other rows. Any other cause fails the requirement, as it does for every filter. **[applies.inputs]** The `$applies` row lists each path its filters read once, sorted by name.

## `missing`

`missing` takes a path and asks whether the field is missing. It's the opposite of `present`.

**[missing.pass]** It passes where `present` would fail with cause `value`: when its path ends `absent` or `null`.

**[missing.fail]** It fails with cause `value` where `present` would pass, so a field that's there fails it whatever it holds, `false` and `""` included. Everywhere else, it fails with the cause `present` would give, so with no params a `missing` check on a path into the params fails as `absent` instead of passing.

**[missing.filter]** As a filter, it rules out a subject whose field is there, with cause `value`, as any filter does.

## `equals`

`equals` takes a path and a value, and asks whether the field equals the value.

**[equals.pass]** It passes when its path ends `found` or `null` and the value read [equals](#values) the value. So a `null` value passes on a field that's there and `null`.

**[equals.fail]** It fails with the path's outcome as its cause when the path ends anything but `found` or `null`, a missing field included, even when the value is `null`. It fails with `null` when the field is `null` and the value isn't. When the field was read, it fails with `unusable` when the field and the value have different types, so `"5"` against `5` can't rule a subject out, and with `value` otherwise. Against a `null` value, a field that was read fails with `value`.

## `in`

`in` takes a path and a list of values, and asks whether the field is one of them.

**[in.values]** The values are a list whose items are values, or a ref to a list. The values all have one type, leaving `null` aside. When the ref reads something other than a list, or the values read through refs have more than one type, the check fails as `unusable`. A list read through a ref is data, so an object in it that looks like a ref is compared as an object.

**[in.pass]** It passes when its path ends `found` and the value read [equals](#values) one of the values.

**[in.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, so a missing or `null` field fails even when the values hold `null`. When the field was read, it fails with `unusable` when its type isn't the type of the values, and with `value` otherwise, an empty list of values included.

## `has_type`

`has_type` takes a path and a `type`, one of `list`, `string`, `number`, `boolean` and `object`, and asks whether the field has that JSON type. It's what the sentence `is a <type>` reads into, see [sentence.phrase.type](syntax.md#phrases).

**[has_type.pass]** It passes when its path ends `found` and the value has the type.

**[has_type.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. A value of any other type fails with `value`, because checking the type is what it's for.

## `not_in`

`not_in` takes a path and a list of values, written like the values of [`in`](#in), and asks whether the field is none of them. It's what the sentences `is not one of` and `is not in` read into, see [sentence.phrase.one_of](syntax.md#phrases).

**[not_in.pass]** It passes when its path ends `found`, the value read has the type of the values, and it [equals](#values) none of them. Any value passes when the list is empty.

**[not_in.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, so a missing or `null` field fails even when the values hold `null`. When the values can't be used, as [in.values](#in) says, or the field has another type than the values, it fails as `unusable`, as `in` does. When the field equals one of the values, it fails with `value`.

## `non_empty_string`

`non_empty_string` takes a path and asks whether the field is a string with something in it.

**[non_empty_string.pass]** It passes when its path ends `found` and the value is a string other than `""`. A string of spaces passes.

**[non_empty_string.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. When the field was read, it fails with `value`, whatever its type, because checking the type is what it's for.

## `empty_string_or_list` and `not_empty_string_or_list`

`empty_string_or_list` takes a path and asks whether the field is `""` or `[]`. `not_empty_string_or_list` asks whether it's a string or a list with something in it. They're what the sentences `is empty` and `is not empty` read into, see [sentence.phrase.empty](syntax.md#phrases).

**[empty_string_or_list.pass]** `empty_string_or_list` passes when its path ends `found` and the value is `""` or `[]`. `not_empty_string_or_list` passes when its path ends `found` and the value is a string with at least one character or a list with at least one item.

**[empty_string_or_list.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`. A value that's neither a string nor a list, like a number, a boolean or an object, fails with `unusable`. Otherwise they fail with `value`.

## `range`

`range` takes a path, a `min` and a `max`, and asks whether the field is a number between them, both included.

**[range.pass]** It passes when its path ends `found`, the value is a number, and `min <= value <= max`, compared by value.

**[range.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, and with `unusable` when the value isn't a number. A number outside the range fails with `value`.

## `matches_any` and `not_matches_any`

`matches_any` takes a path and a list of patterns, and asks whether the field is a string that at least one of them matches. `not_matches_any` asks whether it's a string that none of them match.

**[patterns.syntax]** A pattern is a regular expression in [RE2 syntax](https://github.com/google/re2/wiki/Syntax), run on code points. So there's no lookahead and no backreference. `.` doesn't match a newline, `$` only matches at the very end of the string, and `(?i)` turns on case-insensitive matching. `\d`, `\w`, `\s` and `\b` only know ASCII, as in RE2: `\d` is `0` to `9`, `\w` is those, `A` to `Z`, `a` to `z` and `_`, `\s` is tab, line feed, form feed, carriage return and space, and `\b` is where a `\w` character meets a character that isn't one, or the start or end of the string. `\D`, `\W`, `\S` and `\B` are the opposites. So `^\d$` doesn't match `٣`, and `^a\b` matches `aé`. `(?i)` still folds case, so `(?i)^\w$` matches `ſ`, a long s. A pattern isn't anchored: `svc_` matches `my_svc_account`.

**[patterns.list]** The patterns are a list whose items are strings or refs, or a ref to a list. When a ref reads something other than a list, or a pattern that isn't a string or isn't valid, the check fails with `unusable`.

**[patterns.pass]** `matches_any` passes when its path ends `found`, the value is a string, and at least one pattern matches it. `not_matches_any` passes when its path ends `found`, the value is a string, and no pattern matches it. So with no patterns, `matches_any` always fails and `not_matches_any` passes on any string.

**[patterns.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`, and with `unusable` when the value isn't a string. Otherwise they fail with `value`.

## `includes` and `excludes`

`includes` takes a path and either one value or a list of values. With one value, it asks whether the field is a list that contains it, and with a list, whether it contains every one of them. `excludes` asks whether the field is a list that contains none of them.

**[contains.value]** One value is one value, so a list given as the value is looked for as a list inside the field. A list of values has at least one item, and its items are values. It can be a ref, and when the ref reads something other than a non-empty list, the check fails as `unusable`, because an empty list would pass every field. The values all have one type, leaving `null` aside, and so do the field's items and the values together, so `1` is never looked for in a list of strings. When values read through refs have more than one type, the check fails as `unusable`.

**[contains.pass]** `includes` passes when its path ends `found`, the value is a list, and an item [equals](#values) the value, or with a list of values, when each of them equals an item. `excludes` passes when its path ends `found`, the value is a list, and no item equals the value, or any of the values. So an empty list fails `includes` and passes `excludes`.

**[contains.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`, and with `unusable` when the value isn't a list, a string or an object included, or when its items and the values have more than one type, leaving `null` aside. Otherwise they fail with `value`. An empty list holds no type, so it fails `includes` with `value`.

## `compare`

`compare` takes two sides, `left` and `right`, and a comparison: `eq`, `ne`, `gt`, `gte`, `lt` or `lte`. A side is a path, so it compares two fields of the same subject. [Counts and sums in sentences](#counts-and-sums-in-sentences) says what else a side can be.

**[compare.pass]** It passes when both paths end `found`, the two values have the same type, and `left cmp right` holds. `eq` and `ne` use [equality](#values) and work on any type. `gt`, `gte`, `lt` and `lte` only work on two numbers, compared by value. Two strings aren't ordered, because a number held as a string, like `"9"`, would come after `"80"` as text. [compare.alphabetical](#compare) orders strings, and [compare_time](#compare_time) orders times.

**[compare.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, so two `null` fields fail as `null`, even with `eq`. When both were read, it fails with `unusable` when their types differ, even with `ne`, and when `gt`, `gte`, `lt` or `lte` is used on anything but two numbers, two strings included. Otherwise it fails with `value`.

**[compare.inputs]** Its row has two entries in `inputs`, `left` then `right`.

**[compare.text]** Two more comparisons, `starts_with` and `ends_with`, are what the sentences `starts with` and `ends with` read into, see [sentence.phrase.starts](syntax.md#phrases). They pass when both values are strings and the left one starts, or ends, with the right one, code point by code point. Anything but two strings, two numbers included, fails with `unusable`, and the rest is as [compare.fail](#compare) says.

**[compare.alphabetical]** Two more comparisons, `alphabetically_before` and `alphabetically_after`, are what the sentences `is alphabetically before` and `is alphabetically after` read into, see [sentence.phrase.alphabetical](syntax.md#phrases). They pass when both values are strings and the left one comes before, or after, the right one, compared code point by code point, so `"Z"` comes before `"a"` and `"！"` (U+FF01) before `"😀"` (U+1F600). Equal strings fail both. Anything but two strings, two numbers included, fails with `unusable`, and the rest is as [compare.fail](#compare) says.

**[compare.list]** Eight more comparisons, `in`, `not_in`, `includes`, `excludes`, `includes_all`, `excludes_all`, `matches_any` and `not_matches_any`, are what the sentences `is one of`, `is not one of`, `contains`, `does not contain`, `contains all of`, `contains none of`, `matches` and `does not match` read into when what follows is a field, see [sentence.phrase.field](syntax.md#phrases). Each means what [`in`](#in), [`not_in`](#not_in), [`includes` and `excludes`](#includes-and-excludes) and [`matches_any` and `not_matches_any`](#matches_any-and-not_matches_any) say, with the right side's value as their value, values or patterns, and the check as a whole passes and fails as they say, so `compare.pass` and `compare.fail` don't apply to them. The right side decides first. When it ends anything but `found`, the row fails with that outcome, whatever the left side is. When it was read but can't be used, it fails with `unusable`, again whatever the left side is: a value that isn't a list after `in`, `not_in`, `includes_all`, `excludes_all`, `matches_any` or `not_matches_any`, a list whose values have more than one type after `in`, `not_in`, `includes_all` or `excludes_all`, an empty list after `includes_all` or `excludes_all`, and patterns that aren't all valid regular expressions. Anything that was read is usable after `includes` and `excludes`. Only then are the left side's outcome and type looked at, as the rules named above say. The row has the two entries of [compare.inputs](#compare).

## Counts and sums in sentences

A side of `compare` can also be `count_of` or `sum_of`, each with a path, `whose`, a list of basic checks, and `text`, the words that wrote it, or an `elapsed` side, see [tally.elapsed](#counts-and-sums-in-sentences). `add` can take `text` too, and `count_of`, `sum_of` and `elapsed` among the sides it adds up. They're what `count of`, `sum of` and `plus` read into, see [sentence.derived.count](syntax.md#derived-values).

**[tally.walk]** The path is walked as [walk.lists](#every-and-some) says, except that an empty list adds nothing instead of failing. A list that's missing, `null` or not a list fails the side as `absent`, `null` or `unusable`, and so does a path where no step walks a list, as [walk.lists](#every-and-some) says. On a subject that isn't an object, with a path that starts at the subject, it fails as `not_an_object`, and so does an item that isn't an object when the path goes on into it, as [walk.flaws](#every-and-some) says for `every`. A ref the side reads that can't be used, in its path or its `whose` checks, fails it as `unusable`, and one that's missing or `null` fails it as `absent` or `null`, even when the list is empty.

**[tally.whose]** The `whose` checks read from each item of the innermost list walked, as [walk.items](#every-and-some) says. An item is left out when one of them fails with `value`, or when a `present` check finds the field missing. An item one of them can't decide fails the side with its cause, and its path isn't read, so only that cause counts.

**[tally.count]** `count_of` is the number of values the path ends at in the items left in, `null` included. A value that's missing fails the side as `absent`.

**[tally.sum]** `sum_of` adds up the values the path ends at in the items left in, and is 0 over none. A value that's missing fails the side as `absent`, `null` as `null`, and anything else that isn't a number as `unusable`. Numbers are added as decimals, so `0.1` and `0.2` add up to `0.3`, and so are the sides of an `add` with `text`. Take every number added, a count, a sum or an elapsed number included, and the result, and let p be the most decimal places any of them has, counted on the value, so `1.50` has 1, `1e2` has 0 and `1e-7` has 7. p must be at most 15, and each of them times 10^p must be a whole number below 10^15 in absolute value, the result included. If not, the side fails as `unusable` and its entry is `null`. That's stricter than 15 significant digits for big round numbers: `1e20` plus `1e20` fails, though the result has one significant digit. It fails closed, and every implementation can decide it exactly.

**[tally.elapsed]** An `elapsed` side has `unit`, which is `seconds`, `minutes`, `hours`, `days` or `weeks`, two paths, `elapsed_from` and `elapsed_to`, and `text`. It's the time from the first path to the second, in that unit: the nanoseconds between them divided by 1, 60, 3600, 86400 or 604800 times 10^9, rounded down to 6 decimal places. Working in whole nanoseconds and rounding down keeps the number the same in every runtime. Both paths must end `found` as [time.format](#compare_time) says, both RFC 3339 strings, compared as the instants they name, both dates, read as midnight UTC on that day so that the time between them is whole days, or both numbers from -9000000000 to 9000000000, read as seconds and rounded to the nearest microsecond. Two times in different formats fail the side as `unusable`, as [time.fail](#compare_time) says, and so does anything else. A path that ends anything but `found` fails the side as [tally.fail](#counts-and-sums-in-sentences) says. When `elapsed_to` is before `elapsed_from` the side has no number and the check fails as `value`. Its row shows the entry named after `text`, then one for each path, `elapsed_from` first, each filled as a path in `compare` is. An `elapsed` side can be a side of `compare`, among the sides of an `add`, or in the `whose` checks of a `count_of`, a `sum_of` or an `every`, where an item it fails for with `value` is left out.

**[tally.between]** `is between` after a `count_of`, `sum_of`, `add` or `elapsed` side reads the number the side works out, and passes when `min <= number <= max`, compared by value, as [range.pass](#range) says for a field. Outside the range it fails with `value`, and the bounds are as [range.bounds](#range) says. A side that fails gives the check its cause, as [tally.fail](#counts-and-sums-in-sentences) says, and the row shows what [tally.inputs](#counts-and-sums-in-sentences) says.

**[tally.fail]** A side that fails gives the check its cause, as a path that ends anything but `found` does in [compare.fail](#compare), and the worst one when both sides fail. An `add` fails as its worst operand does.

**[tally.inputs]** For each side that's worked out, the row shows an entry named after its `text`, holding the number, or `null` when the side failed. For a `count_of` or a `sum_of`, the list it walked comes next, named and filled as [walk.inputs](#every-and-some) says. For an `add`, each side it adds up comes next, as if it stood alone. The left side's entries come before the right side's, and an entry already shown isn't shown again ([row.inputs_once](#what-a-row-shows)), so in `count of findings whose severity is "high" is at most count of findings` the right side shows only its number. The paths a `whose` reads from outside the item, a parent's, `$input`'s or the subject's own part, come after those two, sorted by name, as [walk.inputs](#every-and-some) says. A path among them whose `named by` reads a field of the item shows the part before the name and not the path it names, like `artifact.nums` for `count of rows whose n is at least artifact.nums named by key`, as [walk.inputs](#every-and-some) says.

## `compare_time`

`compare_time` takes the same parameters as `compare`, and compares two times.

**[time.format]** A time is a number, an RFC 3339 string or a date. A date is a string `YYYY-MM-DD` with nothing after it, and the date and year follow the same rules as in an RFC 3339 string. An RFC 3339 string has the form `YYYY-MM-DDTHH:MM:SS`, then optionally `.` and one or more digits, then `Z` or an offset `+HH:MM` or `-HH:MM`. The `T` and `Z` are uppercase. The date must exist, so `2024-02-30` and `1900-02-29` don't. The hour is 00 to 23, minutes and seconds 00 to 59, and the offset 00:00 to 23:59. The year, as written, is 1678 to 2261. Only the first nine digits of the fraction count. Any other string isn't a time.

**[time.pass]** It passes when both paths end `found`, both values are RFC 3339 strings, both are dates or both are numbers, and `left cmp right` holds. RFC 3339 strings are compared as the instants they name, so `2024-01-01T01:00:00+01:00` equals `2024-01-01T00:00:00Z`. Dates are compared as days, so `2024-01-31` is before `2024-02-01`. Numbers are compared by value, with no unit attached.

**[time.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, and with `unusable` when the values aren't two times in the same format, a number and a string included, and a date and an RFC 3339 string too, even one at midnight, because a date doesn't say in which time zone it starts. Otherwise it fails with `value`.

## `any_of`

`any_of` takes named options, each a list of checks that must all pass, and passes when one of its options does.

**[any_of.pass]** It passes when every check of at least one option passes.

**[any_of.cause]** Each option that fails has a cause: `value` when one of its `present` checks found its field missing, and otherwise the first, in the order of [causes](#causes), among its checks, or `value`. The row takes the first among its options.

**[any_of.refs]** A ref that ends anything but `found`, as [value.ref](#values) says, fails the checks that read it, and so their option, but not the others: when another option passes, so does the row. A ref that reads the wrong kind of value for its check, like a `values` ref that isn't a list, fails the row as `unusable`, even when another option passes.

**[any_of.inputs]** The row shows every path any option reads, once each, sorted by name. For an `every` or `some` in an option, that's its list, with the whole items, and the names it reads.

## `all_of`

`all_of` takes `checks`, a list of basic checks, and `assertions`, the text of each one. It's what a check written as several sentences reads into, joined with `and` or listed under `assert`, see [sentence.assert.list](syntax.md#the-shape-of-a-sentence). It's one check, with one row per subject, because its sentences say one thing together, and a policy that wants a row for each writes them as separate checks.

**[all_of.pass]** It passes when every one of its checks passes.

**[all_of.cause]** When it fails, its cause is the first, in the order of [causes](#causes), among the checks that failed.

**[all_of.inputs]** The row shows every path any of its checks reads, once each, sorted by name.

**[all_of.failed_assertions]** The row also has `failed_assertions`: one entry for each check that failed, in the order they were written, with its `assertion` and its own `cause`. It's `[]` when the check passes, and the row has no `failed_items`, even when one of the sentences walks a list. When a ref one of them reads can't be used, that one is listed with cause `unusable` and the others with their own causes.

## `every` and `some`

`every` and `some` take a path, a basic check, `whose`, a list of basic checks, and `if_any`. They're what the sentences `every <path> …` and `some <path> …` read into, see [sentence.every.walk](syntax.md#every-some-and-whose).

**[walk.lists]** The path is read one step at a time. At a step where at least one value read so far is a list, and the step isn't a position, every one of those values is walked: each of its items goes on along the path in its place. At that step, a value that's missing, `null` or not a list fails as `absent`, `null` or `unusable`, and an empty list fails as `value`, unless `if_any` is true, when it's skipped. After the last step, a value that's a list is walked the same way. A path where no step walks a list fails at the first value along it that isn't an object, with `absent` when it's missing, `null` when it's `null`, and `unusable` otherwise, or at the value the path ends at, as `unusable`, when every value along it is an object. That place is the one entry in `failed_items`, so a lone list that's `null` fails as `null`, as it does when another item's list is walked.

**[walk.items]** The items of the innermost list walked are what the check is about. Each one is checked on its own: the `whose` checks and the basic check read their paths from the item, and the basic check reads the rest of the path, after the item, as its own. An item is undecided when a `whose` check fails with any cause but `value`, even when another one fails with `value`, as a filter that can't decide fails the requirement (see [scope.unreadable](#scope)). Otherwise it's left out when a `whose` check fails with `value`.

**[walk.every]** `every` passes when nothing failed while walking, no item is undecided, every item left in passes, and at least one item is left in, or `if_any` is true. Otherwise it fails with the first, in the order of [causes](#causes), among what failed, or with `value` when the only problem is that no item was left in.

**[walk.some]** `some` passes when at least one item left in passes. Otherwise it fails with the first, in the order of [causes](#causes), among what failed while walking, the undecided items and the items that failed, or with `value` when there were none.

**[walk.flaws]** When a ref the check reads, in its path, its `whose` checks or its phrase, can't be used, or the input or params hold something JSON can't, the check fails as `unusable` and `failed_items` is `[]`, whatever the items hold, as a plain check does. On a subject that isn't an object, with a path that starts at the subject, it fails as `not_an_object`. When a ref step in its path can't be read, it fails with the ref's cause, and its `inputs` hold `[]`.

**[walk.inputs]** The row's `inputs` has one entry, named after the path with `[]` after each list walked, like `pull_requests[].commits[].signed`, holding the value each item's path ended at, in order, `null` where it ended missing. The items `whose` leaves out are there too. Where the walk stopped early, `[]` only follows the lists it walked. The row also lists each path its check or its `whose` reads from outside the item, as a plain check does, once each: a parent's like `artifact.owner`, one of `$input`, and the subject's own part, named like the plain form names it, `w`, with its `part` tag ([parts.tag](#parts)). The walk's own entry is sorted with these, by name, so a parent that sorts before the list comes first. A path with a `named by` is listed as a plain check lists it, like `artifact.map named by artifact.key`. A `for` alias's value is never listed. A path whose `named by` reads the item or an alias isn't listed as a whole, since it changes with each item, but the part before the name is, like `artifact.nums` for `some rows.n is at least artifact.nums named by key`, once each, whether the check is on a `for` line or in a `from` line's conditions. When that part walks a list, like `artifact.ls.m` in `every artifact.ls.m named by key`, nothing of it is listed, as [for.inputs](#for) says. A `$params` path isn't an entry of `inputs`, and stays in the check's `$refs` where it already is ([value.refs](#values)). A bare name on the right that isn't a part's alias, and a name written with a dot like `.w`, is the item's field and isn't listed.

**[walk.failed_items]** The row's `failed_items` lists what failed, in path order, when the check fails, and is `[]` when it passes: each value that failed the basic check, with `path` the field, `item` the item and `value` what the path ended at, or `null`; each undecided item, with `path` the field of the first `whose` check that couldn't decide, and `value` what that path ended at, or `null`; and each list that failed while walking, with `path` and `item` both the list. An item that `whose` left out isn't listed.

**[walk.failed_items.side]** A `whose` check that compares two sides names one of them: the side that wasn't read, or the left side when neither was read or both were. A side is read when its path ends `found`, so a path that ends `absent`, `null`, `unusable` or `not_an_object` isn't. A `count of` or `sum of` side has the path of its list, and is read only when that path ends `found` on a list, so with `{"kids": 5}` the side named is `count of kids`, with path `kids`. An `add` or `elapsed` side has the first of its paths that wasn't read, or its first path when all were, and a `count of` or `sum of` inside an `add` is read only when its list is a list, as on its own. A side that reads outside the item, a `$params` or `$input` path, a part of the subject or a field of a parent subject, is named by its own path, written as in `inputs`, like `$params.min`, `w` or `art.q`, with its own location, not as a path inside the item. So `whose lo is at least hi` names `hi` for `{"lo": 1}`, `lo` for `{"hi": 1}` and for `{}`, and `lo` for `{"lo": "x", "hi": 1}`, and `whose count of kids is at least min` names `min` for `{"kids": [1]}` and `kids` for `{"min": 1}`.

## `for`

`for` takes `items`, one or two, each with `every` or `some`, a path, `whose`, `if_any` and an alias, and `checks` and `assertions`, as `all_of` does. It's what a check with a `for` line reads into, see [sentence.for.line](syntax.md#the-for-line).

**[for.walk]** Each item's path is walked as an `every` or `some` path is, see [walk.lists](#every-and-some), and its alias stands for the value the path ends at in each item of the innermost list walked. The `whose` checks read from that item, and an item is undecided or left out as [walk.items](#every-and-some) says. An item `whose` keeps, whose path ends at a value that's missing or that can't be read, fails as `absent` or `unusable`, or as `not_an_object` when the item isn't an object, `null` included, and the path goes on into it, without its checks being run. The second item's path and its `whose` checks can start at the first item's alias, and then it's walked again for each item of the first list.

**[for.pick]** An item with a position walks its path as [for.walk](#for) says, with an empty list allowed along the way, and keeps the items its `whose` keeps. An item the `whose` can't decide fails the check with its cause, and nothing is picked. With `sorted by`, the field is read on each item kept: numbers are ordered by value, RFC 3339 times by the moment they name, and dates by day, as [time.pass](#compare_time) says. With `alphabetically`, the field has to be a string, and strings are ordered code point by code point, as [compare.alphabetical](#compare) says. A field that's missing fails its item as `absent`, a `null` one as `null`, one on an item that isn't an object as `not_an_object`, and anything else, without `alphabetically` a string that isn't a time or a date included, as `unusable`. When the fields mix numbers, RFC 3339 times and dates, the items of the first kind in that order are kept and the others fail as `unusable`, so with numbers and times the times fail. When any item fails, nothing is picked. The position counts from 1, from the start of that order or from its end with `last of` and `from last`. Without `sorted by`, the order is the order the walk reads the items. A position past the end, an empty list included, fails the check as `absent`, and there's no item to list in `failed_items`. When another item's field equals the picked item's, it fails as `ambiguous`, and each item with that value fails as `ambiguous` too, with the value as its `value`. Otherwise the alias stands for the picked item and it is tried as [for.try](#for) says, as an `every` over that one item. A picked item that doesn't start at the first item's alias fails the check the same way whether it's written first or second. When its `whose` reads the first item's alias, it's picked again for each item of the first list. An item of the first list that picks nothing fails the check as `absent` and isn't listed in `failed_items`, and one whose pick fails another way is listed, with that failure under it.

**[for.try]** The checks read the subject, with each alias standing for its item. With one item, an item passes when all the checks pass. With two, an item of the first list passes when the second item passes for it, as [walk.every](#every-and-some) or [walk.some](#every-and-some) says, where an item of the second list passes when all the checks pass. A failed item's cause is the first, in the order of [causes](#causes), among the checks that failed, or what failed in the second item's walk.

**[for.named_by]** A path with a `named_by` step reads the key that the step's alias holds for the item being tried, as a ref step reads a key from the params. When the alias holds `null`, the check fails as `null`, and when it holds anything else that isn't a string, a number included, as `unusable`. The alias has to be given before it's used: in the `assert` lines, or in a later item's path or `whose`. Sentences write such a step as `<path> named by <alias>`.

**[for.pass]** The check passes or fails as the first item does, by [walk.every](#every-and-some) or [walk.some](#every-and-some), with its items judged as [for.try](#for) says.

**[for.inputs]** The row shows each item's list once, named after its path with `[]` after each list walked, holding the values its alias stands for, and the inputs the checks would show on their own, leaving out paths that start at an alias, once each, even when no check was run, all sorted by name. A second item that starts at the first item's alias is named with that alias, like `pr.approvers[]`, and one that starts at a parent's name is named with that name, like `artifact.map named by k[]`, and both hold, in order, the items of every list they walked under the items the first item kept. What lies under an item the first item's `whose` leaves out, or can't decide, was never read, so it isn't shown. The first item's own entry still holds every item of its list, those its `whose` leaves out included, as [walk.inputs](#every-and-some) lists them. A picked item is named where it is in the input, like `item 1 of commits`, and holds the item. When nothing is picked, the list is shown as for any item, and so is the second item's list when the first list is empty, even when its `whose` reads the first item's alias. Paths that start at an alias aren't shown, but a path that starts at a parent's name is, like `t.x`, with the parent's value, as a check without a `for` line shows it. A path that reads through an alias further on, like `shas named by persona`, shows the part before the name, `shas`. An `every`, `some`, `count of` or `sum of` through an alias doesn't show the values it reads through the alias, or a count's number, but does show the part before the name, like `artifact.map` in `some artifact.map named by k is at least 1`, unless that part walks a list, like `artifact.ls.m` in `every artifact.ls.m named by k is at least 1`, where nothing of it is shown because it would hold a value for each item, and the parent values its check, its right side or its `whose` reads, also when it reads them through an alias, like `artifact.nums` in `some rows.n is at least artifact.nums named by k`, and a `count of` or `sum of` whose own list doesn't start at an alias shows that list, like `artifact.people[]` in `count of artifact.people whose name is c.author is at least 1`.

**[for.failed_items]** When the check fails, `failed_items` lists the first item's failures, or a picked item's when [for.pick](#for) picks nothing, in path order, as [walk.failed_items](#every-and-some) does, and it's `[]` when the check passes. A failed item has `path` and `item` both the item, like `item 2 of pull_requests`, and `value` what its alias stands for, or `null` when that's missing or can't be read. Each entry also has `failed_assertions`: the sentences that failed for that item, in the order written, each with its cause. With two items, that's the first, in the order of [causes](#causes), among the causes it failed with for the second list's items. It's `[]` when no sentence was checked for it, because a `whose` couldn't decide, a list failed while walking, or `whose` left nothing in, and on the entry of a list that failed while walking. An item of the first list isn't listed when the second item's position picks nothing for it.

**[for.second_items]** With two items, each entry in `failed_assertions` for a sentence that reads the second item's alias also has `items`: the items of the second list that the sentence failed for, in path order, each with `item`, its name, and `cause`, the cause it failed the sentence with. An item is named like `item 2 of commits`, or with the first item's alias when the second item starts at it, like `item 1 of pr.approvers`. An item of the second list that failed before any sentence was checked for it isn't listed. A sentence reads the alias when a path in it starts at the alias, a `whose` included, or has a step `named by` it. A quoted string, like `"$commit"`, doesn't.

**[for.failure_inputs]** Each entry in `items` of [for.second_items](#for) has `inputs`, and so does an entry in `failed_assertions` that has no `items`. They are the entries the sentence would show in its own row's `inputs` on that item, or on that pair of items for an entry of `items`: the same `name`, `value`, `locations` and, where a row has it, `part`, as [path.inputs](#what-a-row-shows), [compare.inputs](#compare) and [tally.inputs](#counts-and-sums-in-sentences) say, with each alias named as the sentence writes it, like `approver.timestamp` or `commit.files[]`. The entries of any other sentence with two sides, like a comparison, `is in`, `contains` or a count, keep the order of its own row, its left side and then its right side ([compare.inputs](#compare), [tally.inputs](#counts-and-sums-in-sentences)), and aren't sorted by name. An `every` or a `some` lists the entries that start at an alias first, sorted by name, and then the rest, sorted by name as [walk.inputs](#every-and-some) says. So `some rows.n is at least x.v` lists `x.v` before `rows[].n`, and `count of rows is at least m` lists `count of rows`, `rows[]` and then `m`. The order for a walk whose `whose` reads something outside the item is [still open](OPEN.md#where-ergorego-and-the-rust-port-differ). A value the sentence reads twice is listed once, and entries with the same name are ordered as [row.inputs_once](#what-a-row-shows) and [location.merged](#where-a-value-was-read) say. A path that starts at an alias starts at the location that alias was read at, as [location.failed_items](#where-a-value-was-read) says, and goes as far as its read went, as [location.read](#where-a-value-was-read) says, so a read that stops early has `value: null` and the location where it stopped. A `count of` on an empty list gives the count `0`, the list `[]` and no locations. A sentence that doesn't read the second item's alias reads the same for every item of the second list, so its entry shows what it read on the item of the first list that the entry belongs to. A `named by` that names an alias adds no entry for it, because the item's `value` holds it. Every sentence that failed has `inputs`, however many items failed, and they never change `passed`, `cause` or an item's name.

**[for.second_failures]** With two items, a failed item of the first list also has `failed_items` when the second item failed for it before any sentence was checked, and leaves it out otherwise. It lists those failures of the second item, in path order, as [walk.failed_items](#every-and-some) does, with `path` and `item` both named as in [for.second_items](#for): an item a `whose` couldn't decide, or whose path ended at a value that's missing or can't be read, with the item as both and `value` what its alias stands for, or `null`; a list that failed while walking, missing, `null`, not a list or empty, with the list as both; and a path whose ref step can't be read, with the path as both and `value` `null`.

**[for.shared_failures]** When the second item doesn't start at the first item's alias, some of what [for.second_failures](#for) lists is the same for every item of the first list: a list that failed while walking and a path whose ref step can't be read, and, when none of the second item's `whose` checks reads the first item's alias, the items that can't be read or that a `whose` couldn't decide. Each of those is listed once in the row's `failed_items`, with `failed_assertions` `[]`, instead of under each item of the first list, also when the second item has a position and its `whose` reads the first item's alias. An item of the first list that failed only because of them isn't listed, and one that is listed has as its cause the first, in the order of [causes](#causes), among the causes of its sentences and of what's still in its `failed_items`. The row's cause doesn't change.

**[for.flaws]** When a ref the check reads can't be used, or the input or params hold something JSON can't, it fails as `unusable` and `failed_items` is `[]`, as [walk.flaws](#every-and-some) says. On a subject that isn't an object, with an item's path that starts at the subject, it fails as `not_an_object`. An item of the innermost list walked that isn't an object, `null` included, fails as `not_an_object` when the item's path goes on into it, as `every` does: with `t` holding `["a"]`, `for: every t.k as x` fails `item 1 of t` as `not_an_object`. That holds with a position, with `some`, and for a second item whose path reads into the first item's name. When a ref step in the first item's path can't be read, it fails with the ref's cause, `failed_items` is `[]`, and that path's input holds `[]`. In the second item's path, the first list's item fails with the ref's cause instead, and the path is listed as [for.second_failures](#for) and [for.shared_failures](#for) say.

## Requirements

A policy has two sections. `subjects` defines each kind of subject once, and `requirements` says what must be true of them. A subject definition has a way to find its subjects (`from`), which can end with filters after `whose`, and a path to each subject's id (`identified_by`). A requirement names one subject definition with `subject`, and has `require`, `min_subjects` and checks. It can also have a `description` and `meta`, which Ergo copies into the report and never reads, and so can the policy.

**[requirement.subject]** A requirement checks the subjects of the definition it names, with its own rows. Several requirements can name the same definition. A requirement that names none, or one that isn't in `subjects`, is written wrong, so its `$well_formed` row fails. The name of the definition is the `type` in each row's `subject`.

**[subjects.from]** A subject definition's `from` is a path into the input. When it ends `found` on a list, each item is a subject, in list order. When it ends `found` on an object, that object is the only subject. With no steps, it reads the whole input. Anything else gives no subjects, and the requirement's `$min_subjects` row fails with the path's outcome, or with `unusable` when it read something that's neither a list nor an object, a `null` input included as `null`. That holds even with `min_subjects: 0`, because that's what a typo in `from` looks like. A `from` line with `named by each of` still makes a subject of each key when its path can't be read, as [subjects.sentence](#requirements) says, unless it's a child subject whose parent isn't an object ([subjects.chain.not_an_object](#requirements)).

**[subjects.no_from]** A subject definition without `from`, or with nothing at all, `null` in YAML, reads the input field named like the subject, as `from: <name>` would. So `artifact:` alone reads `artifact`. `from: $input` reads the whole input.

**[subjects.sentence]** `from` is a string, read as a `from` line (see [sentence.subject.from](syntax.md#subjects)), and `identified_by` a string, read as a path. A `from` or an `identified_by` written any other way, like a list, is written wrong (see [policy.old_fields](syntax.md#policies)). A `from` line's path reads into the input, `named by` reads a key the way a ref step does, and `named by each of` makes each key in the list a subject. Each key is a subject even when the object doesn't have it, with the object as its location, so a missing attestation fails its own checks instead of being skipped. When the path before it doesn't end `found` on an object, each key is still a subject, unless it's a child subject whose parent isn't an object, as [subjects.chain.not_an_object](#requirements) says, and `$min_subjects` fails with the path's outcome, or with `unusable` when it read something that isn't an object, a list included, so the requirement is never met, even when every check passes. The list must be a list of strings, or there are no subjects and `$min_subjects` fails as `unusable`, as a ref that reads the wrong kind of value does ([value.ref](#values)), and as `absent` or `null` when the ref reads nothing. Its `whose` conditions are the subject's filters, in the order written, so the `$applies` row joins them with ` and ` in that order, each printed in the report's spelling. A path that starts at `$input` reads into the input as one without it does, and `$input` alone reads the whole input. A path can't start at `$params`. One whose path is another subject's name and nothing more narrows that subject: its subjects are that subject's, kept when they pass that subject's filters and its own, and the `$applies` row prints the conditions of from lines along the chain outermost first. A loop in that chain is named after `from`. A `from` line that starts at a subject whose name is blank, like `" "`, is written wrong, with `" " isn't a subject name`, because no requirement can name that subject either. One that goes on into another subject is a chain, see [subjects.chain](#requirements).

**[subjects.narrow.id]** A subject that narrows another has the id of the one it narrows, so it can't have its own `identified_by`. One that does is written wrong, and `$well_formed` lists `not allowed on a subject that narrows another` under `subjects.<name>.identified_by`.

**[subjects.chain]** A `from` line whose path starts at another subject's name and goes on, like `artifact.pull_requests`, or ends there and goes on with `named by each of`, like `artifact named by each of $params.keys`, makes a child subject: it reads the rest of its path from each subject of that one, the parent. The parent's own `from` and conditions pick its subjects first, and the child's subjects are read from each of them in turn, in the order the parent's are. Every row of the requirement but `$well_formed` carries the id of the parent it was read from under `in`, like `"in": {"artifact": "sha-1"}`, and `$well_formed` has no `in`, since it's about the requirement as written. A check written as a sentence reads the parent by its name, `artifact.name`, and a bare first key that's the parent's name is the parent, not a field, wherever it is in the sentence. A first key written with a dot, like `.artifact.pull_requests` or `.artifact named by each of $params.keys`, is the input field and never the parent ([sentence.path.start](syntax.md#paths)), so that `from` line isn't a child subject. `artifact.x named by each of …` reads the keys inside `x` of each parent. A parent that's written wrong makes the requirement written wrong too, and its problems are listed in `$well_formed`. A parent can itself be a child subject, see [subjects.chain.levels](#requirements). A subject whose from line narrows a child subject is written wrong. So is every subject in a chain that comes back to a subject already in it, through child subjects or through children and subjects that narrow, with `leads to a loop` under its `from`, however deep the chain looks. A `from` or `identified_by` string that can't be read is written wrong, and `$well_formed` lists its problems under `subjects.<name>.from` or `subjects.<name>.identified_by`.

**[subjects.chain.count]** A child subject is counted per parent: each parent gets its own `$min_subjects` and `$unique_ids` rows, with its `in`, so a parent with fewer subjects than `min_subjects` fails on its own row, and ids only need to be unique within each parent, so `pr/7` under two artifacts is fine. With no parent subject at all, there's one `$min_subjects` row and one `$unique_ids` row, with no `in`, and `$min_subjects` fails with `value`, or passes with `min_subjects: 0`, as it does for any subject that finds none. When the parent's `from` can't be read, `$min_subjects` fails with that cause, on one row with no `in`.

**[subjects.chain.scope]** A parent its own conditions leave out gives no rows at all: its child subjects aren't subjects of the requirement, so nothing in them is read, not even their ids. A parent whose conditions can't be decided, like `environment is "prod"` on an artifact without `environment`, gets one `$min_subjects` row, with its `in`, that fails with the condition's cause, even with `min_subjects: 0`, and its child subjects aren't read or checked, so it has no `$unique_ids` row.

**[subjects.chain.not_an_object]** A child subject whose parent isn't an object, `null` included, can't read its `from` path from it, so its `$min_subjects` row fails as `not_an_object`, with `in` up to the parent, as [subjects.chain.levels](#requirements) says, even with `min_subjects: 0`. Nothing below such a parent is read, so a `named by each of` in the child's `from` line makes no subject of its keys, unlike [subjects.sentence](#requirements). This holds for a child of a child and for a child of a subject that narrows another. A parent that is an object without the field still gives `absent`, and one whose field is `null` or isn't a list or an object still gives `null` or `unusable`, as [subjects.from](#requirements) says. A `from` path whose first step is a position reads the parent as a list, as [path.not_an_object](#reading-a-path) says, so it keeps the cause [subjects.from](#requirements) gives. That holds for a position after the parent's name, like `artifact[0].pulls`, `artifact[0] named by each of $params.keys` and `first of artifact named by each of $params.keys`, and for one further in, like `artifact.x[0] named by each of $params.keys`: the position is read, and never dropped. The keys of such a `named by each of` are still subjects, as [subjects.sentence](#requirements) says, and `$min_subjects` fails as `unusable`.

**[subjects.chain.levels]** A chain can be three subjects deep, like artifact, pull request and commit, with `from: '"pull request".commits'`. Each level picks its subjects within each subject of the level above, so a subject out of scope at any level leaves out everything below it. Every row but `$well_formed` carries the id of every ancestor under `in`, like `"in": {"artifact": "sha-1", "pull request": "pr/7"}`. `$min_subjects` and `$unique_ids` count per direct parent, so each pull request gets its own rows. An ancestor whose conditions can't be decided, or whose child subjects' `from` can't be read, gets one `$min_subjects` row that fails with that cause, with `in` up to that ancestor, and nothing below it is read. With no direct parent at all, across every ancestor, there's one `$min_subjects` row with no `in`, as [subjects.chain.count](#requirements) says. A check reads any ancestor, and its parts, by the ancestor's name, like `artifact.name`, `"pull request".title` or `artifact.pr_attestation.approvers`, and a part's alias can't be the name of any ancestor. Each level is written out in Rego, which can't recurse, so a fourth subject is written wrong, with `a chain of more than three subjects isn't supported yet`.

**[subjects.every]** A `from` line with `every` (see [sentence.subject.every](syntax.md#subjects)) reads its path one step at a time, as [walk.lists](#every-and-some) says, with `if_any` true, and each value at the end is a subject, in the order the walk reaches them. A value at the end that isn't a list item must be an object. The subjects don't belong to the items the walk went through: their rows have no `in`, and a check can't read those items.

**[subjects.every.count]** Subjects read with `every` are counted once, across every list, so there's one `$min_subjects` row and one `$unique_ids` row, and ids must be unique across all of them. An empty list adds no subject and fails nothing, so a path whose lists are all empty finds none, and `$min_subjects` fails with `value`, or passes with `min_subjects: 0`.

**[subjects.every.broken]** A place where the walk breaks, a list that's missing, `null` or not a list, or a value at the end that isn't an object, fails `$min_subjects` with the worst cause found, even with `min_subjects: 0`, and the subjects that could be read are still checked. A path where no step walks a list breaks as [walk.lists](#every-and-some) says. The `$min_subjects` row of a subject read with `every` has `failed_items`, sorted by path: one entry for each place the walk broke, with its `path`, its `item`, the same path, its `cause` and the `value` it read, or `null` when it's missing or can't be read. It's `[]` when nothing broke.

**[subjects.keyed.id]** A subject whose `from` line uses `named by each of` takes its key as its id, because the key is what names a subject the object doesn't have. So it can't have an `identified_by`. One that does is written wrong, and `$well_formed` lists `not allowed with named by each of: the key is the id` under `subjects.<name>.identified_by`, with any other problem with that `identified_by`, like `not a string`. A subject whose parent is a keyed one can have its own `identified_by`.

**[subjects.id]** A subject definition's `identified_by` is a path inside each subject, except for a subject listed by `named by each of` ([subjects.keyed.id](#requirements)). Its value is the subject's id, or `null` when the path doesn't end `found`. A subject that isn't an object is its own id, whatever the path, and so is every subject when there's no `identified_by`. So with `identified_by: id`, the items of `["a", null, {"id": 3}, {}]` have the ids `"a"`, `null`, `3` and `null`. A subject without an id still gets its rows.

**[subjects.not_an_object]** An item that isn't an object is still a subject, and its checks fail as the [paths](#reading-a-path) they read say, usually `not_an_object`.

**[require]** `require` is `every` or `some`, and `every` by default. Under `every`, every subject in scope must pass every check. Under `some`, at least one subject in scope must pass every check by itself, so two subjects that each pass half the checks don't meet it.

**[min_subjects]** `min_subjects` is a whole number from 0 to 1,000,000, and 1 by default. The `$min_subjects` row passes when `from` could be read and at least that many subjects are left after the subject's filters. Its input is the number left. Otherwise it fails with `value`, or with the cause in [subjects.from].

**[unique_ids]** No two subjects can share an id, counting the ones the subject's filters leave out, and `null` counts as an id like any other. The `$unique_ids` row fails with `value` when two do. Its input lists each id more than one subject has, once, sorted by its JSON text as shown in [syntax.md](syntax.md#expressions), so `"b"` comes before `10`, and `10` before `3`.

**[well_formed]** The `$well_formed` row passes when the requirement can be read into the model, names a subject definition that can be read too, and has at least one check. Otherwise it fails with `value`, and the requirement is never met. Its inputs start with `count(checks)` and `require`. A requirement that's written wrong gets only that row: Ergo doesn't read its subjects, so it has no `$min_subjects`, `$unique_ids`, `$applies` or check rows, and its `subjects` counts are 0. The policy alone decides whether it's written wrong, so it fails on every input, and any other row would be checked against a policy Ergo couldn't read as written. Its entry in `requirements` still lists every check, the ones Ergo adds included, so the report shows what the policy wrote. Other requirements of the policy still get their rows.

**[well_formed.reserved]** `$well_formed`, `$min_subjects`, `$unique_ids` and `$applies` are the names of Ergo's own rows, so a check with one of those names is written wrong, with `name reserved` under `checks.<name>`. Its entry in `requirements` lists only Ergo's check of that name, if Ergo adds one, so no name ever stands for two checks.

## Parts

A subject can have parts: named paths inside itself, each with an alias, written as [syntax.md](syntax.md#parts) says. A part is a short name for a long path, so a policy that reads the same attestation in six checks writes where it is once.

**[parts.swap]** A part's alias stands for its path inside the subject. A check that starts a path with the alias gives exactly the rows that the same check gives with the path written out in its place: the same `passed`, the same `cause` and the same values. A part that is missing, `null` or the wrong type fails the check as the full path would, with `absent`, `null`, `unusable`, or `not_an_object` when the subject isn't an object, and a `named by` in the path that can't be read fails it as it would there. Only the names differ. A row's `expression`, its `inputs` and the paths of its `failed_items` keep the alias, see [name.part](syntax.md#naming-a-path).

**[parts.tag]** An entry in a row's `inputs` that was read through a part has `part`, `{"name": ..., "id": ...}`, besides its `name` and `value`. `name` is the alias as the check writes it, so it is also a key of the subject's `parts` in the report. For a part of a child subject's parent it is the parent's name and the alias, like `artifact.pr_attestation`. `id` is the value at the part's `identified_by`, read inside the part for the row's subject (the parent's, for a parent's part), as it is: any JSON value. It is `null` when the part has no `identified_by`, or when it leads nowhere or to `null`. An entry that reads through two parts in one value, like the sum of a `count of` one and a field of another, has no `part`, and neither has an entry that doesn't go through a part, so a policy without parts gives the same inputs as before. The tag is for readers and tools: it never changes `passed`, `cause` or a value. It is on `inputs`, so on the inputs of a violation, and on the `inputs` of a failed sentence on a `for` line, see [for.failure_inputs](#for), and not on `failed_items`. A walk that goes through a list inside the part names the entry with the full path, and the entry keeps its tag.

**[parts.where]** An alias is read wherever a bare first key reads the subject (see [sentence.path.start](syntax.md#paths)): in the subject's checks, in the assertions of a `for` line and in a later item of it whose path starts at the subject, in the conditions of the subject's own `from` line unless the key is written with a dot, like `.cov`, and in the conditions of a subject that narrows it. Where a bare first key reads an item instead, in a `whose` and in the argument of a one-line `every` or `some`, an alias is read on the right side, as a `for` alias is (see [sentence.for.scope](syntax.md#the-for-line)), and never on the left of a `whose`: `whose cov is at least 5` reads the item's `cov`, and `every lst.x is at least cov.x` reads the part's. The item's own field on the right is written `.cov`.

**[parts.shadow]** An alias shadows a field of the subject with the same name, so `cov.x` reads the part and not the field `cov`. The dot in front of a first key, like `.cov`, reads the field: `.cov.x` reads the subject's field `cov`, as it reads a field named like a word of the grammar (see [sentence.path.start](syntax.md#paths)).

**[parts.narrow]** A subject that narrows another keeps its parts, and can add its own. Its checks and its conditions read them like parts of its own, and the report lists them (see [report.subjects](#statuses)).

**[parts.chain]** The alias of a child subject's parent gives everything the parent has, its fields and its parts, so `artifact.pr_attestation.approvers` reads the part `pr_attestation` of `artifact`, and a `from` line can start from one: `from: artifact.pr_attestation.pull_requests`. A part is only reached through its subject. A bare `pr_attestation` in a check of the child subject is its own field, and a part of the child subject isn't one of the parent's.

## Scope

**[scope.filters]** A subject is in scope when it passes every filter in its definition's `from` line. Each subject gets one `$applies` row when the definition has filters, and a subject that's out of scope gets no other rows, but its `$applies` row stays.

**[scope.out]** A subject is out of scope only when every filter it fails fails with `value`, or one of them is a `present` filter that found its field missing ([present.filter]). Then its `$applies` row fails with `value`.

**[scope.unreadable]** When a filter fails with any other cause, Ergo can't tell whether the subject is in scope. Its `$applies` row fails with the first such cause, in the order of [causes](#causes), even when another filter would rule it out, and the requirement isn't met, even with `min_subjects: 0`.

**[scope.failures]** An `$applies` row has the fields the check row would have if its conditions were the assertions of a check. With one condition that's a `some` or an `every`, it has `failed_items`, as [walk.failed_items](#every-and-some) says, and `[]` when it passes. With two or more conditions it has `failed_assertions`, as [all_of.failed_assertions](#all-of) says: an entry for each condition that failed, in the order written, with its `assertion` and its own `cause`, and `[]` when it passes. It has no `failed_items`, even when one of the conditions walks a list. A single condition that isn't a `some` or an `every`, like `environment is "prod"`, adds nothing, as a plain check doesn't. The row's own `cause` is the one [scope.out](#scope) and [scope.unreadable](#scope) give, so the `cause` of an entry can be `absent` or `null` where the row's is `value`, as when a `present` filter rules the subject out.

## Statuses

**[status]** Each requirement has a `status`:

- `not_met` when its `$well_formed`, `$min_subjects` or `$unique_ids` row fails, when an `$applies` row fails with anything but `value`, or when its checks fail under `require`
- `not_applicable` when it would otherwise be met but no subject is in scope, which only happens with `min_subjects: 0`
- `met` otherwise

**[compliant]** The report is `compliant` when it has at least one requirement and none is `not_met`. A policy with no requirements is never compliant, because it doesn't check anything.

**[report.requirements]** The report has an entry for each requirement, with its `description` and `meta`, or `""` and `{}` when it has none, its `require`, `subject`, the name of the subject it checks, or `null` when it names none or one that isn't in the policy's subjects, its `status`, `subjects` with `total`, the number found by `from`, and `matching`, the number in scope, `checks`, each check as written with its `description`, `meta` and `expression`, plus the checks Ergo adds, and `causes`. All the filters share one `$applies` entry.

**[report.policy]** The report has the policy's `description` and `meta` at its top, next to `compliant`, or `""` and `{}` when the policy has none. `null` counts as none. A `description` that isn't a string, or a `meta` that isn't an object or holds something JSON can't, makes the `$well_formed` row of every requirement fail, because the policy belongs to all of them, and the report shows `""` or `{}` in its place.

**[report.keys]** Every object in the report, `meta` and values copied from the input included, has its keys sorted by code point, whatever order the policy or the input wrote them in.

**[report.version]** The report has `ergo` at its top, the version of the spec it follows, like `"ergo": "v0.3-dev"`. That's the version the implementation follows, even when the policy names another or none.

**[report.engine]** The report has `engine` at its top, saying which implementation made it: its `name` and `version`, both strings, like `{"name": "ergo.rego", "version": "0.1.0"}`, and nothing else. Apart from `engine`, a report depends only on the policy, the input and the params, so it says nothing about the machine that made it, like the version of OPA, and an implementation reads nothing from that machine: no clock, randomness, network or environment variables.

**[report.hash]** The hash of a report is the SHA-256, in lowercase hex, of the report without `engine`, written as [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) says. So the same policy, input, params and spec version give the same hash whichever engine made the report, apart from numbers that a 64-bit float doesn't keep (see [OPEN.md](OPEN.md#numbers-in-a-reports-hash)). An implementation doesn't have to compute it.

**[report.subjects]** The report has `subjects` at its top, with an entry for each subject a requirement uses, by name. That's the subject it names, the subjects that one narrows or reads from, and so on all the way back. A subject no requirement uses isn't listed. An entry has:

- `description`, the subject's description, or `""` when it has none or it isn't a string
- `from`, how the subject is found, written as a `from` line: the line itself, printed the same way whatever spaces it was written with. A subject without `from` reads the input field named like it. A `from` that is written wrong, or isn't a string, is `<invalid from>`, even when the line reads and has only a problem like `values of mixed types`. So is the `from` of a subject with `applies_to` or `of`, because those fields said how it was found.
- `identified_by`, the path of the subject's id, or `null` when it has none, because the whole subject is its id. A subject that narrows another has the id of the subject at the top of its chain, the one that narrows nothing, also when its `from` is written wrong, even with an `identified_by` of its own. An id that is written wrong is `<invalid identified_by>`. In a loop of subjects that narrow each other no subject is at the top, so a subject in it has `null`, or `<invalid identified_by>` when it has an `identified_by` of its own, which is written wrong on a subject that narrows another.
- `parts`, every part the subject has, including the ones it keeps from a subject it narrows, by alias. Each is `{"from": ..., "identified_by": ...}`: `from` is the part's path written the way a sentence writes it, so `  dd.b ` is `dd.b` and `x[$params.k]` is `x named by $params.k`, and `identified_by` is the path of the part's id, or `null` when it has none. A part written as one line has no id. A part written wrong is listed as best it can be: `<invalid from>` for a path that can't be read and `<invalid identified_by>` for an id that can't, and a part that is neither a string nor an object has `<invalid from>` and `null`.

A subject that is written wrong still has its entry. A subject whose `from` starts at another subject lists that subject even when the line is written wrong. A `from` that doesn't parse, or isn't a string, lists no other subject.

**[report.causes]** `causes` lists the causes of the rows that would be [violations](#violations) of the requirement, each with `rows`, the number of rows that have it. It counts rows, not subjects, and lists the causes in the order of [causes](#causes), worst first. A requirement that's `met` or `not_applicable` has an empty list.

## Row order

**[order]** Rows come in this order, whatever order the policy was written in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$unique_ids` rows, then all the `$applies` rows, then the requirements' own checks
2. within each of those, requirements in name order
3. within a requirement, subjects in the order the subject's `from` found them
4. within a subject, checks in name order

Names are sorted by code point.

## Violations

**[violations]** The violations of a report are its rows that are real problems, in the order of `results`, each with its check's `description` and `expression` added and its `$refs` added at the end of its `inputs`. A row of an `every` or `some` check keeps its `failed_items`, and a row of an `all_of` check its `failed_assertions`, and so does an `$applies` row that has them ([scope.failures](#scope)). The violations leave out rows that passed, `$applies` rows that failed with `value`, and every row of a requirement that's `met` or `not_applicable`, so under `require: some` the subjects that failed aren't violations when another one passed. They're worked out from the report alone.
