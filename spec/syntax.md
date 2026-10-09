# How today's policies write checks

Draft 0.1. This file covers the syntax policies use today, where a check is a JSON object with an `op` and its parameters, and a path is a list of steps. It says how that syntax is read into the [model](semantics.md#the-model-of-a-check), what counts as written wrong, and how paths and checks are shown in the report. What a check means once it's read is in [semantics.md](semantics.md). A new syntax would get a file like this one and read into the same model.

[`policy/schema.json`](policy/schema.json) describes this syntax as a JSON Schema.

## Paths

**[path.not_a_list]** A path is a list of steps. A path that isn't a list is written wrong, even a string that names one key.

**[path.steps]** A string is a key, unless it's the first step and starts with `$`: `$$input` starts the path at the input, `$$params` at the params, and `$name` at a name. Any other first step that starts with `$$` is written wrong. A whole number of 0 or more, written as digits alone, is an index. `1.0`, `-1`, `true`, `null` and a list can't be steps. `{"where": {...}}` is a selector, `{"ref": [...]}` is a ref step, and `{"literal": "$schema"}` is the key `$schema`, read as written.

## Values

**[value.syntax]** A value is any JSON value, except that an object with a single `ref` key, `{"ref": [...]}`, is a ref, whose path is written like any other. An object with a single `literal` key, `{"literal": x}`, is the value `x` as written, so that's how to compare an object that looks like a ref.

**[value.literal]** Nothing inside a literal is read as a ref or a literal, so `{"literal": {"literal": 1}}` is the object `{"literal": 1}`.

**[value.nested]** A ref or literal anywhere deeper inside a value, like `[{"ref": [...]}]`, is written wrong, because it would be compared as an object. So is an object with a `ref` or `literal` key and any other key, or a ref whose path doesn't start with `$$input` or `$$params`. What's wrong is written `ref inside <field>`, `literal inside <field>` or `invalid ref`.

## Substitutes

**[substitute.syntax]** A check's `substitute` field holds its substitute, written like any other check.

## Checks written wrong

**[written_wrong.row]** A check [written wrong](semantics.md#the-model-of-a-check) makes the `$well_formed` row list it in its `inputs`, named `checks.<name>` or `applies_to.<name>`, after `count(checks)` and `require`, sorted by name, with the list of what's wrong, sorted.

**[present.written_wrong]** A check is written wrong when a parameter its operator needs is missing, which is written `missing <field>`, or when it has a field its operator doesn't take, written `unknown field <name>`. Besides its own parameters, any check can have `description`, `meta`, `expression`, `substitute` and `inputs`. A path that isn't a list is written `path not a list`, and one with a step that can't be a step is written `step that can't be a key in path`. The same goes for `left`, `right` and `each`.

**[tree.inputs]** A check whose path is missing or isn't a list has nothing to name, so its row's `inputs` is `[]`. So does a `compare` or `compare_time` whose `left` or `right` is missing or isn't a list, and an `all` or `any` whose inner check is missing or isn't an object.

**[range.written_wrong]** A `min` or `max` that isn't a number or a ref is written `invalid min` or `invalid max`, and a `min` above `max` is written `min above max`.

**[in.written_wrong]** `values` is a list, a literal holding a list, or a ref, and each item of a list can be a ref or a literal. Anything else is written `invalid values`.

**[patterns.written_wrong]** `patterns` is a list, a literal holding a list, or a ref, and each item of a list can be a ref or a literal. A `patterns` that isn't a list, or an item that isn't a string holding a valid pattern, is written `invalid patterns`, even when another pattern would match.

**[contains.written_wrong]** `includes` and `excludes` take `value` for one value and `values` for a list. Giving both is written `both value and values`, and neither `missing value or values`. An empty `values` is written `empty values`, and one that isn't a list `invalid values`.

**[compare.written_wrong]** A `cmp` that isn't one of `eq`, `ne`, `gt`, `gte`, `lt` and `lte` is written `invalid cmp`. A `compare` or `compare_time` check has no `path`.

**[list.written_wrong]** A name in `as` must be a string that doesn't start with `$`, or it's written `invalid name`. A name already given is written `name given twice`, and a path starting with a name nothing gave is written `unknown name $<name>`. `as` or `each` on another operator is written `as can't go here` or `each can't go here`. A missing inner check is written `missing check`, one that isn't an object `invalid check`, a third level `nested too deep`, and a custom operator `<op> can't go here` (see [REFERENCE.md](../REFERENCE.md#custom-operators)).

**[any_of.written_wrong]** `options` is an object of named options, or a list of them, named by their position as text: `"0"`, `"1"` and so on. A missing `options` is written `missing options`, an empty one `empty options`, an empty option `empty option <name>`, an option that isn't a list `option <name> not a list`, and an `any_of` or custom operator inside an option `<op> can't go here`.

## Naming a path

A row's `inputs`, a ref's entry in `$refs` and an item in `failed_items` name the paths they read.

**[name.keys]** Keys are joined with `.`. A key is written as it is when it starts with an ASCII letter, `_` or `$` and the rest is ASCII letters, digits, `_`, `$` or `-`, and in double quotes otherwise. An index is written as digits: `x.1`.

**[name.selector]** A selector is written `[k=="a"]`, its fields sorted and joined with ` and `.

**[name.ref_step]** A ref step is written `[$$params.key]`.

**[name.subject]** A path with no steps on a subject is named after `from` with `[]` added, like `things[]`.

**[name.invalid_step]** A step that can't be a step is written `<invalid step>`.

**[name.list]** Inside `all` or `any`, a path is named after the list: `cs[].s`, or `cs[]` for the items themselves. With `each`, the inner lists are `prs[].cs`.

## Expressions

Each check's definition in the report has an `expression` that says what it checks.

**[render.value]** A value is shown as JSON: a string in double quotes, escaping only `"`, `\` and control characters, a number in plain decimal with no exponent and no trailing zeros (`1.50` and `1e2` are shown as `1.5` and `100`), and lists and objects with `, ` after each item and `: ` after each key. An object's keys are sorted by code point. A literal is shown as the value it holds. A ref is shown as its path's name, without quotes, like `$$params.allowed`.

**[render.path]** A path is shown with its [name](#naming-a-path).

**[render.missing]** A parameter that's missing is shown as `<missing value>`, `<missing values>` and so on, and a ref written wrong as `<invalid ref>`. A `path`, `left` or `right` that isn't a list is shown as `<invalid path>`, `<invalid left>` or `<invalid right>`.

**[present.expression]** `<path> is present`

**[missing.expression]** `<path> is missing`

**[equals.expression]** `<path> == <value>`

**[in.expression]** `<path> in [<values>]`, with each value sorted by the text it's shown as, in code point order. Values read through a ref are shown as the ref's name: `x in $$params.allowed`.

**[non_empty_string.expression]** `<path> is a non-empty string`

**[empty.expression]** `<path> is empty`

**[range.expression]** `<path> >= <min> and <path> <= <max>`

**[patterns.expression]** `<path> matches one of [<patterns>]` and `<path> matches none of [<patterns>]`, with the patterns sorted as for `in`, or the ref's name.

**[contains.expression]** `contains(<path>, <value>)` and `not contains(<path>, <value>)`, or with `values`, `contains_all(<path>, [<values>])` and `contains_none(<path>, [<values>])`, sorted as for `in`. When both or neither are given, `<both value and values>` or `<missing value or values>` takes the value's place.

**[compare.expression]** `<left> <cmp> <right>`, like `a lt $$input.limit`, with `cmp` as written.

**[time.expression]** Written like `compare`'s.

**[substitute.expression]** A check with a substitute is shown as `<check>, or substitute: <substitute>`, like `pull_request is present, or substitute: verified == true`.

**[list.expression]** `every <list>: <inner>` or `some <list>: <inner>`, with the inner check's paths named inside the item. With `each`, the list is shown as `<list>[].<each>`, and with `as`, it's followed by ` as $<name>`. A path with no steps in the inner check is named `<list>[]`, like `every bs: bs[] matches one of ["^main$"]`. A missing or badly written inner check is shown as `<missing check>`, `<invalid check>`, `<nested too deep>` or `<op can't go here>`, and a bad name as `<invalid name>` or `<name given twice>`.

**[any_of.expression]** `one of: ` followed by the options, sorted by name as text and joined with ` | `, each written `<name>(<check> and <check>)` with its checks in the order written. A missing `options` is shown as `<missing options>`, an empty one as `<empty options>`, an empty option as `<name>(<empty option>)` and one that isn't a list as `<name>(<invalid option>)`.

## Checks ergo adds

**[added.text]** The checks ergo adds have these descriptions and expressions, where `<type>` is the requirement's `subject_type`, `subject` by default, and `<from>` is the name of `from`, or `$$input` when it has no steps:

| Check | Description | Expression |
| --- | --- | --- |
| `$well_formed` | `The requirement is written correctly` | `fields are known and have the right types and count(checks) >= 1 and require in ["every", "some"] and steps are keys and numbers fit a float and checks are written right` |
| `$min_subjects` | `The in-scope <type> count is at least <n>`, or with `min_subjects: 0`, `The <type> list can be read` | `count(matching(<from>)) >= <n>`, or `<from> can be read` |
| `$unique_ids` | `Every <type> id is unique` | `count(repeated(ids(<from>))) == 0` |
| `$applies` | `The <type> is in scope` | the filters' expressions in name order, joined with ` and ` |

**[added.inputs]** `$min_subjects` names its input `in-scope <type> count`, and `$unique_ids` names its input `repeated <type> ids`. `$well_formed` names its first two `count(checks)` and `require`, and when `require` is written wrong, its value is `["neither every nor some"]`. A field ergo doesn't know is listed with `["unknown field"]`, and `checks: {}` with `["empty"]`.
