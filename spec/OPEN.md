# Open questions

Things the spec doesn't settle yet, because they need a decision first. Open questions about the spec live here, not in issues.

## Custom operators

The spec says what a custom operator looks like to a policy and a report. `ergo.rego` and the Rust port, which is on the `core/conformance-suite` branch and not on `main` yet, agree on that much, and differ on the rest:

|                                  | `ergo.rego`                                                                         | Rust port                                                                                                                                                        |
| -------------------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Declaring it                     | the name only: `operators contains "even"`                                          | a JSON definition with each parameter's kind (`path`, `paths`, `value`, `number`, `string`), which ones are optional, defaults, and the type a path must lead to |
| The body                         | an `op_passed` rule in Rego                                                         | a CEL expression                                                                                                                                                 |
| `expression` and `inputs`        | written on every check                                                              | taken from the definition: an expression template, and the parameters that are paths                                                                             |
| A field of the wrong type        | the operator has to guard against it, and when it fails, the row fails with `value` | ergo fails the check as `unusable` before the operator runs                                                                                                      |
| A field that's missing           | if the operator passes anyway, so does the check                                    | ergo fails the check as `absent` before the operator runs                                                                                                        |
| Inside `all`, `any` and `any_of` | written wrong                                                                       | allowed                                                                                                                                                          |
| In the report                    | nothing                                                                             | an `operators` section with a SHA-256 of each definition used and its `version`, which `report/schema.json` doesn't allow yet                                    |

The proposal is to spec the Rust model: a definition in plain JSON that users and auditors can read (name, parameters and their kinds, expression template, version), with only the body left to the engine. ergo then checks for missing, `null` and wrong-typed values in one place instead of trusting every operator to, checks don't repeat `expression` and `inputs`, and a report says which definitions produced it.

It would break the custom operators people write in Rego today, like pr-reviewer's and the Kosli server's, and `ergo.rego` would need to read definitions as data and still call the user's rule for the body. Allowing them inside `all` and `any` is a separate question for Rego, which can't recurse. It might be worth deciding together with #173 (derived values, which would replace many custom operators) and #174 (checks as sentences).

## Derived values

Derived values on a side of `compare` (`count`, `sum`, `add`, `literal`, and `within`, from [#173](https://github.com/kosli-dev/ergo/issues/173)) have an entry in `policy/schema.json` and a rule in `syntax.md`, `compare.derived`. They have no rules in `semantics.md` and no cases yet, so what a derived side reads, when it fails and how it's shown in `expression` and `inputs` is only in [REFERENCE.md](../REFERENCE.md#derived-values).

## Subjects built on another

A subject with `of` (see [REFERENCE.md](../REFERENCE.md#a-subject-built-on-another)) has an entry in `policy/schema.json`, but no rules and no cases yet.

## Time limits

`time.format` only takes years 1678 to 2261 and only counts the first nine digits of a fraction. Both limits come from OPA, which holds a time as nanoseconds since 1970 in a 64-bit integer. A port in another language would have to add them on purpose. Either they stay, and the spec keeps them as a rule every implementation follows, or the spec drops them and `ergo.rego` has to compare times some other way outside that range.

## Where in the input a value was read

A row's `inputs` give each value with a name, written the way a sentence writes the path, like `artifacts named by $params.name.ok`. A name is for people. A program has to parse it to find the value in the input, and even then it only gets the path inside the subject, with the ref still in it.

A report could also give each input its exact location, counted from the root of the input, with every ref already read:

```json
{"name": "artifacts named by $params.name.ok", "location": ["deployments", 0, "artifacts", "web", "ok"], "value": true}
```

A tool could then point at the value itself, like a report viewer that highlights the spot in the input when you hover a row. The open questions are whether it's worth the size it adds to every report, what a value read from the params or worked out from several values (a `count of`, a `sum of`) gets, and whether `failed_items` and `$refs` get one too.

## Rules without cases

Every rule needs a case, apart from the ones listed here. The `sentence` rules here are for forms `ergo.rego` doesn't run yet. `check_rules.py` fails when a rule on this list has a case or doesn't exist, so the list stays true.

- `compare.derived`
- `sentence.forms`
- `sentence.flat`
- `sentence.assert.list`
- `sentence.assert.and`
- `sentence.path.keys`
- `sentence.subject.from`
- `sentence.subject.condition`
- `sentence.subject.applies`
- `sentence.subject.chain`
- `sentence.subject.quoted`
- `sentence.subject.narrow`
- `sentence.subject.depth`
- `sentence.subject.own`
- `sentence.subject.short`
- `sentence.every.walk`
- `sentence.every.empty`
- `sentence.every.if_any`
- `sentence.some.walk`
- `sentence.where.item`
- `sentence.where.undecided`
- `sentence.where.every`
- `sentence.argument.item`
- `sentence.argument.subject`
- `sentence.derived.count`
- `sentence.derived.sum`
- `sentence.derived.plus`
- `sentence.derived.compare`
- `sentence.for.line`
- `sentence.for.depth`
- `sentence.for.scope`
- `sentence.for.name`
- `sentence.for.fail`
- `sentence.for.comma`
- `sentence.for.assert`
- `sentence.phrase.starts`
- `sentence.derived.fail`
- `sentence.print.order`
