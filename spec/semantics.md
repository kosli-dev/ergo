# How ergo turns a policy and an input into a report

Draft 0.1. This file says what a check means, whatever syntax it's written in. [syntax.md](syntax.md) says how today's policies write checks, how they can be written wrong, and how the report shows them. It covers reading values, causes, every built-in operator, and how requirements, scope, statuses and violations work. How `from` names subjects, substitutes and custom operators are still described only in [REFERENCE.md](../REFERENCE.md).

Each rule has a name in brackets, like `[present.missing]`. The cases in [`cases/`](cases) list the rules they test, so you can find the cases for a rule and the rule behind a case. An implementation follows every rule here, and where it does something else, it's wrong, whatever `ergo.rego` does.

## Terms

- The **input** is the JSON document being checked.
- The **params** are a second JSON document the policy can read, or nothing.
- A **subject** is one thing a requirement checks, found in the input by `from`.
- A **check** is one named test in a requirement's `checks` or `applies_to`.
- A **row** is the result of one check on one subject, or of one check ergo adds to a requirement.

## The model of a check

A syntax reads each check into this model. Everything below is said in terms of it.

- A **check** has an operator, like `equals` or `all`, and the parameters that operator takes.
- A **path** has a start and a list of steps. It starts at the subject, at the input, at the params, or at a name given by `from` or by an enclosing list check.
- A **step** is a key (a string, which reads a key of an object), an index (a whole number of 0 or more, which reads an item of a list), a selector (fields and the values they must equal), or a ref step (a ref whose value is the key).
- A **value** is a JSON value or a ref.
- A **ref** is a path that starts at the input or the params and whose steps are all keys or indexes.

**[written_wrong]** A check that can't be read into this model is written wrong. Each of its rows fails with cause `ill_formed`, whatever the subject holds, and the requirement's `$well_formed` row fails with cause `value` and lists what's wrong. A check written wrong in `applies_to` fails the requirement instead of ruling subjects out. [syntax.md](syntax.md#checks-written-wrong) says what counts as written wrong in today's syntax and how it's reported.

## Reading a path

Reading a path ends in one of these outcomes. Each one except `found` is also a [cause](#causes).

| Outcome | When |
| --- | --- |
| `found` | Every step was read, and the value at the end isn't `null`. |
| `null` | Every step was read, and the value at the end is `null`. |
| `absent` | A key isn't in its object, an index is past the end of its list, or a step comes after a value that's missing or `null`. |
| `unusable` | A step comes after a value that can't hold it. |
| `not_an_object` | The path reads a field of a subject that isn't an object. |
| `unmatched` | A selector found no item in a list that's there. |
| `ambiguous` | A selector found more than one item. |

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

**[present.inputs]** A check that reads one path, like `present`, `missing`, `equals` or `in`, has one entry in its row's `inputs`: the path's name and the value read, or `null` when nothing was.

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

## `non_empty_string`

`non_empty_string` takes a path and asks whether the field is a string with something in it.

**[non_empty_string.pass]** It passes when its path ends `found` and the value is a string other than `""`. A string of spaces passes.

**[non_empty_string.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. When the field was read, it fails with `value`, whatever its type, because checking the type is what it's for.

## `empty`

`empty` takes a path and asks whether the field is an empty list.

**[empty.pass]** It passes when its path ends `found` and the value is `[]`.

**[empty.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. A list with items fails with `value`. Anything else that was read, `""` and `{}` included, fails with `unusable`.

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

`compare` takes two paths, `left` and `right`, and a comparison: `eq`, `ne`, `gt`, `gte`, `lt` or `lte`. It compares two fields of the same subject.

**[compare.pass]** It passes when both paths end `found`, the two values have the same type, and `left cmp right` holds. `eq` and `ne` use [equality](#values) and work on any type. `gt`, `gte`, `lt` and `lte` only work on two numbers, compared by value, or two strings, compared code point by code point, so `"Z"` comes before `"a"` and `"！"` (U+FF01) before `"😀"` (U+1F600).

**[compare.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, so two `null` fields fail as `null`, even with `eq`. When both were read, it fails with `unusable` when their types differ, even with `ne`, and when `gt`, `gte`, `lt` or `lte` is used on anything but two numbers or two strings. Otherwise it fails with `value`.

**[compare.inputs]** Its row has two entries in `inputs`, `left` then `right`.

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

**[list.failed_items]** The row also has `failed_items`, the items that made it fail, in list order. Each one has its `path`, like `cs[1]` or, with `each`, `prs[0].cs[1]`, its own `cause`, and its `value`. With `each`, an inner list that can't be read or is empty is listed in place of its items, like `prs[1].cs` with the value it read, or `null`. An item that a `present` check finds missing is listed with cause `value`. For a nested check, only the outer items are listed. `failed_items` is `[]` when the check passes, even for an `any` with items that failed, and when the list itself can't be read. When the check is written wrong, every item is listed as `ill_formed`, and when a ref can't be read, every failing item is listed with the ref's cause.

## `any_of`

`any_of` takes named options, each a list of checks that must all pass, and passes when one of its options does.

**[any_of.options]** There's at least one option, and each option has at least one check. A check in an option is a basic operator, an `all` or an `any`, not another `any_of`.

**[any_of.pass]** It passes when every check of at least one option passes.

**[any_of.cause]** Each option that fails has a cause: `value` when one of its `present` checks found its field missing, and otherwise the first, in the order of [causes](#causes), among its checks, or `value`. The row takes the first among its options.

**[any_of.inputs]** The row shows every path any option reads, once each, sorted by name. For an `all` or `any` in an option, that's its list, with the whole items, and the names it reads.

**[any_of.no_failed_items]** An `any_of` row has no `failed_items`, even with an `all` or `any` inside it.

## Requirements

A policy is a set of named requirements. A requirement has a way to find its subjects (`from`), a path to each subject's id (`id`), `require`, `min_subjects`, filters (`applies_to`) and checks. It can also have a `description` and `meta`, which ergo copies into the report and never reads.

**[subjects.from]** `from` is a path into the input. When it ends `found` on a list, each item is a subject, in list order. When it ends `found` on an object, that object is the only subject. With no steps, it reads the whole input. Anything else gives no subjects, and the requirement's `$min_subjects` row fails with the path's outcome, or with `unusable` when it read something that's neither a list nor an object, a `null` input included as `null`. That holds even with `min_subjects: 0`, because that's what a typo in `from` looks like.

**[subjects.id]** `id` is a path inside each subject. Its value is the subject's id, or `null` when the path doesn't end `found`. With no steps, the id is the whole subject, so an item that isn't an object is its own id. A subject without an id still gets its rows.

**[subjects.not_an_object]** An item that isn't an object is still a subject, and its checks fail as the [paths](#reading-a-path) they read say, usually `not_an_object`.

**[require]** `require` is `every` or `some`, and `every` by default. Under `every`, every subject in scope must pass every check. Under `some`, at least one subject in scope must pass every check by itself, so two subjects that each pass half the checks don't meet it.

**[min_subjects]** `min_subjects` is a whole number of 0 or more, and 1 by default. The `$min_subjects` row passes when `from` could be read and at least that many subjects are left after `applies_to`. Its input is the number left. Otherwise it fails with `value`, or with the cause in [subjects.from].

**[unique_ids]** No two subjects can share an id, counting the ones `applies_to` leaves out, and `null` counts as an id like any other. The `$unique_ids` row fails with `value` when two do. Its input lists each id more than one subject has, once, sorted by its JSON text as shown in [syntax.md](syntax.md#expressions), so `"b"` comes before `10`, and `10` before `3`.

**[well_formed]** The `$well_formed` row passes when the requirement can be read into the model and has at least one check. Otherwise it fails with `value`, and the requirement is never met. Its inputs start with `count(checks)` and `require`. A requirement that's written wrong still gets its rows for its subjects.

## Scope

**[scope.filters]** A subject is in scope when it passes every filter in `applies_to`. Each subject gets one `$applies` row when the requirement has filters, and a subject that's out of scope gets no other rows, but its `$applies` row stays.

**[scope.out]** A subject is out of scope only when every filter it fails fails with `value`, or one of them is a `present` filter that found its field missing ([present.filter]). Then its `$applies` row fails with `value`.

**[scope.unreadable]** When a filter fails with any other cause, ergo can't tell whether the subject is in scope. Its `$applies` row fails with the first such cause, in the order of [causes](#causes), even when another filter would rule it out, and the requirement isn't met, even with `min_subjects: 0`. A filter written wrong gives `ill_formed`, whatever the others give.

## Statuses

**[status]** Each requirement has a `status`:

- `not_met` when its `$well_formed`, `$min_subjects` or `$unique_ids` row fails, when an `$applies` row fails with anything but `value`, or when its checks fail under `require`
- `not_applicable` when it would otherwise be met but no subject is in scope, which only happens with `min_subjects: 0`
- `met` otherwise

**[compliant]** The report is `compliant` when it has at least one requirement and none is `not_met`. A policy with no requirements is never compliant, because it doesn't check anything.

**[report.requirements]** The report has an entry for each requirement, with its `description` and `meta`, or `""` and `{}` when it has none, its `require`, its `status`, `subjects` with `total`, the number found by `from`, and `matching`, the number in scope, and `checks`, each check as written with its `description`, `meta` and `expression`, plus the checks ergo adds. All the filters share one `$applies` entry.

## Row order

**[order]** Rows come in this order, whatever order the policy was written in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$unique_ids` rows, then all the `$applies` rows, then the requirements' own checks
2. within each of those, requirements in name order
3. within a requirement, subjects in the order `from` found them
4. within a subject, checks in name order

Names are sorted by code point.

## Violations

**[violations]** The violations of a report are its rows that are real problems, in the order of `results`, each with its check's `description` and `expression` added and its `$refs` added at the end of its `inputs`. A row of an `all` or `any` check keeps its `failed_items`. The violations leave out rows that passed, `$applies` rows that failed with `value`, and every row of a requirement that's `met` or `not_applicable`, so under `require: some` the subjects that failed aren't violations when another one passed. They're worked out from the report alone.
