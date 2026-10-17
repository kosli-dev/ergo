# How today's policies write checks

Draft 0.1. This file covers the syntax policies use today, where a check is a JSON object with an `op` and its parameters, and a path is a list of steps. It says how that syntax is read into the [model](semantics.md#the-model-of-a-check), what counts as written wrong, and how paths and checks are shown in the report. What a check means once it's read is in [semantics.md](semantics.md). A new syntax would get a file like this one and read into the same model.

[`policy/schema.json`](policy/schema.json) describes this syntax as a JSON Schema.

## Policies

**[policy.shape]** A policy is an object with two sections. `subjects` maps each subject's name to its definition, with `from`, `identified_by`, `applies_to` and `description`, or to `null` for a subject with none of them (see [subjects.no_from](semantics.md#requirements)). `requirements` maps each requirement's name to its definition, with `subject`, `checks`, `require`, `min_subjects`, `description` and `meta`. `subject` is the name of an entry in `subjects`. The policy can also have a `description` and a `meta` of its own, next to its sections. A subject definition can also build on another with `of`, which the spec doesn't cover yet (see [OPEN.md](OPEN.md)).

**[sentence_ops.syntax]** `empty_string_or_list`, `not_empty_string_or_list`, `not_in`, `has_type`, `all_of`, `every`, `some` and `for`, the comparisons `starts_with`, `ends_with`, `in`, `not_in`, `includes`, `excludes`, `includes_all`, `excludes_all`, `matches_any` and `not_matches_any` of `compare`, and the `compare` sides `count_of`, `sum_of` and an `add` with `text`, are only read from sentences. A check in this syntax with one of them as its `op` is written wrong, with `unknown op <op>`, a `compare` with one of them as its `cmp` with `invalid cmp`, and one with one of them as a side with `invalid left` or `invalid right`, as a misspelt operator is, wherever it is and even when it's a copy of what a sentence in the same policy reads into. Whether a check was written as a sentence decides, not what it looks like.

**[policy.old_fields]** A requirement that has `from`, `identified_by`, `applies_to` or `subject_type`, or any other field it doesn't take, is written wrong, and the `$well_formed` row lists the field with `["unknown field"]`. A subject definition with a field it doesn't take is written wrong the same way. So is one with `id`, the old name for `identified_by`.

## Paths

**[path.not_a_list]** A path is a list of steps. A path that isn't a list is written wrong, even a string that names one key.

**[path.steps]** A string is a key, unless it's the first step and starts with `$`: `$$input` starts the path at the input, `$$params` at the params, and `$name` at a name. Any other first step that starts with `$$` is written wrong. A whole number of 0 or more, written as digits alone, is an index. `1.0`, `-1`, `true`, `null` and a list can't be steps. `{"where": {...}}` is a selector, `{"ref": [...]}` is a ref step, and `{"literal": "$schema"}` is the key `$schema`, read as written.

## Values

**[value.syntax]** A value is any JSON value, except that an object with a single `ref` key, `{"ref": [...]}`, is a ref, whose path is written like any other. An object with a single `literal` key, `{"literal": x}`, is the value `x` as written, so that's how to compare an object that looks like a ref.

**[value.literal]** Nothing inside a literal is read as a ref or a literal, so `{"literal": {"literal": 1}}` is the object `{"literal": 1}`.

**[value.nested]** A ref or literal anywhere deeper inside a value, like `[{"ref": [...]}]`, is written wrong, because it would be compared as an object. So is an object with a `ref` or `literal` key and any other key, or a ref whose path doesn't start with `$$input` or `$$params`. What's wrong is written `ref inside <field>`, `literal inside <field>` or `invalid ref`.

## Substitutes

**[substitute.syntax]** A check's `substitute` field holds its substitute, written like any other check.

## Custom operators

**[custom.syntax]** A custom operator check can have any fields, besides `op`. Because ergo can't work out what the operator reads or how to describe it, the check also gives `expression`, the text the report shows, and `inputs`, a list of the paths it reads. An entry in `inputs` can be a path, or `{"path": [...], "each": [...]}` to read one field from every item of a list. `ergo.rego` needs them. An engine that knows more about the operator, like the Rust port on the `core/conformance-suite` branch, uses them when they're there.

## Compare

**[compare.derived]** A side of `compare` can also be a `literal`, or a value worked out from the subject: `count`, `sum` or `add`. [REFERENCE.md](../REFERENCE.md#derived-values) says how each one is written and read. A side that isn't a path, a `literal` or one of those is written wrong, and the `$well_formed` row says `invalid left` or `invalid right`. `compare` also takes `within` with `eq`.

## Checks written wrong

**[written_wrong.row]** A check [written wrong](semantics.md#the-model-of-a-check) makes the `$well_formed` row list it in its `inputs`, after `count(checks)` and `require`, sorted by name, with the list of what's wrong, sorted. A check of the requirement is named `checks.<name>`. A filter is named `subjects.<subject>.applies_to.<name>`, and a field of a subject definition `subjects.<subject>.<field>`, like `subjects.deployment.from`. A `description` or `meta` of the policy that's written wrong comes last, named `policy description` or `policy meta`, in words and not as a path, because a name that starts with `$` is one a check can read.

**[written_wrong.fields]** A check is written wrong when a parameter its operator needs is missing, which is written `missing <field>`, or when it has a field its operator doesn't take, written `unknown field <name>`. Besides its own parameters, any check can have `description`, `meta`, `expression`, `substitute` and `inputs`. A path that isn't a list is written `path not a list`, and one with a step that can't be a step is written `step that can't be a key in path`. The same goes for `left`, `right` and `each`.

**[written_wrong.inputs]** A check whose path is missing or isn't a list has nothing to name, so its row's `inputs` is `[]`. So does a `compare` or `compare_time` whose `left` or `right` is missing or isn't a list, and an `all` or `any` whose inner check is missing or isn't an object.

**[range.written_wrong]** A `min` or `max` that isn't a number or a ref is written `invalid min` or `invalid max`, and a `min` above `max` is written `min above max`.

**[in.written_wrong]** `values` is a list, a literal holding a list, or a ref, and each item of a list can be a ref or a literal. Anything else is written `invalid values`. A list whose written values have more than one type, leaving refs and `null` aside, is written `values of mixed types`.

**[patterns.written_wrong]** `patterns` is a list, a literal holding a list, or a ref, and each item of a list can be a ref or a literal. A `patterns` that isn't a list, or an item that isn't a string holding a valid pattern, is written `invalid patterns`, even when another pattern would match.

**[contains.written_wrong]** `includes` and `excludes` take `value` for one value and `values` for a list. Giving both is written `both value and values`, and neither `missing value or values`. An empty `values` is written `empty values`, and one that isn't a list `invalid values`. A list whose written values have more than one type, leaving refs and `null` aside, is written `values of mixed types`.

**[compare.written_wrong]** A `cmp` that isn't one of `eq`, `ne`, `gt`, `gte`, `lt` and `lte` is written `invalid cmp`. A `compare` or `compare_time` check has no `path`.

**[list.written_wrong]** A name in `as` must be a string that doesn't start with `$` and isn't `params` or `input`, which would name like the params and the input, or it's written `invalid name`. A name already given is written `name given twice`, and a path starting with a name nothing gave is written `unknown name $<name>`. `as` or `each` on another operator is written `as can't go here` or `each can't go here`. A missing inner check is written `missing check`, one that isn't an object `invalid check`, a third level `nested too deep`, and a custom operator `<op> can't go here` (see [REFERENCE.md](../REFERENCE.md#custom-operators)).

**[any_of.written_wrong]** `options` is an object of named options, or a list of them, named by their position as text: `"0"`, `"1"` and so on. A missing `options` is written `missing options`, an empty one `empty options`, an empty option `empty option <name>`, an option that isn't a list `option <name> not a list`, and an `any_of` or custom operator inside an option `<op> can't go here`.

## Naming a path

A row's `inputs`, a ref's entry in `$refs`, an item in `failed_items` and a path in an `expression` name the paths they read the way a sentence writes them (see [sentences.md](sentences.md#paths)). A name made of keys, positions and `named by` one key, starting at the subject, `$params` or `$input`, can be pasted into a sentence. Names given by `each_as` or `as`, like `$pr.author`, selectors, the `[]` of a list's items and refs of more than one key have no sentence spelling yet, so those can't. The names `$well_formed` gives the policy's own fields, like `checks.c` or `subjects.deployment.from`, follow [written_wrong.row](#checks-written-wrong) instead.

**[name.keys]** Keys are joined with `.`. A key is written as it is when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` or `-`, and in double quotes otherwise, so a key with a `$` in it is quoted, like `"$schema".x` or `x."$b"`. A first key that's a word of the sentence grammar (see [sentence.words](sentences.md#words-a-field-cant-be-called)) has a `.` in front, like `.empty` or `.a`. A path that starts at the input or the params starts with `$input` or `$params`, and one that starts at a name keeps it, like `$pr.author`. Since `params` and `input` can't be names, a path that starts with `$params` or `$input` in today's syntax names nothing and is shown as `<unknown name $params>`, so it never looks like the params or the input.

**[name.index]** An index at the end of a path is written `item <n> of <path>`, counting from 1, so `["xs", 1]` is `item 2 of xs`, and so is a position in a list check's `failed_items` whose path is empty: `item 2 of xss[]`. A number written as a `literal` is named like the index it reads. An index with more steps after it, or with nothing before it, is written in brackets, counting from 0: `xs[1].k`, `[0]`.

**[name.selector]** A selector is written `[k=="a"]`, its fields sorted and joined with ` and `.

**[name.ref_step]** A ref step whose ref reads one string key of the input or the params is written ` named by $params.key`, like `obj named by $params.k.v`. Any other ref step, and one that starts the path, is written in brackets, like `k[$params.a.b]` or `[$params.key]`.

**[name.subject]** A path with no steps on a subject is named after the subject's `from` with `[]` added, like `things[]`.

**[name.invalid_step]** A step that can't be a step is written `<invalid step>`.

**[name.list]** Inside `all` or `any`, a path is named after the list: `cs[].s`, or `cs[]` for the items themselves. With `each`, the inner lists are `prs[].cs`.

## Expressions

Each check's definition in the report has an `expression` that says what it checks.

**[render.value]** A value is shown as JSON: a string in double quotes, escaping only `"`, `\` and control characters, a number in plain decimal with no exponent and no trailing zeros (`1.50` and `1e2` are shown as `1.5` and `100`), and lists and objects with `, ` after each item and `: ` after each key. An object's keys are sorted by code point. A literal is shown as the value it holds. A ref is shown as its path's name, without quotes, like `$params.allowed`.

**[render.path]** A path is shown with its [name](#naming-a-path).

**[render.missing]** A parameter that's missing is shown as `<missing value>`, `<missing values>` and so on, and a ref written wrong as `<invalid ref>`. A `path`, `left`, `right` or `each` that isn't a list is shown as `<invalid path>`, `<invalid left>`, `<invalid right>` or `<invalid each>`.

**[present.expression]** `<path> is present`

**[missing.expression]** `<path> is missing`

**[equals.expression]** `<path> == <value>`

**[in.expression]** `<path> in [<values>]`, with each value sorted by the text it's shown as, in code point order. Values read through a ref are shown as the ref's name: `x in $params.allowed`.

**[non_empty_string.expression]** `<path> is a non-empty string`

**[empty.expression]** `<path> is empty`

**[range.expression]** `<path> >= <min> and <path> <= <max>`

**[patterns.expression]** `<path> matches one of [<patterns>]` and `<path> matches none of [<patterns>]`, with the patterns sorted as for `in`, or the ref's name.

**[contains.expression]** `contains(<path>, <value>)` and `not contains(<path>, <value>)`, or with `values`, `contains_all(<path>, [<values>])` and `contains_none(<path>, [<values>])`, sorted as for `in`. When both or neither are given, `<both value and values>` or `<missing value or values>` takes the value's place.

**[compare.expression]** `<left> <cmp> <right>`, like `x lt $input.limit`, with `cmp` as written.

**[time.expression]** Written like `compare`'s.

**[substitute.expression]** A check with a substitute is shown as `<check>, or substitute: <substitute>`, like `pull_request is present, or substitute: verified == true`.

**[list.expression]** `every <list>: <inner>` or `some <list>: <inner>`, with the inner check's paths named inside the item. With `each`, the list is shown as `<list>[].<each>`, and with `as`, it's followed by ` as $<name>`. A path with no steps in the inner check is named `<list>[]`, like `every bs: bs[] matches one of ["^main$"]`. A missing or badly written inner check is shown as `<missing check>`, `<invalid check>`, `<nested too deep>` or `<op can't go here>`, and a bad name as `<invalid name>` or `<name given twice>`.

**[any_of.expression]** `one of: ` followed by the options, sorted by name as text and joined with ` | `, each written `<name>(<check> and <check>)` with its checks in the order written. A missing `options` is shown as `<missing options>`, an empty one as `<empty options>`, an empty option as `<name>(<empty option>)` and one that isn't a list as `<name>(<invalid option>)`.

## Checks ergo adds

**[added.text]** The checks ergo adds have these descriptions and expressions, where `<type>` is the name of the requirement's subject, and `<from>` is the name of the subject's `from`, or `$input` when it has no steps:

| Check           | Description                                                                                           | Expression                                                  |
| --------------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `$well_formed`  | `The requirement is written correctly`                                                                | `count(problems) == 0`                                      |
| `$min_subjects` | `The in-scope <type> count is at least <n>`, or with `min_subjects: 0`, `The <type> list can be read` | `count(matching(<from>)) >= <n>`, or `<from> can be read`   |
| `$unique_ids`   | `Every <type> id is unique`                                                                           | `count(repeated(ids(<from>))) == 0`                         |
| `$applies`      | `The <type> is in scope`                                                                              | the filters' expressions in name order, joined with ` and ` |

**[added.inputs]** `$min_subjects` names its input `in-scope <type> count`, and `$unique_ids` names its input `repeated <type> ids`. `$well_formed` names its first two `count(checks)` and `require`, and when `require` is written wrong, its value is `["neither every nor some"]`. A field ergo doesn't know is listed with `["unknown field"]`, and `checks: {}` with `["empty"]`. A requirement without a `subject` has `{"name": "subject", "value": ["missing"]}`, and one whose `subject` isn't in `subjects` has `["not in subjects"]`.

**[added.causes]** The `causes` of a requirement entry is a list of `{"cause": <cause>, "rows": <number>}`, as in `[{"cause": "value", "rows": 2}]`.
