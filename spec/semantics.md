# How ergo turns a policy and an input into a report

Draft 0.1. This covers reading values, causes, expressions and the operators `present`, `missing`, `equals`, `in`, `non_empty_string`, `empty`, `range`, `matches_any`, `not_matches_any`, `includes`, `excludes`, `compare`, `compare_time`, `all`, `any` and `any_of` so far. Everything else is still described only in [REFERENCE.md](../REFERENCE.md).

Each rule has a name in brackets, like **[present.missing]**. The cases in [`cases/`](cases) list the rules they test, so you can find the cases for a rule and the rule behind a case. An implementation follows every rule here, and where it does something else, it's wrong, whatever `ergo.rego` does.

## Terms

- The **input** is the JSON document being checked.
- The **params** are a second JSON document the policy can read, or nothing.
- A **subject** is one thing a requirement checks, found in the input by `from`.
- A **check** is one named test in a requirement's `checks` or `applies_to`.
- A **row** is the result of one check on one subject, or of one check ergo adds to a requirement.

## Reading a path

A path is a list of steps, read from a starting value one step at a time. **[path.not_a_list]** A path that isn't a list is written wrong (see [Checks written wrong](#checks-written-wrong)), even a string that names one key.

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

**[path.start]** A path starts at the subject, unless its first step is `$$input`, which starts at the input, or `$$params`, which starts at the params. With no params, or params that aren't an object, a `$$params` path ends `absent`.

**[path.empty]** An empty path reads its starting value itself, so on a subject it never ends `not_an_object`. A `null` subject ends `null`.

**[path.not_an_object]** A non-empty path that starts at a subject that isn't an object ends `not_an_object`, `null` subjects included.

**[path.absent]** A string key reads that key of an object. A key the object doesn't have ends `absent`. An index (a whole number of 0 or more) reads that item of a list, and an index past the end ends `absent`. Once a value is missing or `null` partway along, the path ends `absent`, however many steps are left.

**[path.null]** A path whose last step reads `null` ends `null`.

**[path.unusable]** A string key on anything but an object, or an index on anything but a list, ends `unusable`. So does any step after a string, number or boolean. `["x", "y"]` on `"x": "a"` and on `"x": [{"y": 1}]` both end `unusable`, and `["x", 1]` on `"x": {"1": "a"}` does too.

**[path.selector]** A selector step, `{"where": {...}}`, reads the one item of a list, or of an object's values, whose fields equal every field in `where`. No match ends `unmatched`, and more than one ends `ambiguous`. A selector on a value that's missing or `null` ends `absent`, the same as a key would.

**[path.ref_step]** A ref step, `{"ref": [...]}`, reads its ref first and uses the value as the key for that step. If the ref ends anything but `found`, the path ends there with the ref's outcome, and a value that can't be a key ends `unusable`.

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

## Naming a path

A row's `inputs` name each path it read. **[name.keys]** Keys are joined with `.`. A key is written as it is when it starts with an ASCII letter, `_` or `$` and the rest is ASCII letters, digits, `_`, `$` or `-`, and in double quotes otherwise. An index is written as digits: `x.1`. **[name.selector]** A selector is written `[k=="a"]`, its fields sorted and joined with ` and `. **[name.ref_step]** A ref step is written `[$$params.key]`. **[name.subject]** An empty path on a subject is named after `from` with `[]` added, like `things[]`. **[name.invalid_step]** A step that can't be a key is written `<invalid step>`.

## Values in a check

**[value.equal]** Two values are equal when they have the same type and the same content. Numbers are compared by value, so `1` equals `1.0` and `1e0`. Strings are equal when they hold the same code points. Lists are equal when they have the same length and equal items in the same order, and objects when they have the same keys with equal values. `"1"` doesn't equal `1`, and `[1, 2]` doesn't equal `[2, 1]`.

**[value.ref]** A value written `{"ref": [...]}` is read from the input or the params. Its path must start with `$$input` or `$$params`, and every other step must be a key. The check is then run with the value it reads. If the ref ends anything but `found`, the check fails with the ref's outcome as its cause, whatever the subject holds. A ref that reads `null` fails it as `null`, even when the field is `null` too.

**[value.literal]** A value written `{"literal": x}` is `x` exactly as written. Nothing inside it is read as a ref or a literal.

**[value.nested]** A ref or literal anywhere deeper inside a value, like `[{"ref": [...]}]`, is written wrong, because it would be compared as an object. So is an object with a `ref` or `literal` key and any other key, or a ref whose path doesn't start with `$$input` or `$$params`. What's wrong is written `ref inside <field>`, `literal inside <field>` or `invalid ref`.

**[value.refs]** A check that has refs gets `$refs` in its definition in the report: one entry for each ref, named after its path, like `$$params.allowed`, with the value it read, or `null`. They're sorted by name.

## Expressions

Each check's definition in the report has an `expression` that says what it checks.

**[render.value]** A value written in the policy is shown as JSON: a string in double quotes, escaping only `"`, `\` and control characters, a number in plain decimal with no exponent and no trailing zeros (`1.50` and `1e2` are shown as `1.5` and `100`), and lists and objects with `, ` after each item and `: ` after each key. An object's keys are sorted by code point. A literal is shown as the value it holds. A ref is shown as its path's name, without quotes, like `$$params.allowed`.

**[render.path]** A path is shown with its name, as in [Naming a path](#naming-a-path).

**[render.missing]** A parameter that's missing is shown as `<missing value>`, `<missing values>` and so on, and a ref written wrong as `<invalid ref>`. A `path`, `left` or `right` that isn't a list is shown as `<invalid path>`, `<invalid left>` or `<invalid right>`.

## Checks written wrong

**[written_wrong]** A check that's written wrong fails every row with cause `ill_formed`, whatever the subject holds, and the requirement's `$well_formed` row fails with cause `value`. That row has one entry in its `inputs` for each such check, named `checks.<name>` or `applies_to.<name>`, after `count(checks)` and `require`, sorted by name, whose value is the list of what's wrong, sorted.

## `present`

`{"op": "present", "path": [...]}` asks whether a field is there.

**[present.pass]** It passes when its path ends `found`. Any value counts, `""`, `false`, `0`, `[]` and `{}` included.

**[present.missing]** It fails with cause `value` when its path ends `absent` or `null`. Whether the field is there is the question it asks, so "it isn't" is a sound answer, and the cause says so.

**[present.no_params]** On a `$$params` path, it fails with cause `absent` instead when there are no params, or they aren't an object. Then the params weren't given at all, so ergo can't tell whether the field would be there, and a policy run without its params fails instead of ruling every subject out. When the params are an object without the field, it fails with `value` as usual.

**[present.other]** It fails with the outcome as its cause when its path ends any other way: `not_an_object`, `unusable`, `unmatched` or `ambiguous`. A ref step whose ref can't be read keeps the ref's cause too, even `absent` or `null`, because then the field it looks for is unknown, not missing.

**[present.inputs]** Its row has one entry in `inputs`: the path's name and the value read, or `null` when nothing was. When `path` is missing or isn't a list, there's nothing to name, so `inputs` is `[]`. `missing`, `equals` and `in` do the same.

**[present.expression]** Its expression is `<path> is present`.

**[present.written_wrong]** It's [written wrong](#checks-written-wrong) when `path` is missing, isn't a list, or has a step that can't be a key, or when the check has a field besides `op`, `path`, `description`, `meta`, `expression`, `substitute` and `inputs`. What's wrong is written `missing path`, `path not a list`, `step that can't be a key in path` or `unknown field <name>`. The same goes for every operator in this document, which also take the fields they need, like `value` for `equals`, `values` for `in`, `min` and `max` for `range`, and `patterns` for `matches_any` and `not_matches_any`. A missing one is written `missing <field>`.

**[present.filter]** In `applies_to`, a `present` filter that fails with cause `value` rules the subject out, whatever the other filters give. Its `$applies` row fails with cause `value`, and the subject gets no other rows. Any other cause fails the requirement, as it does for every filter. **[applies.inputs]** The `$applies` row lists each path its filters read once, sorted by name.

## `missing`

`{"op": "missing", "path": [...]}` asks whether a field is missing. It's the opposite of `present`.

**[missing.pass]** It passes where `present` would fail with cause `value`: when its path ends `absent` or `null`.

**[missing.fail]** It fails with cause `value` where `present` would pass, so a field that's there fails it whatever it holds, `false` and `""` included. Everywhere else, it fails with the cause `present` would give, so with no params a `missing` check on a `$$params` path fails as `absent` instead of passing.

**[missing.expression]** Its expression is `<path> is missing`.

**[missing.filter]** In `applies_to`, it rules out a subject whose field is there, with cause `value`, as any filter does.

## `equals`

`{"op": "equals", "path": [...], "value": v}` asks whether a field equals a value.

**[equals.pass]** It passes when its path ends `found` or `null` and the value read [equals](#values-in-a-check) `value`. So `"value": null` passes on a field that's there and `null`.

**[equals.fail]** It fails with the path's outcome as its cause when the path ends anything but `found` or `null`, a missing field included, even with `"value": null`. It fails with `null` when the field is `null` and `value` isn't. When the field was read, it fails with `value`, even when the types differ.

**[equals.expression]** Its expression is `<path> == <value>`.

## `in`

`{"op": "in", "path": [...], "values": [...]}` asks whether a field is one of a list of values.

**[in.values]** `values` is a list, a literal holding a list, or a ref. Each item of a list written in the policy can be a ref or a literal. An item read through a ref, or held in a literal, is taken as it is, so an object in it that looks like a ref is compared as an object. When `values` is missing it's written wrong, as `missing values`, and when it isn't a list it's written wrong as `invalid values`. When a ref reads something other than a list, the check fails as `unusable`.

**[in.pass]** It passes when its path ends `found` and the value read [equals](#values-in-a-check) one of `values`.

**[in.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, so a missing or `null` field fails even when `values` holds `null`. When the field was read, it fails with `value`, an empty `values` included.

**[in.expression]** Its expression is `<path> in [<values>]`, with each value shown as in [Expressions](#expressions) and sorted by the text it's shown as, in code point order. A `values` read through a ref is shown as the ref's name: `x in $$params.allowed`.

## `non_empty_string`

`{"op": "non_empty_string", "path": [...]}` asks whether a field is a string with something in it.

**[non_empty_string.pass]** It passes when its path ends `found` and the value is a string other than `""`. A string of spaces passes.

**[non_empty_string.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. When the field was read, it fails with `value`, whatever its type, because checking the type is what it's for.

**[non_empty_string.expression]** Its expression is `<path> is a non-empty string`.

## `empty`

`{"op": "empty", "path": [...]}` asks whether a field is an empty list.

**[empty.pass]** It passes when its path ends `found` and the value is `[]`.

**[empty.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`. A list with items fails with `value`. Anything else that was read, `""` and `{}` included, fails with `unusable`.

**[empty.expression]** Its expression is `<path> is empty`.

## `range`

`{"op": "range", "path": [...], "min": a, "max": b}` asks whether a field is a number between two others, both included.

**[range.bounds]** `min` and `max` are numbers, or refs. A bound that isn't a number, or a `min` above `max`, is written wrong, as `invalid min`, `invalid max` or `min above max`. When a ref reads something other than a number, or the bounds it reads put `min` above `max`, the check fails with `unusable`.

**[range.pass]** It passes when its path ends `found`, the value is a number, and `min <= value <= max`, compared by value.

**[range.fail]** It fails with the path's outcome as its cause when the path ends anything but `found`, and with `unusable` when the value isn't a number. A number outside the range fails with `value`.

**[range.expression]** Its expression is `<path> >= <min> and <path> <= <max>`.

## `matches_any` and `not_matches_any`

`{"op": "matches_any", "path": [...], "patterns": [...]}` asks whether a field is a string that matches at least one regular expression. `not_matches_any` asks whether it matches none of them.

**[patterns.syntax]** A pattern is a regular expression in [RE2 syntax](https://github.com/google/re2/wiki/Syntax), run on code points. So there's no lookahead and no backreference. `.` doesn't match a newline, `$` only matches at the very end of the string, and `(?i)` turns on case-insensitive matching. A pattern isn't anchored: `svc_` matches `my_svc_account`.

**[patterns.list]** `patterns` is a list, a literal holding a list, or a ref, and each item of a list written in the policy can be a ref or a literal. A missing `patterns` is written wrong, as `missing patterns`. When it isn't a list, or an item isn't a string that's a valid pattern, it's written wrong as `invalid patterns`, even when another pattern would match. When a ref reads something other than a list, or a pattern that isn't a string or isn't valid, the check fails with `unusable`.

**[patterns.pass]** `matches_any` passes when its path ends `found`, the value is a string, and at least one pattern matches it. `not_matches_any` passes when its path ends `found`, the value is a string, and no pattern matches it. So with an empty `patterns`, `matches_any` always fails and `not_matches_any` passes on any string.

**[patterns.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`, and with `unusable` when the value isn't a string. Otherwise they fail with `value`.

**[patterns.expression]** Their expressions are `<path> matches one of [<patterns>]` and `<path> matches none of [<patterns>]`, with the patterns shown as values and sorted by the text they're shown as, as for `in`. Patterns read through a ref are shown as the ref's name.

## `includes` and `excludes`

`{"op": "includes", "path": [...], "value": v}` asks whether a field is a list that contains a value, and `excludes` whether it's a list that doesn't. With `"values": [...]` in place of `value`, `includes` asks for every one of them and `excludes` for none.

**[contains.value]** `value` is one value, so a list given as `value` is looked for as a list inside the field. `values` is a list, a literal holding a list, or a ref, and its items can be refs or literals. Giving both, or neither, is written wrong, as `both value and values` or `missing value or values`. An empty `values` would pass every list, so it's written wrong as `empty values`, and a `values` that isn't a list as `invalid values`. When a ref reads something other than a non-empty list for `values`, the check fails as `unusable`.

**[contains.pass]** `includes` passes when its path ends `found`, the value is a list, and an item [equals](#values-in-a-check) `value`, or with `values`, when each of them equals an item. `excludes` passes when its path ends `found`, the value is a list, and no item equals `value`, or any of `values`. So an empty list fails `includes` and passes `excludes`.

**[contains.fail]** Both fail with the path's outcome as their cause when the path ends anything but `found`, and with `unusable` when the value isn't a list, a string or an object included. Otherwise they fail with `value`.

**[contains.expression]** With `value`, the expressions are `contains(<path>, <value>)` and `not contains(<path>, <value>)`. With `values`, they're `contains_all(<path>, [<values>])` and `contains_none(<path>, [<values>])`, with the values sorted as for `in`. When both or neither are given, `<both value and values>` or `<missing value or values>` takes the value's place.

## `compare`

`{"op": "compare", "left": [...], "right": [...], "cmp": c}` compares two fields of the same subject. `cmp` is one of `eq`, `ne`, `gt`, `gte`, `lt` and `lte`. Anything else is written wrong as `invalid cmp`, and a missing `left`, `right` or `cmp` as `missing left` and so on. A `compare` check has no `path`.

**[compare.pass]** It passes when both paths end `found`, the two values have the same type, and `left cmp right` holds. `eq` and `ne` use [equality](#values-in-a-check) and work on any type. `gt`, `gte`, `lt` and `lte` only work on two numbers, compared by value, or two strings, compared code point by code point, so `"Z"` comes before `"a"` and `"！"` (U+FF01) before `"😀"` (U+1F600).

**[compare.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, so two `null` fields fail as `null`, even with `eq`. When both were read, it fails with `unusable` when their types differ, even with `ne`, and when `gt`, `gte`, `lt` or `lte` is used on anything but two numbers or two strings. Otherwise it fails with `value`.

**[compare.inputs]** Its row has two entries in `inputs`, `left` then `right`. When either is missing or isn't a list, `inputs` is `[]`.

**[compare.expression]** Its expression is `<left> <cmp> <right>`, like `a lt $$input.limit`, with `cmp` as written.

## `compare_time`

`{"op": "compare_time", "left": [...], "right": [...], "cmp": c}` compares two times. It's written like `compare`.

**[time.format]** A time is either a number or an RFC 3339 string. A string has the form `YYYY-MM-DDTHH:MM:SS`, then optionally `.` and one or more digits, then `Z` or an offset `+HH:MM` or `-HH:MM`. The `T` and `Z` are uppercase. The date must exist, so `2024-02-30` and `1900-02-29` don't. The hour is 00 to 23, minutes and seconds 00 to 59, and the offset 00:00 to 23:59. The year, as written, is 1678 to 2261. Only the first nine digits of the fraction count. Any other string isn't a time.

**[time.pass]** It passes when both paths end `found`, both values are RFC 3339 strings or both are numbers, and `left cmp right` holds. Strings are compared as the instants they name, so `2024-01-01T01:00:00+01:00` equals `2024-01-01T00:00:00Z`. Numbers are compared by value, with no unit attached.

**[time.fail]** It fails with the worse of the two paths' outcomes when either ends anything but `found`, and with `unusable` when the values aren't two times in the same format, a number and a string included. Otherwise it fails with `value`.

**[time.expression]** Its expression is written like `compare`'s.

## `all` and `any`

`{"op": "all", "path": [...], "check": {...}}` asks whether every item of a list passes a check, and `any` whether at least one does.

**[list.read]** The path must end `found` on a list. A list that's missing fails the check as `absent`, a `null` one as `null`, and anything else, an object included, as `unusable`. An empty list fails as `value`, because no items isn't proof of anything.

**[list.items]** The inner `check` runs on each item, with the item as its subject, so its paths start inside the item. An empty path reads the item itself, and an item that isn't an object fails a non-empty path as `not_an_object`.

**[list.pass]** `all` passes when the list isn't empty and every item passes. `any` passes when it isn't empty and at least one item does.

**[list.cause]** When the items decide the result and it fails, the cause is the first, in the order of [causes](#causes), among the items that failed. So when one item fails as `value` and another is missing its field, the check fails as `absent`, because the second one might have passed.

**[list.each]** With `each`, a path inside each item of the list, the check runs on every item of every inner list. Every inner list must be readable, a list and not empty, for `all` and `any` alike. One that isn't fails the check with the cause it would give as a list, even when an item elsewhere passes.

**[list.as]** `as` names each item, so a check nested inside can still read it as `$name` once its own paths start somewhere else. The name is a string that doesn't start with `$`. Otherwise it's written wrong as `invalid name`, and a name already given by `from` or an outer check as `name given twice`. A path that starts with a name nothing gave, or one given in a neighbouring `any_of` option, is written wrong as `unknown name $name`. `as` or `each` on any operator other than `all` and `any` is written wrong as `as can't go here` or `each can't go here`.

**[list.inner]** The inner check is a basic operator, an `any_of`, or another `all` or `any`. One `all` or `any` can sit inside another, but a third is written wrong as `nested too deep`. An `any_of` doesn't count as a level, but an `all` or `any` in one of its options does. A missing check is written wrong as `missing check`, one that isn't an object as `invalid check`, and a custom operator as `<op> can't go here` (see [REFERENCE.md](../REFERENCE.md#custom-operators)).

**[list.inputs]** When the inner check has a `path` that starts inside the item, not with `$$input`, `$$params` or a name, the row shows that path for every item, named `<list>[].<path>`, like `cs[].s` with `[true, false, null]`. That holds for an inner `all` or `any` too, so its lists are shown. An empty path shows the items themselves, named `<list>[]`. Any other inner check, like `compare` or `any_of`, shows the whole items, named `<list>[]`. In both cases, each `$$input`, `$$params` or `$name` path the inner check reads follows, except names the check itself gives. With `each`, the items are the inner lists, named `<list>[].<each>`. A list that can't be read shows `[]` as its value. When the inner check is missing or isn't an object, `inputs` is `[]`.

**[list.failed_items]** The row also has `failed_items`, the items that made it fail, in list order. Each one has its `path`, like `cs[1]` or, with `each`, `prs[0].cs[1]`, its own `cause`, and its `value`. With `each`, an inner list that can't be read or is empty is listed in place of its items, like `prs[1].cs` with the value it read, or `null`. An item that a `present` check finds missing is listed with cause `value`. For a nested check, only the outer items are listed. `failed_items` is `[]` when the check passes, even for an `any` with items that failed, and when the list itself can't be read. When the check is written wrong, every item is listed as `ill_formed`, and when a ref can't be read, every failing item is listed with the ref's cause.

**[list.expression]** The expression is `every <list>: <inner>` or `some <list>: <inner>`, with the inner check rendered with paths named inside the item. With `each`, the list is shown as `<list>[].<each>`, and with `as`, it's followed by ` as $<name>`. An empty path in the inner check is named `<list>[]`, like `every bs: bs[] matches one of ["^main$"]`. A missing or badly written inner check is shown as `<missing check>`, `<invalid check>`, `<nested too deep>` or `<op can't go here>`, and a bad name as `<invalid name>` or `<name given twice>`.

## `any_of`

`{"op": "any_of", "options": {...}}` passes when one of its options passes. Each option is a list of checks that must all pass.

**[any_of.options]** `options` is an object of named options, or a list of them, named by their position. Each option is a non-empty list of basic checks, `all` or `any`. A missing `options` is written wrong as `missing options`, an empty one as `empty options`, an empty option as `empty option <name>`, one that isn't a list as `option <name> not a list`, and an `any_of` or a custom operator inside an option as `<op> can't go here`.

**[any_of.pass]** It passes when every check of at least one option passes.

**[any_of.cause]** Each option that fails has a cause: `value` when one of its `present` checks found its field missing, and otherwise the first, in the order of [causes](#causes), among its checks, or `value`. The row takes the first among its options.

**[any_of.inputs]** The row shows every path any option reads, once each, sorted by name. For an `all` or `any` in an option, that's its list, with the whole items, and the names it reads.

**[any_of.expression]** The expression is `one of: ` followed by the options, sorted by name and joined with ` | `, each written `<name>(<check> and <check>)` with its checks in the order written. A missing `options` is shown as `<missing options>`, an empty one as `<empty options>`, an empty option as `<name>(<empty option>)` and one that isn't a list as `<name>(<invalid option>)`.

**[any_of.no_failed_items]** An `any_of` row has no `failed_items`, even with an `all` or `any` inside it.
