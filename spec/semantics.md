# How ergo turns a policy and an input into a report

Draft 0.1. This file says what a check means, whatever syntax it's written in. [syntax.md](syntax.md) says how today's policies write checks, how they can be written wrong, and how the report shows them. It covers reading values, causes, every built-in operator, and how requirements, scope, statuses and violations work. How a subject's `from` names subjects is still described only in [REFERENCE.md](../REFERENCE.md). Questions the spec hasn't settled are in [OPEN.md](OPEN.md).

Each rule has a name in brackets, like `[present.missing]`. The cases in [`cases/`](cases) list the rules they test, so you can find the cases for a rule and the rule behind a case. An implementation follows every rule here, and where it does something else, it's wrong, whatever `ergo.rego` does.

## Terms

- The **input** is the JSON document being checked.
- The **params** are a second JSON document the policy can read, or nothing.
- A **subject** is one thing a requirement checks, found in the input by the `from` of the subject definition it names.
- A **check** is one named test in a requirement's `checks` or in a subject definition's `applies_to`.
- A **row** is the result of one check on one subject, or of one check ergo adds to a requirement.

## The model of a check

A syntax reads each check into this model. Everything below is said in terms of it.

- A **check** has an operator, like `equals` or `all`, and the parameters that operator takes.
- A **path** has a start and a list of steps. It starts at the subject, at the input, at the params, or at a name given by a subject's `from` or by an enclosing list check.
- A **step** is a key (a string, which reads a key of an object), an index (a whole number of 0 or more, which reads an item of a list), a selector (fields and the values they must equal), or a ref step (a ref whose value is the key).
- A **value** is a JSON value or a ref.
- A **ref** is a path that starts at the input or the params and whose steps are all keys or indexes.

**[written_wrong]** A check that can't be read into this model is written wrong. Each of its rows fails with cause `ill_formed`, whatever the subject holds, and the requirement's `$well_formed` row fails with cause `value` and lists what's wrong. A check written wrong in `applies_to` fails the requirement instead of ruling subjects out. [syntax.md](syntax.md#checks-written-wrong) says what counts as written wrong in today's syntax and how it's reported.

## Reading a path

Reading a path ends in one of these outcomes. Each one except `found` is also a [cause](#causes).

| Outcome         | When                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `found`         | Every step was read, and the value at the end isn't `null`.                                                              |
| `null`          | Every step was read, and the value at the end is `null`.                                                                 |
| `absent`        | A key isn't in its object, an index is past the end of its list, or a step comes after a value that's missing or `null`. |
| `unusable`      | A step comes after a value that can't hold it.                                                                           |
| `not_an_object` | The path reads a field of a subject that isn't an object.                                                                |
| `unmatched`     | A selector found no item in a list that's there.                                                                         |
| `ambiguous`     | A selector found more than one item.                                                                                     |

**[path.start]** A path starts at the subject, the input, the params or a name. With no params, or params that aren't an object, a path into the params ends `absent`.

**[path.empty]** A path with no steps reads its starting value itself, so on a subject it never ends `not_an_object`. A `null` subject ends `null`.

**[path.not_an_object]** A path with steps that starts at a subject that isn't an object ends `not_an_object`, `null` subjects included.

**[path.absent]** A key the object doesn't have ends `absent`, and so does an index past the end of the list. Once a value is missing or `null` partway along, the path ends `absent`, however many steps are left.

**[path.null]** A path whose last step reads `null` ends `null`.

**[path.unusable]** A key on anything but an object, or an index on anything but a list, ends `unusable`. So does any step after a string, number or boolean. So the key `y` on `"x": "a"` and on `"x": [{"y": 1}]` ends `unusable`, and the index `1` on `"x": {"1": "a"}` does too.

**[path.selector]** A selector reads the one item of a list, or of an object's values, whose fields equal every field the selector gives. No match ends `unmatched`, and more than one ends `ambiguous`. A selector on a value that's missing or `null` ends `absent`, the same as a key would.

**[path.ref_step]** A ref step reads its ref first and uses the value as the key for that step. If the ref ends anything but `found`, the path ends there with the ref's outcome, and a value that can't be a key ends `unusable`.

## Causes

Every row has a cause. When a check reads several values, the row takes the first cause in this order:

1. `satisfied`
2. `substituted`
3. `ill_formed`
4. `not_an_object`
5. `ambiguous`
6. `unmatched`
7. `unusable`
8. `absent`
9. `null`
10. `value`

`satisfied` and `substituted` mean the row passed. Every other cause means it failed. `value` means everything was read and the values didn't pass.

## Values

**[value.equal]** Two values are equal when they have the same type and the same content. Numbers are compared by value, so `1` equals `1.0` and `1e0`. Strings are equal when they hold the same code points. Lists are equal when they have the same length and equal items in the same order, and objects when they have the same keys with equal values. `"1"` doesn't equal `1`, and `[1, 2]` doesn't equal `[2, 1]`.

**[value.ref]** A value that's a ref is read from the input or the params, and the check runs with the value it reads. If the ref ends anything but `found`, the check fails with the ref's outcome as its cause, whatever the subject holds. A ref that reads `null` fails it as `null`, even when the field is `null` too. A value read through a ref is data, so nothing inside it is read as a ref.

**[value.refs]** A check that has refs gets `$refs` in its definition in the report: one entry for each ref, named as in [syntax.md](syntax.md#naming-a-path), with the value it read, or `null`. They're sorted by name.

## What a row shows

**[path.inputs]** A check that reads one path, like `present`, `missing`, `equals` or `in`, has one entry in its row's `inputs`: the path's name and the value read, or `null` when nothing was.

## `present`

`present` takes a path and asks whether the field is there.

**[present.pass]** It passes when its path ends `found`. Any value counts, `""`, `false`, `0`, `[]` and `{}` included.

**[present.missing]** It fails with cause `value` when its path ends `absent` or `null`. Whether the field is there is the question it asks, so "it isn't" is a sound answer, and the cause says so.

**[present.no_params]** On a path into the params, it fails with cause `absent` instead when there are no params, or they aren't an object. Then the params weren't given at all, so ergo can't tell whether the field would be there, and a policy run without its params fails instead of ruling every subject out. When the params are an object without the field, it fails with `value` as usual.

**[present.other]** It fails with the outcome as its cause when its path ends any other way: `not_an_object`, `unusable`, `unmatched` or `ambiguous`. A ref step whose ref can't be read keeps the ref's cause too, even `absent` or `null`, because then the field it looks for is unknown, not missing.

**[present.filter]** In `applies_to`, a `present` filter that fails with cause `value` rules the subject out, whatever the other filters give. Its `$applies` row fails with cause `value`, and the subject gets no other rows. Any other cause fails the requirement, as it does for every filter. **[applies.inputs]** The `$applies` row lists each path its filters read once, sorted by name.

## `missing`

`missing` takes a path and asks whether the field is missing. It's the opposite of `present`.

**[missing.pass]** It passes where `present` would fail with cause `value`: when its path ends `absent` or `null`.

**[missing.fail]** It fails with cause `value` where `present` would pass, so a field that's there fails it whatever it holds, `false` and `""` included. Everywhere else, it fails with the cause `present` would give, so with no params a `missing` check on a path into the params fails as `absent` instead of passing.

**[missing.filter]** In `applies_to`, it rules out a subject whose field is there, with cause `value`, as any filter does.

## `equals`

`equals` takes a path and a value, and asks whether the field equals the value.

**[equals.pass]** It passes when its path ends `found` or `null` and the value read [equals](#values) the value. So a `null` value passes on a field that's there and `null`.

**[equals.fail]** It fails with the path's outcome as its cause when the path ends anything but `found` or `null`, a missing field included, even when the value is `null`. It fails with `null` when the field is `null` and the value isn't. When the field was read, it fails with `value`, even when the types differ.

## `in`

`in` takes a path and a list of values, and asks whether the field is one of them.

**[in.values]** The values are a list whose items are values, or a ref to a list. When the ref reads something other than a list, the check fails as `unusable`. A list read through a ref is data, so an object in it that looks like a ref is compared as an object.

**[in.pass]** It passes when its path ends `found` and the value read [equals](#values) one of the values.

**[in.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, so a missing or `null` field fails even when the values hold `null`. When the field was read, it fails with `value`, an empty list of values included.

## `has_type`

`has_type` takes a path and a `type`, one of `list`, `string`, `number`, `boolean` and `object`, and asks whether the field has that JSON type. It's what the sentence `is a <type>` reads into, see [sentence.phrase.type](sentences.md#phrases), and today's syntax can't use it (see [sentence_ops.syntax](syntax.md#policies)).

**[has_type.pass]** It passes when its path ends `found` and the value has the type.

**[has_type.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. A value of any other type fails with `value`, because checking the type is what it's for.

## `not_in`

`not_in` takes a path and a list of values, written like the values of [`in`](#in), and asks whether the field is none of them. It's what the sentences `is not one of` and `is not in` read into, see [sentence.phrase.one_of](sentences.md#phrases), and today's syntax can't use it (see [sentence_ops.syntax](syntax.md#policies)).

**[not_in.pass]** It passes when its path ends `found` and the value read [equals](#values) none of the values. So a value of another type passes, since `5` isn't one of `"prod"` and `"staging"`, and so does any value when the list is empty.

**[not_in.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, so a missing or `null` field fails even when the values hold `null`. When a ref reads something other than a list, it fails as `unusable`, as `in` does. When the field equals one of the values, it fails with `value`.

## `non_empty_string`

`non_empty_string` takes a path and asks whether the field is a string with something in it.

**[non_empty_string.pass]** It passes when its path ends `found` and the value is a string other than `""`. A string of spaces passes.

**[non_empty_string.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. When the field was read, it fails with `value`, whatever its type, because checking the type is what it's for.

## `empty`

`empty` takes a path and asks whether the field is an empty list.

**[empty.pass]** It passes when its path ends `found` and the value is `[]`.

**[empty.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. A list with items fails with `value`. Anything else that was read, `""` and `{}` included, fails with `unusable`.

## `empty_string_or_list` and `not_empty_string_or_list`

`empty_string_or_list` takes a path and asks whether the field is `""` or `[]`. `not_empty_string_or_list` asks whether it's a string or a list with something in it. They're what the sentences `is empty` and `is not empty` read into, see [sentence.phrase.empty](sentences.md#phrases), and today's syntax can't use them (see [sentence_ops.syntax](syntax.md#policies)).

**[empty_string_or_list.pass]** `empty_string_or_list` passes when its path ends `found` and the value is `""` or `[]`. `not_empty_string_or_list` passes when its path ends `found` and the value is a string with at least one character or a list with at least one item.

**[empty_string_or_list.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`. A value that's neither a string nor a list, like a number, a boolean or an object, fails with `unusable`. Otherwise they fail with `value`.

## `range`

`range` takes a path, a `min` and a `max`, and asks whether the field is a number between them, both included.

**[range.bounds]** `min` and `max` are numbers, or refs, and `min` isn't above `max`. When a ref reads something other than a number, or the bounds it reads put `min` above `max`, the check fails with `unusable`.

**[range.pass]** It passes when its path ends `found`, the value is a number, and `min <= value <= max`, compared by value.

**[range.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, and with `unusable` when the value isn't a number. A number outside the range fails with `value`.

## `matches_any` and `not_matches_any`

`matches_any` takes a path and a list of patterns, and asks whether the field is a string that at least one of them matches. `not_matches_any` asks whether it's a string that none of them match.

**[patterns.syntax]** A pattern is a regular expression in [RE2 syntax](https://github.com/google/re2/wiki/Syntax), run on code points. So there's no lookahead and no backreference. `.` doesn't match a newline, `$` only matches at the very end of the string, and `(?i)` turns on case-insensitive matching. A pattern isn't anchored: `svc_` matches `my_svc_account`.

**[patterns.list]** The patterns are a list whose items are strings or refs, or a ref to a list. When a ref reads something other than a list, or a pattern that isn't a string or isn't valid, the check fails with `unusable`.

**[patterns.pass]** `matches_any` passes when its path ends `found`, the value is a string, and at least one pattern matches it. `not_matches_any` passes when its path ends `found`, the value is a string, and no pattern matches it. So with no patterns, `matches_any` always fails and `not_matches_any` passes on any string.

**[patterns.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`, and with `unusable` when the value isn't a string. Otherwise they fail with `value`.

## `includes` and `excludes`

`includes` takes a path and either one value or a list of values. With one value, it asks whether the field is a list that contains it, and with a list, whether it contains every one of them. `excludes` asks whether the field is a list that contains none of them.

**[contains.value]** One value is one value, so a list given as the value is looked for as a list inside the field. A list of values has at least one item, and its items are values. It can be a ref, and when the ref reads something other than a non-empty list, the check fails as `unusable`, because an empty list would pass every field.

**[contains.pass]** `includes` passes when its path ends `found`, the value is a list, and an item [equals](#values) the value, or with a list of values, when each of them equals an item. `excludes` passes when its path ends `found`, the value is a list, and no item equals the value, or any of the values. So an empty list fails `includes` and passes `excludes`.

**[contains.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`, and with `unusable` when the value isn't a list, a string or an object included. Otherwise they fail with `value`.

## `compare`

`compare` takes two sides, `left` and `right`, and a comparison: `eq`, `ne`, `gt`, `gte`, `lt` or `lte`. A side is a path, so it compares two fields of the same subject. [syntax.md](syntax.md#compare) says what else a side can be.

**[compare.pass]** It passes when both paths end `found`, the two values have the same type, and `left cmp right` holds. `eq` and `ne` use [equality](#values) and work on any type. `gt`, `gte`, `lt` and `lte` only work on two numbers, compared by value, or two strings, compared code point by code point, so `"Z"` comes before `"a"` and `"！"` (U+FF01) before `"😀"` (U+1F600).

**[compare.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, so two `null` fields fail as `null`, even with `eq`. When both were read, it fails with `unusable` when their types differ, even with `ne`, and when `gt`, `gte`, `lt` or `lte` is used on anything but two numbers or two strings. Otherwise it fails with `value`.

**[compare.inputs]** Its row has two entries in `inputs`, `left` then `right`.

**[compare.text]** Two more comparisons, `starts_with` and `ends_with`, are what the sentences `starts with` and `ends with` read into, see [sentence.phrase.starts](sentences.md#phrases), and today's syntax can't use them (see [sentence_ops.syntax](syntax.md#policies)). They pass when both values are strings and the left one starts, or ends, with the right one, code point by code point. Anything but two strings, two numbers included, fails with `unusable`, and the rest is as [compare.fail](#compare) says.

## Counts and sums in sentences

A side of `compare` can also be `count_of` or `sum_of`, each with a path, `whose`, a list of basic checks, and `text`, the words that wrote it. `add` can take `text` too, and `count_of` and `sum_of` among the sides it adds up. They're what `count of`, `sum of` and `plus` read into, see [sentence.derived.count](sentences.md#derived-values), and today's syntax can't use them (see [sentence_ops.syntax](syntax.md#policies)).

**[tally.walk]** The path is walked as [walk.lists](#every-and-some) says, except that an empty list adds nothing instead of failing. A list that's missing, `null` or not a list fails the side as `absent`, `null` or `unusable`, and so does a path where no step walks a list, as [walk.lists](#every-and-some) says. On a subject that isn't an object, with a path that starts at the subject, it fails as `not_an_object`, and so does an item that isn't an object when the path goes on into it, as [walk.flaws](#every-and-some) says for `every`. A ref the side reads that can't be used, in its path or its `whose` checks, fails it as `unusable`, and one that's missing or `null` fails it as `absent` or `null`, even when the list is empty.

**[tally.whose]** The `whose` checks read from each item of the innermost list walked, as [walk.items](#every-and-some) says. An item is left out when one of them fails with `value`, or when a `present` check finds the field missing. An item one of them can't decide fails the side with its cause.

**[tally.count]** `count_of` is the number of values the path ends at in the items left in, `null` included. A value that's missing fails the side as `absent`.

**[tally.sum]** `sum_of` adds up the values the path ends at in the items left in, and is 0 over none. A value that's missing fails the side as `absent`, `null` as `null`, and anything else that isn't a number as `unusable`. Numbers are added as decimals, so `0.1` and `0.2` add up to `0.3`, and so are the sides of an `add` with `text`. A number with more than 15 decimal places, or too large to scale to a whole number below 10^15, is added as the runtime adds it.

**[tally.fail]** A side that fails gives the check its cause, as a path that ends anything but `found` does in [compare.fail](#compare), and the worst one when both sides fail. An `add` fails as its worst operand does.

**[tally.inputs]** For each side that's worked out, the row shows an entry named after its `text`, holding the number, or `null` when the side failed. For a `count_of` or a `sum_of`, the list it walked comes next, named and filled as [walk.inputs](#every-and-some) says. For an `add`, each side it adds up comes next, as if it stood alone. The left side's entries come before the right side's.

## `compare_time`

`compare_time` takes the same parameters as `compare`, and compares two times.

**[time.format]** A time is either a number or an RFC 3339 string. A string has the form `YYYY-MM-DDTHH:MM:SS`, then optionally `.` and one or more digits, then `Z` or an offset `+HH:MM` or `-HH:MM`. The `T` and `Z` are uppercase. The date must exist, so `2024-02-30` and `1900-02-29` don't. The hour is 00 to 23, minutes and seconds 00 to 59, and the offset 00:00 to 23:59. The year, as written, is 1678 to 2261. Only the first nine digits of the fraction count. Any other string isn't a time.

**[time.pass]** It passes when both paths end `found`, both values are RFC 3339 strings or both are numbers, and `left cmp right` holds. Strings are compared as the instants they name, so `2024-01-01T01:00:00+01:00` equals `2024-01-01T00:00:00Z`. Numbers are compared by value, with no unit attached.

**[time.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, and with `unusable` when the values aren't two times in the same format, a number and a string included. Otherwise it fails with `value`.

## `all` and `any`

`all` takes a path to a list and an inner check, and asks whether every item passes the check. `any` asks whether at least one does. Both can also take `each`, a path inside each item to an inner list, and `as`, a name for each item.

**[list.read]** The path must end `found` on a list. A list that's missing fails the check as `absent`, a `null` one as `null`, and anything else, an object included, as `unusable`. An empty list fails as `value`, because no items isn't proof of anything.

**[list.items]** The inner check runs on each item, with the item as its subject, so its paths start inside the item. A path with no steps reads the item itself, and an item that isn't an object fails a path with steps as `not_an_object`.

**[list.pass]** `all` passes when the list isn't empty and every item passes. `any` passes when it isn't empty and at least one item does.

**[list.cause]** When the items decide the result and it fails, the cause is the first, in the order of [causes](#causes), among the items that failed. So when one item fails as `value` and another is missing its field, the check fails as `absent`, because the second one might have passed.

**[list.each]** With `each`, the check runs on every item of every inner list. Every inner list must be readable, a list and not empty, for `all` and `any` alike. One that isn't fails the check with the cause it would give as a list, even when an item elsewhere passes.

**[list.as]** `as` names each item, so a check nested inside can still read it once its own paths start somewhere else. A name can only be given once along a chain of checks, so `from` and an enclosing check can't give the same one. A path can only start with a name that `from` or an enclosing list check gives, not one given in a neighbouring `any_of` option. A check that breaks either rule is [written wrong](#the-model-of-a-check). Only `all` and `any` take `as` and `each`.

**[list.inner]** The inner check is a basic operator, an `any_of`, or another `all` or `any`. One `all` or `any` can sit inside another, but not a third, so ergo can be written in a language without recursion. An `any_of` doesn't count as a level, but an `all` or `any` in one of its options does. Anything else is [written wrong](#the-model-of-a-check).

**[list.inputs]** When the inner check has a path that starts inside the item, the row shows that path for every item, like `cs[].s` with `[true, false, null]`. That holds for an inner `all` or `any` too, so its lists are shown. A path with no steps shows the items themselves. Any other inner check, like `compare` or `any_of`, shows the whole items. In both cases, each path into the input, the params or a name that the inner check reads follows, except names the check itself gives. With `each`, the items are the inner lists. A list that can't be read shows `[]` as its value.

**[list.failed_items]** The row also has `failed_items`, the items that made it fail, in list order. Each one has its `path`, like `item 2 of cs` or, with `each`, `item 2 of prs[0].cs`, its `item`, the path of the list item it belongs to, its own `cause`, and its `value`. For `all` and `any`, the entry is the list item itself, so `item` is the same as `path`. With `each`, an inner list that can't be read or is empty is listed in place of its items, like `prs[1].cs` with the value it read, or `null`. An item that a `present` check finds missing is listed with cause `value`. For a nested check, only the outer items are listed. `failed_items` is `[]` when the check passes, even for an `any` with items that failed, and when the list itself can't be read. When the check is written wrong, every item is listed as `ill_formed`, and when a ref can't be read, every failing item is listed with the ref's cause.

## `any_of`

`any_of` takes named options, each a list of checks that must all pass, and passes when one of its options does.

**[any_of.options]** There's at least one option, and each option has at least one check. A check in an option is a basic operator, an `all` or an `any`, not another `any_of`.

**[any_of.pass]** It passes when every check of at least one option passes.

**[any_of.cause]** Each option that fails has a cause: `value` when one of its `present` checks found its field missing, and otherwise the first, in the order of [causes](#causes), among its checks, or `value`. The row takes the first among its options.

**[any_of.inputs]** The row shows every path any option reads, once each, sorted by name. For an `all` or `any` in an option, that's its list, with the whole items, and the names it reads.

**[any_of.no_failed_items]** An `any_of` row has no `failed_items`, even with an `all` or `any` inside it.

## `all_of`

`all_of` takes `checks`, a list of basic checks, and `assertions`, the text of each one. It's what a check written as several sentences reads into, joined with `and` or listed under `assert`, see [sentence.assert.list](sentences.md#the-shape-of-a-sentence), and today's syntax can't use it (see [sentence_ops.syntax](syntax.md#policies)). It's one check, with one row per subject, because its sentences say one thing together, and a policy that wants a row for each writes them as separate checks.

**[all_of.pass]** It passes when every one of its checks passes.

**[all_of.cause]** When it fails, its cause is the first, in the order of [causes](#causes), among the checks that failed.

**[all_of.inputs]** The row shows every path any of its checks reads, once each, sorted by name.

**[all_of.failed_assertions]** The row also has `failed_assertions`: one entry for each check that failed, in the order they were written, with its `assertion` and its own `cause`. It's `[]` when the check passes, and the row has no `failed_items`, even when one of the sentences walks a list. When a ref one of them reads can't be used, that one is listed with cause `unusable` and the others with their own causes.

## `every` and `some`

`every` and `some` take a path, a basic check, `whose`, a list of basic checks, and `if_any`. They're what the sentences `every <path> …` and `some <path> …` read into, see [sentence.every.walk](sentences.md#every-some-and-whose), and today's syntax can't use them (see [sentence_ops.syntax](syntax.md#policies)).

**[walk.lists]** The path is read one step at a time. At a step where at least one value read so far is a list, and the step isn't a position, every one of those values is walked: each of its items goes on along the path in its place. At that step, a value that's missing, `null` or not a list fails as `absent`, `null` or `unusable`, and an empty list fails as `value`, unless `if_any` is true, when it's skipped. After the last step, a value that's a list is walked the same way. A path where no step walks a list fails at the first value along it that isn't an object, with `absent` when it's missing, `null` when it's `null`, and `unusable` otherwise, or at the value the path ends at, as `unusable`, when every value along it is an object. That place is the one entry in `failed_items`, so a lone list that's `null` fails as `null`, as it does when another item's list is walked.

**[walk.items]** The items of the innermost list walked are what the check is about. Each one is checked on its own: the `whose` checks and the basic check read their paths from the item, and the basic check reads the rest of the path, after the item, as its own. An item is undecided when a `whose` check fails with any cause but `value`, even when another one fails with `value`, as a filter that can't decide fails the requirement (see [scope.unreadable](#scope)). Otherwise it's left out when a `whose` check fails with `value`.

**[walk.every]** `every` passes when nothing failed while walking, no item is undecided, every item left in passes, and at least one item is left in, or `if_any` is true. Otherwise it fails with the first, in the order of [causes](#causes), among what failed, or with `value` when the only problem is that no item was left in.

**[walk.some]** `some` passes when at least one item left in passes. Otherwise it fails with the first, in the order of [causes](#causes), among what failed while walking, the undecided items and the items that failed, or with `value` when there were none.

**[walk.flaws]** When a ref the check reads, in its path, its `whose` checks or its phrase, can't be used, or the input or params hold something JSON can't, the check fails as `unusable` and `failed_items` is `[]`, whatever the items hold, as a plain check does. On a subject that isn't an object, with a path that starts at the subject, it fails as `not_an_object`. When a ref step in its path can't be read, it fails with the ref's cause, and its `inputs` hold `[]`.

**[walk.inputs]** The row's `inputs` has one entry, named after the path with `[]` after each list walked, like `pull_requests[].commits[].signed`, holding the value each item's path ended at, in order, `null` where it ended missing. The items `whose` leaves out are there too. Where the walk stopped early, `[]` only follows the lists it walked.

**[walk.failed_items]** The row's `failed_items` lists what failed, in path order, when the check fails, and is `[]` when it passes: each value that failed the basic check, with `path` the field, `item` the item and `value` what the path ended at, or `null`; each undecided item, with `path` the field of the first `whose` check that couldn't decide; and each list that failed while walking, with `path` and `item` both the list. An item that `whose` left out isn't listed.

## `for`

`for` takes `items`, one or two, each with `every` or `some`, a path, `whose`, `if_any` and a name, and `checks` and `assertions`, as `all_of` does. It's what a check with a `for` line reads into, see [sentence.for.line](sentences.md#the-for-line), and today's syntax can't use it (see [sentence_ops.syntax](syntax.md#policies)).

**[for.walk]** Each item's path is walked as an `every` or `some` path is, see [walk.lists](#every-and-some), and its name stands for the value the path ends at in each item of the innermost list walked. The `whose` checks read from that item, and an item is undecided or left out as [walk.items](#every-and-some) says. An item `whose` keeps, whose path ends at a value that's missing or that can't be read, fails as `absent` or `unusable` without its checks being run. The second item's path and its `whose` checks can start at the first item's name, and then it's walked again for each item of the first list.

**[for.try]** The checks read the subject, with each name standing for its item. With one item, an item passes when all the checks pass. With two, an item of the first list passes when the second item passes for it, as [walk.every](#every-and-some) or [walk.some](#every-and-some) says, where an item of the second list passes when all the checks pass. A failed item's cause is the first, in the order of [causes](#causes), among the checks that failed, or what failed in the second item's walk.

**[for.pass]** The check passes or fails as the first item does, by [walk.every](#every-and-some) or [walk.some](#every-and-some), with its items judged as [for.try](#for) says.

**[for.inputs]** The row shows each item's list once, named after its path with `[]` after each list walked, holding the values its name stands for, and the inputs the checks would show on their own, leaving out paths that start at a name, once each, even when no check was run, all sorted by name. A second item that starts at the first item's name is named with that name, like `pr.approvers[]`, and holds the items of every list it walked, in order. Paths that start at a name aren't shown.

**[for.failed_items]** When the check fails, `failed_items` lists the first item's failures, in path order, as [walk.failed_items](#every-and-some) does, and it's `[]` when the check passes. A failed item has `path` and `item` both the item, like `item 2 of pull_requests`, and `value` `null`. Each entry also has `failed_assertions`: the sentences that failed for that item, in the order written, each with the first cause it failed with. It's `[]` when no sentence was checked for it, because a `whose` couldn't decide, a list failed while walking, or `whose` left nothing in, and on the entry of a list that failed while walking.

**[for.flaws]** When a ref the check reads can't be used, or the input or params hold something JSON can't, it fails as `unusable` and `failed_items` is `[]`, as [walk.flaws](#every-and-some) says. On a subject that isn't an object, with an item's path that starts at the subject, it fails as `not_an_object`. A second item whose path reads into the first item's name fails that item as `not_an_object` when it isn't an object. When a ref step in the first item's path can't be read, it fails with the ref's cause, `failed_items` is `[]`, and that path's input holds `[]`. In the second item's path, the first list's item fails with the ref's cause instead.

## Substitutes

A check in `checks` or `applies_to` can have a substitute: another check that satisfies it when the first one fails. It's for other evidence that the same requirement was met, like an attestation from a verified committer standing in for the pull request a repository's first commit can't have.

**[substitute.pass]** When the check passes, the row passes with `satisfied`. When it fails and the substitute passes, the row passes with `substituted`.

**[substitute.cause]** When both fail, the row takes the first cause, in the order of [causes](#causes), among the check's own cause and the substitute's, except that the substitute's `absent`, `null` and `value` don't count, because a substitute is usually missing. A substitute whose path runs into the wrong kind of value, whose selector matches nothing or several items, or whose values are the wrong kind for its operator gives its cause to the row. So does a ref in it that can't be read. In `applies_to`, a substitute that's missing doesn't stop a filter from ruling the subject out, but one with any other problem does.

**[substitute.written_wrong]** A substitute that's written wrong makes the check written wrong, so its row fails as `ill_formed` even when the check itself passes.

**[substitute.where]** A substitute's own substitute is ignored, and so is a substitute on the inner check of an `all` or `any`, or on a check in an `any_of` option. A substitute can be any check that can go in `checks`, an `all`, `any` or `any_of` included.

**[substitute.inputs]** The row shows the check's inputs, then the substitute's, leaving out a path already shown. An `all` or `any` row keeps the `failed_items` of the check itself, even when the substitute passed.

## Custom operators

A custom operator is for a check the built-in operators can't express. The policy uses it by name, with its own parameters, and doesn't say how it works: whoever runs the policy supplies it, the way Cucumber is given step definitions that feature files never mention. How it's written depends on the engine, like a Rego rule or a CEL expression, so this section only covers what the policy and the report see. [OPEN.md](OPEN.md#custom-operators) lists what the engines don't agree on yet.

**[custom.use]** A check uses a custom operator like any other, with `op` set to its name and any parameters the operator takes.

**[custom.unknown]** An operator that isn't built in and that nobody supplied is [written wrong](#the-model-of-a-check), so a misspelt operator fails, and in `applies_to` it fails the requirement instead of ruling every subject out.

**[custom.pass]** The check passes when the operator says it does, given the values its parameters hold.

**[custom.fail]** When the operator says it doesn't and every field it reads was found, the check fails with `value`.

**[custom.cause]** When it fails, the cause is the first, in the order of [causes](#causes), among the outcomes of the paths it reads, so a missing field fails it as `absent` and a `null` one as `null`.

**[custom.refs]** ergo reads the refs in a custom operator's parameters itself, so the operator gets the values. They're recorded under `$refs` like any other, and one that can't be read fails the check with its cause.

**[custom.inputs]** The row shows each path the operator reads, in order. It has no `failed_items`.

**[custom.where]** A custom operator works in `checks`, in `applies_to` and as a substitute, and as a filter it follows the same [scope](#scope) rules as any other.

## Requirements

A policy has two sections. `subjects` defines each kind of subject once, and `requirements` says what must be true of them. A subject definition has a way to find its subjects (`from`), a path to each subject's id (`id`) and filters (`applies_to`). A requirement names one subject definition with `subject`, and has `require`, `min_subjects` and checks. It can also have a `description` and `meta`, which ergo copies into the report and never reads.

**[requirement.subject]** A requirement checks the subjects of the definition it names, with its own rows. Several requirements can name the same definition. A requirement that names none, or one that isn't in `subjects`, has no subjects, and its `$well_formed` and `$min_subjects` rows fail. The name of the definition is the `type` in each row's `subject`.

**[subjects.from]** A subject definition's `from` is a path into the input. When it ends `found` on a list, each item is a subject, in list order. When it ends `found` on an object, that object is the only subject. With no steps, it reads the whole input. Anything else gives no subjects, and the requirement's `$min_subjects` row fails with the path's outcome, or with `unusable` when it read something that's neither a list nor an object, a `null` input included as `null`. That holds even with `min_subjects: 0`, because that's what a typo in `from` looks like.

**[subjects.no_from]** A subject definition without `from`, or with nothing at all, `null` in YAML, reads the input field named like the subject, as `from: [<name>]` would. So `artifact:` alone reads `artifact`. `from: []` reads the whole input. A definition with `of` takes its `from` from the subject it builds on.

**[subjects.sentence]** `from` can be a string, read as a `from` line (see [sentence.subject.from](sentences.md#subjects)), and `id` a string, read as a path. A `from` line's path reads into the input, `named by` reads a key the way a ref step does, and `named by each of` makes each key in the list a subject, as a naming step with `keys` does. Its `whose` conditions are the subject's filters, in the order written, so the `$applies` row joins them with ` and ` in that order, each printed in the report's spelling. A path that starts at `$input` reads into the input as one without it does, and `$input` alone reads the whole input. A path can't start at `$params`. A `from` line can't go with `applies_to`. One that starts at another subject's name isn't supported yet. A `from` or `id` string that can't be read is written wrong, and `$well_formed` lists its problems under `subjects.<name>.from` or `subjects.<name>.id`.

**[subjects.id]** A subject definition's `id` is a path inside each subject. Its value is the subject's id, or `null` when the path doesn't end `found`. With no steps, the id is the whole subject, so an item that isn't an object is its own id. A subject without an id still gets its rows.

**[subjects.not_an_object]** An item that isn't an object is still a subject, and its checks fail as the [paths](#reading-a-path) they read say, usually `not_an_object`.

**[require]** `require` is `every` or `some`, and `every` by default. Under `every`, every subject in scope must pass every check. Under `some`, at least one subject in scope must pass every check by itself, so two subjects that each pass half the checks don't meet it.

**[min_subjects]** `min_subjects` is a whole number of 0 or more, and 1 by default. The `$min_subjects` row passes when `from` could be read and at least that many subjects are left after the subject's `applies_to`. Its input is the number left. Otherwise it fails with `value`, or with the cause in [subjects.from].

**[unique_ids]** No two subjects can share an id, counting the ones the subject's `applies_to` leaves out, and `null` counts as an id like any other. The `$unique_ids` row fails with `value` when two do. Its input lists each id more than one subject has, once, sorted by its JSON text as shown in [syntax.md](syntax.md#expressions), so `"b"` comes before `10`, and `10` before `3`.

**[well_formed]** The `$well_formed` row passes when the requirement can be read into the model, names a subject definition that can be read too, and has at least one check. Otherwise it fails with `value`, and the requirement is never met. Its inputs start with `count(checks)` and `require`. A requirement that's written wrong still gets its rows for its subjects.

## Scope

**[scope.filters]** A subject is in scope when it passes every filter in its definition's `applies_to`. Each subject gets one `$applies` row when the definition has filters, and a subject that's out of scope gets no other rows, but its `$applies` row stays.

**[scope.out]** A subject is out of scope only when every filter it fails fails with `value`, or one of them is a `present` filter that found its field missing ([present.filter]). Then its `$applies` row fails with `value`.

**[scope.unreadable]** When a filter fails with any other cause, ergo can't tell whether the subject is in scope. Its `$applies` row fails with the first such cause, in the order of [causes](#causes), even when another filter would rule it out, and the requirement isn't met, even with `min_subjects: 0`. A filter written wrong gives `ill_formed`, whatever the others give.

## Statuses

**[status]** Each requirement has a `status`:

- `not_met` when its `$well_formed`, `$min_subjects` or `$unique_ids` row fails, when an `$applies` row fails with anything but `value`, or when its checks fail under `require`
- `not_applicable` when it would otherwise be met but no subject is in scope, which only happens with `min_subjects: 0`
- `met` otherwise

**[compliant]** The report is `compliant` when it has at least one requirement and none is `not_met`. A policy with no requirements is never compliant, because it doesn't check anything.

**[report.requirements]** The report has an entry for each requirement, with its `description` and `meta`, or `""` and `{}` when it has none, its `require`, its `status`, `subjects` with `total`, the number found by `from`, and `matching`, the number in scope, `checks`, each check as written with its `description`, `meta` and `expression`, plus the checks ergo adds, and `causes`. All the filters share one `$applies` entry.

**[report.causes]** `causes` lists the causes of the rows that would be [violations](#violations) of the requirement, each with `rows`, the number of rows that have it. It counts rows, not subjects, and lists the causes in the order of [causes](#causes), worst first. A requirement that's `met` or `not_applicable` has an empty list.

## Row order

**[order]** Rows come in this order, whatever order the policy was written in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$unique_ids` rows, then all the `$applies` rows, then the requirements' own checks
2. within each of those, requirements in name order
3. within a requirement, subjects in the order the subject's `from` found them
4. within a subject, checks in name order

Names are sorted by code point.

## Violations

**[violations]** The violations of a report are its rows that are real problems, in the order of `results`, each with its check's `description` and `expression` added and its `$refs` added at the end of its `inputs`. A row of an `all` or `any` check keeps its `failed_items`, and a row of an `all_of` check its `failed_assertions`. The violations leave out rows that passed, `$applies` rows that failed with `value`, and every row of a requirement that's `met` or `not_applicable`, so under `require: some` the subjects that failed aren't violations when another one passed. They're worked out from the report alone.
