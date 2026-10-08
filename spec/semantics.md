# How ergo turns a policy and an input into a report

Draft 0.1. This covers reading values, causes, expressions and the operators `present`, `missing`, `equals` and `in` so far. Everything else is still described only in [REFERENCE.md](../REFERENCE.md).

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

**[render.missing]** A parameter that's missing is shown as `<missing value>`, `<missing values>` and so on, and a ref written wrong as `<invalid ref>`.

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

**[present.written_wrong]** It's [written wrong](#checks-written-wrong) when `path` is missing, isn't a list, or has a step that can't be a key, or when the check has a field besides `op`, `path`, `description`, `meta`, `expression`, `substitute` and `inputs`. What's wrong is written `missing path`, `path not a list`, `step that can't be a key in path` or `unknown field <name>`. The same goes for `missing`, `equals` and `in`, which also take the fields they need: `value` for `equals` and `values` for `in`.

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
