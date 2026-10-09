# Open questions

Things the spec doesn't settle yet, because they need a decision first. This branch is experimental, so they're kept here rather than in issues.

## Custom operators

The spec says what a custom operator looks like to a policy and a report. `ergo.rego` and the Rust port agree on that much, and differ on the rest:

| | `ergo.rego` | Rust port |
| --- | --- | --- |
| Declaring it | the name only: `operators contains "even"` | a JSON definition with each parameter's kind (`path`, `paths`, `value`, `number`, `string`), which ones are optional, defaults, and the type a path must lead to |
| The body | an `op_passed` rule in Rego | a CEL expression |
| `expression` and `inputs` | written on every check | taken from the definition: an expression template, and the parameters that are paths |
| A field of the wrong type | the operator has to guard against it, and when it fails, the row fails with `value` | ergo fails the check as `unusable` before the operator runs |
| A field that's missing | if the operator passes anyway, so does the check | ergo fails the check as `absent` before the operator runs |
| Inside `all`, `any` and `any_of` | written wrong | allowed |
| In the report | nothing | an `operators` section with a SHA-256 of each definition used and its `version`, which `report/schema.json` doesn't allow yet |

The proposal is to spec the Rust model: a definition in plain JSON that users and auditors can read (name, parameters and their kinds, expression template, version), with only the body left to the engine. ergo then checks for missing, `null` and wrong-typed values in one place instead of trusting every operator to, checks don't repeat `expression` and `inputs`, and a report says which definitions produced it.

It would break the custom operators people write in Rego today, like pr-reviewer's and the Kosli server's, and `ergo.rego` would need to read definitions as data and still call the user's rule for the body. Allowing them inside `all` and `any` is a separate question for Rego, which can't recurse. It might be worth deciding together with #173 (derived values, which would replace many custom operators) and #174 (checks as sentences).
