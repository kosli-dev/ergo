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

Decided on 2026-10-16: the spec will take the Rust model's definition, a plain JSON object that users and auditors can read, with the name, each parameter's kind and type, an expression template and a version. The body stays up to each implementation: a Rego rule in `ergo.rego`, CEL or anything else in a port. ergo then checks for missing, `null` and wrong-typed values in one place instead of trusting every operator to, checks don't repeat `expression` and `inputs`, and a report says which definitions produced it. The parameters' names and kinds are also what a sentence needs to call an operator, because they say whether a word after it is a path or a value. Two implementations can still give the same definition different bodies, and the report can't show that.

It's put off until a control needs logic that no phrase covers. On 2026-10-16, pr-reviewer was the only known policy with custom operators, and all seven of them can be written as sentences that ergo runs. The last one, `contains_all`, is `contains all of` with a field of the subject, and so is DEV-0406's `does not contain`, both since #224. The deadlines DEV-0401, 0402, 0705 and 0802 work out in Rego can be sentences too since #232 and #234, with `days elapsed from X to Y` and a limit looked up by a field of the subject. Until then, custom operators keep working in the [syntax of syntax.md](syntax.md), so that syntax can't be removed while a policy still needs one. Allowing them inside `all` and `any` is a separate question for Rego, which can't recurse.

### Where sentences fall short

When a policy needs something no sentence can say, the first question is whether it should be a phrase. These gaps are guesses as of 2026-10-17. Only version order and reshaped evidence show up in the corpus. Date arithmetic did until #234.

| Gap                            | Example                                                                | Where it belongs                                                                |
| ------------------------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Calendar time                  | renewed every 12 months, a review once a year                          | `months` and `years elapsed`, once a control needs them. Fixed units run (#234) |
| Arithmetic beyond `plus`       | coverage of at least 80% (`covered / total`), a difference, an average | more derived values next to `count of`, `sum of` and `plus`                     |
| Uniqueness and distinct counts | no two approvers are the same user, at least 2 distinct reviewers      | a derived value, like `count of distinct approvers.username`                    |
| Orderings of one domain        | version order, an address in a network range, a path matching a glob   | a custom operator, because each has its own rules and isn't shared widely       |
| Decoding                       | base64 payloads, signed tokens, a hash matching some content           | before ergo, when the evidence is attested, so the report still shows the facts |
| Recursion                      | dependencies of dependencies, chains of approvals                      | before ergo. Rego can't recurse, so a custom operator can't either              |
| Rules across subjects          | at most 5% of deployments failed, every service deployed this week     | something on the requirement, since a check sees one subject at a time          |

A gap that many controls share becomes a phrase or a derived value, which stays readable, runs the same everywhere and fails closed in one place. A gap that belongs to one domain becomes a custom operator, with a definition that says what it means. Parsing and decoding stay out of ergo, because an operator that decodes hides the evidence from the report as much as Rego that runs before ergo does.

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

## Which steps a walk walks

`every` and `some` walk "into every list along the path" ([walk.lists](semantics.md#every-and-some)), and ergo decides that from the data: a step is walked when at least one value there is a list, and then every value there must be one. So `every prs.commits.signed is true` on `{"prs": [{"commits": {"signed": true}}]}` passes, because `commits` is an object and nothing is walked at that step, but the same pull request fails as `unusable` when another one has a list of commits. It fails closed whenever the data shows a list, and only passes data shaped wrong when every item is shaped wrong the same way and the wrong shape still holds a field that passes.

Three ways to settle it:

- Keep it as it is, and say so in the spec.
- Have the author mark the lists, like `every prs[].commits[].signed`. That changes the grammar of [#174](https://github.com/kosli-dev/ergo/issues/174), and costs some of its plain reading.
- Give ergo the shape of the input, as a schema, so a step is walked because the schema says it holds a list. [#191](https://github.com/kosli-dev/ergo/pull/191) already declares a schema for part of `input`.

## Sentences the spec doesn't say enough about yet

`ergo.rego` doesn't run these forms, and the spec doesn't pin down their rows, so there are no cases for them. A case for each can go in once the question is settled, and be listed in `known_differences` in `spec_test.rego` while `ergo.rego` fails it.

- `last of`: what a row's `inputs` name is. `first of xs` prints `item 1 of xs`, because the position is known when the sentence is read. The last position isn't, and an empty list has no item to number. It could print `last of xs`, or `item 3 of xs` for a list of three and something else for an empty one. The meaning is clear: the last item, absent on an empty list, `unusable` on something that isn't a list, as `first of` is.
- `count of`, `sum of` and `plus` in the phrase of an `every` or `some`, like `every xs is count of ys`, and an elapsed time there, like `every xs is days elapsed from started to ended`: [sentence.argument.item](sentences.md#every-some-and-whose) says a path in the argument starts at the item, but not what the row's `inputs` show for a number worked out from each item.
- An elapsed time in the `whose` of a `count of`, a `sum of` or an `every`, when an item can't be decided: which path `failed_items` names when the check reads two, `started` or `ended`.
- An elapsed time in a subject's `from` line, like `vulns whose days elapsed from started to ended is 1`: what the `$applies` row shows for it, and which paths its `inputs` list.
- A `plus` in the `whose` of a `count of` or a `sum of`, like `count of xs whose a plus b is 3 is 1`: whether a `whose` condition can have `plus` on its left.

## Rules without cases

Every rule needs a case, apart from the ones listed here. The `sentence` rules here are for forms `ergo.rego` doesn't run or check yet. `check_rules.py` fails when a rule on this list has a case or doesn't exist, so the list stays true.

- `compare.derived`
- `sentence.forms`
- `sentence.flat`
- `sentence.subject.depth`
- `sentence.argument.subject`
- `sentence.for.depth`
